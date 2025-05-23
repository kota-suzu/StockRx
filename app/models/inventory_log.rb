# frozen_string_literal: true

class InventoryLog < ApplicationRecord
  belongs_to :inventory
  belongs_to :user, optional: true

  # バリデーション
  validates :delta, presence: true
  validates :operation_type, presence: true
  validates :previous_quantity, presence: true
  validates :current_quantity, presence: true

  # 操作種別の定数定義
  OPERATION_TYPES = %w[add remove adjust].freeze

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_operation, ->(type) { where(operation_type: type) }
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
    operation_data = by_date_range(start_date, end_date)
      .group(:operation_type)
      .select("operation_type, COUNT(*) as count, SUM(ABS(delta)) as total_quantity")

    {
      total_operations: operation_data.sum(&:count),
      operations_by_type: operation_data.index_by(&:operation_type)
    }
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
end
