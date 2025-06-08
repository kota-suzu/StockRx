# frozen_string_literal: true

# マイグレーション進行状況詳細ログテーブル
#
# 設計原則（CLAUDE.md準拠）:
# - リアルタイム監視対応
# - 高頻度インサート最適化
# - ActionCable統合準備
class CreateMigrationProgressLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :migration_progress_logs do |t|
      # ============================================
      # 関連性
      # ============================================

      # 親のマイグレーション実行レコード
      t.references :migration_execution, null: false, foreign_key: true, comment: 'マイグレーション実行ID'

      # ============================================
      # 進行状況情報
      # ============================================

      # 実行フェーズ（schema_change, data_migration, cleanup等）
      t.string :phase, null: false, comment: '実行フェーズ'

      # 進行率（0-100）
      t.decimal :progress_percentage, precision: 5, scale: 2, null: false, default: 0.0, comment: '進行率（%）'

      # 処理済みレコード数（このログ時点）
      t.bigint :processed_records, default: 0, comment: '処理済みレコード数'

      # バッチ情報
      t.integer :current_batch_size, comment: '現在のバッチサイズ'
      t.integer :current_batch_number, comment: '現在のバッチ番号'

      # ============================================
      # ログメッセージ
      # ============================================

      # メインメッセージ
      t.text :message, comment: 'ログメッセージ'

      # ログレベル（info, warn, error, debug）
      t.string :log_level, default: 'info', comment: 'ログレベル'

      # ============================================
      # システムメトリクス
      # ============================================

      # リアルタイムシステム情報（JSON格納）
      t.json :metrics, comment: 'システムメトリクス'
      # 格納例:
      # {
      #   "cpu_usage": 45.2,
      #   "memory_usage": 72.8,
      #   "db_connections": 15,
      #   "query_time": 0.245,
      #   "records_per_second": 1250
      # }

      # ============================================
      # パフォーマンス情報
      # ============================================

      # このログエントリ時点でのパフォーマンス
      t.decimal :records_per_second, precision: 10, scale: 2, comment: 'レコード処理速度（/秒）'
      t.decimal :estimated_remaining_seconds, precision: 10, scale: 2, comment: '推定残り時間（秒）'

      # ============================================
      # ActionCable用情報
      # ============================================

      # ブロードキャスト済みフラグ（重複配信防止）
      t.boolean :broadcasted, default: false, comment: 'ActionCableブロードキャスト済み'

      # ブロードキャスト日時
      t.datetime :broadcasted_at, comment: 'ブロードキャスト日時'

      # ============================================
      # タイムスタンプ
      # ============================================
      t.timestamps null: false
    end

    # ============================================
    # インデックス（高頻度アクセス最適化）
    # ============================================

    # 主要検索パターン（時系列順取得）
    add_index :migration_progress_logs,
              [ :migration_execution_id, :created_at ],
              name: 'idx_progress_logs_execution_time'

    # フェーズ別検索
    add_index :migration_progress_logs,
              [ :migration_execution_id, :phase ],
              name: 'idx_progress_logs_execution_phase'

    # ログレベル検索（エラー調査用）
    add_index :migration_progress_logs, :log_level, name: 'idx_progress_logs_level'

    # ActionCable配信管理用
    add_index :migration_progress_logs,
              [ :broadcasted, :created_at ],
              name: 'idx_progress_logs_broadcast_time'

    # パフォーマンス分析用
    add_index :migration_progress_logs, :records_per_second, name: 'idx_progress_logs_performance'
  end
end

# ============================================
# 設計ノート（CLAUDE.md準拠）
# ============================================

# 1. 高頻度インサート対応
#    - 外部キー制約を最小限に抑制
#    - インデックス数の最適化
#    - JSON型による柔軟なメトリクス格納

# 2. リアルタイム監視対応
#    - ActionCable統合フィールド準備
#    - ブロードキャスト制御機構
#    - パフォーマンス情報の即座計算

# 3. 運用性考慮
#    - ログレベルによる重要度分類
#    - フェーズによる進行状況可視化
#    - システムメトリクスによる負荷監視

# 4. データライフサイクル管理
#    - 大量データ対応（BigInt使用）
#    - 将来のパーティショニング準備
#    - 自動クリーンアップ機能準備

# TODO: 運用最適化
# - 古いログの自動アーカイブ（7日以上）
# - パーティショニング実装（月次分割）
# - メトリクス集約テーブル（時系列DB連携）
# - アラート閾値管理テーブル
