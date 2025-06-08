# frozen_string_literal: true

module PasswordRules
  # 長さ範囲ベースのパスワードルールバリデーター
  # Strategy Pattern実装
  #
  # 使用例:
  # validator = LengthRangeValidator.new(8, 128)
  # validator.valid?("Password123") # => true
  #
  # TODO: 機能拡張検討
  # - Unicode正規化を考慮した文字数カウント（現在はString#lengthを使用）
  # - グラフィムクラスタ単位でのカウントオプション
  class LengthRangeValidator < BaseRuleValidator
    # ============================================
    # セキュリティ設定（定数化）
    # ============================================

    # NIST推奨値に基づく設定
    MIN_SECURE_LENGTH = 8
    MAX_SECURE_LENGTH = 128
    RECOMMENDED_MIN_LENGTH = 12

    # ============================================
    # 初期化・設定
    # ============================================

    attr_reader :min_length, :max_length, :error_message_text

    def initialize(min_length, max_length = nil, error_message = nil)
      @min_length = validate_min_length!(min_length)
      @max_length = validate_max_length!(max_length)
      @error_message_text = error_message || default_error_message

      validate_range_consistency!
    end

    # ============================================
    # インターフェース実装
    # ============================================

    def valid?(value)
      # 長さバリデーターは純粋に長さのみを検証
      # nil/空文字列の処理は他のバリデーターまたは上位レイヤーで行う
      return false if value.nil?

      length = value.length
      result = length_in_range?(length)

      log_validation_result(value, result)
    end

    def error_message
      @error_message_text
    end

    # ============================================
    # ファクトリーメソッド（利便性向上）
    # ============================================

    def self.minimum(min_length, error_message = nil)
      new(min_length, nil, error_message)
    end

    def self.maximum(max_length, error_message = nil)
      new(0, max_length, error_message)
    end

    def self.exact(length, error_message = nil)
      new(length, length, error_message)
    end

    def self.secure(error_message = nil)
      new(RECOMMENDED_MIN_LENGTH, MAX_SECURE_LENGTH, error_message)
    end

    def self.nist_compliant(error_message = nil)
      new(MIN_SECURE_LENGTH, MAX_SECURE_LENGTH, error_message)
    end

    # ============================================
    # 情報取得メソッド
    # ============================================

    def range_description
      if @min_length && @max_length
        if @min_length == @max_length
          "#{@min_length}文字"
        elsif @min_length == 0
          "#{@max_length}文字以下"
        else
          "#{@min_length}〜#{@max_length}文字"
        end
      elsif @min_length
        "#{@min_length}文字以上"
      elsif @max_length
        "#{@max_length}文字以下"
      else
        "制限なし"
      end
    end

    def security_level
      return :unknown unless @min_length
      return :unknown if @min_length == 0

      case @min_length
      when 0...MIN_SECURE_LENGTH
        :weak
      when MIN_SECURE_LENGTH...RECOMMENDED_MIN_LENGTH
        :moderate
      when RECOMMENDED_MIN_LENGTH..Float::INFINITY
        :strong
      end
    end

    # ============================================
    # デバッグ・情報表示
    # ============================================

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} range=#{range_description}>"
    end

    private

    # ============================================
    # バリデーション処理
    # ============================================

    def length_in_range?(length)
      min_valid = @min_length.nil? || length >= @min_length
      max_valid = @max_length.nil? || length <= @max_length

      min_valid && max_valid
    end

    # ============================================
    # 入力値検証
    # ============================================

    def validate_min_length!(min_length)
      return nil if min_length.nil?

      unless min_length.is_a?(Integer) && min_length >= 0
        raise ArgumentError, "min_length must be a non-negative integer, got: #{min_length.inspect}"
      end

      min_length
    end

    def validate_max_length!(max_length)
      return nil if max_length.nil?

      unless max_length.is_a?(Integer) && max_length >= 0
        raise ArgumentError, "max_length must be a non-negative integer, got: #{max_length.inspect}"
      end

      max_length
    end

    def validate_range_consistency!
      return unless @min_length && @max_length

      if @min_length > @max_length
        raise ArgumentError, "min_length (#{@min_length}) cannot be greater than max_length (#{@max_length})"
      end
    end

    # ============================================
    # エラーメッセージ生成
    # ============================================

    def default_error_message
      if @min_length && @max_length
        if @min_length == @max_length
          "パスワードは#{@min_length}文字である必要があります"
        elsif @min_length == 0
          "パスワードは#{@max_length}文字以下である必要があります"
        else
          "パスワードは#{@min_length}〜#{@max_length}文字である必要があります"
        end
      elsif @min_length
        "パスワードは#{@min_length}文字以上である必要があります"
      elsif @max_length
        "パスワードは#{@max_length}文字以下である必要があります"
      else
        "パスワードの長さが無効です"
      end
    end
  end
end
