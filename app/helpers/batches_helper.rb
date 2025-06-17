# frozen_string_literal: true

# ロット関連のヘルパーメソッド
# admin_helpers/batches_helper.rbから移行
module BatchesHelper
  # ロットの状態に応じた行のスタイルクラスを返す
  # @param batch [Batch] ロットオブジェクト
  # @return [String] CSSクラス
  def batch_row_class(batch)
    if batch.expired?
      "bg-red-50"
    elsif batch.expiring_soon?
      "bg-yellow-50"
    else
      ""
    end
  end

  # ロットの状態バッジを生成
  # @param batch [Batch] ロットオブジェクト
  # @return [SafeBuffer] HTMLバッジ
  def batch_status_badge(batch)
    if batch.expired?
      tag.span("期限切れ", class: "bg-red-200 text-red-700 px-2 py-1 rounded")
    elsif batch.expiring_soon?
      tag.span("期限間近", class: "bg-yellow-200 text-yellow-700 px-2 py-1 rounded")
    else
      tag.span("正常", class: "bg-green-200 text-green-700 px-2 py-1 rounded")
    end
  end

  # 有効期限の表示
  # @param batch [Batch] ロットオブジェクト
  # @return [SafeBuffer] フォーマットされた日付（または「設定なし」）
  def formatted_expires_on(batch)
    if batch.expires_on.present?
      l(batch.expires_on, format: :long)
    else
      tag.span("設定なし", class: "text-gray-400 italic")
    end
  end
end
