# frozen_string_literal: true

# クエリ数制限のカスタムマッチャー
# ============================================
# CLAUDE.md準拠: パフォーマンステスト用マッチャー
# メタ認知: N+1クエリの検出と防止
# ============================================

RSpec::Matchers.define :exceed_query_limit do |expected_count|
  supports_block_expectations

  match do |block|
    @query_count = count_queries(&block)
    @query_count > expected_count
  end

  failure_message do
    "expected block to execute more than #{expected_count} queries, but executed #{@query_count}"
  end

  failure_message_when_negated do
    "expected block not to execute more than #{expected_count} queries, but executed #{@query_count}"
  end

  def count_queries(&block)
    count = 0
    counter = ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
      # SCHEMA関連のクエリを除外
      unless event.payload[:sql]&.match?(/\A(?:PRAGMA|SCHEMA|SHOW|SET|BEGIN|COMMIT|ROLLBACK)/)
        count += 1
      end
    end

    block.call

    ActiveSupport::Notifications.unsubscribe(counter)
    count
  end

  # クエリログの表示（デバッグ用）
  def with_query_log
    @show_queries = true
    self
  end
end

# クエリ記録用のヘルパーモジュール
module QueryRecorderHelpers
  class QueryRecorder
    attr_reader :queries, :count

    def initialize
      @queries = []
      @count = 0
    end

    def record(&block)
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |event|
        query = event.payload[:sql]
        # SCHEMA関連のクエリを除外
        unless query&.match?(/\A(?:PRAGMA|SCHEMA|SHOW|SET|BEGIN|COMMIT|ROLLBACK)/)
          @queries << {
            sql: query,
            name: event.payload[:name],
            duration: event.duration,
            cached: event.payload[:cached]
          }
          @count += 1 unless event.payload[:cached]
        end
      end

      result = block.call

      ActiveSupport::Notifications.unsubscribe(subscriber)
      result
    end

    def queries_by_table
      @queries.group_by { |q| extract_table_name(q[:sql]) }
    end

    def slow_queries(threshold_ms = 10)
      @queries.select { |q| q[:duration] > threshold_ms }
    end

    def cached_queries
      @queries.select { |q| q[:cached] }
    end

    def non_cached_queries
      @queries.reject { |q| q[:cached] }
    end

    private

    def extract_table_name(sql)
      # FROM句からテーブル名を抽出
      match = sql.match(/FROM\s+["`]?(\w+)["`]?/i)
      match ? match[1] : 'unknown'
    end
  end

  def record_queries(&block)
    recorder = QueryRecorder.new
    recorder.record(&block)
    recorder
  end

  # N+1クエリの検出
  def detect_n_plus_one_queries(&block)
    recorder = record_queries(&block)

    # 同じテーブルに対する複数の類似クエリを検出
    potential_n_plus_one = recorder.queries_by_table.select do |table, queries|
      # 類似のWHERE句を持つクエリをグループ化
      similar_queries = queries.group_by do |q|
        q[:sql].gsub(/\d+/, 'N').gsub(/'[^']*'/, "'STRING'")
      end

      # 同じパターンのクエリが3回以上実行されている場合はN+1の可能性
      similar_queries.any? { |pattern, qs| qs.size >= 3 }
    end

    potential_n_plus_one
  end
end

# RSpecの設定でヘルパーを有効化
RSpec.configure do |config|
  config.include QueryRecorderHelpers
end
