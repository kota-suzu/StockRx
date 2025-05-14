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
          inventory = new(
            name: row["name"],
            quantity: row["quantity"].to_i,
            price: row["price"].to_f,
            status: row["status"] || "active"
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

  # TODO: 在庫アラート機能（在庫切れ・期限切れ）の実装
  # TODO: バーコードスキャン対応のためのメソッド追加
end
