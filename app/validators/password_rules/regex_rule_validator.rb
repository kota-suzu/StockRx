# frozen_string_literal: true

module PasswordRules
  # 正規表現ベースのパスワードルールバリデーター
  # Strategy Pattern実装
  #
  # 使用例:
  # validator = RegexRuleValidator.new(/\d/, "数字が必要です")
  # validator.valid?("Password123") # => true
  #
  # TODO: パフォーマンス最適化
  # - 正規表現のコンパイル結果キャッシュ（現在は定数化で対応済み）
  # - 複雑なパターンマッチングの最適化検討
  class RegexRuleValidator < BaseRuleValidator
    # ============================================
    # 正規表現パターン定数（パフォーマンス最適化）
    # ============================================

    DIGIT_REGEX = /\d/.freeze
    LOWER_CASE_REGEX = /[a-z]/.freeze
    UPPER_CASE_REGEX = /[A-Z]/.freeze
    SPECIAL_CHAR_REGEX = /[^A-Za-z0-9]/.freeze

    # よく使用される定義済みパターン
    PREDEFINED_PATTERNS = {
      digit: DIGIT_REGEX,
      lowercase: LOWER_CASE_REGEX,
      uppercase: UPPER_CASE_REGEX,
      special: SPECIAL_CHAR_REGEX
    }.freeze

    # ============================================
    # 初期化・設定
    # ============================================

    attr_reader :pattern, :error_message_text

    def initialize(pattern, error_message = nil)
      @pattern = normalize_pattern(pattern)
      @error_message_text = error_message || default_error_message
      validate_pattern!
    end

    # ============================================
    # インターフェース実装
    # ============================================

    def valid?(value)
      return false if blank_value?(value)

      result = if @pattern.is_a?(Array)
                 valid_for_array_pattern?(value)
      else
                 value.match?(@pattern)
      end

      log_validation_result(value, result)
    end

    def error_message
      @error_message_text
    end

    # ============================================
    # ファクトリーメソッド（利便性向上）
    # ============================================

    def self.digit(error_message = "数字を含む必要があります")
      new(DIGIT_REGEX, error_message)
    end

    def self.lowercase(error_message = "小文字を含む必要があります")
      new(LOWER_CASE_REGEX, error_message)
    end

    def self.uppercase(error_message = "大文字を含む必要があります")
      new(UPPER_CASE_REGEX, error_message)
    end

    def self.special_char(error_message = "特殊文字を含む必要があります")
      new(SPECIAL_CHAR_REGEX, error_message)
    end

    # ============================================
    # 複合パターン（AND/OR条件）
    # ============================================

    def self.any_of(*patterns, error_message: "指定されたパターンのいずれかに一致する必要があります")
      # 各パターンを正規化
      normalized_patterns = patterns.map do |pattern|
        case pattern
        when Symbol
          PREDEFINED_PATTERNS[pattern] || raise(ArgumentError, "Unknown pattern: #{pattern}")
        when String
          Regexp.new(pattern)
        when Regexp
          pattern
        else
          raise ArgumentError, "Pattern must be Regexp, String, or Symbol"
        end
      end

      combined_pattern = Regexp.union(*normalized_patterns)
      new(combined_pattern, error_message)
    end

    def self.all_of(*patterns, error_message: "すべてのパターンに一致する必要があります")
      new(patterns, error_message)
    end

    # ============================================
    # デバッグ・情報表示
    # ============================================

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} pattern=#{@pattern.inspect}>"
    end

    private

    # ============================================
    # 内部処理
    # ============================================

    def normalize_pattern(pattern)
      case pattern
      when Symbol
        PREDEFINED_PATTERNS[pattern] || raise(ArgumentError, "Unknown pattern: #{pattern}")
      when String
        Regexp.new(pattern)
      when Regexp
        pattern
      when Array
        # 複数パターンのAND条件
        pattern
      else
        raise ArgumentError, "Pattern must be Regexp, String, Symbol, or Array"
      end
    end

    def validate_pattern!
      return if @pattern.is_a?(Regexp) || @pattern.is_a?(Array)

      raise ArgumentError, "Invalid pattern: #{@pattern.inspect}"
    end

    def default_error_message
      "パスワードが必要な形式に一致していません"
    end

    # 複数パターンのAND条件チェック
    def valid_for_array_pattern?(value)
      @pattern.all? do |pattern|
        normalized = case pattern
        when Symbol
                       PREDEFINED_PATTERNS[pattern] || raise(ArgumentError, "Unknown pattern: #{pattern}")
        when String
                       Regexp.new(pattern)
        when Regexp
                       pattern
        else
                       raise ArgumentError, "Pattern must be Regexp, String, or Symbol"
        end
        value.match?(normalized)
      end
    end
  end
end
