class Batch < ApplicationRecord
  belongs_to :inventory

  # バリデーション
  validates :lot_code, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  # ロットコードと在庫IDの組み合わせでユニーク（DBレベルでも制約あり）
  validates :lot_code, uniqueness: { scope: :inventory_id }

  # TODO: 期限切れアラート機能の実装
  # TODO: バッチ詳細表示機能の追加

  # 期限切れかどうかを判定するメソッド
  def expired?
    expires_on.present? && expires_on < Date.current
  end

  # 期限切れが近いかどうかを判定するメソッド（デフォルト30日前）
  def expiring_soon?(days_threshold = 30)
    expires_on.present? && !expired? && expires_on < Date.current + days_threshold.days
  end
end
