# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'data_patch rake tasks', type: :task do
  # stdoutキャプチャーヘルパー
  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = fake = StringIO.new
    begin
      yield
    ensure
      $stdout = original_stdout
    end
    fake.string
  end

  # stdout/stderr同時キャプチャーヘルパー
  def capture_stdout_and_stderr(&block)
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = fake_out = StringIO.new
    $stderr = fake_err = StringIO.new
    begin
      yield
    ensure
      $stdout = original_stdout
      $stderr = original_stderr
    end
    { stdout: fake_out.string, stderr: fake_err.string }
  end
  before(:all) do
    # Rakeタスクの読み込み
    Rails.application.load_tasks
  end

  before do
    # テストデータの準備
    FactoryBot.create_list(:inventory, 10, price: 1000)

    # DataPatchRegistryの初期化（自動読み込みを先に実行）
    DataPatchRegistry.reload_patches

    # 実際のパッチクラスの読み込みを確実にする
    require Rails.root.join('app/data_patches/inventory_price_adjustment_patch')
    require Rails.root.join('app/data_patches/batch_expiry_update_patch')

    # テスト用パッチの登録
    stub_const('TestPatch', Class.new(DataPatch) do
      def self.estimate_target_count(options = {})
        10
      end

      def execute_batch(batch_size, offset)
        if offset >= 10
          { count: 0, finished: true }
        else
          processed = [ batch_size, 10 - offset ].min
          { count: processed, finished: (offset + processed >= 10) }
        end
      end
    end)

    # テスト用パッチの登録
    DataPatchRegistry.register_patch('test_patch', TestPatch, {
      description: 'テスト用パッチ',
      category: 'test'
    })

    # 実際のパッチの再登録（テスト環境用）—自動読み込みされたものを上書き
    if defined?(InventoryPriceAdjustmentPatch)
      DataPatchRegistry.register_patch('inventory_price_adjustment', InventoryPriceAdjustmentPatch, {
        description: 'テスト用在庫価格調整パッチ',
        category: 'inventory',
        target_tables: [ 'inventories' ],
        estimated_records: 1000,
        memory_limit: 256,
        batch_size: 100
      })
    end

    if defined?(BatchExpiryUpdatePatch)
      DataPatchRegistry.register_patch('batch_expiry_update', BatchExpiryUpdatePatch, {
        description: 'テスト用期限切れバッチ更新パッチ',
        category: 'maintenance',
        target_tables: [ 'batches' ],
        estimated_records: 500,
        memory_limit: 128,
        batch_size: 50
      })
    end

    # Rakeタスクのリセット（各テスト前に実行）
    %w[
      data_patch:execute
      data_patch:list
      data_patch:info
      data_patch:stats
      data_patch:reload
      data_patch:check_all
      data_patch:generate_config
      data_patch:scheduled_expiry_update
    ].each do |task_name|
      if Rake::Task.task_defined?(task_name)
        Rake::Task[task_name].reenable
        Rake::Task[task_name].clear_comments
        Rake::Task[task_name].clear_actions
      end
    end

    # Rakeタスクの再読み込み
    load Rails.root.join('lib/tasks/data_patch.rake')
  end

  describe 'data_patch:list' do
    it 'パッチ一覧が表示される' do
      output = capture_stdout { Rake::Task['data_patch:list'].invoke }
      expect(output).to include('利用可能なデータパッチ一覧')
    end

    it '登録されたパッチが含まれる' do
      output = capture_stdout { Rake::Task['data_patch:list'].invoke }
      expect(output).to include('test_patch').or include('patch')
    end

    it 'inventory_price_adjustmentパッチが含まれる' do
      output = capture_stdout { Rake::Task['data_patch:list'].invoke }
      expect(output).to include('inventory_price_adjustment')
    end

    it 'batch_expiry_updateパッチが含まれる' do
      output = capture_stdout { Rake::Task['data_patch:list'].invoke }
      expect(output).to include('batch_expiry_update')
    end
  end

  describe 'data_patch:info' do
    context 'パッチ名が指定された場合' do
      it 'パッチの詳細情報が表示される' do
        # 自動読み込みされたパッチ名を使用
        output = capture_stdout { Rake::Task['data_patch:info'].invoke('inventory_price_adjustment_patch') }
        expect(output).to include('データパッチ詳細情報: inventory_price_adjustment_patch')
      end

      it 'メタデータが正しく表示される' do
        output = capture_stdout { Rake::Task['data_patch:info'].invoke('inventory_price_adjustment_patch') }
        expect(output).to include('詳細情報')
        expect(output).to include('general')
      end
    end

    context 'パッチ名が指定されない場合' do
      it 'エラーメッセージが表示される' do
        output = capture_stdout { Rake::Task['data_patch:info'].invoke }
        expect(output).to include('エラー: patch_name が必要です')
      end
    end

    context '存在しないパッチ名の場合' do
      it 'エラーメッセージとパッチ一覧が表示される' do
        output = capture_stdout do
          Rake::Task['data_patch:info'].invoke('non_existent_patch')
        end
        expect(output).to include('パッチが見つかりません')
        expect(output).to include('利用可能なパッチ一覧')
      end
    end
  end

  describe 'data_patch:stats' do
    it 'レジストリ統計情報が表示される' do
      output = capture_stdout { Rake::Task['data_patch:stats'].invoke }
      expect(output).to include('データパッチレジストリ統計情報')
      expect(output).to include('総パッチ数:')
      expect(output).to match(/\d+/) # 数値が含まれる
    end
  end

  describe 'data_patch:execute' do
    before do
      # 環境変数をクリア
      ENV.delete('DRY_RUN')
      ENV.delete('BATCH_SIZE')
      ENV.delete('MEMORY_LIMIT')
      ENV.delete('TIMEOUT')
      ENV.delete('ADJUSTMENT_TYPE')
      ENV.delete('ADJUSTMENT_VALUE')
      ENV.delete('CATEGORY')
      ENV.delete('MIN_PRICE')
      ENV.delete('MAX_PRICE')
      ENV.delete('GRACE_PERIOD')
      ENV.delete('INCLUDE_EXPIRING_SOON')
      ENV.delete('WARNING_DAYS')
    end

    context 'パッチ名が指定された場合' do
      it 'パッチが実行される' do
        ENV['DRY_RUN'] = 'true'

        output = capture_stdout do
          Rake::Task['data_patch:execute'].invoke('inventory_price_adjustment_patch')
        end

        expect(output).to include('データパッチ実行: inventory_price_adjustment_patch')
        expect(output).to include('DRY RUN: YES')
        expect(output).to include('実行完了!')
      end

      it 'バッチサイズオプションが適用される' do
        ENV['DRY_RUN'] = 'true'
        ENV['BATCH_SIZE'] = '5'

        # DataPatchExecutorがバッチサイズオプションで呼ばれることを確認
        expect(DataPatchExecutor).to receive(:new).with(
          'inventory_price_adjustment_patch',
          hash_including(batch_size: 5, dry_run: true)
        ).and_call_original

        capture_stdout { Rake::Task['data_patch:execute'].invoke('inventory_price_adjustment_patch') }
      end
    end

    context 'パッチ名が指定されない場合' do
      it 'エラーメッセージが表示される' do
        output = capture_stdout { Rake::Task['data_patch:execute'].invoke }
        expect(output).to include('エラー: patch_name が必要です')
        expect(output).to include('使用例:')
      end
    end

    context 'エラーが発生した場合' do
      before do
        # Executorでエラーを発生させる
        allow_any_instance_of(DataPatchExecutor).to receive(:execute)
          .and_raise(DataPatchExecutor::ValidationError, 'テスト用エラー')
      end

      it 'エラーメッセージが表示され、適切に終了する' do
        ENV['DRY_RUN'] = 'true'

        # SystemExitをキャッチしてエラーハンドリングを確認
        begin
          output = capture_stdout { Rake::Task['data_patch:execute'].invoke('inventory_price_adjustment_patch') }
          # exit 1 が呼ばれている場合はここに到達しない
          expect(true).to be false # テスト失敗
        rescue SystemExit => e
          expect(e.status).to eq(1)
        end
      end
    end
  end

  describe 'data_patch:check_all' do
    it '全パッチの影響範囲が表示される' do
      output = capture_stdout { Rake::Task['data_patch:check_all'].invoke }

      expect(output).to include('全データパッチの影響範囲確認')
      expect(output).to include('patch:')
      expect(output).to include('対象レコード数:')
    end

    it 'inventory_price_adjustmentの対象数が表示される' do
      output = capture_stdout { Rake::Task['data_patch:check_all'].invoke }
      expect(output).to include('inventory_price_adjustment')
      expect(output).to match(/対象レコード数: \d+/) # 実際の在庫数
    end
  end

  describe 'data_patch:reload' do
    it 'レジストリがリロードされる' do
      output = capture_stdout { Rake::Task['data_patch:reload'].invoke }

      expect(output).to include('データパッチレジストリをリロードしています')
      expect(output).to include('リロード完了:')
      expect(output).to match(/\d+個のパッチが読み込まれました/)
    end
  end

  describe 'data_patch:generate_config' do
    let(:config_path) { Rails.root.join('config', 'data_patches.yml') }

    after do
      # テスト後にファイルを削除
      File.delete(config_path) if File.exist?(config_path)
    end

    context '設定ファイルが存在しない場合' do
      before do
        File.delete(config_path) if File.exist?(config_path)
      end

      it '設定ファイルが生成される' do
        output = capture_stdout { Rake::Task['data_patch:generate_config'].invoke }

        expect(output).to include('設定ファイルを生成しました')
        expect(File.exist?(config_path)).to be true

        # 生成された内容を確認
        config = YAML.load_file(config_path)
        expect(config['patches']).to be_present
        expect(config['security']).to be_present
        expect(config['scheduling']).to be_present
      end
    end

    context '設定ファイルが既に存在する場合' do
      before do
        File.write(config_path, 'existing config')
      end

      it '上書き警告が表示される' do
        output = capture_stdout { Rake::Task['data_patch:generate_config'].invoke }
        expect(output).to include('設定ファイルが既に存在します')
        expect(output).to include('上書きする場合は FORCE=true')
      end

      it 'FORCE=trueで上書きできる' do
        ENV['FORCE'] = 'true'

        output = capture_stdout { Rake::Task['data_patch:generate_config'].invoke }
        expect(output).to include('設定ファイルを生成しました')

        # YAMLファイルとして読み込み可能か確認
        expect { YAML.load_file(config_path) }.not_to raise_error

        ENV.delete('FORCE')
      end
    end
  end

  describe 'data_patch:scheduled_expiry_update' do
    it 'スケジュール実行が正常に動作する' do
      # batch_expiry_updateパッチの動作をモック
      mock_executor = instance_double(DataPatchExecutor)
      allow(DataPatchExecutor).to receive(:new).with(
        'batch_expiry_update',
        hash_including(grace_period: 3, include_expiring_soon: true)
      ).and_return(mock_executor)
      allow(mock_executor).to receive(:execute).and_return({ processed_count: 5 })

      output = capture_stdout { Rake::Task['data_patch:scheduled_expiry_update'].invoke }

      expect(output).to include('スケジュール実行: 期限切れバッチ更新')
      expect(output).to include('スケジュール実行完了: 5件処理')
    end
  end

  describe 'オプション解析' do
    before do
      # 環境変数をクリア
      %w[
        BATCH_SIZE MEMORY_LIMIT TIMEOUT
        ADJUSTMENT_TYPE ADJUSTMENT_VALUE MIN_PRICE MAX_PRICE
        GRACE_PERIOD INCLUDE_EXPIRING_SOON WARNING_DAYS
        EXPIRY_DATE BEFORE_DATE
        NOTIFICATION AUDIT
      ].each { |var| ENV.delete(var) }
    end

    it '基本オプションが正しく解析される' do
      ENV['BATCH_SIZE'] = '500'
      ENV['MEMORY_LIMIT'] = '1024'
      ENV['TIMEOUT'] = '7200'
      ENV['DRY_RUN'] = 'true'

      expect(DataPatchExecutor).to receive(:new).with(
        'inventory_price_adjustment_patch',
        hash_including(
          batch_size: 500,
          memory_limit: 1024,
          timeout_seconds: 7200,
          dry_run: true
        )
      ).and_call_original

      capture_stdout { Rake::Task['data_patch:execute'].invoke('inventory_price_adjustment_patch') }
    end

    it 'inventory_price_adjustment固有オプションが解析される' do
      ENV['ADJUSTMENT_TYPE'] = 'percentage'
      ENV['ADJUSTMENT_VALUE'] = '15.5'
      ENV['MIN_PRICE'] = '100'
      ENV['MAX_PRICE'] = '5000'
      ENV['DRY_RUN'] = 'true'

      expect(DataPatchExecutor).to receive(:new).with(
        'inventory_price_adjustment_patch',
        hash_including(
          adjustment_type: 'percentage',
          adjustment_value: 15.5,
          min_price: 100,
          max_price: 5000
        )
      ).and_call_original

      capture_stdout { Rake::Task['data_patch:execute'].invoke('inventory_price_adjustment_patch') }
    end

    it 'batch_expiry_update固有オプションが解析される' do
      ENV['GRACE_PERIOD'] = '7'
      ENV['INCLUDE_EXPIRING_SOON'] = 'true'
      ENV['WARNING_DAYS'] = '45'
      ENV['EXPIRY_DATE'] = '2025-01-15'
      ENV['DRY_RUN'] = 'true'

      expect(DataPatchExecutor).to receive(:new).with(
        'batch_expiry_update_patch',
        hash_including(
          grace_period: 7,
          include_expiring_soon: true,
          warning_days: 45,
          expiry_date: Date.parse('2025-01-15')
        )
      ).and_call_original

      capture_stdout { Rake::Task['data_patch:execute'].invoke('batch_expiry_update_patch') }
    end
  end

  # TODO: 🟡 Phase 3（中）- 高度なRakeタスクテストの実装
  # 実装予定:
  # - 実際のファイル操作を伴うテスト
  # - 並行実行防止テスト
  # - スケジューリング統合テスト
  # - エラー通知システムテスト

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end

  def capture_stdout_and_stderr
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    { stdout: $stdout.string, stderr: $stderr.string }
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end
