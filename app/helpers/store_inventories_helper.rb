# frozen_string_literal: true

module StoreInventoriesHelper
  # 店舗タイプのアイコンクラス取得
  # CLAUDE.md準拠: 横展開確認済み - StoreSelectionControllerと同じロジック
  def store_type_icon(type)
    case type
    when "pharmacy"
      "fas fa-prescription-bottle-alt"
    when "warehouse"
      "fas fa-warehouse"
    when "headquarters"
      "fas fa-building"
    else
      "fas fa-store"
    end
  end

  # 在庫状態バッジ表示
  # TODO: Phase 2 - 他の在庫関連ビューでも同様のバッジ表示を統一
  #   - 管理者用在庫一覧
  #   - 店舗ユーザー用在庫一覧
  #   - 横展開: ApplicationHelperへの移動検討
  def stock_status_badge(quantity)
    case quantity
    when 0
      content_tag(:span, "在庫切れ", class: "badge bg-danger")
    when 1..10
      content_tag(:span, "在庫少", class: "badge bg-warning text-dark")
    else
      content_tag(:span, "在庫あり", class: "badge bg-success")
    end
  end

  # ソート可能なカラムのリンク生成
  # CLAUDE.md準拠: セキュリティ考慮 - 許可されたカラムのみソート可能
  def sort_link(text, column)
    # 現在のソート状態を判定
    current_sort = params[:sort] == column
    current_direction = params[:direction] || "asc"

    # 次のソート方向を決定
    next_direction = if current_sort && current_direction == "asc"
                      "desc"
    else
                      "asc"
    end

    # アイコンの選択
    icon_class = if current_sort
                  current_direction == "asc" ? "fa-sort-up" : "fa-sort-down"
    else
                  "fa-sort"
    end

    # リンクの生成（既存のパラメータを保持）
    link_params = request.query_parameters.merge(
      sort: column,
      direction: next_direction
    )

    link_to store_inventories_path(@store, link_params),
            class: "text-decoration-none text-dark",
            data: { turbo_action: "replace" } do
      safe_join([ text, " ", content_tag(:i, "", class: "fas #{icon_class} ms-1") ])
    end
  end

  # 在庫数の表示形式（公開用）
  # セキュリティ: 具体的な数量は非表示
  def public_stock_display(quantity)
    case quantity
    when 0
      "在庫なし"
    when 1..5
      "残りわずか"
    when 6..20
      "在庫少"
    else
      "在庫あり"
    end
  end

  # 最終更新日時の表示
  def last_updated_display(datetime)
    return "データなし" if datetime.nil?

    time_ago = time_ago_in_words(datetime)
    content_tag(:span, "#{time_ago}前",
                title: l(datetime, format: :long),
                data: { bs_toggle: "tooltip" })
  end
end

# ============================================
# TODO: Phase 3以降の拡張予定
# ============================================
# 1. 🔴 共通ヘルパーへの統合
#    - ApplicationHelperへの移動検討
#    - 他のヘルパーとの重複確認
#    - 名前空間の整理
#
# 2. 🟡 国際化対応
#    - 在庫状態の多言語対応
#    - 数値フォーマットの地域対応
#
# 3. 🟢 アクセシビリティ向上
#    - ARIA属性の追加
#    - スクリーンリーダー対応
