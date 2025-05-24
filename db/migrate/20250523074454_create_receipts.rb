class CreateReceipts < ActiveRecord::Migration[7.2]
  def change
    create_table :receipts do |t|
      t.references :inventory, null: false, foreign_key: true
      t.integer :quantity
      t.string :source
      t.date :receipt_date
      t.integer :receipt_status
      t.string :batch_number
      t.string :purchase_order
      t.decimal :cost_per_unit
      t.text :notes

      t.timestamps
    end
  end
end
