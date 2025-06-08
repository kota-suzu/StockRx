# frozen_string_literal: true

# SearchResult - 検索結果の構造化と型安全性向上
#
# 設計書に基づいた統一的な検索結果オブジェクト
# パフォーマンス、セキュリティ、可観測性を統合
SearchResult = Struct.new(
  :records,           # ActiveRecord::Relation | Array
  :total_count,       # Integer
  :current_page,      # Integer
  :per_page,          # Integer
  :conditions_summary, # String
  :query_metadata,    # Hash
  :execution_time,    # Float (seconds)
  :search_params,     # Hash (original parameters)
  keyword_init: true
) do
  # ============================================
  # ページネーション関連メソッド
  # ============================================

  def total_pages
    return 0 if total_count <= 0 || per_page <= 0
    (total_count.to_f / per_page).ceil
  end

  def has_next_page?
    current_page < total_pages
  end

  def has_prev_page?
    current_page > 1
  end

  def next_page
    has_next_page? ? current_page + 1 : nil
  end

  def prev_page
    has_prev_page? ? current_page - 1 : nil
  end

  # ============================================
  # メタデータ関連メソッド
  # ============================================

  def pagination_info
    {
      current_page: current_page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next_page?,
      has_prev: has_prev_page?
    }
  end

  def search_metadata
    {
      conditions: conditions_summary,
      execution_time: execution_time,
      query_complexity: query_metadata[:joins_count] || 0,
      **query_metadata
    }
  end

  # ============================================
  # セキュリティ関連メソッド
  # ============================================

  def sanitized_records
    # 機密情報を除外したレコードを返す
    case records
    when ActiveRecord::Relation
      records.select(safe_attributes)
    when Array
      records.map { |record| sanitize_record(record) }
    else
      records
    end
  end

  # ============================================
  # API出力用メソッド
  # ============================================

  def to_api_hash
    {
      data: sanitized_records,
      pagination: pagination_info,
      metadata: search_metadata,
      timestamp: Time.current.iso8601
    }
  end

  def to_json(*args)
    to_api_hash.to_json(*args)
  end

  # ============================================
  # Enumerable委譲（既存コード互換性）
  # ============================================

  def each(&block)
    records.each(&block)
  end

  def map(&block)
    records.map(&block)
  end

  def select(&block)
    records.select(&block)
  end

  def size
    records.size
  end

  def length
    records.length
  end

  def count
    records.count
  end

  def empty?
    records.empty?
  end

  def present?
    !empty?
  end

  def first
    records.first
  end

  def last
    records.last
  end

  # ============================================
  # デバッグ・開発支援メソッド
  # ============================================

  def debug_info
    return {} unless Rails.env.development?

    {
      sql_query: records.respond_to?(:to_sql) ? records.to_sql : nil,
      search_params: search_params,
      performance: {
        execution_time: execution_time,
        record_count: total_count,
        query_complexity: query_metadata[:joins_count] || 0
      }
    }
  end

  # ============================================
  # キャッシュ関連メソッド
  # ============================================

  def cache_key
    # 検索条件とページネーション情報を基にキャッシュキーを生成
    key_parts = [
      "search_result",
      search_params.to_s.hash,
      current_page,
      per_page
    ]
    key_parts.join("-")
  end

  def cache_version
    # レコードの最終更新時刻を基にバージョンを生成
    if records.respond_to?(:maximum)
      records.maximum(:updated_at)&.to_i || Time.current.to_i
    else
      Time.current.to_i
    end
  end

  private

  def safe_attributes
    # モデルに応じて安全な属性のみを選択
    # TODO: 管理者権限に応じた属性選択の実装
    base_attributes = %w[id name status price quantity created_at updated_at]

    # 管理者の場合は追加属性を含める
    # 注意: Adminモデルにはsuper_admin?メソッドがないため、将来の拡張で実装予定
    if Current.admin.present?
      # TODO: Adminモデルにsuper_admin?メソッドを追加した後に有効化
      # if Current.admin.super_admin?
      #   base_attributes + %w[cost internal_notes]
      # else
      #   base_attributes
      # end
      # 現在は管理者の場合もベーシック属性のみ
      base_attributes
    else
      base_attributes
    end
  end

  def sanitize_record(record)
    # レコードから機密情報を除外
    case record
    when Hash
      record.slice(*safe_attributes)
    when ActiveRecord::Base
      record.attributes.slice(*safe_attributes)
    else
      record
    end
  end
end
