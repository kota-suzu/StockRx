class AddReorderLevelToStoreInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :store_inventories, :reorder_level, :integer, comment: "発注レベル（この数量以下で発注が必要）"
  end
end
