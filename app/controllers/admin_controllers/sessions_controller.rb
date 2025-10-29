# frozen_string_literal: true

module AdminControllers
  # 管理者ログイン・ログアウト処理用コントローラ
  class SessionsController < Devise::SessionsController
    layout "admin"

    # Chrome対応: POSTアクションでsign_inが機能しない問題への対応
    # https://github.com/heartcombo/devise/issues/5155
    skip_before_action :verify_authenticity_token, only: :create

    # セキュリティ強化TODO: 代替策の検討
    # 現在のCSRF検証スキップは臨時対応。以下の方法で恒久対策を検討すべき:
    # 1. トークンベースのクロスサイトリクエスト保護に切り替え
    # 2. GETリクエストベースの認証フローへの変更
    # 3. fetch APIを使用したXHRリクエスト化

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

    def create
      self.resource = warden.authenticate(auth_options)

      if resource
        set_flash_message!(:notice, :signed_in)
        sign_in(resource_name, resource)
        respond_with resource, location: after_sign_in_path_for(resource)
      else
        self.resource = resource_class.new(sign_in_params)
        clean_up_passwords(resource)
        flash.now[:alert] = sanitized_failure_message
        respond_with_navigational(resource) { render :new, status: :unprocessable_entity }
      end
    end

    # TODO: 将来的な機能拡張
    # - ログイン履歴の記録と表示
    # - ブルートフォース攻撃対策の強化
    # - 2要素認証の実装（devise-two-factor gem）
    # - 同時セッション数の制限
    # - レート制限実装（429対応）
    # - 多要素認証（MFA）導入
    # - 最終ログイン情報の表示

    protected

    # セッションタイムアウト対応
    def auth_options
      { scope: :admin, recall: "#{controller_path}#new" }
    end

    private

    def sanitized_failure_message
      raw_message = I18n.t('devise.failure.invalid', authentication_keys: Admin.human_attribute_name(:email))
      ERB::Util.html_escape(raw_message)
    end
  end
end
