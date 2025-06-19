# frozen_string_literal: true

module AdminControllers
  module ApplicationHelper
    # レガシー形式のボタン設定を新形式に変換
    def legacy_button_to_new_format(button)
      return button if button.is_a?(Hash) && button[:text]

      case button
      when Hash
        # 既存のハッシュ形式をそのまま使用
        button
      when Symbol, String
        # シンボルや文字列からデフォルト設定を生成
        default_button_config(button, nil)
      else
        # 不明な形式の場合は空ハッシュ
        {}
      end
    end

    # デフォルトボタン設定
    def default_button_config(type, resource = nil)
      case type.to_s
      when "show", "view"
        {
          text: "詳細",
          path: resource ? admin_inventory_path(resource) : "#",
          icon: "bi-eye",
          class: "btn-outline-primary",
          tooltip: "詳細を表示"
        }
      when "edit"
        {
          text: "編集",
          path: resource ? edit_admin_inventory_path(resource) : "#",
          icon: "bi-pencil",
          class: "btn-outline-warning",
          tooltip: "編集"
        }
      when "delete", "destroy"
        {
          text: "削除",
          path: resource ? admin_inventory_path(resource) : "#",
          icon: "bi-trash",
          class: "btn-outline-danger",
          method: :delete,
          confirm: "削除してもよろしいですか？",
          tooltip: "削除"
        }
      else
        {
          text: type.to_s.humanize,
          path: "#",
          icon: "bi-gear",
          class: "btn-outline-secondary"
        }
      end
    end
  end
end
