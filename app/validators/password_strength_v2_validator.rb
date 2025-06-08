# frozen_string_literal: true

# パスワード強度を検証するカスタムバリデータ（クラス分割版）
# ActiveModel::EachValidatorを継承した再利用可能なカスタムバリデーター
#
# アーキテクチャ改善版：
# - クラス分割による責務の完全分離
# - 再利用可能なルールバリデーター群
# - Strategy Patternによる高い拡張性
# - 独立テスト可能な設計
#
# TODO: 機能拡張・改善検討
# - 国際化対応のエラーメッセージ（I18n統合）
# - パスワード履歴チェック機能の追加
# - 辞書攻撃対策（一般的な単語チェック）
# - パスワード生成機能の提供
# - カスタムルールのDSL化

# Rails の命名規則に合わせてクラス名を変更
# password_strength_v2 => PasswordStrengthV2Validator
class PasswordStrengthV2Validator < ActiveModel::EachValidator
  # ============================================
  # 依存関係の注入（分割されたクラスの読み込み）
  # ============================================

  require_relative "password_rules/base_rule_validator"
  require_relative "password_rules/regex_rule_validator"
  require_relative "password_rules/length_range_validator"
  require_relative "password_rules/complexity_score_validator"

  # ============================================
  # 強度ルール設定（設定ドリブン）
  # ============================================

  # 事前定義済みルールセット
  PREDEFINED_RULE_SETS = {
    basic: {
      min_length: 8,
      require_digit: true,
      require_lowercase: true,
      require_uppercase: true,
      require_symbol: false,
      complexity_score: 3
    },
    standard: {
      min_length: 12,
      require_digit: true,
      require_lowercase: true,
      require_uppercase: true,
      require_symbol: true,
      complexity_score: 4
    },
    enterprise: {
      min_length: 14,
      require_digit: true,
      require_lowercase: true,
      require_uppercase: true,
      require_symbol: true,
      complexity_score: 6,
      max_length: 128
    }
  }.freeze

  # デフォルト設定
  DEFAULT_CONFIG = PREDEFINED_RULE_SETS[:standard].freeze

  # ============================================
  # メインバリデーションロジック
  # ============================================

  def validate_each(record, attribute, value)
    return if value.nil?

    config = build_validation_config
    validators = build_validators(config)

    # 各バリデーターを実行
    validators.each do |validator|
      next if validator.valid?(value)

      record.errors.add(attribute, validator.error_message)
    end
  end

  private

  # ============================================
  # 設定管理（カプセル化された設定処理）
  # ============================================

  def build_validation_config
    # 事前定義ルールセット使用
    if options[:rule_set] && PREDEFINED_RULE_SETS.key?(options[:rule_set])
      base_config = PREDEFINED_RULE_SETS[options[:rule_set]]
    else
      base_config = DEFAULT_CONFIG
    end

    # カスタム設定でオーバーライド
    base_config.merge(options.except(:rule_set))
  end

  # ============================================
  # バリデーター群の構築（Factory Pattern）
  # ============================================

  def build_validators(config)
    validators = []

    # 長さバリデーター
    validators << build_length_validator(config) if length_validation_required?(config)

    # 文字種バリデーター群
    validators.concat(build_character_validators(config))

    # 複雑度バリデーター
    validators << build_complexity_validator(config) if config[:complexity_score]

    # カスタムバリデーター（拡張ポイント）
    validators.concat(build_custom_validators(config))

    validators.compact
  end

  # ============================================
  # 個別バリデーター構築メソッド
  # ============================================

  def build_length_validator(config)
    min_length = config[:min_length]
    max_length = config[:max_length]

    PasswordRules::LengthRangeValidator.new(min_length, max_length)
  end

  def build_character_validators(config)
    validators = []

    if config[:require_digit]
      validators << PasswordRules::RegexRuleValidator.digit("数字を含む必要があります")
    end

    if config[:require_lowercase]
      validators << PasswordRules::RegexRuleValidator.lowercase("小文字を含む必要があります")
    end

    if config[:require_uppercase]
      validators << PasswordRules::RegexRuleValidator.uppercase("大文字を含む必要があります")
    end

    if config[:require_symbol]
      validators << PasswordRules::RegexRuleValidator.special_char("特殊文字を含む必要があります")
    end

    validators
  end

  def build_complexity_validator(config)
    min_score = config[:complexity_score]
    PasswordRules::ComplexityScoreValidator.new(min_score)
  end

  def build_custom_validators(config)
    custom_validators = []

    if config[:custom_rules]
      config[:custom_rules].each do |rule_config|
        validator = build_custom_rule_validator(rule_config)
        custom_validators << validator if validator
      end
    end

    custom_validators
  end

  # ============================================
  # カスタムルール拡張機能（将来の拡張性）
  # ============================================

  def build_custom_rule_validator(rule_config)
    case rule_config[:type]&.to_sym
    when :regex
      PasswordRules::RegexRuleValidator.new(
        rule_config[:pattern],
        rule_config[:error_message]
      )
    when :length_range
      PasswordRules::LengthRangeValidator.new(
        rule_config[:min_length],
        rule_config[:max_length],
        rule_config[:error_message]
      )
    when :complexity_score
      PasswordRules::ComplexityScoreValidator.new(
        rule_config[:min_score],
        rule_config[:error_message]
      )
    when :custom_lambda
      # ラムダ関数による独自バリデーション
      build_lambda_validator(rule_config)
    else
      Rails.logger.warn("Unknown custom rule type: #{rule_config[:type]}")
      nil
    end
  end

  def build_lambda_validator(rule_config)
    # ラムダバリデーターのラッパークラス
    Class.new(PasswordRules::BaseRuleValidator) do
      define_method(:initialize) do |lambda_func, error_msg|
        @lambda_func = lambda_func
        @error_msg = error_msg
      end

      define_method(:valid?) do |value|
        @lambda_func.call(value)
      end

      define_method(:error_message) do
        @error_msg
      end
    end.new(rule_config[:lambda], rule_config[:error_message])
  end

  # ============================================
  # ヘルパーメソッド
  # ============================================

  def length_validation_required?(config)
    config[:min_length] || config[:max_length]
  end
end
