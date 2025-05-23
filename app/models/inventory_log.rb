# frozen_string_literal: true

class InventoryLog < ApplicationRecord
  belongs_to :inventory
  belongs_to :user, optional: true

  # バリデーション
  validates :delta, presence: true, numericality: true
  validates :operation_type, presence: true
  validates :previous_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :current_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # 操作種別の定数定義
  OPERATION_TYPES = %w[add remove adjust ship receive].freeze

  # 操作種別のenum定義
  enum operation_type: {
    add: "add",
    remove: "remove",
    adjust: "adjust",
    ship: "ship",
    receive: "receive"
  }

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_operation_type, ->(type) { where(operation_type: type) }
  scope :by_operation, ->(type) { where(operation_type: type) } # 後方互換性のため残す
  scope :by_date_range, ->(start_date, end_date) {
    start_date = start_date.beginning_of_day if start_date
    end_date = end_date.end_of_day if end_date

    query = all
    query = query.where("created_at >= ?", start_date) if start_date
    query = query.where("created_at <= ?", end_date) if end_date
    query
  }

  # 統計スコープ
  scope :additions, -> { by_operation("add") }
  scope :removals, -> { by_operation("remove") }
  scope :adjustments, -> { by_operation("adjust") }
  scope :shipments, -> { by_operation("ship") }
  scope :receipts, -> { by_operation("receive") }
  scope :this_month, -> { by_date_range(Time.current.beginning_of_month, Time.current) }
  scope :previous_month, -> { by_date_range(1.month.ago.beginning_of_month, 1.month.ago.end_of_month) }
  scope :this_year, -> { by_date_range(Time.current.beginning_of_year, Time.current) }

  # 操作種別のバリデーション
  validates :operation_type, inclusion: { in: OPERATION_TYPES }

  # CSVヘッダー
  def self.csv_header
    %w[ID 在庫ID 在庫名 操作種別 変化量 変更前数量 変更後数量 備考 作成日時]
  end

  # CSVデータ行
  def csv_row
    [
      id,
      inventory_id,
      inventory.name,
      operation_type,
      delta,
      previous_quantity,
      current_quantity,
      note,
      created_at.strftime("%Y-%m-%d %H:%M:%S")
    ]
  end

  # CSVデータ生成
  def self.generate_csv(logs)
    CSV.generate(headers: true) do |csv|
      csv << csv_header

      logs.each do |log|
        csv << log.csv_row
      end
    end
  end

  # 統計メソッド
  def self.operation_summary(start_date = 30.days.ago, end_date = Time.current)
    by_date_range(start_date, end_date)
      .group(:operation_type)
      .select("operation_type, COUNT(*) as count, SUM(ABS(delta)) as total_quantity")
  end

  def self.daily_transaction_summary(days = 30)
    start_date = days.days.ago.beginning_of_day

    by_date_range(start_date, Time.current)
      .group("DATE(created_at)")
      .select("DATE(created_at) as date, COUNT(*) as count, SUM(ABS(delta)) as total_quantity")
      .order("date DESC")
  end

  def self.top_products_by_activity(limit = 10, days = 30)
    start_date = days.days.ago.beginning_of_day

    joins(:inventory)
      .by_date_range(start_date, Time.current)
      .group("inventory_id, inventories.name")
      .select("inventory_id, inventories.name, COUNT(*) as operation_count")
      .order("operation_count DESC")
      .limit(limit)
  end

  # 日時フォーマット
  def formatted_created_at
    created_at.strftime("%Y年%m月%d日 %H:%M:%S")
  end

  # 操作タイプの日本語表示名
  def operation_display_name
    case operation_type
    when "add" then "\u8FFD\u52A0"
    when "remove" then "\u524A\u9664"
    when "adjust" then "\u8ABF\u6574"
    when "ship" then "\u51FA\u8377"
    when "receive" then "\u5165\u8377"
    else operation_type
    end
  end
end
