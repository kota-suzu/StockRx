# ============================================================================
# CreateReportFiles Migration
# ============================================================================
# 目的: 生成されたレポートファイルの追跡とメタデータ管理
# 機能: ファイル保管・検索・保持期間管理・削除ポリシー

class CreateReportFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :report_files do |t|
      # ============================================
      # 基本情報
      # ============================================
      t.string :report_type, null: false, comment: 'レポート種別 (monthly_summary, inventory_analysis)'
      t.string :file_format, null: false, comment: 'ファイル形式 (excel, pdf)'
      t.date :report_period, null: false, comment: 'レポート対象期間 (YYYY-MM-01形式)'

      # ============================================
      # ファイル情報
      # ============================================
      t.string :file_name, null: false, comment: 'ファイル名'
      t.string :file_path, null: false, comment: 'ファイル保存パス'
      t.string :storage_type, null: false, default: 'local', comment: '保存場所 (local, s3, gcs)'
      t.bigint :file_size, comment: 'ファイルサイズ（バイト）'
      t.string :file_hash, comment: 'ファイルハッシュ値（整合性確認用）'

      # ============================================
      # 生成メタデータ
      # ============================================
      t.references :admin, null: false, foreign_key: true, comment: '生成実行者'
      t.json :generation_metadata, comment: '生成時のメタデータ（実行時間、パラメータ等）'
      t.datetime :generated_at, null: false, comment: 'ファイル生成日時'

      # ============================================
      # アクセス・配信管理
      # ============================================
      t.integer :download_count, default: 0, comment: 'ダウンロード回数'
      t.datetime :last_accessed_at, comment: '最終アクセス日時'
      t.integer :email_delivery_count, default: 0, comment: 'メール配信回数'
      t.datetime :last_delivered_at, comment: '最終配信日時'

      # ============================================
      # 保持・削除管理
      # ============================================
      t.string :retention_policy, default: 'standard', comment: '保持ポリシー (standard, extended, permanent)'
      t.date :expires_at, comment: '保持期限日'
      t.string :status, default: 'active', comment: 'ファイル状態 (active, archived, deleted)'
      t.datetime :archived_at, comment: 'アーカイブ日時'
      t.datetime :deleted_at, comment: '削除日時'

      # ============================================
      # システム管理
      # ============================================
      t.string :checksum_algorithm, default: 'sha256', comment: 'チェックサム算出アルゴリズム'
      t.text :notes, comment: '管理者メモ'

      t.timestamps
    end

    # ============================================
    # インデックス設定
    # ============================================

    # 基本検索用インデックス
    add_index :report_files, [ :report_type, :report_period ], name: 'idx_report_files_type_period'
    add_index :report_files, [ :file_format, :status ], name: 'idx_report_files_format_status'
    add_index :report_files, :generated_at, name: 'idx_report_files_generated_at'

    # 管理用インデックス
    add_index :report_files, :admin_id, name: 'idx_report_files_admin_id'
    add_index :report_files, [ :status, :expires_at ], name: 'idx_report_files_cleanup'
    add_index :report_files, :last_accessed_at, name: 'idx_report_files_last_access'

    # ユニーク制約（同一期間・タイプ・フォーマットの重複防止）
    add_index :report_files, [ :report_type, :file_format, :report_period, :status ],
              unique: true,
              where: "status = 'active'",
              name: 'idx_report_files_unique_active'
  end
end
