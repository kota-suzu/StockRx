class AddNotesAndRequestedDeliveryDateToInterStoreTransfers < ActiveRecord::Migration[8.0]
  def change
    add_column :inter_store_transfers, :notes, :text
    add_column :inter_store_transfers, :requested_delivery_date, :date
  end
end
