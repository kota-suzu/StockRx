# frozen_string_literal: true

module PasswordRules
  # パスワードルールバリデーターの基底クラス
  # Strategy Patternのコンテキスト定義
  #
  # 設計原則：
  # - Open/Closed Principle: 拡張に開き、修正に閉じる
  # - Dependency Inversion: 抽象に依存し、具象に依存しない
  # - Interface Segregation: 必要最小限のインターフェース
  class BaseRuleValidator
    # ============================================
    # 共通インターフェース（必須実装メソッド）
    # ============================================

    def valid?(value)
      raise NotImplementedError, "#{self.class}#valid? must be implemented"
    end

    def error_message
      raise NotImplementedError, "#{self.class}#error_message must be implemented"
    end

    # ============================================
    # 共通ユーティリティメソッド
    # ============================================

    # ============================================
    # デバッグ・ログ支援
    # ============================================

    def inspect
      class_name = self.class.name || "AnonymousClass"
      "#<#{class_name}:0x#{object_id.to_s(16)}>"
    end

    protected

    def blank_value?(value)
      value.nil? || value.empty?
    end

    def numeric_value?(value)
      value.to_s.match?(/\A\d+(\.\d+)?\z/)
    end

    def validate_options!(options, required_keys)
      missing_keys = required_keys - options.keys
      unless missing_keys.empty?
        raise ArgumentError, "Missing required options: #{missing_keys.join(', ')}"
      end
    end

    private

    def log_validation_result(value, result)
      Rails.logger.debug("#{self.class.name}: value=#{value.inspect}, valid=#{result}")
      result
    end
  end
end
