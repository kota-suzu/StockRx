# frozen_string_literal: true

# テスト最適化支援ヘルパー（CLAUDE.md準拠）
# メタ認知: テスト実行時間を大幅短縮し、開発者の生産性向上を図る
# 横展開: 他のRailsプロジェクトでも同様の最適化パターン適用可能

module TestOptimization
  # テスト分類定数
  module TestCategory
    ULTRA_FAST = [ :unit, :validator, :decorator ].freeze
    FAST = [ :model, :helper, :lib ].freeze
    MEDIUM = [ :controller, :request, :service ].freeze
    SLOW = [ :feature, :integration, :system ].freeze

    ALL_CATEGORIES = (ULTRA_FAST + FAST + MEDIUM + SLOW).freeze
  end

  # パフォーマンスメトリクス収集
  class PerformanceMetrics
    attr_accessor :execution_time, :database_queries, :memory_usage, :test_count

    def initialize
      @execution_time = 0.0
      @database_queries = 0
      @memory_usage = 0
      @test_count = 0
    end

    def record_execution_time(time)
      @execution_time += time
    end

    def record_query_count(count)
      @database_queries += count
    end

    def average_time_per_test
      return 0.0 if @test_count.zero?
      @execution_time / @test_count
    end

    def queries_per_test
      return 0.0 if @test_count.zero?
      @database_queries.to_f / @test_count
    end
  end

  # テスト高速化ヘルパーメソッド
  module Helpers
    # FactoryBot最適化実行
    def with_fast_factory(**options, &block)
      original_strategy = FactoryBot.default_strategy
      begin
        # build_stubbed戦略を使用してDBアクセスを削減
        FactoryBot.default_strategy = :build_stubbed if options[:stub_records]
        yield
      ensure
        FactoryBot.default_strategy = original_strategy
      end
    end

    # 遅いテストのスキップ
    def skip_slow_tests
      skip 'Slow test skipped for fast execution' if ENV['FAST_TESTS_ONLY'] == 'true'
    end

    # パフォーマンス測定
    def measure_performance(&block)
      start_time = Time.current
      result = yield
      end_time = Time.current

      execution_time = end_time - start_time
      puts "🚀 Test execution time: #{execution_time.round(4)}s" if ENV['SHOW_PERFORMANCE'] == 'true'

      result
    end

    # データベースクエリ数カウント
    def count_queries(&block)
      query_count = 0
      callback = ->(name, started, finished, unique_id, payload) {
        query_count += 1 unless payload[:name] == 'SCHEMA'
      }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        yield
      end

      puts "📊 Database queries: #{query_count}" if ENV['SHOW_QUERIES'] == 'true'
      query_count
    end

    # メモリ使用量測定
    def measure_memory(&block)
      start_memory = get_memory_usage
      result = yield
      end_memory = get_memory_usage

      memory_diff = end_memory - start_memory
      puts "💾 Memory usage: #{memory_diff}KB" if ENV['SHOW_MEMORY'] == 'true'

      result
    end

    private

    def get_memory_usage
      `ps -o rss= -p #{Process.pid}`.to_i
    end
  end

  # RSpec設定拡張
  module RSpecExtensions
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      # 高速テストタグの追加
      def fast_test(description, **options, &block)
        it description, :fast, **options, &block
      end

      # 超高速テストタグの追加
      def ultra_fast_test(description, **options, &block)
        it description, :ultra_fast, **options, &block
      end

      # 遅いテストタグの追加
      def slow_test(description, **options, &block)
        it description, :slow, **options, &block
      end
    end
  end
end

# RSpec設定への統合
RSpec.configure do |config|
  config.include TestOptimization::Helpers
  config.include TestOptimization::RSpecExtensions

  # タグベースのテスト分類
  config.define_derived_metadata(file_path: %r{/spec/models/}) do |metadata|
    metadata[:type] = :model
    metadata[:fast] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/helpers/}) do |metadata|
    metadata[:type] = :helper
    metadata[:fast] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/decorators/}) do |metadata|
    metadata[:type] = :decorator
    metadata[:ultra_fast] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/features/}) do |metadata|
    metadata[:type] = :feature
    metadata[:slow] = true
  end

  config.define_derived_metadata(file_path: %r{/spec/system/}) do |metadata|
    metadata[:type] = :system
    metadata[:slow] = true
  end

  # 環境変数による自動スキップ設定
  config.filter_run_excluding slow: true if ENV['FAST_TESTS_ONLY'] == 'true'
  config.filter_run_including ultra_fast: true if ENV['ULTRA_FAST_TESTS_ONLY'] == 'true'

  # パフォーマンスメトリクス収集
  if ENV['COLLECT_METRICS'] == 'true'
    metrics = TestOptimization::PerformanceMetrics.new

    config.around(:each) do |example|
      start_time = Time.current
      example.run
      end_time = Time.current

      metrics.record_execution_time(end_time - start_time)
      metrics.test_count += 1
    end

    config.after(:suite) do
      puts "\n📊 === テスト実行メトリクス ==="
      puts "総実行時間: #{metrics.execution_time.round(4)}s"
      puts "テスト数: #{metrics.test_count}"
      puts "平均実行時間: #{metrics.average_time_per_test.round(4)}s/test"
      puts "=========================="
    end
  end
end

# TODO: Phase 2 - 追加最適化機能（推定2日）
# 優先度: 中（さらなる高速化）
# 実装内容:
#   - 並列実行支援機能
#   - テストデータキャッシュ機能
#   - N+1クエリ自動検出機能
#   - メモリリーク検出機能
# 横展開確認:
#   - CI環境での自動メトリクス収集
#   - 本番環境パフォーマンス監視との連携
#   - 他のプロジェクトへの最適化パターン適用
