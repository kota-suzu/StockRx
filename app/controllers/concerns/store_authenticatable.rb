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
    # CLAUDE.md準拠: ルーティングヘルパーの正しい命名規則
    # メタ認知: singular resourceのmember routeは action_namespace_resource_path
    # 横展開: ビューファイルでも同様の修正実施済み
    allowed_paths = [
      change_password_store_profile_path,
      update_password_store_profile_path,
      destroy_store_user_session_path
    ]

    unless allowed_paths.include?(request.path)
      redirect_to change_password_store_profile_path,
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
      # sign_out前にユーザー情報を保存（CLAUDE.md: ベストプラクティス横展開適用）
      inactive_store_slug = current_store&.slug || "unknown"
      user_email = current_store_user&.email || "unknown"
      user_ip = request.remote_ip

      sign_out(:store_user)

      # セキュリティログ記録（横展開: StoreSelectionControllerと一貫したログ形式）
      Rails.logger.warn "SECURITY: User signed out due to inactive store - " \
                       "store: #{inactive_store_slug}, " \
                       "user: #{user_email}, " \
                       "ip: #{user_ip}"

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
# TODO: Phase 3以降の拡張予定（CLAUDE.md準拠の包括的改善）
# ============================================
#
# 🔴 Phase 3: セキュリティ強化（優先度: 高、推定4日）
# 1. IPアドレス制限
#    - 店舗ごとの許可IPリスト管理
#    - アクセス拒否時の詳細ログ（nil安全性確保）
#    - 横展開: 全認証ポイントでの統一IP制限実装
#
# 2. 営業時間制限
#    - 店舗営業時間外のアクセス制限
#    - 管理者の例外設定
#    - タイムゾーン対応の包括的時間管理
#
# 3. デバイス認証
#    - 登録済みデバイスのみアクセス許可
#    - 新規デバイスの承認フロー
#    - デバイス情報のセキュアな保存
#
# 🟡 Phase 4: 監査・コンプライアンス（優先度: 中、推定3日）
# 1. 監査ログ強化
#    - 構造化ログの統一フォーマット
#    - ログローテーションとアーカイブ
#    - GDPR/PCI DSS準拠の個人情報保護
#
# 🟢 Phase 5: パフォーマンス最適化（優先度: 低、推定2日）
# 1. セッション管理最適化
#    - Redis活用のセッション最適化
#    - 認証キャッシュの効率化
#
# ============================================
# メタ認知的改善ポイント（今回の横展開から得た教訓）
# ============================================
# 1. **一貫性の確保**: sign_out処理で共通パターン確立
#    - 事前情報保存→セッションクリア→詳細ログ記録
#    - 横展開完了: StoreSelectionController, StoreAuthenticatable
#    - 既存対応済み: SessionsController（手動実装済み）
#
# 2. **エラー処理の標準化**:
#    - nil安全性の徹底（safe navigation演算子活用）
#    - フォールバック機能の実装
#    - 例外時の適切なログ記録
#
# 3. **セキュリティログの標準化**:
#    - SECURITY: プレフィックスによる分類
#    - 構造化された情報記録（店舗、ユーザー、IP、理由）
#    - 適切なログレベル設定（INFO/WARN/ERROR）
#
# 4. **今後の実装チェックリスト**:
#    - [ ] 全sign_out処理でのnil安全性確認
#    - [ ] セキュリティログの統一フォーマット適用
#    - [ ] 認証例外処理の包括的レビュー
#    - [ ] ルーティング競合の事前検証
