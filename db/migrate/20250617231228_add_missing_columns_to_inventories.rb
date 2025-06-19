class AddMissingColumnsToInventories < ActiveRecord::Migration[8.0]
  # CLAUDE.md準拠: 🔴 Phase 1（緊急）- 欠落カラムの追加
  # 優先度: 最高（現在のエラーの原因）
  # 目的: コントローラーが参照する存在しないカラムを追加
  # 横展開: 全てのinventory関連コントローラー・ビューが対象

  def change
    # SKU（Stock Keeping Unit）: 商品識別コード
    add_column :inventories, :sku, :string, comment: "商品識別コード"
    add_index :inventories, :sku, unique: true, name: "index_inventories_on_sku"

    # メーカー名
    add_column :inventories, :manufacturer, :string, comment: "メーカー名"
    add_index :inventories, :manufacturer, name: "index_inventories_on_manufacturer"

    # 単位（例：箱、個、ml等）
    add_column :inventories, :unit, :string, comment: "数量単位"
    add_index :inventories, :unit, name: "index_inventories_on_unit"
  end

  # ロールバック時の注意事項
  def down
    # カラム削除前に参照するコードがないことを確認
    # TODO: ロールバック前に関連コントローラーの修正が必要
    remove_column :inventories, :unit
    remove_column :inventories, :manufacturer
    remove_column :inventories, :sku
  end
end
