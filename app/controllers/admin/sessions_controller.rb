# frozen_string_literal: true

module AdminNamespace
  # 管理者ログイン・ログアウト処理用コントローラ
  class SessionsController < Devise::SessionsController
    layout "admin"

    # Turbo対応: Rails 7でDeviseとTurboの互換性を確保
    # https://github.com/heartcombo/devise/issues/5439

    # ログイン後のリダイレクト先
    def after_sign_in_path_for(resource)
      admin_root_path
    end

    # ログアウト後のリダイレクト先
    def after_sign_out_path_for(resource_or_scope)
      new_admin_session_path
    end

    protected

    # セッションタイムアウト対応
    def auth_options
      { scope: :admin, recall: "#{controller_path}#new" }
    end
  end
end
