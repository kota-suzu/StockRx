# frozen_string_literal: true

module AdminControllers
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

    # TODO: 将来的な機能拡張
    # - ログイン履歴の記録と表示
    # - ブルートフォース攻撃対策の強化
    # - 2要素認証の実装（devise-two-factor gem）
    # - 同時セッション数の制限

    protected

    # セッションタイムアウト対応
    def auth_options
      { scope: :admin, recall: "#{controller_path}#new" }
    end
  end
end
