# frozen_string_literal: true

# マイグレーション実行履歴管理テーブル
#
# 設計原則（CLAUDE.md準拠）:
# - Google L8品質基準
# - Security by Design
# - パフォーマンス最適化
# - 横展開一貫性
class CreateMigrationExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :migration_executions do |t|
      # ============================================
      # 基本情報
      # ============================================

      # マイグレーションバージョン（一意制約）
      t.string :version, null: false, comment: 'マイグレーションバージョン（タイムスタンプ）'

      # マイグレーション名（可読性向上）
      t.string :name, null: false, comment: 'マイグレーション名'

      # 実行ステータス（ワークフロー管理）
      t.string :status, null: false, default: 'pending', comment: 'pending/running/completed/failed/rolled_back'

      # ============================================
      # 実行者・実行時刻情報
      # ============================================

      # 実行者（監査ログ）
      t.references :admin, null: false, foreign_key: true, comment: '実行者'

      # 実行時刻（SLA管理）
      t.datetime :started_at, comment: '実行開始日時'
      t.datetime :completed_at, comment: '実行完了日時'

      # ============================================
      # 進行状況管理
      # ============================================

      # 処理済みレコード数（BigInt対応）
      t.bigint :processed_records, default: 0, comment: '処理済みレコード数'

      # 総レコード数（BigInt対応）
      t.bigint :total_records, default: 0, comment: '総レコード数'

      # 進行率（計算用キャッシュ）
      t.decimal :progress_percentage, precision: 5, scale: 2, default: 0.0, comment: '進行率（%）'

      # ============================================
      # 設定・メタデータ（JSON格納）
      # ============================================

      # 実行時設定（負荷制御パラメータ等）
      t.json :configuration, comment: '実行時設定（バッチサイズ、閾値等）'

      # ロールバック用データ（ReversibleMigration連携）
      t.json :rollback_data, comment: 'ロールバック用データ'

      # パフォーマンスメトリクス
      t.json :metrics, comment: 'パフォーマンスメトリクス（CPU、メモリ等）'

      # ============================================
      # エラー情報
      # ============================================

      # エラーメッセージ
      t.text :error_message, comment: 'エラーメッセージ'

      # エラーバックトレース
      t.text :error_backtrace, comment: 'エラーバックトレース'

      # リトライ回数
      t.integer :retry_count, default: 0, comment: 'リトライ回数'

      # ============================================
      # システム情報
      # ============================================

      # 実行環境
      t.string :environment, default: 'development', comment: '実行環境'

      # 実行ホスト
      t.string :hostname, comment: '実行ホスト名'

      # プロセスID
      t.integer :process_id, comment: 'プロセスID'

      # ============================================
      # タイムスタンプ
      # ============================================
      t.timestamps null: false
    end

    # ============================================
    # インデックス（パフォーマンス最適化）
    # ============================================

    # 一意制約（バージョン重複防止）
    add_index :migration_executions, :version, unique: true, name: 'idx_migration_executions_version'

    # 複合インデックス（管理画面検索最適化）
    add_index :migration_executions, [ :status, :created_at ], name: 'idx_migration_executions_status_created'
    add_index :migration_executions, [ :admin_id, :created_at ], name: 'idx_migration_executions_admin_created'

    # ステータス検索用
    add_index :migration_executions, :status, name: 'idx_migration_executions_status'

    # 時系列検索用
    add_index :migration_executions, :started_at, name: 'idx_migration_executions_started'
    add_index :migration_executions, :completed_at, name: 'idx_migration_executions_completed'

    # 進行状況監視用
    add_index :migration_executions, :progress_percentage, name: 'idx_migration_executions_progress'

    # 環境別検索用
    add_index :migration_executions, :environment, name: 'idx_migration_executions_environment'
  end
end

# ============================================
# 設計ノート（CLAUDE.md準拠）
# ============================================

# 1. セキュリティ考慮事項
#    - 外部キー制約によるデータ整合性保証
#    - admin_id による実行者の確実な記録
#    - エラー情報の適切な管理

# 2. パフォーマンス考慮事項
#    - BigInt使用による大量レコード対応
#    - 適切なインデックス設計
#    - JSON型によるメタデータ効率格納

# 3. 拡張性考慮事項
#    - JSON型によるスキーマレス拡張
#    - 環境・ホスト情報による分散対応
#    - メトリクス情報による将来の分析対応

# 4. 運用性考慮事項
#    - 明確なコメントによる保守性向上
#    - 適切なデフォルト値設定
#    - エラー情報の完全な記録

# TODO: 次フェーズでの拡張予定
# - migration_progress_logs テーブル（詳細進行状況）
# - migration_alerts テーブル（アラート履歴）
# - パーティショニング（大量データ対応）
# - 自動アーカイブ機能（古いデータの移動）
