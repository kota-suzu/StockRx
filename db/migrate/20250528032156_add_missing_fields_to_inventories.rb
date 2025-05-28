class AddMissingFieldsToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :category, :string, default: '一般薬'
    add_column :inventories, :unit, :string, default: '個'
    add_column :inventories, :minimum_stock, :integer, default: 0
  end
end
