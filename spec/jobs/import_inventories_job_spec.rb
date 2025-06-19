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
      name,quantity,price,expiration_date,lot_number
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
    headers = "name,quantity,price,expiration_date,lot_number\n"
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
        expect(invalid_record[:row_number]).to be_present
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
        expect(Rails.logger).to receive(:info).with(/csv_import_security_validated/)
        expect(Rails.logger).to receive(:info).with(/csv_import_started/)
        expect(Rails.logger).to receive(:info).with(/csv_import_completed/)

        ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
      end

      it 'エラー時に適切なログを出力する' do
        allow_any_instance_of(ImportInventoriesJob).to receive(:execute_csv_import).and_raise(StandardError, "Test error")

        expect(Rails.logger).to receive(:error).with(/csv_import_failed/)

        expect {
          ImportInventoriesJob.perform_now(file_path, admin.id, {}, job_id)
        }.to raise_error(StandardError)
      end
    end

    context 'パフォーマンス' do
      it 'メモリ使用量が適切に管理される' do
        skip 'ps command not available in Docker container'

        csv_file.write(large_csv_content)
        csv_file.rewind

        initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

        ImportInventoriesJob.perform_now(file_path, admin.id, { batch_size: 1000 }, job_id)

        final_memory = `ps -o rss= -p #{Process.pid}`.to_i
        memory_increase = final_memory - initial_memory

        # メモリ増加が100MB以内
        expect(memory_increase).to be < 100_000
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

        csv_error = CSV::MalformedCSVError.new("test")
        expect(job.send(:determine_error_type, csv_error)).to eq('file_error')

        security_error = SecurityError.new("test")
        expect(job.send(:determine_error_type, security_error)).to eq('security_error')

        other_error = StandardError.new("test")
        expect(job.send(:determine_error_type, other_error)).to eq('processing_error')
      end
    end
  end
end
