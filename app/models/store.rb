# frozen_string_literal: true

class Store < ApplicationRecord
  # アソシエーション
  has_many :store_inventories, dependent: :destroy
  has_many :inventories, through: :store_inventories
  has_many :admins, dependent: :restrict_with_error

  # 店舗間移動関連
  has_many :outgoing_transfers, class_name: "InterStoreTransfer", foreign_key: "source_store_id", dependent: :destroy
  has_many :incoming_transfers, class_name: "InterStoreTransfer", foreign_key: "destination_store_id", dependent: :destroy

  # ============================================
  # バリデーション
  # ============================================
  validates :name, presence: true, length: { maximum: 100 }
  validates :code, presence: true,
                   length: { maximum: 20 },
                   uniqueness: { case_sensitive: false },
                   format: { with: /\A[A-Z0-9_-]+\z/i, message: "は英数字、ハイフン、アンダースコアのみ使用できます" }
  validates :store_type, presence: true, inclusion: { in: %w[pharmacy warehouse headquarters] }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :phone, format: { with: /\A[0-9\-\+\(\)\s]*\z/ }, allow_blank: true

  # ============================================
  # enum定義
  # ============================================
  enum :store_type, { pharmacy: "pharmacy", warehouse: "warehouse", headquarters: "headquarters" }

  # ============================================
  # スコープ
  # ============================================
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :by_region, ->(region) { where(region: region) if region.present? }
  scope :by_type, ->(type) { where(store_type: type) if type.present? }

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 店舗の表示名（コード + 名前）
  def display_name
    "#{code} - #{name}"
  end

  # 店舗の総在庫価値
  def total_inventory_value
    store_inventories.joins(:inventory)
                    .sum("store_inventories.quantity * inventories.price")
  end

  # 在庫回転率計算
  # TODO: Phase 3 で詳細な在庫分析機能を実装予定
  # - 過去12ヶ月の売上データとの連携
  # - 季節変動を考慮した回転率計算
  # - 商品カテゴリ別回転率分析
  def inventory_turnover_rate
    # 簡易実装：将来的に売上データと連携
    return 0.0 if average_inventory_value.zero?

    # 仮の年間売上原価（実装時に実際のデータと置き換え）
    estimated_annual_cogs = total_inventory_value * 4.2  # 業界平均回転率
    estimated_annual_cogs / average_inventory_value
  end

  # 低在庫商品数
  def low_stock_items_count
    store_inventories.joins(:inventory)
                    .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                    .count
  end

  # 在庫切れ商品数
  def out_of_stock_items_count
    store_inventories.where(quantity: 0).count
  end

  # 利用可能な在庫商品数（reserved_quantityを除く）
  def available_items_count
    store_inventories.where("quantity > reserved_quantity").count
  end

  # ============================================
  # クラスメソッド
  # ============================================

  # 管理者がアクセス可能な店舗のみを取得
  def self.accessible_to_admin(admin)
    if admin.headquarters_admin?
      all
    else
      where(id: admin.accessible_store_ids)
    end
  end

  # 店舗コード生成ヘルパー
  def self.generate_code(prefix = "ST")
    loop do
      code = "#{prefix}#{SecureRandom.alphanumeric(6).upcase}"
      break code unless exists?(code: code)
    end
  end

  # アクティブな店舗の統計情報
  def self.active_stores_stats
    active_stores = active.includes(:store_inventories, :inventories)

    {
      total_stores: active_stores.count,
      total_inventory_value: active_stores.sum(&:total_inventory_value),
      average_inventory_per_store: StoreInventory.joins(:store).where(stores: { active: true }).average(:quantity) || 0,
      stores_with_low_stock: active_stores.select { |store| store.low_stock_items_count > 0 }.count
    }
  end

  # ============================================
  # TODO: Phase 2以降で実装予定の機能
  # ============================================
  # 1. 店舗間距離計算（配送時間・コスト最適化）
  #    - Google Maps API連携
  #    - 配送ルート最適化アルゴリズム
  #
  # 2. 店舗パフォーマンス分析
  #    - 売上対在庫効率分析
  #    - 店舗別KPI計算・比較
  #    - ベンチマーキング機能
  #
  # 3. 自動補充提案機能
  #    - 需要予測AIとの連携
  #    - 季節変動・地域特性を考慮した提案
  #    - ROI最適化アルゴリズム
  #
  # 4. 店舗設定カスタマイズ
  #    - 営業時間設定
  #    - 在庫アラート閾値のカスタマイズ
  #    - 移動申請承認フローの設定

  private

  # 平均在庫価値計算（将来的に時系列データで改善）
  def average_inventory_value
    @average_inventory_value ||= total_inventory_value
  end
end
