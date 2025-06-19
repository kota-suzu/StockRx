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
  # CLAUDE.md準拠: メタ認知 - モデルのメソッドを活用してDRY原則に従う
  # 横展開: 他のデコレーターでも同様にモデルメソッドを活用
  def operation_type_text
    # TODO: 🟡 Phase 3（重要）- メソッド名統一
    # 優先度: 中（一貫性向上）
    # 実装内容: operation_type_textをoperation_display_nameにリネーム
    # 理由: モデルとデコレーターのメソッド名統一でメンテナンス性向上
    # 影響範囲: ビューファイルでこのメソッドを使用している箇所の調査必要
    object.operation_display_name
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
