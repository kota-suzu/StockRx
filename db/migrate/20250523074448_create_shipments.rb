class CreateShipments < ActiveRecord::Migration[7.2]
  def change
    create_table :shipments do |t|
      t.references :inventory, null: false, foreign_key: true
      t.integer :quantity
      t.string :destination
      t.date :scheduled_date
      t.integer :shipment_status
      t.string :tracking_number
      t.string :carrier
      t.text :notes
      t.integer :return_quantity
      t.string :return_reason
      t.date :return_date

      t.timestamps
    end
  end
end
