# frozen_string_literal: true

# 在庫データアクセスのRepository層
# ============================================
# CLAUDE.md準拠: パフォーマンス最適化 - クエリ最適化とキャッシュ
# メタ認知: データアクセスロジックの一元化と最適化
# ============================================
class InventoryRepository
  include Singleton

  # キャッシュ有効期限
  CACHE_EXPIRES_IN = 5.minutes

  class << self
    delegate :find_with_associations, :search, :by_status, :low_stock,
             :expiring_soon, :recently_updated, :with_stats,
             :batch_find, :preload_for_index, :preload_for_show,
             to: :instance
  end

  # 関連データを含めて取得
  def find_with_associations(id, associations = [ :batches ])
    Inventory.includes(associations).find(id)
  end

  # 検索実行
  def search(params)
    query = Queries::InventorySearchQuery.new(params)
    result = query.call

    # パフォーマンス統計をログ出力
    log_performance_stats(query.performance_stats)

    result
  end

  # ステータス別取得
  def by_status(status, includes: [])
    scope = Inventory.where(status: status)
    scope = scope.includes(includes) if includes.present?
    scope
  end

  # 在庫不足商品
  def low_stock(threshold = 10, includes: [ :batches ])
    Inventory.includes(includes)
             .where("quantity <= ?", threshold)
             .order(quantity: :asc)
  end

  # 期限切れ間近の商品
  def expiring_soon(days = 30)
    # CLAUDE.md準拠: Rails 7+ セキュリティ - Arel.sql()使用
    expiration_date = days.days.from_now

    Inventory.joins(:batches)
             .where("batches.expiration_date <= ?", expiration_date)
             .where("batches.expiration_date >= ?", Date.current)
             .distinct
             .includes(:batches)
             .order(Arel.sql("batches.expiration_date ASC"))
  end

  # 最近更新された商品
  def recently_updated(limit: 10)
    Rails.cache.fetch("inventories/recently_updated/#{limit}", expires_in: CACHE_EXPIRES_IN) do
      Inventory.includes(:batches, :inventory_logs)
               .order(updated_at: :desc)
               .limit(limit)
               .to_a
    end
  end

  # 統計情報付き取得
  def with_stats
    # CLAUDE.md準拠: Counter Cache活用
    # メタ認知: 集計クエリを避けてCounter Cacheを活用
    Inventory.select(
      "inventories.*",
      "inventories.batches_count",
      "inventories.inventory_logs_count"
    )
  end

  # バッチ取得（大量データ処理用）
  def batch_find(batch_size: 1000)
    Inventory.find_in_batches(batch_size: batch_size) do |batch|
      # 関連データを効率的にプリロード
      ActiveRecord::Associations::Preloader.new(
        records: batch,
        associations: [ :batches ]
      ).call

      yield batch
    end
  end

  # インデックス画面用のプリロード
  def preload_for_index(scope)
    # CLAUDE.md準拠: 画面表示に必要な最小限の関連のみ
    # メタ認知: インデックス画面ではCounter Cacheで十分
    scope
  end

  # 詳細画面用のプリロード
  def preload_for_show(inventory)
    # CLAUDE.md準拠: 詳細画面では全関連データが必要
    # メタ認知: N+1を防ぐため全関連を事前読み込み
    ActiveRecord::Associations::Preloader.new(
      records: [ inventory ],
      associations: [ :batches, :inventory_logs, :receipts, :shipments ]
    ).call

    inventory
  end

  # 集計クエリ
  def aggregate_stats(scope = Inventory.all)
    # CLAUDE.md準拠: 効率的な集計クエリ
    stats = scope.select(
      "COUNT(*) as total_count",
      "SUM(quantity) as total_quantity",
      "SUM(quantity * price) as total_value",
      "AVG(price) as average_price"
    ).take

    {
      total_count: stats.total_count || 0,
      total_quantity: stats.total_quantity || 0,
      total_value: stats.total_value || 0,
      average_price: stats.average_price || 0
    }
  end

  # カテゴリ別集計
  def stats_by_category
    # CLAUDE.md準拠: 商品名パターンによるカテゴリ推定
    categories = ApplicationHelper.category_patterns.keys

    stats = {}
    categories.each do |category|
      category_items = search(category: category)
      stats[category] = aggregate_stats(category_items)
    end

    stats
  end

  private

  # パフォーマンス統計のログ出力
  def log_performance_stats(stats)
    return unless stats.present?

    Rails.logger.info(
      "[InventoryRepository] Query Performance: " \
      "#{stats[:query_time_ms]}ms, " \
      "#{stats[:record_count]} records, " \
      "includes: #{stats[:includes_used].join(', ')}"
    )

    # 開発環境では詳細なSQLも出力
    if Rails.env.development?
      Rails.logger.debug("[InventoryRepository] SQL: #{stats[:sql_query]}")
    end
  end
end
