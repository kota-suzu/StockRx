# frozen_string_literal: true

module BatchManageable
  extend ActiveSupport::Concern

  included do
    has_many :batches, dependent: :destroy

    after_save :sync_total_quantity, if: :saved_change_to_quantity?
  end

  # インスタンスメソッド
  def add_batch(quantity, expiry_date = nil, batch_number = nil)
    batch_number ||= generate_batch_number

    batch = batches.create!(
      quantity: quantity,
      expires_on: expiry_date,
      lot_code: batch_number
    )

    sync_total_quantity

    batch
  end

  def consume_batch(quantity_to_use)
    return false if quantity_to_use <= 0
    return false if total_batch_quantity < quantity_to_use

    remaining = quantity_to_use

    # 先に有効期限が近いバッチから消費
    batches.order(:expires_on).each do |batch|
      break if remaining <= 0

      use_from_batch = [ batch.quantity, remaining ].min
      batch.update!(quantity: batch.quantity - use_from_batch)

      remaining -= use_from_batch
    end

    # ゼロになったバッチを削除（オプション）
    batches.where(quantity: 0).destroy_all

    sync_total_quantity

    true
  end

  def total_batch_quantity
    batches.sum(:quantity)
  end

  def nearest_expiry_date
    batches.where("quantity > 0").order(:expires_on).first&.expires_on
  end

  def expiring_batches(days = 30)
    batches.where("expires_on > ? AND expires_on <= ?", Date.current, Date.current + days.days)
           .where("quantity > 0")
           .order(:expires_on)
  end

  # 期限切れが近いバッチを取得するメソッド
  def expiring_soon_batches(days = 30)
    expiring_batches(days)
  end

  # 期限切れのバッチを取得するメソッド
  def expired_batches
    batches.where("expires_on < ?", Date.current)
           .where("quantity > 0")
           .order(:expires_on)
  end

  private

  def sync_total_quantity
    # バッチが存在しない場合は同期しない（初期作成時など）
    return if batches.count == 0

    new_quantity = total_batch_quantity
    update_column(:quantity, new_quantity) if new_quantity != quantity
  end

  def generate_batch_number
    "BN-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}"
  end

  # クラスメソッド
  module ClassMethods
    def with_expiring_batches(days = 30)
      joins(:batches)
        .where("batches.expires_on <= ?", Date.current + days.days)
        .where("batches.quantity > 0")
        .distinct
    end

    def batch_expiry_report
      joins(:batches)
        .where("batches.quantity > 0")
        .group("inventories.id")
        .select("inventories.*, MIN(batches.expires_on) as nearest_expiry")
        .order("nearest_expiry")
    end

    # TODO: バッチ管理機能の拡張
    # 1. バッチの自動期限切れ通知機能
    #    - 期限切れ間近のバッチに対する自動通知システム
    #    - 通知タイミングの設定機能（例：7日前、3日前、当日）
    #    - メール・Slack等への通知配信機能
    #
    # 2. バッチのトレーサビリティ強化
    #    - 製造元・入荷元情報の管理
    #    - 品質管理データの追加
    #    - バッチごとのQRコード生成機能
    #
    # 3. 先入先出（FIFO）自動消費機能
    #    - 出荷時の自動バッチ選択ロジック
    #    - 期限切れリスクの最小化
    #    - 手動上書き機能の提供
  end
end
