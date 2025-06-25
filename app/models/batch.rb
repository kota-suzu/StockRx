# frozen_string_literal: true

class Batch < ApplicationRecord
  include InventoryStatistics
  include Auditable

  belongs_to :inventory, counter_cache: true
  has_many :batch_movements, dependent: :destroy
  has_many :store_inventories, through: :batch_movements

  # バリデーション
  validates :lot_code, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :initial_quantity, numericality: { greater_than: 0 }, allow_nil: true

  # ロットコードと在庫IDの組み合わせでユニーク（DBレベルでも制約あり）
  validates :lot_code, uniqueness: { scope: :inventory_id, case_sensitive: false }

  # カスタムバリデーション
  validate :expiration_date_must_be_in_future, on: :create
  validate :quantity_cannot_exceed_initial

  # コールバック
  before_validation :normalize_lot_code
  before_create :set_initial_quantity
  after_update :log_quantity_change, if: :saved_change_to_quantity?

  # スコープ
  scope :expired, -> { where("expires_on < ?", Date.current) }
  scope :not_expired, -> { where("expires_on >= ? OR expires_on IS NULL", Date.current) }
  scope :expiring_soon, ->(days = 30) { where("expires_on BETWEEN ? AND ?", Date.current, Date.current + days.days) }
  scope :out_of_stock, -> { where(quantity: 0) }
  scope :low_stock, ->(threshold = nil) { where("quantity > 0 AND quantity <= ?", threshold || 5) }
  scope :with_stock, -> { where("quantity > 0") }
  scope :by_expiry, -> { order(Arel.sql("CASE WHEN expires_on IS NULL THEN 1 ELSE 0 END, expires_on ASC")) }
  scope :by_lot_code, -> { order(:lot_code) }

  # TODO: 期限切れアラート機能の実装
  # TODO: バッチ詳細表示機能の追加

  # TODO: 入荷登録機能の拡張
  # - 入荷日の記録と追跡
  # - サプライヤー情報の関連付け
  # - 入荷コストの記録

  # TODO: バッチ移動・譲渡機能
  # - 他の在庫への移動履歴
  # - 複数ロケーション管理

  # TODO: バッチ品質管理機能
  # - 品質検査結果の記録
  # - 温度管理要件の設定と監視
  # - バッチごとの安全性情報の記録

  # ============================================
  # TODO: バッチ管理機能の拡張計画
  # ============================================
  # 1. 高度なトレーサビリティ
  #    - サプライチェーン全体の追跡機能
  #    - 原材料から最終製品までの完全な履歴
  #    - ブロックチェーンによる改ざん防止
  #    - QRコード/RFID による即座のトレース
  #
  # 2. 品質管理・コンプライアンス
  #    - リコール対象範囲の即座特定
  #    - 品質検査結果の自動記録
  #    - GMP（Good Manufacturing Practice）対応
  #    - FDA/厚労省等規制当局への報告書自動生成
  #
  # 3. 期限管理・最適化
  #    - FEFO（First Expired, First Out）自動適用
  #    - 期限切れアラートの高度化
  #    - 廃棄コスト最小化アルゴリズム
  #    - 動的な安全在庫計算
  #
  # 4. 分析・最適化機能
  #    - バッチサイズ最適化提案
  #    - 製造効率性分析レポート
  #    - 品質データの統計分析
  #    - 収率改善提案システム
  #
  # 5. 国際対応・多拠点管理
  #    - 各国規制への自動対応
  #    - 多言語でのバッチ情報管理
  #    - 拠点間でのバッチ移動追跡
  #    - 通貨・単位の自動変換
  #
  # 6. IoT・自動化連携
  #    - センサーデータとの自動連携
  #    - 製造設備からの自動データ取得
  #    - 環境条件（温度・湿度）の自動記録
  #    - スマートファクトリー対応

  # 期限切れかどうかを判定するメソッド
  def expired?
    expires_on.present? && expires_on < Date.current
  end

  # 期限切れが近いかどうかを判定するメソッド（デフォルト30日前）
  def expiring_soon?(days_threshold = 30)
    expires_on.present? && !expired? && expires_on < Date.current + days_threshold.days
  end

  # 在庫切れかどうかを判定するメソッド
  def out_of_stock?
    quantity == 0
  end

  # 在庫が少ないかどうかを判定するメソッド（デフォルト閾値は5）
  def low_stock?(threshold = nil)
    threshold ||= low_stock_threshold
    quantity > 0 && quantity <= threshold
  end

  # 在庫アラート閾値の設定（将来的には設定から取得するなど拡張予定）
  def low_stock_threshold
    5 # デフォルト値
  end

  # 期限までの日数を計算
  def days_until_expiry
    return nil if expires_on.blank?
    (expires_on - Date.current).to_i
  end

  # 期限ステータスを返す
  def expiry_status
    return :no_expiry if expires_on.blank?
    return :expired if expired?
    return :expiring_soon if expiring_soon?
    :valid
  end

  # 在庫消費（減少）処理
  def consume(amount)
    return false if amount > quantity

    ActiveRecord::Base.transaction do
      self.quantity -= amount
      if save
        # InventoryLogの作成はafter_updateコールバックで処理される
        true
      else
        errors.add(:base, "Failed to update quantity")
        raise ActiveRecord::Rollback
      end
    end
  rescue => e
    errors.add(:base, "Insufficient quantity in batch #{lot_code}")
    false
  end

  # 在庫補充処理
  def replenish(amount)
    new_quantity = quantity + amount

    if initial_quantity && new_quantity > initial_quantity
      errors.add(:base, "Cannot exceed initial quantity of #{initial_quantity}")
      return false
    end

    ActiveRecord::Base.transaction do
      self.quantity = new_quantity
      save
    end
  end

  # 使用率の計算
  def usage_percentage
    return 0 if initial_quantity.nil? || initial_quantity.zero?
    ((initial_quantity - quantity).to_f / initial_quantity * 100).round(2)
  end

  # 店舗への移動処理
  def move_to_store(store, amount)
    return false if amount > quantity

    ActiveRecord::Base.transaction do
      # BatchMovementが定義されていればそれを使用
      if defined?(BatchMovement)
        BatchMovement.create!(
          batch: self,
          store: store,
          quantity: amount,
          movement_date: Date.current
        )
      end

      consume(amount)
    end
  end

  # 現在の配布先店舗と数量
  def current_locations
    return {} unless defined?(BatchMovement)

    batch_movements
      .joins(:store)
      .group(:store)
      .sum(:quantity)
  end

  # バッチの価値計算
  def calculate_value
    return 0 unless inventory&.price
    (quantity * inventory.price).to_f
  end

  # FIFO優先度（期限が近い、または作成日が古いものが優先）
  def fifo_priority
    # 期限がある場合は期限日を基準に、ない場合は作成日を基準に
    if expires_on.present?
      # 期限が近いほど高い優先度（小さい値）
      -expires_on.to_time.to_i
    else
      # 作成日が古いほど高い優先度（小さい値）
      -created_at.to_i
    end
  end

  private

  # バリデーションメソッド
  def expiration_date_must_be_in_future
    return unless expires_on.present? && new_record?

    if expires_on < Date.current
      errors.add(:expires_on, "must be in the future")
    end
  end

  def quantity_cannot_exceed_initial
    return unless initial_quantity.present? && quantity.present?

    if quantity > initial_quantity
      errors.add(:quantity, "cannot exceed initial quantity")
    end
  end

  # コールバックメソッド
  def normalize_lot_code
    self.lot_code = lot_code.to_s.strip.upcase if lot_code.present?
  end

  def set_initial_quantity
    self.initial_quantity ||= quantity
  end

  def log_quantity_change
    return unless inventory.present?

    delta = quantity - quantity_before_last_save
    return if delta.zero?

    InventoryLog.create!(
      inventory: inventory,
      operation_type: "adjust",
      delta: delta,
      user: Current.user || Current.admin,
      note: "Batch #{lot_code} quantity adjusted",
      previous_quantity: quantity_before_last_save || 0,
      current_quantity: quantity || 0
    )
  end
end
