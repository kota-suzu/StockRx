# frozen_string_literal: true

# 監査ログの重要なエラークラス
# 監査ログの記録に失敗した場合に発生する例外
class AuditLogCriticalError < StandardError
  attr_reader :action, :context

  def initialize(message, action: nil, context: {})
    super(message)
    @action = action
    @context = context
  end

  # エラー情報を構造化形式で取得
  def to_h
    {
      error_class: self.class.name,
      message: message,
      action: action,
      context: context,
      timestamp: Time.current.iso8601,
      severity: "critical"
    }
  end

  # JSON形式でエラー情報を出力
  def to_json(*args)
    to_h.to_json(*args)
  end
end