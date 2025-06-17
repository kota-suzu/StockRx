# frozen_string_literal: true

require 'rails_helper'

# パフォーマンス監視システムテスト
# ============================================
# パフォーマンス監視機能の動作検証
# N+1クエリ再発防止・メモリ監視・レスポンス時間測定
# ============================================
RSpec.describe PerformanceMonitoring, type: :model do
  describe 'MemoryMonitor' do
    let(:monitor) { PerformanceMonitoring::MemoryMonitor }

    describe '.current_memory_usage' do
      it 'メモリ使用量を取得できること' do
        usage = monitor.current_memory_usage
        expect(usage).to be > 0
        expect(usage).to be < 2000 # 2GB以下であることを確認
      end
    end

    describe '.check_memory_usage' do
      it '正常なメモリ使用量の場合はtrueを返すこと' do
        allow(monitor).to receive(:current_memory_usage).and_return(100)
        expect(monitor.check_memory_usage).to be true
      end

      it '閾値を超えた場合はfalseを返し、警告ログを出力すること' do
        allow(monitor).to receive(:current_memory_usage).and_return(600)
        allow(Rails.logger).to receive(:warn)

        expect(monitor.check_memory_usage).to be false
        expect(Rails.logger).to have_received(:warn).with(/Memory usage high/)
      end
    end

    describe '.log_memory_stats' do
      it 'メモリ統計をログ出力し、使用量を返すこと' do
        allow(monitor).to receive(:current_memory_usage).and_return(150)
        allow(Rails.logger).to receive(:info)

        result = monitor.log_memory_stats

        expect(result).to eq(150)
        expect(Rails.logger).to have_received(:info).with(/Memory usage: 150/)
      end
    end
  end

  describe 'QueryMonitor' do
    let(:monitor) { PerformanceMonitoring::QueryMonitor }

    describe '.monitor_request' do
      it 'クエリ数と実行時間を監視できること' do
        result = monitor.monitor_request do
          # テスト用のクエリ実行
          Store.first
          "test_result"
        end

        expect(result).to include(:result, :query_count, :duration)
        expect(result[:result]).to eq("test_result")
        expect(result[:query_count]).to be >= 1
        expect(result[:duration]).to be > 0
      end

      it '閾値を超えるクエリ数の場合に警告ログを出力すること' do
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:info)

        # 多数のクエリを実行してテスト
        monitor.monitor_request do
          12.times { Store.count } # 閾値（10）を超える
        end

        expect(Rails.logger).to have_received(:warn).with(/High query count detected/)
      end

      it '統計ログを出力すること' do
        allow(Rails.logger).to receive(:info)

        monitor.monitor_request do
          Store.first
        end

        expect(Rails.logger).to have_received(:info).with(/📊 SQL:/)
      end
    end
  end

  describe 'ResponseTimeBenchmark' do
    let(:benchmark) { PerformanceMonitoring::ResponseTimeBenchmark }

    describe '.benchmark_endpoint' do
      it 'レスポンス時間を測定できること' do
        result = benchmark.benchmark_endpoint('GET', '/store') do
          sleep 0.01 # 10ms待機
          "test_response"
        end

        expect(result).to include(:result, :duration, :threshold, :within_threshold)
        expect(result[:result]).to eq("test_response")
        expect(result[:duration]).to be >= 10
        expect(result[:threshold]).to eq(50) # GET /store の閾値
      end

      it '閾値を超える場合に警告ログを出力すること' do
        allow(Rails.logger).to receive(:warn)
        allow(Rails.logger).to receive(:info)

        benchmark.benchmark_endpoint('GET', '/admin/inventories') do
          sleep 0.5 # 500ms待機（閾値400msを超える）
          "slow_response"
        end

        expect(Rails.logger).to have_received(:warn).with(/Slow response detected/)
      end

      it 'パフォーマンスログを出力すること' do
        allow(Rails.logger).to receive(:info)

        benchmark.benchmark_endpoint('GET', '/store') do
          "fast_response"
        end

        expect(Rails.logger).to have_received(:info).with(/🚀 GET \/store:/)
      end

      it 'パスの正規化が正しく動作すること' do
        result = benchmark.benchmark_endpoint('GET', '/admin/inventories/123') do
          "normalized_response"
        end

        # 内部でnormalize_pathが呼ばれ、閾値が正しく適用されることを確認
        # パスが正規化されてGET /admin/inventories/:idとなるが、
        # RESPONSE_TIME_THRESHOLDSにはGET /admin/inventoriesしか定義されていないため、
        # デフォルトの500msが適用される
        expect(result[:threshold]).to eq(500) # デフォルト閾値
      end
    end
  end

  describe 'PerformanceStats' do
    let(:stats) { PerformanceMonitoring::PerformanceStats }

    describe '.collect_system_stats' do
      it 'システム統計情報を収集できること' do
        result = stats.collect_system_stats

        expect(result).to include(
          :timestamp,
          :memory_usage_mb,
          :active_record_pool_size,
          :active_record_pool_connections,
          :redis_connected,
          :sidekiq_queue_size,
          :counter_cache_health
        )

        expect(result[:timestamp]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        expect(result[:memory_usage_mb]).to be > 0
        expect(result[:active_record_pool_size]).to be > 0
      end
    end

    describe '.log_system_stats' do
      it 'システム統計をJSON形式でログ出力すること' do
        allow(Rails.logger).to receive(:info)

        result = stats.log_system_stats

        expect(Rails.logger).to have_received(:info).with(/📈 System Stats:/)
        expect(result).to be_a(Hash)
      end
    end
  end

  describe 'PerformanceMonitoringMiddleware' do
    let(:app) { double('app') }
    let(:middleware) { PerformanceMonitoringMiddleware.new(app) }
    let(:env) { { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/store' } }

    context '開発環境の場合' do
      before do
        allow(Rails.env).to receive(:development?).and_return(true)
      end

      it 'パフォーマンス監視を実行すること' do
        allow(app).to receive(:call).with(env).and_return([200, {}, ['response']])
        allow(PerformanceMonitoring::QueryMonitor).to receive(:monitor_request).and_yield.and_return({
          result: { result: [200, {}, ['response']] },
          query_count: 1,
          duration: 10
        })
        allow(PerformanceMonitoring::ResponseTimeBenchmark).to receive(:benchmark_endpoint).and_yield.and_return({
          result: [200, {}, ['response']],
          duration: 10,
          threshold: 50,
          within_threshold: true
        })
        allow(PerformanceMonitoring::MemoryMonitor).to receive(:check_memory_usage)
        allow(PerformanceMonitoring::PerformanceStats).to receive(:log_system_stats)

        result = middleware.call(env)

        expect(result).to eq([200, {}, ['response']])
        expect(PerformanceMonitoring::QueryMonitor).to have_received(:monitor_request)
        expect(PerformanceMonitoring::ResponseTimeBenchmark).to have_received(:benchmark_endpoint)
        expect(PerformanceMonitoring::MemoryMonitor).to have_received(:check_memory_usage)
      end

      it '静的ファイルリクエストの場合は監視をスキップすること' do
        static_env = { 'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/assets/application.css' }
        allow(app).to receive(:call).with(static_env).and_return([200, {}, ['css']])

        result = middleware.call(static_env)

        expect(result).to eq([200, {}, ['css']])
        # 監視メソッドが呼ばれていないことを確認
        expect(PerformanceMonitoring::QueryMonitor).not_to receive(:monitor_request)
      end
    end

    context '本番環境の場合' do
      before do
        allow(Rails.env).to receive(:development?).and_return(false)
      end

      it 'パフォーマンス監視をスキップすること' do
        allow(app).to receive(:call).with(env).and_return([200, {}, ['response']])

        result = middleware.call(env)

        expect(result).to eq([200, {}, ['response']])
        expect(PerformanceMonitoring::QueryMonitor).not_to receive(:monitor_request)
      end
    end
  end

  describe '統合テスト' do
    it 'Counter Cache健全性チェックが正常に動作すること' do
      # テストデータ作成
      store = create(:store)
      create_list(:store_inventory, 3, store: store)

      # Counter Cacheが正常な状態での健全性チェック
      health = PerformanceMonitoring::PerformanceStats.send(:counter_cache_health_check)
      expect(health).to eq('healthy')

      # 不整合を作成してテスト
      store.update_column(:store_inventories_count, 999)
      
      # Store.firstが不整合のあるstoreを返すように設定
      allow(Store).to receive(:first).and_return(store)
      
      health = PerformanceMonitoring::PerformanceStats.send(:counter_cache_health_check)
      expect(health).to eq('inconsistencies_detected')
    end

    it 'パフォーマンス監視の全機能が連携して動作すること' do
      allow(Rails.logger).to receive(:info)
      allow(Rails.logger).to receive(:warn)

      # 実際のリクエストをシミュレート
      result = PerformanceMonitoring::QueryMonitor.monitor_request do
        PerformanceMonitoring::ResponseTimeBenchmark.benchmark_endpoint('GET', '/store') do
          Store.first # SQLクエリ実行
          PerformanceMonitoring::MemoryMonitor.check_memory_usage
          "integration_test_result"
        end
      end

      expect(result[:result][:result]).to eq("integration_test_result")
      expect(result[:query_count]).to be >= 1
      expect(result[:duration]).to be > 0

      # ログが適切に出力されていることを確認
      expect(Rails.logger).to have_received(:info).with(/📊 SQL:/)
      expect(Rails.logger).to have_received(:info).with(/🚀 GET \/store:/)
    end
  end

  describe 'エラーハンドリング' do
    let(:stats) { PerformanceMonitoring::PerformanceStats }

    it 'Redis接続エラー時に適切にハンドリングすること' do
      allow(Redis).to receive(:new).and_raise(StandardError.new("Connection failed"))

      result = stats.collect_system_stats
      expect(result[:redis_connected]).to be false
    end

    it 'Sidekiq接続エラー時に適切にハンドリングすること' do
      allow(Sidekiq::Queue).to receive(:new).and_raise(StandardError.new("Sidekiq not available"))

      result = stats.collect_system_stats
      expect(result[:sidekiq_queue_size]).to eq(0)
    end

    it 'Counter Cache健全性チェックエラー時に適切にハンドリングすること' do
      allow(Store).to receive(:first).and_raise(StandardError.new("Database error"))

      health = stats.send(:counter_cache_health_check)
      expect(health).to eq('check_failed')
    end
  end
end

# ============================================
# TODO: Phase 3以降のテスト拡張
# ============================================
# 1. 🟡 本番環境監視機能のテスト
#    - APMツール連携のモックテスト
#    - Slack/メール通知のテスト
#    - メトリクス送信のテスト
#
# 2. 🟢 負荷テスト
#    - 大量リクエスト時のパフォーマンス監視
#    - メモリリーク検出のテスト
#    - 長時間実行時の安定性テスト
#
# 3. 🟢 設定可能な閾値テスト
#    - 環境変数による閾値変更
#    - 動的閾値調整のテスト
#    - アラート頻度制御のテスト