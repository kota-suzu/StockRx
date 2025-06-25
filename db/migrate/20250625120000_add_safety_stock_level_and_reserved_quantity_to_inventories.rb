# frozen_string_literal: true

# Add safety_stock_level and reserved_quantity columns to inventories table
# CLAUDE.md準拠: データベース設計原則 - 強制制約・インデックス・デフォルト値設定
class AddSafetyStockLevelAndReservedQuantityToInventories < ActiveRecord::Migration[8.0]
  def change
    add_column :inventories, :safety_stock_level, :integer,
               default: 10,
               null: false,
               comment: "安全在庫レベル（アラート閾値、デフォルト10）"

    add_column :inventories, :reserved_quantity, :integer,
               default: 0,
               null: false,
               comment: "予約済み在庫数（移動申請中・予約中等、デフォルト0）"

    # インデックス追加 - パフォーマンス最適化
    add_index :inventories, [ :quantity, :safety_stock_level ],
              name: "idx_inventories_stock_levels",
              comment: "在庫レベル検索最適化（low_stock判定用）"

    add_index :inventories, :reserved_quantity,
              name: "idx_inventories_reserved",
              comment: "予約済み在庫検索最適化"

    # チェック制約追加 - データ整合性保証
    # reserved_quantity <= quantity の制約
    add_check_constraint :inventories,
                        "reserved_quantity <= quantity",
                        name: "chk_reserved_not_exceed_quantity"

    # safety_stock_level > 0 の制約
    add_check_constraint :inventories,
                        "safety_stock_level > 0",
                        name: "chk_positive_safety_stock"
  end
end
