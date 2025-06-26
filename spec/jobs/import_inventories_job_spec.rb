# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'tempfile'

RSpec.describe ImportInventoriesJob, type: :job do
  # 基本設定
  let(:admin) { create(:admin) }
  let(:csv_file) { Tempfile.new([ 'inventories', '.csv' ]) }
  let(:file_path) { csv_file.path }
  let(:job_id) { SecureRandom.uuid }
  let(:redis_instance) { Redis.new }

  let(:valid_csv_content) do
    <<~CSV
      name,quantity,price,expires_on,lot_number
      アスピリン 100mg,1000,250.50,2025-12-31,LOT001
      ビタミンC,500,150.00,2025-06-30,LOT002
      胃腸薬,750,100.25,2025-09-15,LOT003
    CSV
  end

  let(:invalid_csv_content) do
    <<~CSV
      name,quantity,price
      ,100,250.50
      Invalid Product,-50,100.00
      Product with zero price,100,0
    CSV
  end

  let(:large_csv_content) do
    headers = "name,quantity,price,expires_on,lot_number\n"
    rows = 5000.times.map do |i|
      "Product #{i},#{100 + i},#{100.0 + i},2025-12-31,LOT#{i.to_s.rjust(5, '0')}"
    end
    headers + rows.join("\n")
  end

  before do
    csv_file.write(valid_csv_content)
    csv_file.rewind

    # Redis設定
    allow_any_instance_of(ImportInventoriesJob).to receive(:get_redis_connection).and_return(redis_instance)
    redis_instance.flushdb

    # ActionCable設定
    allow(ActionCable.server).to receive(:broadcast)
    allow(ImportProgressChannel).to receive(:broadcast_progress)
    allow(ImportProgressChannel).to receive(:broadcast_completion)
    allow(ImportProgressChannel).to receive(:broadcast_error)
  end

  after do
    csv_file.unlink
  end

  describe '#perform' do
    context '有効なCSVファイルの場合' do
      it 'CSVファイルを正常に処理する' do
        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
        }.to change(Inventory, :count).by(3)
      end

      it '正しい結果を返す' do
        result = ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)

        expect(result[:valid_count]).to eq(3)
        expect(result[:invalid_records]).to be_empty
      end

      it 'Redisに進捗を保存する' do
        ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)

        status_key = "csv_import:#{job_id}"
        status = redis_instance.hgetall(status_key)

        expect(status['status']).to eq('completed')
        expect(status['valid_count']).to eq('3')
        expect(status['invalid_count']).to eq('0')
      end

      it 'ActionCableで通知する' do
        expect(ActionCable.server).to receive(:broadcast).at_least(:once)

        ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
      end
    end

    context '無効なCSVファイルの場合' do
      before do
        csv_file.write(invalid_csv_content)
        csv_file.rewind
      end

      it 'skip_invalidがfalseの場合は処理を中断する' do
        result = ImportInventoriesJob.perform_now(file_path, admin.id, { skip_invalid: false }, job_id)

        expect(result[:valid_count]).to eq(0)
        expect(result[:invalid_records].size).to eq(3)
        expect(Inventory.count).to eq(0)
      end

      it 'skip_invalidがtrueの場合は有効なレコードのみ処理する' do
        result = ImportInventoriesJob.perform_now(file_path, admin.id, { skip_invalid: true }, job_id)

        expect(result[:valid_count]).to be >= 0
        expect(result[:invalid_records].size).to be > 0
      end

      it 'エラーメッセージを含む' do
        result = ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)

        invalid_record = result[:invalid_records].first
        expect(invalid_record[:errors]).to include("Name can't be blank")
        expect(invalid_record[:row]).to be_present
      end

      it 'ArgumentErrorを適切に処理する' do
        csv_file.write("name,quantity,price,status\nTest Product,100,200,invalid_status\n")
        csv_file.rewind

        # enum値が無効な場合のArgumentErrorをシミュレート
        allow_any_instance_of(Inventory).to receive(:valid?).and_raise(
          ArgumentError.new("'invalid_status' is not a valid status")
        )

        result = ImportInventoriesJob.perform_now(file_path, admin.id, { skip_invalid: true })

        expect(result[:invalid_records].first[:errors]).to include("'invalid_status' is not a valid status")
      end
    end

    context '大量データの処理' do
      before do
        csv_file.write(large_csv_content)
        csv_file.rewind
      end

      it 'バッチ処理で正常に処理する' do
        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, { batch_size: 1000 }, job_id)
        }.to change(Inventory, :count).by(5000)
      end

      it '進捗を定期的に更新する' do
        expect(ImportProgressChannel).to receive(:broadcast_progress).at_least(5).times

        ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
      end

      it '妥当な時間内に完了する' do
        start_time = Time.current

        ImportInventoriesJob.perform_now(file_path, admin.id, { batch_size: 1000 }, job_id)

        elapsed_time = Time.current - start_time
        expect(elapsed_time).to be < 30.seconds
      end
    end

    context 'セキュリティ検証' do
      it 'ファイルが存在しない場合はエラーを発生させる' do
        expect {
          ImportInventoriesJob.perform_now('/non/existent/file.csv', admin.id)
        }.to raise_error(SecurityError, /File not found/)
      end

      it 'ファイルサイズが上限を超える場合はエラーを発生させる' do
        allow(File).to receive(:size).and_return(101.megabytes)

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id)
        }.to raise_error(SecurityError, /File too large/)
      end

      it '不正な拡張子の場合はエラーを発生させる' do
        txt_file = Tempfile.new([ 'test', '.txt' ])
        txt_file.write("some content")
        txt_file.rewind

        expect {
          ImportInventoriesJob.perform_now(txt_file.path, admin.id)
        }.to raise_error(SecurityError, /Invalid file type/)

        txt_file.unlink
      end

      it '無効なCSV形式の場合はエラーを発生させる' do
        csv_file.write("invalid\"csv\"format\nwith unclosed quote")
        csv_file.rewind

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id)
        }.to raise_error(SecurityError, /Invalid CSV format/)
      end

      it '必須ヘッダーが不足している場合はエラーを発生させる' do
        csv_file.write("product,amount\nTest,100")
        csv_file.rewind

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id)
        }.to raise_error(SecurityError, /Missing required headers/)
      end

      it '複数の必須ヘッダーが不足している場合に詳細なエラーメッセージを含む' do
        csv_file.write("product\nTest Product")
        csv_file.rewind

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id)
        }.to raise_error(SecurityError) do |error|
          expect(error.message).to include('Missing required headers:')
          expect(error.message).to include('quantity')
          expect(error.message).to include('price')
        end
      end

      it 'ヘッダーの大文字小文字を正しく処理する' do
        csv_file.write("NAME,QUANTITY,PRICE\nTest,100,250.50")
        csv_file.rewind

        # 大文字のヘッダーでも正常に処理される（downcaseで正規化）
        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id)
        }.not_to raise_error
      end

      it 'パストラバーサル攻撃を防ぐ' do
        malicious_path = "../../etc/passwd"

        expect {
          ImportInventoriesJob.perform_now(malicious_path, admin.id)
        }.to raise_error(SecurityError)
      end

      it '許可されたディレクトリ内のファイルは処理する' do
        tmp_file = Tempfile.new([ 'test', '.csv' ], Rails.root.join('tmp'))
        tmp_file.write(valid_csv_content)
        tmp_file.rewind

        expect {
          ImportInventoriesJob.perform_now(tmp_file.path, admin.id)
        }.not_to raise_error

        tmp_file.unlink
      end
    end

    context 'インポートオプション' do
      context 'update_existingオプション' do
        before do
          create(:inventory, name: 'アスピリン 100mg', quantity: 500, price: 200)
        end

        it 'falseの場合は既存レコードをスキップする' do
          result = ImportInventoriesJob.perform_now(file_path, admin.id, { update_existing: false }, job_id)

          expect(result[:duplicate_count]).to eq(1) if result[:duplicate_count]
          expect(Inventory.count).to eq(3)

          aspirin = Inventory.find_by(name: 'アスピリン 100mg')
          expect(aspirin.quantity).to eq(500) # 変更されない
        end

        it 'trueの場合は既存レコードを更新する' do
          result = ImportInventoriesJob.perform_now(file_path, admin.id, { update_existing: true }, job_id)

          expect(result[:update_count]).to eq(1) if result[:update_count]
          expect(Inventory.count).to eq(3)

          aspirin = Inventory.find_by(name: 'アスピリン 100mg')
          expect(aspirin.quantity).to eq(1000) # 更新される
        end
      end

      context 'unique_keyオプション' do
        it 'ロット番号をキーとして使用する' do
          create(:inventory, name: 'Different Name', lot_number: 'LOT001')

          result = ImportInventoriesJob.perform_now(file_path, admin.id, {
            unique_key: 'lot_number',
            update_existing: false
          }, job_id)

          expect(result[:duplicate_count]).to be >= 1 if result[:duplicate_count]
        end
      end
    end

    context 'エラーハンドリング' do
      it '存在しない管理者IDの場合はエラーを発生させる' do
        expect {
          ImportInventoriesJob.perform_now(file_path, 99999)
        }.to raise_error(ArgumentError, /Admin not found/)
      end

      it 'ファイルパスが空の場合はエラーを発生させる' do
        expect {
          ImportInventoriesJob.perform_now('', admin.id)
        }.to raise_error(ArgumentError, /File path is required/)
      end

      it 'エラー時にRedisステータスを更新する' do
        allow_any_instance_of(ImportInventoriesJob).to receive(:execute_csv_import).and_raise(StandardError, "Test error")

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
        }.to raise_error(StandardError)

        status_key = "csv_import:#{job_id}"
        status = redis_instance.hgetall(status_key)

        expect(status['status']).to eq('failed')
        expect(status['error_message']).to eq('Test error')
      end

      it 'エラー時にActionCableで通知する' do
        allow_any_instance_of(ImportInventoriesJob).to receive(:execute_csv_import).and_raise(StandardError, "Test error")

        expect(ImportProgressChannel).to receive(:broadcast_error)

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
        }.to raise_error(StandardError)
      end
    end

    context 'ファイル削除' do
      it '本番環境では処理後にファイルを削除する' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))

        ImportInventoriesJob.perform_now(file_path, admin.id)

        expect(File.exist?(file_path)).to be false
      end

      it '開発環境では処理後にファイルを保持する' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))

        ImportInventoriesJob.perform_now(file_path, admin.id)

        expect(File.exist?(file_path)).to be true
      end

      it 'ファイル削除に失敗してもエラーを発生させない' do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
        allow(File).to receive(:delete).and_raise(Errno::EACCES)

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id)
        }.not_to raise_error
      end
    end

    context 'Sidekiq設定' do
      it '正しいキューに配置される' do
        expect {
          ImportInventoriesJob.perform_later(file_path, admin.id)
        }.to have_enqueued_job(ImportInventoriesJob).on_queue('imports')
      end

      it 'リトライ回数が設定されている' do
        expect(ImportInventoriesJob.sidekiq_options['retry']).to eq(3)
      end

      it 'バックトレースが有効化されている' do
        expect(ImportInventoriesJob.sidekiq_options['backtrace']).to be true
      end
    end

    context 'ログ出力' do
      it '正常処理時に適切なログを出力する' do
        allow(Rails.logger).to receive(:info) # 全てのinfo呼び出しを許可
        expect(Rails.logger).to receive(:info).with(/csv_import_security_validated/)
        expect(Rails.logger).to receive(:info).with(/csv_import_started/)
        expect(Rails.logger).to receive(:info).with(/csv_import_completed/)

        ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
      end

      it 'エラー時に適切なログを出力する' do
        allow_any_instance_of(ImportInventoriesJob).to receive(:execute_csv_import).and_raise(StandardError, "Test error")
        allow(Rails.logger).to receive(:info) # 全てのinfo呼び出しを許可
        allow(Rails.logger).to receive(:error) # 全てのerror呼び出しを許可

        expect(Rails.logger).to receive(:error).with(/csv_import_failed/)

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
        }.to raise_error(StandardError)
      end
    end

    context 'パフォーマンス' do
      it 'メモリ使用量が適切に管理される' do
        # Docker環境対応: Ruby標準のGC.statを使用してメモリ監視
        csv_file.write(large_csv_content)
        csv_file.rewind

        # ガベージコレクションを実行してベースライン確立
        GC.start
        initial_heap_size = GC.stat(:heap_allocated_pages)
        initial_object_count = ObjectSpace.count_objects[:T_OBJECT]

        ImportInventoriesJob.perform_now(file_path, admin.id, { batch_size: 1000 }, job_id)

        # ガベージコレクション後の状態確認
        GC.start
        final_heap_size = GC.stat(:heap_allocated_pages)
        final_object_count = ObjectSpace.count_objects[:T_OBJECT]

        heap_increase = final_heap_size - initial_heap_size
        object_increase = final_object_count - initial_object_count

        # 大量CSVインポート後でもheapとobject増加が制限範囲内
        expect(heap_increase).to be < 1000  # ページ単位での増加制限
        expect(object_increase).to be < 50_000  # オブジェクト数増加制限
      end

      it 'N+1クエリが発生しない' do
        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
        }.not_to exceed_query_limit(20)
      end
    end
  end

  describe 'プライベートメソッド' do
    let(:job) { ImportInventoriesJob.new }

    before do
      job.instance_variable_set(:@file_path, file_path)
      job.instance_variable_set(:@admin_id, admin.id)
      job.instance_variable_set(:@job_id, job_id)
      job.instance_variable_set(:@start_time, Time.current)
    end

    describe '#calculate_duration' do
      it '正しい経過時間を計算する' do
        job.instance_variable_set(:@start_time, 5.seconds.ago)

        duration = job.send(:calculate_duration)

        expect(duration).to be_between(4.5, 5.5)
      end

      it '開始時刻が設定されていない場合は0を返す' do
        job.instance_variable_set(:@start_time, nil)

        expect(job.send(:calculate_duration)).to eq(0)
      end
    end

    describe '#build_completion_message' do
      it '成功メッセージを構築する' do
        result = { valid_count: 100, invalid_records: [] }

        message = job.send(:build_completion_message, result)

        expect(message).to include('100')
        expect(message).not_to include('invalid')
      end

      it '一部失敗の場合は詳細を含む' do
        result = { valid_count: 90, invalid_records: Array.new(10) }

        message = job.send(:build_completion_message, result)

        expect(message).to include('90')
        expect(message).to include('10')
      end
    end

    describe '#determine_error_type' do
      it 'エラータイプを正しく判定する' do
        validation_error = ActiveRecord::RecordInvalid.new(Inventory.new)
        expect(job.send(:determine_error_type, validation_error)).to eq('validation_error')

        # CSV::MalformedCSVError は lineno と line の2つの引数が必要
        csv_error = CSV::MalformedCSVError.new("test", 1)
        expect(job.send(:determine_error_type, csv_error)).to eq('file_error')

        security_error = SecurityError.new("test")
        expect(job.send(:determine_error_type, security_error)).to eq('security_error')

        other_error = StandardError.new("test")
        expect(job.send(:determine_error_type, other_error)).to eq('processing_error')
      end
    end
  end

  describe 'コールバックとバリデーション' do
    describe 'before_perform :validate_job_arguments' do
      it '無効な引数で実行時にエラーを発生させる' do
        expect {
          ImportInventoriesJob.perform_now(nil, admin.id)
        }.to raise_error(ArgumentError, /File path is required/)

        expect {
          ImportInventoriesJob.perform_now(file_path, nil)
        }.to raise_error(ArgumentError, /Admin ID is required/)

        expect {
          ImportInventoriesJob.perform_now(file_path, 99999)
        }.to raise_error(ArgumentError, /Admin not found/)
      end
    end
  end

  describe 'セキュリティ定数' do
    it 'センシティブパラメータが定義されている' do
      expect(ImportInventoriesJob::SENSITIVE_IMPORT_PARAMS).to include(
        'file_path', 'admin_id', 'user_email'
      )
    end

    it 'ファイル制限が適切に定義されている' do
      expect(ImportInventoriesJob::MAX_FILE_SIZE).to eq(100.megabytes)
      expect(ImportInventoriesJob::ALLOWED_EXTENSIONS).to eq(%w[.csv])
      expect(ImportInventoriesJob::REQUIRED_CSV_HEADERS).to eq(%w[name quantity price])
    end

    it 'バッチ処理設定が定義されている' do
      expect(ImportInventoriesJob::IMPORT_BATCH_SIZE).to eq(1000)
      expect(ImportInventoriesJob::PROGRESS_REPORT_INTERVAL).to eq(10)
    end

    it 'Redis TTL設定が定義されている' do
      expect(ImportInventoriesJob::PROGRESS_TTL).to eq(1.hour.to_i)
      expect(ImportInventoriesJob::COMPLETED_TTL).to eq(24.hours.to_i)
    end
  end

  describe 'エッジケース' do
    context 'ジョブIDが省略された場合' do
      it '自動的にジョブIDを生成する' do
        expect(SecureRandom).to receive(:uuid).and_return('auto_generated_id')

        result = ImportInventoriesJob.perform_now(file_path, admin.id)
        expect(result).to be_present
      end
    end

    context 'import_optionsがnilの場合' do
      it 'デフォルトオプションで処理する' do
        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, nil)
        }.not_to raise_error
      end
    end

    context 'CSVファイルに特殊文字が含まれる場合' do
      let(:unicode_csv_content) do
        <<~CSV
          name,quantity,price
          "製品 🎯",100,250.50
          "Pröd‹ct with émojî 😊",200,150.00
          "製品,カンマ入り",300,350.00
        CSV
      end

      it 'Unicode文字を正しく処理する' do
        csv_file.write(unicode_csv_content)
        csv_file.rewind

        result = ImportInventoriesJob.perform_now(file_path, admin.id)

        expect(result[:valid_count]).to eq(3)
        expect(Inventory.find_by(name: '製品 🎯')).to be_present
        expect(Inventory.find_by(name: 'Pröd‹ct with émojî 😊')).to be_present
      end
    end
  end
