module BatchManageable
  extend ActiveSupport::Concern

  included do
    has_many :batches, dependent: :destroy
    after_save :sync_total_quantity, if: :saved_change_to_quantity?
  end

  def add_batch(quantity, expiry_date = nil, batch_number = nil)
    batch_number ||= generate_batch_number

    batch = batches.create!(
      quantity: quantity,
      expiry_date: expiry_date,
      batch_number: batch_number
    )

    sync_total_quantity

    batch
  end

  def consume_batch(quantity_to_use)
    return false if quantity_to_use <= 0
    return false if total_batch_quantity < quantity_to_use

    remaining = quantity_to_use

    batches.order(:expiry_date).each do |batch|
      break if remaining <= 0
      use_from_batch = [batch.quantity, remaining].min
      batch.update!(quantity: batch.quantity - use_from_batch)
      remaining -= use_from_batch
    end

    batches.where(quantity: 0).destroy_all

    sync_total_quantity

    true
  end

  def total_batch_quantity
    batches.sum(:quantity)
  end

  def nearest_expiry_date
    batches.where('quantity > 0').order(:expiry_date).first&.expiry_date
  end

  def expiring_batches(days = 30)
    batches.where('expiry_date <= ?', Date.current + days.days)
           .where('quantity > 0')
           .order(:expiry_date)
  end

  private

  def sync_total_quantity
    update_column(:quantity, total_batch_quantity) if total_batch_quantity != quantity
  end

  def generate_batch_number
    "BN-#{Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}"
  end

  module ClassMethods
    def with_expiring_batches(days = 30)
      joins(:batches)
        .where('batches.expiry_date <= ?', Date.current + days.days)
        .where('batches.quantity > 0')
        .distinct
    end

    def batch_expiry_report
      joins(:batches)
        .where('batches.quantity > 0')
        .group('inventories.id')
        .select('inventories.*, MIN(batches.expiry_date) as nearest_expiry')
        .order('nearest_expiry')
    end
  end
end
