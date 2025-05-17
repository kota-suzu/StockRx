require "csv"

class Inventory < ApplicationRecord
  has_many :batches, dependent: :destroy

  # ステータス定義（Rails 8.0向けに更新）
  enum :status, { active: 0, archived: 1 }
  STATUSES = statuses.keys.freeze # 不変保証

  # バリデーション
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  # スコープ
  scope :active, -> { where(status: :active) }
  scope :out_of_stock, -> { where(quantity: 0) }
  scope :low_stock, ->(threshold = nil) { where("quantity > 0 AND quantity <= ?", threshold || 5) }

  # バルク登録用クラスメソッド
  class << self
    # CSVからの一括インポート
    def import_from_csv(file)
      # CSVデータの検証
      valid_records = []
      invalid_records = []

      # トランザクション内で処理
      ActiveRecord::Base.transaction do
        CSV.foreach(file.path, headers: true) do |row|
          # ステータスのバリデーション（無効な値の場合はデフォルト値を使用）
          status_value = row["status"].presence || "active"
          unless STATUSES.include?(status_value)
            status_value = "active" # デフォルト値を使用
          end

          inventory = new(
            name: row["name"],
            quantity: row["quantity"].to_i,
            price: row["price"].to_f,
            status: status_value
          )

          if inventory.valid?
            valid_records << inventory
          else
            invalid_records << { row: row, errors: inventory.errors.full_messages }
          end
        end

        # バルクインサート（Rails 6以降）
        # 大量データの場合はactiverecord-importのbatch_sizeオプションも検討
        Inventory.insert_all(
          valid_records.map { |record|
            record.attributes.except("id", "created_at", "updated_at").merge(
              created_at: Time.current,
              updated_at: Time.current
            )
          }
        ) if valid_records.present?
      end

      { valid_count: valid_records.size, invalid_records: invalid_records }
    end
  end

  # バッチの合計数量を取得するメソッド
  def total_batch_quantity
    batches.sum(:quantity)
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

  # 期限切れのバッチを取得するメソッド
  def expired_batches
    batches.expired
  end

  # 期限切れが近いバッチを取得するメソッド
  def expiring_soon_batches(days = 30)
    batches.expiring_soon(days)
  end

  # TODO: 在庫アラート機能の実装
  # - アラートのメール通知機能
  # - 在庫切れ商品の自動レポート生成機能
  # - アラート閾値の設定インターフェース

  # TODO: バーコードスキャン対応
  # - バーコードでの商品検索機能
  # - QRコード生成機能
  # - モバイルスキャンアプリとの連携

  # TODO: 高度な在庫分析機能
  # - 在庫回転率の計算
  # - 発注点（Reorder Point）の計算と通知
  # - 需要予測と最適在庫レベルの提案
  # - 履歴データに基づく季節変動分析

  # TODO: システムテスト環境の整備
  # - CapybaraとSeleniumの設定改善
  # - Docker環境でのUIテスト対応
  # - E2Eテストの実装
end
