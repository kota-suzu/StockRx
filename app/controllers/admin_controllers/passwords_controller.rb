# frozen_string_literal: true

module AdminControllers
  # 管理者パスワードリセット処理用コントローラ
  class PasswordsController < Devise::PasswordsController
    layout "admin"

    # Turbo対応: Rails 7でDeviseとTurboの互換性を確保
    # https://github.com/heartcombo/devise/issues/5439

    # TODO: 将来的な機能拡張
    # - パスワード有効期限の設定と管理（devise-securityと連携）
    # - パスワード変更履歴の記録
    # - パスワードリセットの通知強化（管理者や上位権限者への通知）
    # - パスワードポリシーの段階的な強化

    protected

    # パスワードリセット後のリダイレクト先
    def after_resetting_password_path_for(resource)
      admin_root_path
    end

    # パスワードリセットメール送信後のリダイレクト先
    def after_sending_reset_password_instructions_path_for(resource_name)
      new_admin_session_path
    end
  end
end
