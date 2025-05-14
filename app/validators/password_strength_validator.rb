# frozen_string_literal: true

# パスワード強度を検証するカスタムバリデータ
class PasswordStrengthValidator < ActiveModel::EachValidator
  DIGIT_REGEX = /\d/.freeze
  LOWER_REGEX = /[a-z]/.freeze
  UPPER_REGEX = /[A-Z]/.freeze
  SYMBOL_REGEX = /[^A-Za-z0-9]/.freeze

  def validate_each(record, attribute, value)
    return if value.nil?

    # 最小長さ検証（devise自身のvalidatabaleでも検証されるが、明示的に実装）
    min_length = options[:min_length] || 12
    if value.length < min_length
      record.errors.add(attribute, :too_short, count: min_length)
    end

    # 数字を含むか
    if options[:digit] != false && !value.match?(DIGIT_REGEX)
      record.errors.add(attribute, :missing_digit)
    end

    # 小文字を含むか
    if options[:lower] != false && !value.match?(LOWER_REGEX)
      record.errors.add(attribute, :missing_lower)
    end

    # 大文字を含むか
    if options[:upper] != false && !value.match?(UPPER_REGEX)
      record.errors.add(attribute, :missing_upper)
    end

    # 記号を含むか
    if options[:symbol] != false && !value.match?(SYMBOL_REGEX)
      record.errors.add(attribute, :missing_symbol)
    end
  end
end
