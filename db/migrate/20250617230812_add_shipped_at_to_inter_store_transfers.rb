class AddShippedAtToInterStoreTransfers < ActiveRecord::Migration[8.0]
  # CLAUDE.md準拠: InterStoreTransferモデルのshipped_atカラム追加
  # メタ認知: 完全なイベントトラッキング（申請→承認→出荷→完了）のため必須
  # 横展開: requested_at, approved_at, completed_atとの一貫性確保
  def change
    add_column :inter_store_transfers, :shipped_at, :datetime,
               comment: "出荷日時"

    # パフォーマンス最適化: 出荷日時での検索・ソート用インデックス
    # ベストプラクティス: タイムライン表示での高速化
    add_index :inter_store_transfers, :shipped_at,
              comment: "出荷日時検索最適化"

    # TODO: 🔴 Phase 1（緊急）- shipped_by_idとの複合インデックス検討
    #   - 出荷者別の出荷履歴検索最適化
    #   - 管理者別パフォーマンス分析機能
    #   - 横展開: 他のタイムスタンプ + ユーザーID複合インデックス
    #
    # TODO: 🟡 Phase 3（重要）- shipped_atとステータスの整合性制約
    #   - CHECK制約: in_transit/completedステータス時のshipped_at必須化
    #   - データ整合性確保とビジネスルール強制
    #   - 横展開: 他のタイムスタンプでも同様の制約検討
  end
end
