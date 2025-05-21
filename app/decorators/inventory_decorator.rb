# frozen_string_literal: true

class InventoryDecorator < ApplicationDecorator
  delegate_all

  # TODO: InventoryDecorator#badge css クラスを tailwind コンポーネントに統合
  # TODO: バッジの文言と色はi18n化を検討
  def alert_badge
    if object.out_of_stock?
      badge("在庫切れ", "bg-red-200 text-red-700")
    elsif object.low_stock? # Inventoryモデルのlow_stock?が使われる
      badge("要補充",  "bg-amber-200 text-red-600")
    else
      badge("OK",    "bg-green-200 text-green-700")
    end
  end

  def as_json_with_decorated
    # RSpecの期待値に合わせるため、object.id も含める
    # また、キー名をスネークケースからキャメルケースに変換するような処理は
    # RSpecのテスト内容からは読み取れないため、object.as_jsonの結果をそのまま使う
    # object.as_json の結果のキーをシンボルに変換し、デコレートした値を追加する
    result = object.as_json.transform_keys(&:to_sym)
    result.merge!(
      # id は transform_keys(&:to_sym) によって既にシンボルキーになっている想定
      alert_badge: alert_badge,
      formatted_price: formatted_price # self. は省略可能
    )
    result
  end

  # 金額を通貨形式でフォーマットするメソッド
  def formatted_price
    h.number_to_currency(object.price, unit: "¥", precision: 0) # RSpecのテスト `expect(inventory.formatted_price).to eq('¥1,234')` に合わせる
  end

  # ステータスに応じたバッジを返すメソッド
  def status_badge
    case object.status
    when "active"
      badge("有効", "bg-blue-200 text-blue-700") # 色は適宜調整
    when "archived"
      badge("アーカイブ", "bg-gray-200 text-gray-700") # 色は適宜調整
    end
  end

  private

  def badge(text, classes)
    h.content_tag(:span, text, class: "#{classes} px-2 py-1 rounded")
  end
end
