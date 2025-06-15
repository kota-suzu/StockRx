# frozen_string_literal: true

class InventoryDecorator < Draper::Decorator
  delegate_all

  # 在庫状態に応じたアラートバッジを生成
  def alert_badge
    if quantity <= 0
      h.tag.span("要補充", class: "bg-amber-200 text-red-600 px-2 py-1 rounded")
    else
      h.tag.span("OK", class: "bg-emerald-200 px-2 py-1 rounded")
    end
  end

  # 金額のフォーマット
  def formatted_price
    h.number_to_currency(price)
  end

  # ステータス表示
  def status_badge
    case status
    when "active"
      h.tag.span("有効", class: "bg-blue-200 px-2 py-1 rounded")
    when "archived"
      h.tag.span("アーカイブ", class: "bg-gray-200 px-2 py-1 rounded")
    else
      h.tag.span(status, class: "bg-gray-100 px-2 py-1 rounded")
    end
  end

  # 最終更新日のフォーマット
  def updated_at_formatted
    h.l(updated_at, format: :short) if updated_at.present?
  end

  # バッチ数を効率的に取得（N+1クエリ対策）
  def batches_count
    # Counter Cacheカラムが存在する場合は最優先で使用（通常のケース）
    if object.has_attribute?('batches_count')
      # nilの場合は0として扱う（Counter Cacheの標準動作）
      object.batches_count || 0
    # サブクエリで取得したカウンターキャッシュを利用（SearchQuery使用時）
    elsif respond_to?(:batches_count_cache) && batches_count_cache.present?
      batches_count_cache
    # フォールバック: 直接カウントクエリ（Counter Cacheが無効な場合のみ）
    else
      # eager loadingチェックを避けて直接countを実行
      object.association(:batches).target&.size || object.batches.count
    end
  end

  # JSON出力用の属性ハッシュ
  def as_json_with_decorated
    {
      id: id,
      name: name,
      quantity: quantity,
      price: price,
      status: status,
      updated_at: updated_at,
      formatted_price: formatted_price,
      alert_status: quantity <= 0 ? "low" : "ok",
      batches_count: batches_count
    }
  end
end
