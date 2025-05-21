module InventoryLoggable
  extend ActiveSupport::Concern

  included do
    has_many :inventory_logs, dependent: :destroy
    after_save :log_inventory_changes, if: :saved_change_to_quantity?
  end

  def log_operation(operation_type, delta, note = nil, user_id = nil)
    previous_quantity = quantity - delta

    inventory_logs.create!(
      delta: delta,
      operation_type: operation_type,
      previous_quantity: previous_quantity,
      current_quantity: quantity,
      user_id: user_id || (defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil),
      note: note || "手動記録: #{operation_type}"
    )
  end

  def adjust_quantity(new_quantity, note = nil, user_id = nil)
    delta = new_quantity - quantity
    return if delta.zero?

    operation_type = delta.positive? ? 'add' : 'remove'

    with_transaction do
      update!(quantity: new_quantity)
      log_operation(operation_type, delta, note, user_id)
    end
  end

  private

  def log_inventory_changes
    previous_quantity = saved_change_to_quantity.first || 0
    current_quantity = quantity
    delta = current_quantity - previous_quantity

    return if delta.zero?

    inventory_logs.create!(
      delta: delta,
      operation_type: determine_operation_type(delta),
      previous_quantity: previous_quantity,
      current_quantity: current_quantity,
      user_id: defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil,
      note: "自動記録：数量変更"
    )
  rescue => e
    Rails.logger.error("在庫ログ記録エラー: #{e.message}")
  end

  def determine_operation_type(delta)
    case
    when delta > 0 then 'add'
    when delta < 0 then 'remove'
    else 'adjust'
    end
  end

  def with_transaction(&block)
    self.class.transaction(&block)
  end

  module ClassMethods
    def recent_operations(limit = 50)
      includes(:inventory_logs, :batches)
        .joins(:inventory_logs)
        .order('inventory_logs.created_at DESC')
        .limit(limit)
    end

    def operation_summary(start_date = 30.days.ago, end_date = Time.current)
      joins(:inventory_logs)
        .where('inventory_logs.created_at BETWEEN ? AND ?', start_date, end_date)
        .group('inventory_logs.operation_type')
        .select('inventory_logs.operation_type, COUNT(*) as count, SUM(ABS(inventory_logs.delta)) as total_quantity')
    end
  end
end
