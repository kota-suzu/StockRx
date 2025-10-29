# frozen_string_literal: true

# パフォーマンステスト支援モジュール
# N+1クエリ検出、レスポンス時間測定、メモリ使用量監視
module PerformanceTests
  extend ActiveSupport::Concern

  included do
    # N+1クエリ検出のカスタムマッチャー
    RSpec::Matchers.define :exceed_query_limit do |expected|
      supports_block_expectations

      match do |block|
        @queries_count = count_queries(&block)
        @queries_count > expected
      end

      failure_message do
        "Expected to run more than #{expected} queries, but ran #{@queries_count}"
      end

      failure_message_when_negated do
        "Expected to run #{expected} or fewer queries, but ran #{@queries_count}"
      end

      description do
        "run more than #{expected} database queries"
      end

      private

      def count_queries(&block)
        count = 0
        callback = ->(name, started, finished, unique_id, payload) {
          count += 1 unless payload[:name] == 'SCHEMA'
        }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
        count
      end
    end

    # レスポンス時間測定のカスタムマッチャー
    RSpec::Matchers.define :complete_within do |expected_time|
      supports_block_expectations

      match do |block|
        @start_time = Time.current
        block.call
        @actual_time = Time.current - @start_time
        @actual_time <= expected_time
      end

      failure_message do
        "Expected block to complete within #{expected_time}s, but took #{@actual_time.round(3)}s"
      end

      description do
        "complete within #{expected_time} seconds"
      end
    end

    # メモリ使用量測定のカスタムマッチャー
    RSpec::Matchers.define :use_memory_within do |expected_mb|
      supports_block_expectations

      match do |block|
        GC.start # ガベージコレクションを実行
        before_memory = memory_usage_mb
        block.call
        GC.start
        after_memory = memory_usage_mb
        @memory_used = after_memory - before_memory
        @memory_used <= expected_mb
      end

      failure_message do
        "Expected block to use #{expected_mb}MB or less, but used #{@memory_used.round(2)}MB"
      end

      description do
        "use #{expected_mb}MB of memory or less"
      end

      private

      def memory_usage_mb
        `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
      end
    end
  end

  module_function

  # パフォーマンステストの共通ヘルパー
  def measure_performance(description, &block)
    puts "\n📊 パフォーマンス測定: #{description}"

    # 実行時間測定
    start_time = Time.current
    result = yield
    execution_time = Time.current - start_time

    puts "  ⏱️  実行時間: #{execution_time.round(3)}秒"

    # クエリ数測定
    query_count = 0
    callback = ->(name, started, finished, unique_id, payload) {
      query_count += 1 unless payload[:name] == 'SCHEMA'
    }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
      yield if block_given?
    end

    puts "  🗃️  クエリ数: #{query_count}件"

    # 判定
    if execution_time > 0.2 # 200ms
      puts "  ⚠️  レスポンス時間が推奨値を超えています"
    elsif query_count > 5
      puts "  ⚠️  クエリ数が多すぎます（N+1の可能性）"
    else
      puts "  ✅ パフォーマンス良好"
    end

    result
  end

  # N+1問題の詳細診断
  def diagnose_n_plus_one(&block)
    queries = []
    callback = ->(name, started, finished, unique_id, payload) {
      unless payload[:name] == 'SCHEMA'
        queries << {
          sql: payload[:sql],
          binds: payload[:binds]&.map(&:value) || []
        }
      end
    }

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)

    # 同じようなクエリパターンを検出
    similar_queries = queries.group_by { |q| q[:sql].gsub(/\d+/, '?') }
    n_plus_one_detected = similar_queries.any? { |pattern, queries| queries.size > 3 }

    if n_plus_one_detected
      puts "\n🚨 N+1クエリが検出されました:"
      similar_queries.each do |pattern, queries|
        if queries.size > 3
          puts "  📋 パターン: #{pattern}"
          puts "     実行回数: #{queries.size}回"
        end
      end
    else
      puts "\n✅ N+1クエリは検出されませんでした"
    end

    {
      total_queries: queries.size,
      n_plus_one_detected: n_plus_one_detected,
      query_patterns: similar_queries
    }
  end
end

# RSpec設定
RSpec.configure do |config|
  config.include PerformanceTests

  # パフォーマンステスト用のタグ
  config.define_derived_metadata(file_path: %r{spec/(controllers|features)/}) do |metadata|
    metadata[:performance] = true
  end

  # パフォーマンステスト専用の設定
  config.around(:each, :performance) do |example|
    if ENV['PERFORMANCE_TEST'] == 'true'
      measure_performance(example.description) do
        example.run
      end
    else
      example.run
    end
  end
end
