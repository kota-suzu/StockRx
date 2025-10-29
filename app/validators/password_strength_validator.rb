# frozen_string_literal: true

# パスワード強度を検証するカスタムバリデータ
# ============================================
# CLAUDE.md準拠: セキュリティ要件の実装
# Phase 1: 店舗別ログインシステムのセキュリティ基盤
# ============================================
# カプセル化改善版：
# - 責務の分離（設定・検証・エラー処理を独立）
# - 拡張性の向上（新しい強度ルールの簡単追加）
# - テスタビリティの向上（個別メソッドのテスト可能）
class PasswordStrengthValidator < ActiveModel::EachValidator
  # ============================================
  # 強度ルール定義（カプセル化された設定）
  # ============================================

  # 強度ルールの構造体定義
  PasswordRule = Struct.new(:name, :regex, :error_key, :enabled_by_default, keyword_init: true) do
    def enabled?(options)
      return enabled_by_default if options[name].nil?
      options[name] != false
    end

    def validate_against(value)
      value.match?(regex)
    end
  end

  # 強度ルール定義（拡張可能な設計）
  STRENGTH_RULES = [
    PasswordRule.new(
      name: :digit,
      regex: /\d/.freeze,
      error_key: :missing_digit,
      enabled_by_default: true
    ),
    PasswordRule.new(
      name: :lower,
      regex: /[a-z]/.freeze,
      error_key: :missing_lower,
      enabled_by_default: true
    ),
    PasswordRule.new(
      name: :upper,
      regex: /[A-Z]/.freeze,
      error_key: :missing_upper,
      enabled_by_default: true
    ),
    PasswordRule.new(
      name: :symbol,
      regex: /[^A-Za-z0-9]/.freeze,
      error_key: :missing_symbol,
      enabled_by_default: true
    )
  ].freeze

  # デフォルト設定（設定管理のカプセル化）
  DEFAULT_CONFIG = {
    min_length: 12,
    custom_rules: []
  }.freeze

  # ============================================
  # メインバリデーションロジック
  # ============================================

  def validate_each(record, attribute, value)
    return if value.nil?

    config = build_validation_config

    # 長さバリデーション
    validate_length(record, attribute, value, config)

    # 強度ルールバリデーション
    validate_strength_rules(record, attribute, value, config)

    # カスタムルールバリデーション（拡張ポイント）
    validate_custom_rules(record, attribute, value, config) if config[:custom_rules].any?
  end

  private

  # ============================================
  # 設定管理（カプセル化された設定処理）
  # ============================================

  def build_validation_config
    DEFAULT_CONFIG.merge(options)
  end

  # ============================================
  # 個別バリデーションメソッド（責務分離）
  # ============================================

  def validate_length(record, attribute, value, config)
    min_length = config[:min_length]
    return if value.length >= min_length

    record.errors.add(attribute, :too_short, count: min_length)
  end

  def validate_strength_rules(record, attribute, value, config)
    STRENGTH_RULES.each do |rule|
      next unless rule.enabled?(config)
      next if rule.validate_against(value)

      record.errors.add(attribute, rule.error_key)
    end
  end

  def validate_custom_rules(record, attribute, value, config)
    config[:custom_rules].each do |custom_rule|
      validator = build_custom_rule_validator(custom_rule)
      next if validator.valid?(value)

      record.errors.add(attribute, custom_rule[:error_key] || :custom_rule_failed)
    end
  end

  # ============================================
  # カスタムルール拡張機能（将来の拡張性）
  # ============================================

  def build_custom_rule_validator(rule_config)
    case rule_config[:type]
    when :regex
      RegexRuleValidator.new(rule_config[:pattern])
    when :length_range
      LengthRangeValidator.new(rule_config[:min], rule_config[:max])
    when :complexity_score
      ComplexityScoreValidator.new(rule_config[:min_score])
    else
      raise ArgumentError, "Unknown custom rule type: #{rule_config[:type]}"
    end
  end

  # ============================================
  # カスタムルールバリデーター群（Strategy Pattern）
  # ============================================

  class RegexRuleValidator
    def initialize(pattern)
      @pattern = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern)
    end

    def valid?(value)
      value.match?(@pattern)
    end
  end

  class LengthRangeValidator
    def initialize(min_length, max_length)
      @min_length = min_length
      @max_length = max_length
    end

    def valid?(value)
      (@min_length..@max_length).include?(value.length)
    end
  end

  class ComplexityScoreValidator
    # ============================================
    # 複雑度計算用正規表現定数（パフォーマンス最適化）
    # ============================================

    LOWER_CASE_REGEX = /[a-z]/.freeze
    UPPER_CASE_REGEX = /[A-Z]/.freeze
    DIGIT_REGEX = /\d/.freeze
    SYMBOL_REGEX = /[^A-Za-z0-9]/.freeze

    def initialize(min_score)
      @min_score = min_score
    end

    def valid?(value)
      calculate_complexity_score(value) >= @min_score
    end

    private

    def calculate_complexity_score(value)
      score = 0
      score += 1 if value.match?(LOWER_CASE_REGEX)
      score += 1 if value.match?(UPPER_CASE_REGEX)
      score += 1 if value.match?(DIGIT_REGEX)
      score += 1 if value.match?(SYMBOL_REGEX)
      score += 1 if value.length >= 12
      score += 1 if value.length >= 16
      score
    end
  end
end
