# frozen_string_literal: true

module StoreControllers
  # 店舗ユーザー用セッションコントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # Devise::SessionsControllerをカスタマイズ
  # ============================================
  class SessionsController < Devise::SessionsController
    # CSRFトークン検証をスキップ（APIモード対応）
    skip_before_action :verify_authenticity_token, only: [:create], if: :json_request?
    
    # 店舗の事前確認
    before_action :set_store_from_params, only: [:new, :create]
    before_action :check_store_active, only: [:create]
    
    # レイアウト設定
    layout 'store_auth'

    # ============================================
    # アクション
    # ============================================

    # ログインフォーム表示
    def new
      # 店舗が指定されていない場合は店舗選択画面へ
      redirect_to store_selection_path and return unless @store
      
      super
    end

    # ログイン処理
    def create
      # 店舗が指定されていない場合はエラー
      unless @store
        redirect_to store_selection_path, 
                    alert: I18n.t("devise.failure.store_selection_required")
        return
      end
      
      # カスタム認証処理
      self.resource = warden.authenticate!(auth_options_with_store)
      
      # ログイン成功時の処理
      set_flash_message!(:notice, :signed_in)
      sign_in(resource_name, resource)
      yield resource if block_given?
      
      # 初回ログインチェック
      if resource.must_change_password?
        redirect_to store_change_password_profile_path,
                    notice: I18n.t("devise.passwords.must_change_on_first_login")
      else
        respond_with resource, location: after_sign_in_path_for(resource)
      end
    end

    # ログアウト処理
    def destroy
      super do
        # ログアウト後は店舗選択画面へ
        redirect_to store_selection_path and return
      end
    end

    protected

    # ============================================
    # 認証設定
    # ============================================

    # 店舗を含む認証オプション
    def auth_options_with_store
      {
        scope: resource_name,
        recall: "#{controller_path}#new",
        store_id: @store&.id
      }
    end

    # 認証パラメータの設定
    def configure_sign_in_params
      devise_parameter_sanitizer.permit(:sign_in, keys: [:store_slug])
    end

    # ログイン後のリダイレクト先
    def after_sign_in_path_for(resource)
      stored_location_for(resource) || store_root_path
    end

    # ログアウト後のリダイレクト先
    def after_sign_out_path_for(resource_or_scope)
      store_selection_path
    end

    # ============================================
    # 店舗管理
    # ============================================

    # パラメータから店舗を設定
    def set_store_from_params
      store_slug = params[:store_slug] || params[:store_user]&.dig(:store_slug)
      
      if store_slug.present?
        @store = Store.active.find_by(slug: store_slug)
        unless @store
          redirect_to store_selection_path,
                      alert: I18n.t("errors.messages.store_not_found")
        end
      end
    end

    # 店舗が有効かチェック
    def check_store_active
      return unless @store
      
      unless @store.active?
        redirect_to store_selection_path,
                    alert: I18n.t("errors.messages.store_inactive")
      end
    end

    # ============================================
    # セッション管理
    # ============================================

    # サインイン時の追加処理
    def sign_in(resource_name, resource)
      super
      
      # 店舗情報をセッションに保存
      session[:current_store_id] = resource.store_id
      
      # ログイン履歴の記録
      log_sign_in_event(resource)
    end

    # サインアウト時の追加処理  
    def sign_out(resource_name)
      # 店舗情報をセッションから削除
      session.delete(:current_store_id)
      
      super
    end

    private

    # ============================================
    # ユーティリティ
    # ============================================

    # JSONリクエストかどうか
    def json_request?
      request.format.json?
    end

    # ログイン履歴の記録
    def log_sign_in_event(resource)
      # TODO: Phase 5 - 監査ログの実装
      # SignInEvent.create!(
      #   store_user: resource,
      #   store: resource.store,
      #   ip_address: request.remote_ip,
      #   user_agent: request.user_agent,
      #   signed_in_at: Time.current
      # )
    end

    # ============================================
    # Warden認証のカスタマイズ
    # ============================================

    # 認証失敗時のカスタム処理
    def auth_failed
      # 失敗回数の記録（ブルートフォース対策）
      if params[:store_user]&.dig(:email).present?
        # TODO: Phase 5 - 認証失敗の記録
        # track_failed_attempt(params[:store_user][:email])
      end
      
      super
    end
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 二要素認証
#    - SMS/TOTP認証の追加
#    - バックアップコード生成
#
# 2. 🟡 デバイス管理
#    - 信頼されたデバイスの記憶
#    - 新規デバイスからのアクセス通知
#
# 3. 🟢 ソーシャルログイン
#    - Google Workspace連携
#    - Microsoft Azure AD連携