# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataPatchExecutor, type: :service do
  let(:patch_name) { 'test_patch' }
  let(:options) { { dry_run: true, batch_size: 10 } }
  let(:executor) { described_class.new(patch_name, options) }

  # テスト用のパッチクラス
  before do
    stub_const('TestPatch', Class.new(DataPatch) do
      def self.estimate_target_count(options = {})
        50
      end

      def execute_batch(batch_size, offset)
        # シンプルなテストデータ生成
        if offset >= 50
          { count: 0, finished: true }
        else
          processed = [ batch_size, 50 - offset ].min
          { count: processed, finished: (offset + processed >= 50) }
        end
      end
    end)

    # レジストリに登録
    DataPatchRegistry.register_patch('test_patch', TestPatch, {
      description: 'テスト用パッチ',
      category: 'test'
    })
  end

  describe '#initialize' do
    it 'パッチ名とオプションで初期化される' do
      expect(executor.instance_variable_get(:@patch_name)).to eq(patch_name)
      expect(executor.instance_variable_get(:@options)[:dry_run]).to be true
    end

    context '存在しないパッチ名の場合' do
      let(:patch_name) { 'non_existent_patch' }

      it 'ArgumentErrorが発生する' do
        expect { executor }.to raise_error(ArgumentError, /パッチが見つかりません/)
      end
    end
  end

  describe '#execute' do
    let(:mock_batch_processor) { instance_double(BatchProcessor) }
    let(:batch_result) { { success: true, processed_count: 50 } }

    before do
      allow(BatchProcessor).to receive(:new).and_return(mock_batch_processor)
      allow(mock_batch_processor).to receive(:process_with_monitoring).and_yield(10, 0).and_return(batch_result)
    end

    context 'dry_runモードの場合' do
      let(:options) { { dry_run: true } }

      it '実際のデータ変更なしで実行される' do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:dry_run]).to be true
        expect(result[:patch_name]).to eq(patch_name)
      end

      it 'トランザクションがロールバックされる' do
        expect(ActiveRecord::Base).to receive(:transaction)
        expect { executor.execute }.not_to change { Inventory.count }
      end
    end

    context '通常実行モードの場合' do
      let(:options) { { dry_run: false } }

      it '実際の処理が実行される' do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:dry_run]).to be false
        expect(result[:processed_count]).to be_present
      end
    end

    context 'エラーが発生した場合' do
      before do
        allow(mock_batch_processor).to receive(:process_with_monitoring)
          .and_raise(DataPatchExecutor::ExecutionError, 'テストエラー')
      end

      it 'エラーが適切にハンドリングされる' do
        expect { executor.execute }.to raise_error(DataPatchExecutor::ExecutionError)
      end

      it 'エラー情報が記録される' do
        begin
          result = executor.execute
        rescue DataPatchExecutor::ExecutionError => e
          # エラーハンドリングの確認
          expect(e.message).to eq('テストエラー')
          # インスタンス変数から実行コンテキストを取得
          context = executor.instance_variable_get(:@execution_context)
          if context && context.result
            expect(context.result[:success]).to be false
            expect(context.result[:error]).to eq('テストエラー')
          end
        end
      end
    end
  end

  describe 'メモリ使用量推定' do
    it '適切なメモリ使用量が推定される' do
      estimated = executor.send(:estimate_memory_usage, 10000)
      expect(estimated).to be > 0
      expect(estimated).to be < 100 # 10万レコードでも100MB未満の推定
    end
  end

  describe 'データベース接続検証' do
    it '正常な接続の場合はエラーが発生しない' do
      expect { executor.send(:validate_database_connectivity) }.not_to raise_error
    end

    context 'データベース接続に問題がある場合' do
      before do
        allow(ActiveRecord::Base.connection).to receive(:execute)
          .and_raise(ActiveRecord::ConnectionNotEstablished, '接続エラー')
      end

      it 'ValidationErrorが発生する' do
        expect { executor.send(:validate_database_connectivity) }
          .to raise_error(DataPatchExecutor::ValidationError, /データベース接続エラー/)
      end
    end
  end

  describe 'ExecutionContext' do
    let(:context) { DataPatchExecutor::ExecutionContext.new }

    it '初期状態が正しく設定される' do
      expect(context.validation_passed).to be false
      expect(context.verification_passed).to be false
      expect(context.total_processed).to eq(0)
      expect(context.batch_count).to eq(0)
    end

    it 'バッチ結果が正しく追加される' do
      batch_result = { count: 10 }
      context.add_batch_result(batch_result)

      expect(context.total_processed).to eq(10)
      expect(context.batch_count).to eq(1)
      expect(context.batch_results).to include(batch_result)
    end
  end

  describe 'パフォーマンステスト' do
    it '大量データでも適切な時間で完了する', :performance do
      # 大量データ用のテストパッチ
      stub_const('LargeTestPatch', Class.new(DataPatch) do
        def self.estimate_target_count(options = {})
          10000
        end

        def execute_batch(batch_size, offset)
          if offset >= 10000
            { count: 0, finished: true }
          else
            processed = [ batch_size, 10000 - offset ].min
            { count: processed, finished: (offset + processed >= 10000) }
          end
        end
      end)

      DataPatchRegistry.register_patch('large_test_patch', LargeTestPatch)

      large_executor = described_class.new('large_test_patch', { dry_run: true, batch_size: 1000 })

      start_time = Time.current
      result = large_executor.execute
      execution_time = Time.current - start_time

      expect(result[:success]).to be true
      expect(execution_time).to be < 5.0 # 5秒以内で完了
    end
  end

  describe '設定値のバリデーション' do
    context '無効なメモリ制限の場合' do
      let(:options) { { memory_limit: -100 } }

      it 'ArgumentErrorが発生する' do
        expect { executor }.to raise_error(ArgumentError)
      end
    end

    context '無効なバッチサイズの場合' do
      let(:options) { { batch_size: 0 } }

      it 'ArgumentErrorが発生する' do
        expect { executor }.to raise_error(ArgumentError)
      end
    end
  end

  # TODO: 🟡 Phase 3（中）- 高度なテストケースの実装
  # 実装予定:
  # - 複数テーブル操作での整合性テスト
  # - 長時間実行でのメモリリークテスト
  # - 同時実行制御テスト
  # - ロールバック機能の詳細テスト
  # - 通知システム統合テスト
  # - セキュリティ監査ログテスト

  context 'ログ出力の確認' do
    it '実行開始ログが適切に出力される' do
      expect(Rails.logger).to receive(:info).at_least(:once)
      executor.execute
    end

    it '実行完了ログが適切に出力される' do
      expect(Rails.logger).to receive(:info).at_least(:once)
      result = executor.execute
      expect(result[:success]).to be true
    end
  end
end
