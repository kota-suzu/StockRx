# frozen_string_literal: true

module Queries
  # 在庫検索の複雑なクエリロジックを管理するQuery Object
  # ============================================
  # CLAUDE.md準拠: パフォーマンス最適化 - 動的includes最適化
  # メタ認知: N+1問題の解決とクエリパフォーマンスの測定
  # ============================================
  class InventorySearchQuery
    include ActiveModel::Model

    attr_accessor :keyword, :status, :min_quantity, :max_quantity,
                  :min_price, :max_price, :sort_by, :sort_direction,
                  :include_associations, :category

    # デフォルトの関連読み込み設定
    DEFAULT_INCLUDES = [ :batches ].freeze

    # ソート可能なカラム（ホワイトリスト）
    SORTABLE_COLUMNS = %w[
      name quantity price status created_at updated_at
      batches_count inventory_logs_count
    ].freeze

    # ソート方向（ホワイトリスト）
    SORT_DIRECTIONS = %w[asc desc].freeze

    # 🛡️ セキュリティ対策: SQLインジェクション防止のためのカラムマッピング
    # Arel.sql()使用前に安全なカラム名のみ許可
    SORT_COLUMN_MAPPING = {
      "name" => "inventories.name",
      "quantity" => "inventories.quantity",
      "price" => "inventories.price",
      "status" => "inventories.status",
      "created_at" => "inventories.created_at",
      "updated_at" => "inventories.updated_at",
      "batches_count" => "inventories.batches_count",
      "inventory_logs_count" => "inventories.inventory_logs_count"
    }.freeze

    def initialize(params = {})
      super(params)
      @sort_by ||= "created_at"
      @sort_direction ||= "desc"
      @include_associations ||= []
    end

    # クエリを実行して結果を返す
    def call
      scope = Inventory.all
      scope = apply_search_filters(scope)
      scope = apply_sorting(scope)
      scope = apply_includes(scope)

      # パフォーマンス測定
      measure_query_performance(scope)

      scope
    end

    # パフォーマンス統計を返す
    def performance_stats
      @performance_stats ||= {}
    end

    private

    # 検索フィルターの適用
    def apply_search_filters(scope)
      scope = filter_by_keyword(scope) if keyword.present?
      scope = filter_by_status(scope) if status.present?
      scope = filter_by_quantity_range(scope)
      scope = filter_by_price_range(scope)
      scope = filter_by_category(scope) if category.present?
      scope
    end

    # キーワード検索
    def filter_by_keyword(scope)
      # CLAUDE.md準拠: セキュリティ - Arel.sql()によるSQLインジェクション対策
      keyword_pattern = "%#{sanitize_sql_like(keyword)}%"
      scope.where(
        "inventories.name LIKE ? OR inventories.description LIKE ?",
        keyword_pattern, keyword_pattern
      )
    end

    # ステータスフィルター
    def filter_by_status(scope)
      scope.where(status: status)
    end

    # 数量範囲フィルター
    def filter_by_quantity_range(scope)
      scope = scope.where("inventories.quantity >= ?", min_quantity) if min_quantity.present?
      scope = scope.where("inventories.quantity <= ?", max_quantity) if max_quantity.present?
      scope
    end

    # 価格範囲フィルター
    def filter_by_price_range(scope)
      scope = scope.where("inventories.price >= ?", min_price) if min_price.present?
      scope = scope.where("inventories.price <= ?", max_price) if max_price.present?
      scope
    end

    # カテゴリフィルター
    def filter_by_category(scope)
      # CLAUDE.md準拠: 商品名パターンマッチングによるカテゴリ推定
      category_patterns = ApplicationHelper.category_patterns[category]
      return scope unless category_patterns

      pattern_conditions = category_patterns.map { |pattern|
        "inventories.name LIKE ?"
      }.join(" OR ")

      pattern_values = category_patterns.map { |pattern|
        "%#{sanitize_sql_like(pattern)}%"
      }

      scope.where(pattern_conditions, *pattern_values)
    end

    # ソートの適用
    def apply_sorting(scope)
      return scope unless SORTABLE_COLUMNS.include?(sort_by) &&
                          SORT_DIRECTIONS.include?(sort_direction)

      # 🛡️ セキュリティ対策: ホワイトリストベースのカラムマッピング
      # メタ認知: SQLインジェクション完全防止のため、事前定義マッピングを使用
      safe_column = SORT_COLUMN_MAPPING[sort_by]
      return scope unless safe_column # 不正なカラムの場合はソートなし

      # CLAUDE.md準拠: Rails 7+ セキュリティ - Arel.sql()でSQL文字列をラップ
      # 横展開: 他の検索系クエリでも同様のパターン適用
      # 🛡️ セキュリティ強化: 文字列補間を完全に回避した安全なクエリ構築
      safe_direction = SORT_DIRECTIONS.include?(sort_direction) ? sort_direction : "asc"
      
      # メタ認知: Brakemanの警告完全解決のため、文字列補間を避ける
      case safe_direction
      when "desc"
        scope.order(Arel.sql(safe_column).desc)
      else
        scope.order(Arel.sql(safe_column).asc)
      end
    end

    # 動的includes最適化
    def apply_includes(scope)
      # CLAUDE.md準拠: パフォーマンス最適化 - 必要な関連のみを読み込み
      # メタ認知: 画面表示に必要な関連データのみを事前読み込み
      associations = calculate_required_associations

      return scope if associations.empty?

      # 複数の関連を効率的に読み込み
      associations.reduce(scope) do |s, association|
        s.includes(association)
      end
    end

    # 必要な関連データを計算
    def calculate_required_associations
      associations = []

      # デフォルトの関連
      associations.concat(DEFAULT_INCLUDES)

      # 明示的に指定された関連
      if include_associations.present?
        associations.concat(Array(include_associations))
      end

      # 検索条件に基づく追加の関連
      if keyword.present?
        # キーワード検索時はバッチ情報も必要
        associations << :batches unless associations.include?(:batches)
      end

      # 重複を除去して返す
      associations.uniq
    end

    # クエリパフォーマンスの測定
    def measure_query_performance(scope)
      # CLAUDE.md準拠: パフォーマンス監視
      # メタ認知: クエリ実行時間とメモリ使用量を測定

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      initial_memory = GC.stat[:heap_allocated_pages]

      # クエリを実行（to_aで強制的に実行）
      result = scope.to_a

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      final_memory = GC.stat[:heap_allocated_pages]

      @performance_stats = {
        query_time_ms: ((end_time - start_time) * 1000).round(2),
        memory_pages_allocated: final_memory - initial_memory,
        record_count: result.size,
        includes_used: calculate_required_associations,
        sql_query: scope.to_sql
      }

      # パフォーマンスログ出力
      if @performance_stats[:query_time_ms] > 100
        Rails.logger.warn(
          "Slow inventory query detected: #{@performance_stats[:query_time_ms]}ms, " \
          "#{@performance_stats[:record_count]} records"
        )
      end

      scope
    end

    # SQLインジェクション対策のためのサニタイズ
    def sanitize_sql_like(string)
      string.gsub(/[\\%_]/) { |x| "\\#{x}" }
    end
  end
end
