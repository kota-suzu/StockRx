class InventoryLogDecorator < ApplicationDecorator
  delegate_all

  # Define presentation-specific methods here. Helpers are accessed through
  # `helpers` (aka `h`). You can override attributes, for example:
  #
  #   def created_at
  #     helpers.content_tag :span, class: 'time' do
  #       object.created_at.strftime("%a %m/%d/%y")
  #     end
  #   end

  # テキスト形式の作成日時を返す
  def formatted_timestamp
    object.created_at.strftime("%Y年%m月%d日 %H:%M:%S")
  end

  # 操作種別の日本語表現を返す
  def operation_type_text
    case object.operation_type
    when "add"
      "追加"
    when "remove"
      "削除"
    when "adjust"
      "調整"
    else
      object.operation_type
    end
  end

  # 変化量のフォーマット（正の値には+を付ける）
  def formatted_delta
    delta = object.delta
    if delta > 0
      "+#{delta}"
    else
      delta.to_s
    end
  end

  # 色付きの変化量HTML
  def colored_delta
    delta = object.delta
    css_class = delta >= 0 ? "text-green-600" : "text-red-600"

    h.content_tag :span, formatted_delta, class: css_class
  end

  # 操作者の表示
  def operator_name
    if object.user.present?
      object.user.respond_to?(:name) ? object.user.name : object.user.email
    else
      "自動処理"
    end
  end
end
