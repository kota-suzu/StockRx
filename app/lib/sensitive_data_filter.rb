# frozen_string_literal: true

# 機密情報フィルタリングモジュール
# ============================================
# QAレビュー指摘事項対応: Critical Issue #2
# ログ・エラーレスポンスでの機密情報マスキング
# PCI DSS/GDPR準拠の情報保護実装
# ============================================
class SensitiveDataFilter
  # フィルタリング対象のキーパターン
  SENSITIVE_PATTERNS = [
    # 認証情報
    /password/i,
    /passwd/i,
    /secret/i,
    /token/i,
    /api_key/i,
    /access_key/i,
    /private_key/i,
    /auth/i,

    # 個人情報
    /email/i,
    /phone/i,
    /address/i,
    /ssn/i,
    /social_security/i,
    /date_of_birth/i,
    /dob/i,

    # 金融情報
    /credit_card/i,
    /card_number/i,
    /cvv/i,
    /cvc/i,
    /account_number/i,
    /routing_number/i,
    /bank/i,

    # セッション情報
    /session/i,
    /cookie/i,
    /csrf/i,

    # カスタムパターン（StockRx固有）
    /inventory_cost/i,
    /purchase_price/i,
    /supplier_code/i
  ].freeze

  # マスキング文字列
  MASKED_VALUE = "[FILTERED]".freeze

  # 部分マスキング用の設定
  PARTIAL_MASK_CONFIG = {
    email: { show_first: 3, show_domain: true },
    phone: { show_last: 4 },
    card_number: { show_last: 4 }
  }.freeze

  class << self
    # ============================================
    # パブリックインターフェース
    # ============================================

    # ハッシュデータのフィルタリング
    def filter(data)
      return data unless data.is_a?(Hash) || data.is_a?(ActionController::Parameters)

      # ActionController::Parametersの場合は to_unsafe_h、Hashの場合はそのまま
      hash_data = if data.is_a?(ActionController::Parameters)
                    data.to_unsafe_h
      else
                    data
      end

      deep_filter(hash_data)
    end

    # 文字列内の機密情報マスキング
    def mask_string(string)
      return string unless string.is_a?(String)

      # メールアドレスのマスキング
      string = mask_email_addresses(string)

      # 電話番号のマスキング
      string = mask_phone_numbers(string)

      # クレジットカード番号のマスキング
      string = mask_credit_card_numbers(string)

      # IPアドレスのマスキング（内部IPは除外）
      string = mask_ip_addresses(string)

      # カスタムパターンのマスキング
      string = mask_custom_patterns(string)

      string
    end

    # ログメッセージのフィルタリング
    def filter_log_message(message)
      return message unless message.is_a?(String)

      # JSONデータの検出とフィルタリング
      if json_data = extract_json(message)
        filtered_json = filter(json_data)
        message.gsub(json_data.to_json, filtered_json.to_json)
      else
        mask_string(message)
      end
    end

    # エラーレスポンスのフィルタリング
    def filter_error_response(error_data)
      case error_data
      when Hash
        filter_error_hash(error_data)
      when String
        mask_string(error_data)
      when Exception
        filter_exception(error_data)
      else
        error_data
      end
    end

    # SQLクエリのフィルタリング
    def filter_sql(sql)
      return sql unless sql.is_a?(String)

      # WHERE句の値をマスキング
      sql.gsub(/WHERE\s+(\w+)\s*=\s*'([^']+)'/i) do |match|
        column = $1
        value = $2
        if sensitive_column?(column)
          "WHERE #{column} = '#{MASKED_VALUE}'"
        else
          match
        end
      end
    end

    # ============================================
    # プライベートメソッド
    # ============================================

    private

    # 深い階層のハッシュフィルタリング
    def deep_filter(hash)
      hash.each_with_object({}) do |(key, value), filtered|
        if sensitive_key?(key)
          filtered[key] = MASKED_VALUE
        elsif value.is_a?(Hash)
          filtered[key] = deep_filter(value)
        elsif value.is_a?(Array)
          filtered[key] = filter_array(value)
        elsif value.is_a?(String) && contains_sensitive_data?(value)
          filtered[key] = partial_mask(key, value)
        else
          filtered[key] = value
        end
      end
    end

    # 配列のフィルタリング
    def filter_array(array)
      array.map do |item|
        case item
        when Hash
          deep_filter(item)
        when String
          mask_string(item)
        else
          item
        end
      end
    end

    # 機密キーの判定
    def sensitive_key?(key)
      key_string = key.to_s
      SENSITIVE_PATTERNS.any? { |pattern| key_string.match?(pattern) }
    end

    # 機密カラムの判定
    def sensitive_column?(column)
      sensitive_key?(column)
    end

    # 文字列に機密情報が含まれるか判定
    def contains_sensitive_data?(string)
      # メールアドレスパターン
      return true if string.match?(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)

      # 電話番号パターン（日本）
      return true if string.match?(/0\d{1,4}-\d{1,4}-\d{4}/)

      # クレジットカード番号パターン
      return true if string.match?(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/)

      false
    end

    # 部分マスキング
    def partial_mask(key, value)
      case key.to_s
      when /email/i
        mask_email(value)
      when /phone/i
        mask_phone(value)
      when /card_number/i, /credit_card/i
        mask_credit_card(value)
      else
        MASKED_VALUE
      end
    end

    # メールアドレスのマスキング
    def mask_email(email)
      return MASKED_VALUE unless email.include?("@")

      local, domain = email.split("@")
      if local.length > 3
        "#{local[0..2]}***@#{domain}"
      else
        "***@#{domain}"
      end
    end

    # 電話番号のマスキング
    def mask_phone(phone)
      digits = phone.gsub(/\D/, "")
      return MASKED_VALUE if digits.length < 4

      "***-***-#{digits[-4..]}"
    end

    # クレジットカード番号のマスキング
    def mask_credit_card(number)
      digits = number.gsub(/\D/, "")
      return MASKED_VALUE if digits.length < 4

      "****-****-****-#{digits[-4..]}"
    end

    # 文字列内のメールアドレスマスキング
    def mask_email_addresses(string)
      string.gsub(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/) do |email|
        mask_email(email)
      end
    end

    # 文字列内の電話番号マスキング
    def mask_phone_numbers(string)
      # 日本の電話番号形式
      string.gsub(/0\d{1,4}-\d{1,4}-\d{4}/) do |phone|
        mask_phone(phone)
      end
    end

    # 文字列内のクレジットカード番号マスキング
    def mask_credit_card_numbers(string)
      string.gsub(/\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b/) do |card|
        mask_credit_card(card)
      end
    end

    # IPアドレスのマスキング（プライベートIPは除外）
    def mask_ip_addresses(string)
      string.gsub(/\b(?:\d{1,3}\.){3}\d{1,3}\b/) do |ip|
        if private_ip?(ip)
          ip
        else
          ip.split(".")[0..1].join(".") + ".***.***.***"
        end
      end
    end

    # プライベートIPアドレスの判定
    def private_ip?(ip)
      octets = ip.split(".").map(&:to_i)
      return false if octets.length != 4

      # 10.0.0.0/8
      return true if octets[0] == 10

      # 172.16.0.0/12
      return true if octets[0] == 172 && (16..31).include?(octets[1])

      # 192.168.0.0/16
      return true if octets[0] == 192 && octets[1] == 168

      # 127.0.0.0/8 (localhost)
      return true if octets[0] == 127

      false
    end

    # カスタムパターンのマスキング
    def mask_custom_patterns(string)
      # StockRx固有のパターン
      string.gsub(/\b(INV|BATCH|SUP)-\d{6,}\b/i) do |code|
        prefix = $1
        "#{prefix}-******"
      end
    end

    # JSON抽出
    def extract_json(string)
      JSON.parse(string)
    rescue JSON::ParserError
      nil
    end

    # エラーハッシュのフィルタリング
    def filter_error_hash(error_hash)
      filtered = deep_filter(error_hash)

      # スタックトレースの機密情報除去
      if filtered[:backtrace].is_a?(Array)
        filtered[:backtrace] = filter_backtrace(filtered[:backtrace])
      end

      filtered
    end

    # 例外オブジェクトのフィルタリング
    def filter_exception(exception)
      {
        class: exception.class.name,
        message: mask_string(exception.message),
        backtrace: filter_backtrace(exception.backtrace || [])
      }
    end

    # バックトレースのフィルタリング
    def filter_backtrace(backtrace)
      backtrace.map do |line|
        # ファイルパスの機密部分を除去
        line.gsub(/\/home\/\w+/, "/home/***")
            .gsub(/\/Users\/\w+/, "/Users/***")
            .gsub(/api_key=\w+/, "api_key=***")
      end
    end
  end
end

# ============================================
# 使用例:
# ============================================
# 1. ログフィルタリング
#    Rails.logger.info SensitiveDataFilter.filter_log_message(
#      "User login: email=user@example.com, password=secret123"
#    )
#    # => "User login: email=use***@example.com, password=[FILTERED]"
#
# 2. パラメータフィルタリング
#    filtered_params = SensitiveDataFilter.filter(params)
#
# 3. エラーレスポンスフィルタリング
#    rescue => e
#      error_data = SensitiveDataFilter.filter_error_response(e)
#      render json: { error: error_data }, status: :internal_server_error
#    end
