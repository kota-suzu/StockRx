# frozen_string_literal: true

# 全デコレータの基底クラス
class ApplicationDecorator < Draper::Decorator
  # 標準的なデコレータメソッドを全デコレータで利用可能にする
  delegate_all

  # 日付のフォーマッタ
  def formatted_date(date, format = :default)
    return nil unless date
    I18n.l(date, format: format)
  end

  # 日時のフォーマッタ
  def formatted_datetime(datetime, format = :default)
    return nil unless datetime
    I18n.l(datetime, format: format)
  end

  # 金額のフォーマッタ
  def formatted_currency(amount)
    return "¥0" if amount.blank?
    h.number_to_currency(amount, unit: "¥", precision: 0)
  end

  # 状態によって色分けされたバッジを生成
  def status_badge(status, options = {})
    status_text = options[:text] || status.to_s.humanize
    css_class = options[:class] || "px-2 py-1 text-xs rounded"

    case status.to_s
    when "active", "normal"
      css_class += " bg-green-100 text-green-800"
    when "archived", "inactive"
      css_class += " bg-gray-100 text-gray-800"
    when "expired"
      css_class += " bg-red-100 text-red-800"
    when "warning", "expiring_soon"
      css_class += " bg-yellow-100 text-yellow-800"
    else
      css_class += " bg-blue-100 text-blue-800"
    end

    h.content_tag(:span, status_text, class: css_class)
  end
end
