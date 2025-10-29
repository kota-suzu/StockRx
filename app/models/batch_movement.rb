# frozen_string_literal: true

class BatchMovement < ApplicationRecord
  belongs_to :batch
  belongs_to :store
  belongs_to :store_inventory, optional: true

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :movement_date, presence: true

  # スコープ
  scope :recent, -> { order(movement_date: :desc) }
  scope :by_store, ->(store) { where(store: store) }
  scope :by_batch, ->(batch) { where(batch: batch) }

  # コールバック
  after_create :update_store_inventory

  private

  def update_store_inventory
    # StoreInventoryの在庫を更新
    store_inv = StoreInventory.find_or_create_by(
      store: store,
      inventory: batch.inventory
    )

    store_inv.increment!(:quantity, quantity)
  end
end