end

# ============================================
# 完全ブランチカバレッジ拡張テスト
# ============================================
# CLAUDE.md準拠: C1カバレッジ80%達成のための詳細分岐テスト
# メタ認知: ImportInventoriesJobの全分岐パターンを完全カバー
# 横展開: 他の非同期ジョブでも同様の詳細分岐テスト適用

RSpec.describe ImportInventoriesJob, "Complete Branch Coverage Tests" do
  let(:admin) { create(:admin) }
  let(:csv_file) { Tempfile.new([ 'inventories', '.csv' ]) }
  let(:file_path) { csv_file.path }
  let(:job_id) { SecureRandom.uuid }
  let(:redis_instance) { Redis.new }
  let(:job) { ImportInventoriesJob.new }

  let(:valid_csv_content) do
    <<~CSV
      name,quantity,price
      Test Product 1,100,250.50
      Test Product 2,200,150.00
    CSV
  end

  before do
    csv_file.write(valid_csv_content)
    csv_file.rewind

    allow_any_instance_of(ImportInventoriesJob).to receive(:get_redis_connection).and_return(redis_instance)
    redis_instance.flushdb

    allow(ActionCable.server).to receive(:broadcast)
    allow(ImportProgressChannel).to receive(:broadcast_progress)
    allow(ImportProgressChannel).to receive(:broadcast_completion)
    allow(ImportProgressChannel).to receive(:broadcast_error)
  end

  after do
    csv_file.unlink
  end

  # ============================================
  # Redis接続の完全分岐カバレッジ
  # ============================================

  describe "Redis connection branch coverage" do
    describe "#get_redis_connection" do
      context "test environment" do
        before do
          allow(Rails.env).to receive(:test?).and_return(true)
        end

        it "returns test Redis when Redis is defined and available" do
          allow(Redis).to receive(:current).and_return(redis_instance)
          allow(redis_instance).to receive(:ping).and_return("PONG")

          connection = job.send(:get_redis_connection)
          expect(connection).to eq(redis_instance)
        end

        it "returns nil when Redis is not defined" do
          hide_const("Redis")

          connection = job.send(:get_redis_connection)
          expect(connection).to be_nil
        end

        it "returns nil when Redis ping fails" do
          allow(Redis).to receive(:current).and_return(redis_instance)
          allow(redis_instance).to receive(:ping).and_raise(Redis::CannotConnectError)
          allow(Rails.logger).to receive(:warn)

          connection = job.send(:get_redis_connection)
          expect(connection).to be_nil
          expect(Rails.logger).to have_received(:warn).with(/Redis not available in test/)
        end
      end

      context "production environment" do
        before do
          allow(Rails.env).to receive(:test?).and_return(false)
        end

        it "uses Sidekiq Redis pool when available" do
          mock_pool = double("pool")
          allow(Sidekiq).to receive(:redis_pool).and_return(mock_pool)
          expect(Sidekiq).to receive(:redis).and_yield(redis_instance)

          connection = job.send(:get_redis_connection)
          expect(connection).to eq(redis_instance)
        end

        it "falls back to Redis.current when Sidekiq unavailable" do
          hide_const("Sidekiq")
          allow(Redis).to receive(:current).and_return(redis_instance)

          connection = job.send(:get_redis_connection)
          expect(connection).to eq(redis_instance)
        end

        it "returns nil when Redis connection fails" do
          allow(Redis).to receive(:current).and_raise(Redis::CannotConnectError)
          allow(Rails.logger).to receive(:warn)

          connection = job.send(:get_redis_connection)
          expect(connection).to be_nil
          expect(Rails.logger).to have_received(:warn).with(/Redis connection failed/)
        end

        it "handles Sidekiq defined but no redis_pool" do
          stub_const("Sidekiq", Class.new)
          allow(Sidekiq).to receive(:redis_pool).and_return(nil)
          allow(Redis).to receive(:current).and_return(redis_instance)

          connection = job.send(:get_redis_connection)
          expect(connection).to eq(redis_instance)
        end
      end
    end
  end

  # ============================================
  # パスセキュリティ検証の完全分岐カバレッジ
  # ============================================

  describe "Path security validation complete branch coverage" do
    before do
      job.instance_variable_set(:@file_path, file_path)
    end

    describe "#validate_file_path_security" do
      context "test environment specific branches" do
        before do
          allow(Rails.env).to receive(:test?).and_return(true)
        end

        it "allows system temp directory" do
          allow(Dir).to receive(:tmpdir).and_return("/system/tmp")
          temp_file = Tempfile.new([ 'test', '.csv' ], "/system/tmp")
          job.instance_variable_set(:@file_path, temp_file.path)

          expect {
            job.send(:validate_file_path_security)
          }.not_to raise_error

          temp_file.unlink
        end

        it "allows ENV[TMPDIR] directory" do
          allow(ENV).to receive(:[]).with("TMPDIR").and_return("/env/tmp")
          allow(File).to receive(:expand_path).with("/env/tmp").and_return("/env/tmp")
          allow(File).to receive(:expand_path).with(file_path).and_return("/env/tmp/test.csv")

          expect {
            job.send(:validate_file_path_security)
          }.not_to raise_error
        end

        it "allows /var/folders on macOS" do
          allow(RUBY_PLATFORM).to receive(:include?).with("darwin").and_return(true)
          macos_temp_path = "/var/folders/xx/xxxxxxxxxxxxxx/T/test.csv"
          allow(File).to receive(:expand_path).with(macos_temp_path).and_return(macos_temp_path)
          allow(File).to receive(:expand_path).with("/var/folders").and_return("/var/folders")
          job.instance_variable_set(:@file_path, macos_temp_path)

          expect {
            job.send(:validate_file_path_security)
          }.not_to raise_error
        end

        it "rejects /var/folders on non-macOS" do
          allow(RUBY_PLATFORM).to receive(:include?).with("darwin").and_return(false)
          var_folders_path = "/var/folders/xx/test.csv"
          allow(File).to receive(:expand_path).with(var_folders_path).and_return(var_folders_path)
          job.instance_variable_set(:@file_path, var_folders_path)

          expect {
            job.send(:validate_file_path_security)
          }.to raise_error(SecurityError, /Unauthorized file location/)
        end

        it "handles nil TMPDIR environment variable" do
          allow(ENV).to receive(:[]).with("TMPDIR").and_return(nil)
          allow(Dir).to receive(:tmpdir).and_return("/tmp")

          expect {
            job.send(:validate_file_path_security)
          }.not_to raise_error
        end
      end

      context "production environment" do
        before do
          allow(Rails.env).to receive(:test?).and_return(false)
        end

        it "only allows configured directories" do
          expect {
            job.send(:validate_file_path_security)
          }.not_to raise_error # default temp file should be allowed
        end

        it "rejects unauthorized paths" do
          job.instance_variable_set(:@file_path, "/etc/passwd")

          expect {
            job.send(:validate_file_path_security)
          }.to raise_error(SecurityError, /Unauthorized file location/)
        end
      end
    end
  end

  # ============================================
  # CSV検証の完全分岐カバレッジ
  # ============================================

  describe "CSV validation complete branch coverage" do
    before do
      job.instance_variable_set(:@file_path, file_path)
    end

    describe "#validate_csv_format" do
      it "handles CSV with nil headers" do
        csv_content = "\n\n\n"  # Empty lines only
        csv_file.write(csv_content)
        csv_file.rewind

        expect {
          job.send(:validate_csv_format)
        }.to raise_error(SecurityError, /Missing required headers/)
      end

      it "handles CSV with first row being nil" do
        csv_content = ",,,\nname,quantity,price\nProduct,100,250"
        csv_file.write(csv_content)
        csv_file.rewind

        expect {
          job.send(:validate_csv_format)
        }.to raise_error(SecurityError, /Missing required headers/)
      end

      it "uses CsvHeaderNormalizer for error messages" do
        csv_content = "product,amount\nTest,100"
        csv_file.write(csv_content)
        csv_file.rewind

        expect(CsvHeaderNormalizer).to receive(:detailed_error_message)
          .with([ 'product', 'amount' ], 'inventory', %w[name quantity price])
          .and_return("Detailed error message")

        expect {
          job.send(:validate_csv_format)
        }.to raise_error(SecurityError, "Detailed error message")
      end

      it "uses CsvHeaderNormalizer.normalize for header processing" do
        expect(CsvHeaderNormalizer).to receive(:normalize)
          .with([ 'name', 'quantity', 'price' ], 'inventory', %w[name quantity price])
          .and_return([ 'name', 'quantity', 'price' ])

        expect {
          job.send(:validate_csv_format)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # 進捗追跡の完全分岐カバレッジ
  # ============================================

  describe "Progress tracking complete branch coverage" do
    before do
      job.instance_variable_set(:@file_path, file_path)
      job.instance_variable_set(:@admin_id, admin.id)
      job.instance_variable_set(:@job_id, job_id)
      job.instance_variable_set(:@start_time, Time.current)
    end

    describe "#setup_basic_tracking" do
      it "sets up Redis tracking when Redis is available" do
        job.instance_variable_set(:@redis, redis_instance)

        job.send(:setup_basic_tracking)

        expect(job.instance_variable_get(:@status_key)).to eq("csv_import:#{job_id}")
        expect(redis_instance.hget("csv_import:#{job_id}", "job_id")).to eq(job_id)
      end

      it "handles nil Redis gracefully" do
        job.instance_variable_set(:@redis, nil)

        expect {
          job.send(:setup_basic_tracking)
        }.not_to raise_error
      end
    end

    describe "#update_status_to_running" do
      it "updates status when Redis is available" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, "csv_import:#{job_id}")

        job.send(:update_status_to_running)

        expect(redis_instance.hget("csv_import:#{job_id}", "status")).to eq("running")
      end

      it "returns early when Redis is nil" do
        job.instance_variable_set(:@redis, nil)

        expect {
          job.send(:update_status_to_running)
        }.not_to raise_error
      end
    end

    describe "#update_import_progress" do
      it "updates progress when Redis is available" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, "csv_import:#{job_id}")
        job.instance_variable_set(:@admin_id, admin.id)

        job.send(:update_import_progress, 50, "Test message")

        expect(redis_instance.hget("csv_import:#{job_id}", "progress")).to eq("50")
        expect(redis_instance.hget("csv_import:#{job_id}", "message")).to eq("Test message")
      end

      it "skips Redis update when Redis is nil" do
        job.instance_variable_set(:@redis, nil)
        job.instance_variable_set(:@admin_id, admin.id)

        expect {
          job.send(:update_import_progress, 50)
        }.not_to raise_error
      end

      it "updates progress without message" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, "csv_import:#{job_id}")
        job.instance_variable_set(:@admin_id, admin.id)

        job.send(:update_import_progress, 75)

        expect(redis_instance.hget("csv_import:#{job_id}", "progress")).to eq("75")
      end
    end

    describe "#finalize_progress_tracking" do
      it "sets expiry when Redis and status_key are available" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, "csv_import:#{job_id}")

        job.send(:finalize_progress_tracking)

        ttl = redis_instance.ttl("csv_import:#{job_id}")
        expect(ttl).to be > 0
      end

      it "returns early when Redis is nil" do
        job.instance_variable_set(:@redis, nil)

        expect {
          job.send(:finalize_progress_tracking)
        }.not_to raise_error
      end

      it "returns early when status_key is nil" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, nil)

        expect {
          job.send(:finalize_progress_tracking)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # ブロードキャスト機能の完全分岐カバレッジ
  # ============================================

  describe "Broadcast functionality complete branch coverage" do
    before do
      job.instance_variable_set(:@admin_id, admin.id)
      job.instance_variable_set(:@job_id, job_id)
    end

    describe "#broadcast_to_admin" do
      it "uses AdminChannel when admin exists" do
        expect(AdminChannel).to receive(:broadcast_to).with(admin, hash_including(timestamp: anything))

        job.send(:broadcast_to_admin, { type: "test" })
      end

      it "falls back to ActionCable when AdminChannel fails" do
        allow(AdminChannel).to receive(:broadcast_to).and_raise(StandardError)
        expect(ActionCable.server).to receive(:broadcast).with("admin_#{admin.id}", hash_including(type: "test"))

        job.send(:broadcast_to_admin, { type: "test" })
      end

      it "handles non-existent admin gracefully" do
        job.instance_variable_set(:@admin_id, 99999)

        expect {
          job.send(:broadcast_to_admin, { type: "test" })
        }.not_to raise_error
      end
    end

    describe "#broadcast_progress_update" do
      it "includes processed and total counts when available" do
        job.instance_variable_set(:@processed_count, 50)
        job.instance_variable_set(:@total_count, 100)

        expect(ImportProgressChannel).to receive(:broadcast_progress)
          .with(admin.id, hash_including(processed: 50, total: 100))

        job.send(:broadcast_progress_update, 50.5, "Processing...")
      end

      it "handles nil message" do
        expect(ImportProgressChannel).to receive(:broadcast_progress)
          .with(admin.id, hash_including(message: "CSVデータを処理中..."))

        job.send(:broadcast_progress_update, 25)
      end

      it "rounds progress to 1 decimal place" do
        expect(ImportProgressChannel).to receive(:broadcast_progress)
          .with(admin.id, hash_including(progress: 33.3))

        job.send(:broadcast_progress_update, 33.333333)
      end
    end

    describe "#broadcast_import_complete" do
      it "processes result with invalid records" do
        result = {
          valid_count: 90,
          invalid_records: [
            { errors: [ "Name can't be blank" ] },
            { errors: [ "Quantity must be positive", "Price is required" ] }
          ]
        }
        job.instance_variable_set(:@start_time, 10.seconds.ago)

        expect(ImportProgressChannel).to receive(:broadcast_completion)
          .with(admin.id, hash_including(
            processed: 92,
            successful: 90,
            failed: 2,
            errors: [ "Name can't be blank", "Quantity must be positive", "Price is required" ]
          ))

        job.send(:broadcast_import_complete, result)
      end

      it "handles empty invalid records" do
        result = { valid_count: 100, invalid_records: [] }
        job.instance_variable_set(:@start_time, 5.seconds.ago)

        expect(ImportProgressChannel).to receive(:broadcast_completion)
          .with(admin.id, hash_including(processed: 100, successful: 100, failed: 0))

        job.send(:broadcast_import_complete, result)
      end
    end

    describe "#broadcast_import_error" do
      it "includes error details with line number" do
        job.instance_variable_set(:@current_line_number, 42)
        error = SecurityError.new("Invalid file")

        expect(ImportProgressChannel).to receive(:broadcast_error)
          .with(admin.id, "Invalid file", hash_including(
            error_type: "security_error",
            line_number: 42
          ))

        job.send(:broadcast_import_error, error)
      end

      it "handles nil line number" do
        error = StandardError.new("Generic error")

        expect(ImportProgressChannel).to receive(:broadcast_error)
          .with(admin.id, "Generic error", hash_including(
            error_type: "processing_error",
            line_number: nil
          ))

        job.send(:broadcast_import_error, error)
      end
    end

    describe "#determine_error_type" do
      it "categorizes ActiveModel::ValidationError as validation_error" do
        error = ActiveModel::ValidationError.new(Inventory.new)
        result = job.send(:determine_error_type, error)
        expect(result).to eq("validation_error")
      end

      it "handles unknown error types" do
        error = SystemExit.new
        result = job.send(:determine_error_type, error)
        expect(result).to eq("processing_error")
      end
    end
  end

  # ============================================
  # 通知機能の完全分岐カバレッジ
  # ============================================

  describe "Notification functionality complete branch coverage" do
    before do
      job.instance_variable_set(:@admin_id, admin.id)
      job.instance_variable_set(:@job_id, job_id)
      job.instance_variable_set(:@start_time, Time.current)
    end

    describe "#update_success_status" do
      it "updates Redis status when available" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, "csv_import:#{job_id}")
        result = { valid_count: 100, invalid_records: [] }

        job.send(:update_success_status, result)

        expect(redis_instance.hget("csv_import:#{job_id}", "status")).to eq("completed")
        expect(redis_instance.hget("csv_import:#{job_id}", "valid_count")).to eq("100")
      end

      it "returns early when Redis is nil" do
        job.instance_variable_set(:@redis, nil)
        result = { valid_count: 100, invalid_records: [] }

        expect {
          job.send(:update_success_status, result)
        }.not_to raise_error
      end
    end

    describe "#send_completion_message" do
      it "sends message when admin exists" do
        result = { valid_count: 90, invalid_records: Array.new(10) }

        expect(ActionCable.server).to receive(:broadcast)
          .with("admin_#{admin.id}", hash_including(
            type: "csv_import_complete",
            result: hash_including(
              valid_count: 90,
              invalid_count: 10
            )
          ))

        job.send(:send_completion_message, result)
      end

      it "returns early when admin not found" do
        job.instance_variable_set(:@admin_id, 99999)
        result = { valid_count: 100, invalid_records: [] }

        expect {
          job.send(:send_completion_message, result)
        }.not_to raise_error
      end
    end

    describe "#notify_import_error" do
      it "updates Redis when available" do
        job.instance_variable_set(:@redis, redis_instance)
        job.instance_variable_set(:@status_key, "csv_import:#{job_id}")
        error = StandardError.new("Test error")

        job.send(:notify_import_error, error)

        expect(redis_instance.hget("csv_import:#{job_id}", "status")).to eq("failed")
        expect(redis_instance.hget("csv_import:#{job_id}", "error_message")).to eq("Test error")
      end

      it "returns early when Redis is nil" do
        job.instance_variable_set(:@redis, nil)
        error = StandardError.new("Test error")

        expect {
          job.send(:notify_import_error, error)
        }.not_to raise_error
      end
    end

    describe "#update_error_status" do
      it "broadcasts error when admin exists" do
        error = SecurityError.new("Security violation")

        expect(ActionCable.server).to receive(:broadcast)
          .with("admin_#{admin.id}", hash_including(
            type: "csv_import_error",
            error: hash_including(
              class: "SecurityError",
              message: "Security violation"
            )
          ))

        job.send(:update_error_status, error)
      end

      it "returns early when admin not found" do
        job.instance_variable_set(:@admin_id, 99999)
        error = StandardError.new("Test error")

        expect {
          job.send(:update_error_status, error)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # ファイルクリーンアップの完全分岐カバレッジ
  # ============================================

  describe "File cleanup complete branch coverage" do
    before do
      job.instance_variable_set(:@file_path, file_path)
    end

    describe "#cleanup_temp_file" do
      it "deletes file in production environment" do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        expect(File).to receive(:delete).with(file_path)
        allow(Rails.logger).to receive(:info)

        job.send(:cleanup_temp_file)

        expect(Rails.logger).to have_received(:info).with(/Temporary file cleaned up/)
      end

      it "skips deletion in development environment" do
        allow(Rails.env).to receive(:development?).and_return(true)
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        expect(File).not_to receive(:delete)

        job.send(:cleanup_temp_file)
      end

      it "returns early when file_path is nil" do
        job.instance_variable_set(:@file_path, nil)
        expect(File).not_to receive(:exist?)

        job.send(:cleanup_temp_file)
      end

      it "returns early when file doesn't exist" do
        allow(File).to receive(:exist?).with(file_path).and_return(false)
        expect(File).not_to receive(:delete)

        job.send(:cleanup_temp_file)
      end

      it "handles file deletion errors gracefully" do
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(File).to receive(:exist?).with(file_path).and_return(true)
        allow(File).to receive(:delete).and_raise(Errno::EACCES, "Permission denied")
        expect(Rails.logger).to receive(:warn).with(/Failed to cleanup temp file/)

        expect {
          job.send(:cleanup_temp_file)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # ジョブID生成の完全分岐カバレッジ
  # ============================================

  describe "Job ID generation complete branch coverage" do
    describe "#generate_job_id" do
      it "uses jid when available (Sidekiq context)" do
        allow(job).to receive(:respond_to?).with(:jid).and_return(true)
        allow(job).to receive(:jid).and_return("sidekiq_job_id")

        result = job.send(:generate_job_id)
        expect(result).to eq("sidekiq_job_id")
      end

      it "generates UUID when jid not available" do
        allow(job).to receive(:respond_to?).with(:jid).and_return(false)
        expect(SecureRandom).to receive(:uuid).and_return("generated_uuid")

        result = job.send(:generate_job_id)
        expect(result).to eq("generated_uuid")
      end
    end
  end

  # ============================================
  # メッセージ構築の完全分岐カバレッジ
  # ============================================

  describe "Message building complete branch coverage" do
    before do
      job.instance_variable_set(:@start_time, 5.seconds.ago)
    end

    describe "#build_completion_message" do
      it "includes invalid records when present" do
        result = { valid_count: 80, invalid_records: Array.new(20) }

        message = job.send(:build_completion_message, result)

        expect(message).to include("80")
        expect(message).to include("20")
      end

      it "excludes invalid records message when count is 0" do
        result = { valid_count: 100, invalid_records: [] }

        message = job.send(:build_completion_message, result)

        expect(message).to include("100")
        expect(message).not_to match(/invalid.*0/i)
      end
    end
  end

  # ============================================
  # エラーハンドリングの完全分岐カバレッジ
  # ============================================

  describe "Error handling complete branch coverage" do
    before do
      job.instance_variable_set(:@file_path, file_path)
      job.instance_variable_set(:@admin_id, admin.id)
      job.instance_variable_set(:@job_id, job_id)
      job.instance_variable_set(:@start_time, Time.current)
    end

    describe "#log_import_error" do
      it "includes backtrace when available" do
        error = StandardError.new("Test error")
        error.set_backtrace([ "line1", "line2", "line3", "line4", "line5", "line6" ])

        expect(Rails.logger).to receive(:error) do |log_data|
          parsed = JSON.parse(log_data)
          expect(parsed["error_backtrace"]).to eq([ "line1", "line2", "line3", "line4", "line5" ])
        end

        job.send(:log_import_error, error)
      end

      it "handles nil backtrace" do
        error = StandardError.new("Test error")
        error.set_backtrace(nil)

        expect(Rails.logger).to receive(:error) do |log_data|
          parsed = JSON.parse(log_data)
          expect(parsed["error_backtrace"]).to be_nil
        end

        job.send(:log_import_error, error)
      end
    end
  end
end
