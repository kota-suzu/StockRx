# frozen_string_literal: true

# 店舗ユーザー認証のための共通機能
# ============================================
# Phase 2: 店舗別ログインシステム
# 店舗スコープの認証とアクセス制御を提供
# ============================================
module StoreAuthenticatable
  extend ActiveSupport::Concern

  included do
    # Deviseヘルパーメソッドの設定
    helper_method :current_store, :store_signed_in?

    # フィルター設定
    before_action :configure_permitted_parameters, if: :devise_controller?
    before_action :check_password_expiration, if: :store_user_signed_in?
  end

  # ============================================
  # 認証関連メソッド
  # ============================================

  # 現在の店舗を取得
  def current_store
    @current_store ||= current_store_user&.store
  end

  # 店舗ユーザーがサインインしているか
  def store_signed_in?
    store_user_signed_in? && current_store.present?
  end

  # 店舗認証を要求
  def authenticate_store_user!
    unless store_user_signed_in?
      store_slug = params[:store_slug] || params[:slug]

      # 店舗が指定されている場合はその店舗のログインページへ
      if store_slug.present?
        redirect_to store_login_page_path(slug: store_slug),
                    alert: I18n.t("devise.failure.unauthenticated")
      else
        # 店舗が指定されていない場合は店舗選択画面へ
        redirect_to store_selection_path,
                    alert: I18n.t("devise.failure.store_selection_required")
      end
    end
  end

  # 店舗管理者のみアクセス可能
  def require_store_manager!
    authenticate_store_user!

    unless current_store_user.manager?
      redirect_to store_root_path,
                  alert: I18n.t("errors.messages.insufficient_permissions")
    end
  end

  # ============================================
  # パスワード管理
  # ============================================

  # パスワード有効期限チェック
  def check_password_expiration
    return unless current_store_user.password_expired?

    # パスワード変更ページ以外へのアクセスは制限
    allowed_paths = [
      store_change_password_profile_path,
      store_update_password_profile_path,
      destroy_store_user_session_path
    ]

    unless allowed_paths.include?(request.path)
      redirect_to store_change_password_profile_path,
                  alert: I18n.t("devise.passwords.expired")
    end
  end

  # ============================================
  # アクセス制御
  # ============================================

  # 自店舗のリソースのみアクセス可能
  def ensure_own_store_resource
    resource_store_id = params[:store_id] ||
                       instance_variable_get("@#{controller_name.singularize}")&.store_id

    if resource_store_id && resource_store_id.to_i != current_store.id
      redirect_to store_root_path,
                  alert: I18n.t("errors.messages.access_denied")
    end
  end

  # 店舗が有効かチェック
  def ensure_store_active
    return unless current_store

    unless current_store.active?
      sign_out(:store_user)
      redirect_to store_selection_path,
                  alert: I18n.t("errors.messages.store_inactive")
    end
  end

  private

  # Devise用のパラメータ設定
  def configure_permitted_parameters
    return unless devise_controller?

    # サインアップ時（将来的に管理者が作成する場合）
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :name, :employee_code, :store_id ])

    # アカウント更新時
    devise_parameter_sanitizer.permit(:account_update, keys: [ :name, :employee_code ])
  end
end

# ============================================
# TODO: Phase 3以降の拡張予定
# ============================================
# 1. 🔴 IPアドレス制限
#    - 店舗ごとの許可IPリスト管理
#    - アクセス拒否時の詳細ログ
#
# 2. 🟡 営業時間制限
#    - 店舗営業時間外のアクセス制限
#    - 管理者の例外設定
#
# 3. 🟢 デバイス認証
#    - 登録済みデバイスのみアクセス許可
#    - 新規デバイスの承認フロー
