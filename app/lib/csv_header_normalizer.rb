# frozen_string_literal: true

# CSVヘッダー正規化ユーティリティクラス
# ============================================
# 目的: 多言語CSVヘッダーの正規化処理を統一
# 使用箇所: ImportInventoriesJob, CsvImportable concern
#
class CsvHeaderNormalizer
  # ヘッダーマッピングのキャッシュ（メモリ効率化）
  @mapping_cache = {}

  class << self
    # CSVヘッダーを正規化して英語カラム名に変換
    # @param raw_headers [Array<String>] CSVファイルの元ヘッダー
    # @param mapping_key [String] I18n設定のキー（例: 'inventory'）
    # @param required_headers [Array<String>] 必須ヘッダー（省略時は全て通す）
    # @return [Array<String>] 正規化されたヘッダー（英語カラム名）
    def normalize(raw_headers, mapping_key, required_headers = nil)
      header_mapping = get_cached_mapping(mapping_key)

      normalized = raw_headers.map do |header|
        next nil if header.nil? || header.strip.empty?

        # 1. 空白を正規化
        normalized_header = header.strip

        # 2. 多言語マッピングを適用
        mapped_header = header_mapping[normalized_header] ||
                       header_mapping[normalized_header.downcase] ||
                       normalized_header.downcase

        # 3. 必要なヘッダーのみを残す（指定されている場合）
        if required_headers
          required_headers.include?(mapped_header) ? mapped_header : nil
        else
          mapped_header
        end
      end.compact.uniq

      normalized
    end

    # 不足している必須ヘッダーを検出
    # @param raw_headers [Array<String>] CSVファイルの元ヘッダー
    # @param mapping_key [String] I18n設定のキー
    # @param required_headers [Array<String>] 必須ヘッダー
    # @return [Array<String>] 不足しているヘッダー
    def missing_headers(raw_headers, mapping_key, required_headers)
      normalized = normalize(raw_headers, mapping_key, required_headers)
      required_headers - normalized
    end

    # ヘッダーマッピング設定の詳細エラーメッセージ生成
    # @param raw_headers [Array<String>] CSVファイルの元ヘッダー
    # @param mapping_key [String] I18n設定のキー
    # @param required_headers [Array<String>] 必須ヘッダー
    # @return [String] 詳細なエラーメッセージ
    def detailed_error_message(raw_headers, mapping_key, required_headers)
      missing = missing_headers(raw_headers, mapping_key, required_headers)
      available = raw_headers.reject { |h| h.nil? || h.strip.empty? }.join(", ")

      "Missing required headers: #{missing.join(', ')}. " \
      "Available headers: #{available}. " \
      "Please ensure your CSV has columns for: #{required_headers.join(', ')}. " \
      "Supported Japanese headers: #{japanese_header_examples(mapping_key)}"
    end

    private

    # ヘッダーマッピングをキャッシュから取得（パフォーマンス改善）
    # @param mapping_key [String] I18n設定のキー
    # @return [Hash] 文字列キーのヘッダーマッピング
    def get_cached_mapping(mapping_key)
      cache_key = "csv.header_mappings.#{mapping_key}"

      @mapping_cache[cache_key] ||= begin
        raw_mapping = I18n.t(cache_key, default: {})
        # シンボルキーを文字列キーに変換（I18n設定との互換性確保）
        raw_mapping.transform_keys(&:to_s)
      end
    end

    # 日本語ヘッダーの例を取得（エラーメッセージ用）
    # @param mapping_key [String] I18n設定のキー
    # @return [String] 日本語ヘッダーの例
    def japanese_header_examples(mapping_key)
      mapping = get_cached_mapping(mapping_key)
      # Unicode文字クラスを使用して日本語を検出
      japanese_headers = mapping.keys.select { |key| key.match?(/[\p{Han}\p{Hiragana}\p{Katakana}]/) }
      japanese_headers.take(3).join(", ")
    end
  end
end
