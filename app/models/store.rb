# frozen_string_literal: true

class Store < ApplicationRecord
  # Concerns
  include Auditable

  # 監査ログ設定
  auditable except: [ :created_at, :updated_at, :low_stock_items_count,
                     :pending_outgoing_transfers_count, :pending_incoming_transfers_count,
                     :store_inventories_count ],
            sensitive: [ :api_key, :secret_token ]

  # アソシエーション
  has_many :store_inventories, dependent: :destroy, counter_cache: true
  has_many :inventories, through: :store_inventories
  has_many :admins, dependent: :restrict_with_error
  has_many :store_users, dependent: :destroy

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
  validates :slug, presence: true, uniqueness: true,
                  format: { with: /\A[a-z0-9\-]+\z/, message: "は小文字英数字とハイフンのみ使用できます" }

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
  # コールバック
  # ============================================
  before_validation :generate_slug, if: :new_record?

  # ============================================
  # インスタンスメソッド
  # ============================================

  # 店舗の表示名（コード + 名前）
  def display_name
    "#{code} - #{name}"
  end

  # 店舗タイプの日本語表示
  def store_type_text
    I18n.t("activerecord.attributes.store.store_types.#{store_type}", default: store_type.humanize)
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

  # 低在庫商品数（Counter Cacheを使用）
  def low_stock_items_count
    # Counter Cacheカラムが存在する場合はそれを使用、なければ計算
    if has_attribute?(:low_stock_items_count)
      read_attribute(:low_stock_items_count)
    else
      calculate_low_stock_items_count
    end
  end

  # 低在庫商品数を計算
  def calculate_low_stock_items_count
    store_inventories.joins(:inventory)
                    .where("store_inventories.quantity <= store_inventories.safety_stock_level")
                    .count
  end

  # 低在庫商品数カウンタを更新
  def update_low_stock_items_count!
    count = calculate_low_stock_items_count
    update_column(:low_stock_items_count, count) if has_attribute?(:low_stock_items_count)
    count
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

  # Counter Cacheの安全なリセット
  def self.reset_counters_safely
    find_each do |store|
      # store_inventories_countのリセット
      Store.reset_counters(store.id, :store_inventories)

      # pending_outgoing_transfers_countのリセット
      store.update_column(:pending_outgoing_transfers_count,
                         store.outgoing_transfers.pending.count)

      # pending_incoming_transfers_countのリセット
      store.update_column(:pending_incoming_transfers_count,
                         store.incoming_transfers.pending.count)

      # low_stock_items_countのリセット
      store.update_low_stock_items_count!
    end
  end

  # Counter Cache整合性チェック
  def self.check_counter_cache_integrity
    inconsistencies = []

    find_each do |store|
      # store_inventories_count チェック
      actual_inventories = store.store_inventories.count
      if store.store_inventories_count != actual_inventories
        inconsistencies << {
          store: store.display_name,
          counter: "store_inventories_count",
          actual: actual_inventories,
          cached: store.store_inventories_count
        }
      end

      # pending_outgoing_transfers_count チェック
      actual_outgoing = store.outgoing_transfers.pending.count
      if store.pending_outgoing_transfers_count != actual_outgoing
        inconsistencies << {
          store: store.display_name,
          counter: "pending_outgoing_transfers_count",
          actual: actual_outgoing,
          cached: store.pending_outgoing_transfers_count
        }
      end

      # pending_incoming_transfers_count チェック
      actual_incoming = store.incoming_transfers.pending.count
      if store.pending_incoming_transfers_count != actual_incoming
        inconsistencies << {
          store: store.display_name,
          counter: "pending_incoming_transfers_count",
          actual: actual_incoming,
          cached: store.pending_incoming_transfers_count
        }
      end

      # low_stock_items_count チェック
      actual_low_stock = store.calculate_low_stock_items_count
      if store.low_stock_items_count != actual_low_stock
        inconsistencies << {
          store: store.display_name,
          counter: "low_stock_items_count",
          actual: actual_low_stock,
          cached: store.low_stock_items_count
        }
      end
    end

    inconsistencies
  end

  # 単一店舗のCounter Cache整合性チェック
  def check_counter_cache_integrity
    inconsistencies = []

    # store_inventories_count チェック
    actual_inventories = store_inventories.count
    if store_inventories_count != actual_inventories
      inconsistencies << {
        counter: "store_inventories_count",
        actual: actual_inventories,
        cached: store_inventories_count
      }
    end

    # pending_outgoing_transfers_count チェック
    actual_outgoing = outgoing_transfers.pending.count
    if pending_outgoing_transfers_count != actual_outgoing
      inconsistencies << {
        counter: "pending_outgoing_transfers_count",
        actual: actual_outgoing,
        cached: pending_outgoing_transfers_count
      }
    end

    # pending_incoming_transfers_count チェック
    actual_incoming = incoming_transfers.pending.count
    if pending_incoming_transfers_count != actual_incoming
      inconsistencies << {
        counter: "pending_incoming_transfers_count",
        actual: actual_incoming,
        cached: pending_incoming_transfers_count
      }
    end

    # low_stock_items_count チェック
    actual_low_stock = calculate_low_stock_items_count
    if low_stock_items_count != actual_low_stock
      inconsistencies << {
        counter: "low_stock_items_count",
        actual: actual_low_stock,
        cached: low_stock_items_count
      }
    end

    inconsistencies
  end

  # 単一店舗のCounter Cache修正
  def fix_counter_cache_integrity!
    # store_inventories_countの修正
    actual_inventories = store_inventories.count
    update_column(:store_inventories_count, actual_inventories) if store_inventories_count != actual_inventories

    # pending_outgoing_transfers_countの修正
    actual_outgoing = outgoing_transfers.pending.count
    update_column(:pending_outgoing_transfers_count, actual_outgoing) if pending_outgoing_transfers_count != actual_outgoing

    # pending_incoming_transfers_countの修正
    actual_incoming = incoming_transfers.pending.count
    update_column(:pending_incoming_transfers_count, actual_incoming) if pending_incoming_transfers_count != actual_incoming

    # low_stock_items_countの修正
    update_low_stock_items_count!

    Rails.logger.info "Counter Cache fixed for store: #{display_name}"
  end

  # Counter Cache統計情報
  def counter_cache_stats
    {
      store_inventories: {
        actual: store_inventories.count,
        cached: store_inventories_count,
        consistent: store_inventories.count == store_inventories_count
      },
      pending_outgoing_transfers: {
        actual: outgoing_transfers.pending.count,
        cached: pending_outgoing_transfers_count,
        consistent: outgoing_transfers.pending.count == pending_outgoing_transfers_count
      },
      pending_incoming_transfers: {
        actual: incoming_transfers.pending.count,
        cached: pending_incoming_transfers_count,
        consistent: incoming_transfers.pending.count == pending_incoming_transfers_count
      },
      low_stock_items: {
        actual: calculate_low_stock_items_count,
        cached: low_stock_items_count,
        consistent: calculate_low_stock_items_count == low_stock_items_count
      }
    }
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
  #
  # TODO: 🔴 Phase 1（緊急）- Counter Cache最適化の拡張
  # 優先度: 高（パフォーマンス向上）
  # 実装内容:
  #   - ActiveJob経由での非同期カウンタ更新
  #   - カウンタ更新のバッチ処理最適化
  #   - カウンタ整合性チェックの定期実行
  #
  # TODO: 🟡 Phase 2（重要）- 統計情報のキャッシュ戦略
  # 優先度: 中（スケーラビリティ向上）
  # 実装内容:
  #   - 店舗統計情報のRedisキャッシュ
  #   - 時系列データの効率的な保存
  #   - リアルタイムダッシュボード用のデータ準備

  private

  # 平均在庫価値計算（将来的に時系列データで改善）
  def average_inventory_value
    @average_inventory_value ||= total_inventory_value
  end

  # スラッグ生成（URL-friendly店舗識別子）
  # ============================================
  # Phase 1: 店舗別ログインシステムのURL生成基盤
  # ベストプラクティス:
  # - 小文字英数字とハイフンのみ使用
  # - 重複時は自動的に番号付与
  # - 日本語対応（transliterateは使用しない）
  # ============================================
  def generate_slug
    return if slug.present?
    return unless code.present?

    base_slug = code.downcase.gsub(/[^a-z0-9]/, "-").squeeze("-").gsub(/^-|-$/, "")

    # 重複チェックと番号付与
    candidate_slug = base_slug
    counter = 1

    while Store.exists?(slug: candidate_slug)
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    self.slug = candidate_slug
  end
end
