# frozen_string_literal: true

# Database Agnostic Search Concern
# ============================================
# CLAUDE.md準拠: MySQL/PostgreSQL両対応の検索機能
# 横展開: 全コントローラーで共通使用
# ============================================
module DatabaseAgnosticSearch
  extend ActiveSupport::Concern

  # ============================================
  # データベース非依存検索メソッド
  # ============================================

  private

  # 大文字小文字を区別しない LIKE 検索
  # MySQL: LIKE (大文字小文字区別しない設定済み)
  # PostgreSQL: ILIKE
  def case_insensitive_like_operator
    case ActiveRecord::Base.connection.adapter_name.downcase
    when "postgresql"
      "ILIKE"
    when "mysql", "mysql2"
      "LIKE"
    else
      # その他のDB（SQLite等）はLIKEを使用
      "LIKE"
    end
  end

  # 複数カラムでの case-insensitive 検索
  # 使用例: search_across_columns(User, ['name', 'email'], 'search_term')
  def search_across_columns(relation, columns, search_term)
    return relation if search_term.blank? || columns.empty?

    # SQLインジェクション対策: パラメータ化クエリ使用
    search_pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_term)}%"
    operator = case_insensitive_like_operator

    # 各カラムでの検索条件を構築
    conditions = columns.map { |column| "#{column} #{operator} ?" }
    where_clause = conditions.join(" OR ")

    # パラメータ配列（カラム数分の検索パターン）
    parameters = Array.new(columns.length, search_pattern)

    relation.where(where_clause, *parameters)
  end

  # 単一カラムでの case-insensitive 検索
  # 使用例: search_single_column(User, 'name', 'search_term')
  def search_single_column(relation, column, search_term)
    search_across_columns(relation, [ column ], search_term)
  end

  # 階層構造を持つ検索（JOINが必要な場合）
  # 使用例: search_with_joins(Transfer, :source_store, ['stores.name'], 'search_term')
  def search_with_joins(relation, join_table, columns, search_term)
    return relation if search_term.blank? || columns.empty?

    relation_with_joins = relation.joins(join_table)
    search_across_columns(relation_with_joins, columns, search_term)
  end

  # 複数テーブル横断検索
  # より複雑な検索パターンに対応
  def search_across_joined_tables(relation, table_column_mappings, search_term)
    return relation if search_term.blank? || table_column_mappings.empty?

    search_pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search_term)}%"
    operator = case_insensitive_like_operator

    all_columns = []
    required_joins = []

    table_column_mappings.each do |table, columns|
      if table == :base
        # ベーステーブルのカラム
        all_columns.concat(columns)
      else
        # JOINが必要なテーブルのカラム
        required_joins << table
        # テーブル名を明示したカラム指定
        prefixed_columns = columns.map { |col| "#{table.to_s.tableize}.#{col}" }
        all_columns.concat(prefixed_columns)
      end
    end

    # 必要なJOINを適用
    relation_with_joins = required_joins.reduce(relation) { |rel, join| rel.joins(join) }

    # 検索条件を構築
    conditions = all_columns.map { |column| "#{column} #{operator} ?" }
    where_clause = conditions.join(" OR ")
    parameters = Array.new(all_columns.length, search_pattern)

    relation_with_joins.where(where_clause, *parameters)
  end

  # ============================================
  # パフォーマンス最適化メソッド
  # ============================================

  # 検索結果のカウント（大量データ対応）
  def efficient_search_count(relation)
    # EXPLAIN PLAN での最適化確認
    if Rails.env.development?
      Rails.logger.debug "Search Query Plan: #{relation.explain}"
    end

    relation.count
  end

  # 検索結果のページネーション（Kaminari対応）
  def paginated_search_results(relation, page: 1, per_page: 20)
    relation.page(page).per([ per_page, 100 ].min) # 最大100件制限
  end

  # ============================================
  # セキュリティ関連メソッド
  # ============================================

  # 検索キーワードのサニタイゼーション
  def sanitize_search_term(term)
    return "" if term.blank?

    # SQLインジェクション対策
    sanitized = ActiveRecord::Base.sanitize_sql_like(term.to_s)

    # XSS対策（HTMLエスケープ）
    sanitized = ERB::Util.html_escape(sanitized)

    # 検索キーワード長制限（DoS攻撃対策）
    sanitized.truncate(100)
  end

  # 許可された検索カラムのみを使用
  def validate_search_columns(columns, allowed_columns)
    invalid_columns = columns - allowed_columns

    if invalid_columns.any?
      Rails.logger.warn "Invalid search columns attempted: #{invalid_columns.join(', ')}"
      raise ArgumentError, "不正な検索対象が指定されました"
    end

    columns
  end
end

# ============================================
# TODO: 🟡 Phase 3 - 高度な検索機能の拡張
# ============================================
# 優先度: 中（機能強化）
#
# 【計画中の拡張機能】
# 1. 🔍 全文検索対応
#    - MySQL: FULLTEXT INDEX + MATCH() AGAINST()
#    - PostgreSQL: tsvector + tsquery
#    - 日本語形態素解析対応
#
# 2. 🎯 ファジー検索
#    - 類似度計算（Levenshtein距離）
#    - 曖昧検索（typo許容）
#    - 同義語展開
#
# 3. 📊 検索分析
#    - 検索キーワード統計
#    - 検索結果0件の分析
#    - 検索パフォーマンス監視
#
# 4. 🎛️ 高度フィルタリング
#    - 範囲検索（日付、数値）
#    - 複数条件組み合わせ
#    - 保存可能な検索条件
#
# 【実装時の考慮事項】
# - インデックス設計の最適化
# - キャッシュ戦略の検討
# - レスポンス時間の維持
# - メモリ使用量の監視
#
# ============================================
