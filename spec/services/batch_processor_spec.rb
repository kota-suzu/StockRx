# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BatchProcessor, type: :service do
  let(:options) { { batch_size: 10, memory_limit: 100 } }
  let(:processor) { described_class.new(options) }

  describe '#initialize' do
    it '正しいオプションで初期化される' do
      expect(processor.batch_size).to eq(10)
      expect(processor.memory_limit).to eq(100)
      expect(processor.processed_count).to eq(0)
      expect(processor.batch_count).to eq(0)
    end

    context '無効なオプションの場合' do
      it 'batch_sizeが0以下の場合はエラー' do
        expect { described_class.new(batch_size: 0) }
          .to raise_error(ArgumentError, /batch_sizeは正の整数である必要があります/)
      end

      it 'memory_limitが0以下の場合はエラー' do
        expect { described_class.new(memory_limit: 0) }
          .to raise_error(ArgumentError, /memory_limitは正の数値である必要があります/)
      end
    end
  end

  describe '#process_with_monitoring' do
    let(:test_data) { Array.new(25) { |i| "item_#{i}" } }

    context '正常な処理の場合' do
      it 'バッチ処理が正常に実行される' do
        processed_items = []

        result = processor.process_with_monitoring do |batch_size, offset|
          batch = test_data[offset, batch_size]
          next [] if batch.empty?

          processed_items.concat(batch)
          batch
        end

        expect(result[:success]).to be true
        expect(processed_items.size).to eq(25)
        expect(processor.processed_count).to eq(25)
        expect(processor.batch_count).to eq(3) # 10, 10, 5のバッチ
      end

      it '統計情報が正しく計算される' do
        # 少し時間がかかる処理をシミュレート
        processor.process_with_monitoring do |batch_size, offset|
          sleep(0.01) # 10ms待機
          batch = test_data[offset, batch_size]
          next [] if batch.empty?
          batch
        end

        stats = processor.processing_statistics
        expect(stats[:processed_count]).to eq(25)
        expect(stats[:batch_count]).to eq(3)
        expect(stats[:processing_rate]).to be > 0
        expect(stats[:elapsed_time]).to be > 0
      end
    end

    context 'メモリ制限を超過する場合' do
      before do
        allow(processor).to receive(:current_memory_usage).and_return(150) # 制限の100MBを超過
      end

      it 'MemoryLimitExceededErrorが発生する' do
        expect do
          processor.process_with_monitoring do |batch_size, offset|
            test_data[offset, batch_size] || []
          end
        end.to raise_error(BatchProcessor::MemoryLimitExceededError)
      end
    end

    context 'タイムアウトが発生する場合' do
      let(:options) { { batch_size: 10, timeout_seconds: 0.1 } }

      it 'ProcessingTimeoutErrorが発生する' do
        expect do
          processor.process_with_monitoring do |batch_size, offset|
            sleep(0.2) # タイムアウト時間を超過
            test_data[offset, batch_size] || []
          end
        end.to raise_error(BatchProcessor::ProcessingTimeoutError)
      end
    end

    context 'ブロックが渡されない場合' do
      it 'ArgumentErrorが発生する' do
        expect { processor.process_with_monitoring }
          .to raise_error(ArgumentError, /ブロックが必要です/)
      end
    end
  end

  describe '#process_with_custom_control' do
    let(:test_data) { Array.new(30) { |i| "item_#{i}" } }

    context '動的バッチサイズの場合' do
      it 'カスタムバッチサイズ計算が適用される' do
        dynamic_batch_size = ->(processed_count) { processed_count < 10 ? 5 : 15 }

        batch_sizes = []
        processor.process_with_custom_control(dynamic_batch_size: dynamic_batch_size) do |batch_size, offset|
          batch_sizes << batch_size
          batch = test_data[offset, batch_size]
          next [] if batch.empty?
          batch
        end

        expect(batch_sizes).to include(5) # 初期の小さいバッチサイズ
        expect(batch_sizes).to include(15) # 後の大きいバッチサイズ
      end
    end

    context 'メモリ適応モードの場合' do
      let(:options) { { batch_size: 20, memory_limit: 100 } }

      before do
        # メモリ使用量をシミュレート（徐々に増加）
        call_count = 0
        allow(processor).to receive(:current_memory_usage) do
          call_count += 1
          50 + (call_count * 10) # 50, 60, 70, 80MB...
        end
      end

      it 'メモリ使用量に応じてバッチサイズが調整される' do
        batch_sizes = []
        call_count = 0

        # メモリ制限チェックを一時的に無効化
        allow(processor).to receive(:check_memory_usage)

        # メモリ使用量を段階的に増加させる
        allow(processor).to receive(:current_memory_usage) do
          call_count += 1
          case call_count
          when 1..2 then 40.0  # 40% - 通常サイズ
          when 3..4 then 60.0  # 60% - 80%サイズ
          else 85.0           # 85% - 50%サイズ
          end
        end

        processor.process_with_custom_control(memory_adaptive: true) do |batch_size, offset|
          batch_sizes << batch_size
          batch = test_data[offset, batch_size]
          next [] if batch.empty?
          batch
        end

        # メモリ使用量増加に伴ってバッチサイズが小さくなることを確認
        expect(batch_sizes).to include(20) # 通常サイズ
        expect(batch_sizes).to include(16) # 80%サイズ
        expect(batch_sizes).to include(10) # 50%サイズ
      end
    end
  end

  describe '#current_memory_usage' do
    context 'GetProcessMemが利用可能な場合' do
      before do
        # GetProcessMemクラスを定義してモック
        process_mem_instance = double('GetProcessMemInstance')
        allow(process_mem_instance).to receive(:mb).and_return(256.5)

        get_process_mem_class = Class.new do
          define_singleton_method(:new) { process_mem_instance }
        end

        stub_const('GetProcessMem', get_process_mem_class)
      end

      it '正確なメモリ使用量が返される' do
        expect(processor.current_memory_usage).to eq(256.5)
      end
    end

    context 'GetProcessMemが利用できない場合' do
      before do
        # GetProcessMemを未定義状態にする
        hide_const('GetProcessMem') if defined?(GetProcessMem)
      end

      it 'フォールバック推定値が返される' do
        memory_usage = processor.current_memory_usage
        expect(memory_usage).to be_a(Numeric)
        expect(memory_usage).to be > 0
      end
    end
  end

  describe 'ガベージコレクション' do
    it 'GC実行後にメモリ解放がログ出力される' do
      expect(Rails.logger).to receive(:debug).with(/GC実行/)
      processor.send(:perform_gc)
    end

    it '緊急GC実行時は適切に処理される' do
      expect(Rails.logger).to receive(:warn).with(/緊急GC実行/)
      processor.send(:perform_emergency_gc)
    end
  end

  describe '適応的バッチサイズ計算' do
    let(:processor) { described_class.new(batch_size: 1000, memory_limit: 100) }

    it 'メモリ使用量50%未満では通常サイズ' do
      allow(processor).to receive(:current_memory_usage).and_return(40.0)
      expect(processor.send(:calculate_adaptive_batch_size)).to eq(1000)
    end

    it 'メモリ使用量50-70%では20%削減' do
      allow(processor).to receive(:current_memory_usage).and_return(60.0)
      expect(processor.send(:calculate_adaptive_batch_size)).to eq(800)
    end

    it 'メモリ使用量70-90%では50%削減' do
      allow(processor).to receive(:current_memory_usage).and_return(80.0)
      expect(processor.send(:calculate_adaptive_batch_size)).to eq(500)
    end

    it 'メモリ使用量90%超では最小サイズ' do
      allow(processor).to receive(:current_memory_usage).and_return(95.0)
      expect(processor.send(:calculate_adaptive_batch_size)).to eq(250)
    end
  end

  describe '終了条件判定' do
    it 'Array型の場合は空配列で終了' do
      expect(processor.send(:batch_finished?, [])).to be true
      expect(processor.send(:batch_finished?, [ 1, 2, 3 ])).to be false
    end

    it 'Hash型の場合はcountが0で終了' do
      expect(processor.send(:batch_finished?, { count: 0 })).to be true
      expect(processor.send(:batch_finished?, { count: 5 })).to be false
      expect(processor.send(:batch_finished?, { finished: true })).to be true
    end

    it 'Integer型の場合は0で終了' do
      expect(processor.send(:batch_finished?, 0)).to be true
      expect(processor.send(:batch_finished?, 5)).to be false
    end
  end

  describe 'エラーハンドリング' do
    it '処理中のエラーが適切にログ出力される' do
      # より具体的なログメッセージをチェック
      expect(Rails.logger).to receive(:error).with(/バッチ処理エラー: StandardError - テストエラー/)
      expect(Rails.logger).to receive(:error).with(/処理済み件数: 0件/)
      expect(Rails.logger).to receive(:error).with(/実行バッチ数: 0バッチ/)

      expect do
        processor.process_with_monitoring do |batch_size, offset|
          raise StandardError, 'テストエラー'
        end
      end.to raise_error(StandardError, 'テストエラー')
    end
  end

  # TODO: 🟡 Phase 3（中）- パフォーマンス最適化テストの実装
  # 実装予定:
  # - 大量データでのメモリ効率テスト
  # - 長時間実行での安定性テスト
  # - 異なるデータパターンでの性能テスト
  # - GC効率の最適化テスト

  describe 'パフォーマンスベンチマーク' do
    it '1万件処理が適切な時間で完了する', :performance do
      large_data = Array.new(10000) { |i| "item_#{i}" }

      start_time = Time.current
      processor.process_with_monitoring do |batch_size, offset|
        batch = large_data[offset, batch_size]
        next [] if batch.empty?
        batch
      end
      execution_time = Time.current - start_time

      expect(execution_time).to be < 2.0 # 2秒以内で完了
      expect(processor.processed_count).to eq(10000)
    end
  end
end
