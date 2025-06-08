# frozen_string_literal: true

module PasswordRules
  # 複雑度スコアベースのパスワードルールバリデーター
  # Strategy Pattern実装
  #
  # 使用例:
  # validator = ComplexityScoreValidator.new(4)
  # validator.valid?("Password123!") # => true (スコア5)
  class ComplexityScoreValidator < BaseRuleValidator
    # ============================================
    # 複雑度計算用正規表現定数（パフォーマンス最適化）
    # ============================================

    LOWER_CASE_REGEX = /[a-z]/.freeze
    UPPER_CASE_REGEX = /[A-Z]/.freeze
    DIGIT_REGEX = /\d/.freeze
    SYMBOL_REGEX = /[^A-Za-z0-9]/.freeze

    # ============================================
    # スコア計算設定
    # ============================================

    # 基本文字種スコア
    BASIC_SCORES = {
      lowercase: 1,
      uppercase: 1,
      digit: 1,
      symbol: 1
    }.freeze

    # 長さボーナススコア
    LENGTH_BONUSES = [
      { threshold: 8, score: 1 },
      { threshold: 12, score: 1 },
      { threshold: 16, score: 1 },
      { threshold: 20, score: 1 }
    ].freeze

    # セキュリティレベル定義
    SECURITY_LEVELS = {
      very_weak: 0..1,
      weak: 2..3,
      moderate: 4..5,
      strong: 6..7,
      very_strong: 8..Float::INFINITY
    }.freeze

    # ============================================
    # 初期化・設定
    # ============================================

    attr_reader :min_score, :error_message_text, :custom_scoring

    def initialize(min_score, error_message = nil, custom_scoring: nil)
      @min_score = validate_min_score!(min_score)
      @error_message_text = error_message || default_error_message
      @custom_scoring = custom_scoring || default_scoring_config
    end

    # ============================================
    # インターフェース実装
    # ============================================

    def valid?(value)
      return false if blank_value?(value)

      score = calculate_complexity_score(value)
      result = score >= @min_score

      log_validation_result("#{value} (score: #{score})", result)
    end

    def error_message
      @error_message_text
    end

    # TODO: テストの期待値とスコア計算ロジックの整合性確認
    # - マルチバイト文字のスコア計算（長さボーナスを考慮）
    # - strongファクトリーメソッドのテストケース修正
    # - 境界値テストの期待値修正

    # ============================================
    # ファクトリーメソッド（利便性向上）
    # ============================================

    def self.weak(error_message = nil)
      new(2, error_message)
    end

    def self.moderate(error_message = nil)
      new(4, error_message)
    end

    def self.strong(error_message = nil)
      new(6, error_message)
    end

    def self.very_strong(error_message = nil)
      new(8, error_message)
    end

    # ============================================
    # スコア計算・分析
    # ============================================

    def calculate_complexity_score(value)
      return 0 if blank_value?(value)

      score = 0

      # 基本文字種スコア
      score += character_type_score(value)

      # 長さボーナススコア
      score += length_bonus_score(value)

      # カスタムスコア（拡張ポイント）
      score += custom_score(value) if @custom_scoring[:enabled]

      score
    end

    def complexity_breakdown(value)
      return {} if blank_value?(value)

      {
        character_types: character_type_breakdown(value),
        length_bonus: length_bonus_score(value),
        custom_score: custom_score(value),
        total_score: calculate_complexity_score(value),
        security_level: security_level(value),
        meets_requirement: valid?(value)
      }
    end

    def security_level(value)
      score = calculate_complexity_score(value)
      # TODO: スコアとセキュリティレベルのマッピング確認
      # 現在: very_weak(0-1), weak(2-3), moderate(4-5), strong(6-7), very_strong(8+)
      SECURITY_LEVELS.find { |level, range| range.include?(score) }&.first || :unknown
    end

    # ============================================
    # デバッグ・情報表示
    # ============================================

    def inspect
      "#<#{self.class.name}:0x#{object_id.to_s(16)} min_score=#{@min_score}>"
    end

    private

    # ============================================
    # スコア計算の詳細実装
    # ============================================

    def character_type_score(value)
      score = 0
      score += @custom_scoring[:lowercase] if value.match?(LOWER_CASE_REGEX)
      score += @custom_scoring[:uppercase] if value.match?(UPPER_CASE_REGEX)
      score += @custom_scoring[:digit] if value.match?(DIGIT_REGEX)
      score += @custom_scoring[:symbol] if value.match?(SYMBOL_REGEX)
      score
    end

    def character_type_breakdown(value)
      {
        lowercase: value.match?(LOWER_CASE_REGEX),
        uppercase: value.match?(UPPER_CASE_REGEX),
        digit: value.match?(DIGIT_REGEX),
        symbol: value.match?(SYMBOL_REGEX)
      }
    end

    def length_bonus_score(value)
      return 0 unless @custom_scoring[:length_bonus]
      return 0 if value.nil?

      LENGTH_BONUSES.sum do |bonus|
        value.length >= bonus[:threshold] ? bonus[:score] : 0
      end
    end

    def custom_score(value)
      return 0 unless @custom_scoring[:custom_rules]

      @custom_scoring[:custom_rules].sum do |rule|
        rule.call(value) rescue 0
      end
    end

    # ============================================
    # 設定・バリデーション
    # ============================================

    def validate_min_score!(min_score)
      unless min_score.is_a?(Integer) && min_score >= 0
        raise ArgumentError, "min_score must be a non-negative integer, got: #{min_score.inspect}"
      end

      min_score
    end

    def default_scoring_config
      {
        enabled: true,
        lowercase: BASIC_SCORES[:lowercase],
        uppercase: BASIC_SCORES[:uppercase],
        digit: BASIC_SCORES[:digit],
        symbol: BASIC_SCORES[:symbol],
        length_bonus: true,
        custom_rules: []
      }
    end

    def default_error_message
      level_name = SECURITY_LEVELS.find { |level, range| range.include?(@min_score) }&.first

      if level_name
        "パスワードの複雑度が不十分です（要求レベル: #{level_name}, 最小スコア: #{@min_score}）"
      else
        "パスワードの複雑度スコアが#{@min_score}以上である必要があります"
      end
    end
  end
end
