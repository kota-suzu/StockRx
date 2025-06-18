# frozen_string_literal: true

class AddIndexToInventoriesQuantity < ActiveRecord::Migration[7.2]
  def change
    # CLAUDE.md準拠: パフォーマンス最適化 - 在庫数範囲検索の高速化
    # メタ認知: 在庫数でのフィルタリングは頻繁に使用される機能
    # ベストプラクティス: 範囲検索に最適なB-treeインデックス
    # 横展開: store_inventoriesテーブルには既に同様のインデックスが存在
    
    # 在庫数単体でのインデックス（範囲検索最適化）
    add_index :inventories, :quantity, 
              name: "idx_inventories_quantity",
              comment: "在庫数範囲検索最適化（min_quantity/max_quantity フィルター用）"
    
    # 複合インデックス（ステータスと在庫数の組み合わせ検索最適化）
    add_index :inventories, [:status, :quantity], 
              name: "idx_inventories_status_quantity",
              comment: "ステータス別在庫数検索最適化"
    
    # TODO: 🟡 Phase 3（重要）- 追加インデックスの検討
    # 優先度: 中（クエリパフォーマンス向上）
    # 実装内容:
    #   - price と quantity の複合インデックス（価格・在庫数同時フィルター用）
    #   - created_at と quantity の複合インデックス（期間別在庫分析用）
    #   - カバリングインデックスの検討（SELECT時のテーブルアクセス削減）
    # 期待効果: 複雑な検索クエリの実行時間50%削減
  end
end