# frozen_string_literal: true

module StoreControllers
  # プロフィール管理コントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # 店舗ユーザーの個人設定管理
  # ============================================
  class ProfilesController < BaseController
    # 更新アクションのみ強いパラメータチェック
    before_action :set_user
    
    # ============================================
    # アクション
    # ============================================

    # プロフィール表示
    def show
      # ログイン履歴
      @login_history = build_login_history
      
      # セキュリティ設定
      @security_settings = build_security_settings
    end

    # プロフィール編集
    def edit
      # 編集フォーム表示
    end

    # プロフィール更新
    def update
      if @user.update(profile_params)
        redirect_to store_profile_path, 
                    notice: I18n.t("messages.profile_updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # パスワード変更画面
    def change_password
      # パスワード有効期限の確認
      @password_expires_in = password_expiration_days
      @must_change = @user.must_change_password?
    end

    # パスワード更新
    def update_password
      # 現在のパスワードの確認
      unless @user.valid_password?(password_update_params[:current_password])
        @user.errors.add(:current_password, :invalid)
        render :change_password, status: :unprocessable_entity
        return
      end
      
      # 新しいパスワードの設定
      if @user.update(password_update_params.except(:current_password))
        # パスワード変更日時の更新
        @user.update_columns(
          password_changed_at: Time.current,
          must_change_password: false
        )
        
        # 再ログインは不要（セッション維持）
        bypass_sign_in(@user)
        
        redirect_to store_profile_path,
                    notice: I18n.t("devise.passwords.updated")
      else
        render :change_password, status: :unprocessable_entity
      end
    end

    private

    # ============================================
    # 共通処理
    # ============================================

    def set_user
      @user = current_store_user
    end

    # ============================================
    # パラメータ
    # ============================================

    def profile_params
      params.require(:store_user).permit(:name, :email, :employee_code)
    end

    def password_update_params
      params.require(:store_user).permit(
        :current_password,
        :password,
        :password_confirmation
      )
    end

    # ============================================
    # データ準備
    # ============================================

    # ログイン履歴の構築
    def build_login_history
      {
        current_sign_in_at: @user.current_sign_in_at,
        last_sign_in_at: @user.last_sign_in_at,
        current_sign_in_ip: @user.current_sign_in_ip,
        last_sign_in_ip: @user.last_sign_in_ip,
        sign_in_count: @user.sign_in_count,
        failed_attempts: @user.failed_attempts
      }
    end

    # セキュリティ設定の構築
    def build_security_settings
      {
        password_changed_at: @user.password_changed_at,
        password_expires_at: @user.password_changed_at&.+ 90.days,
        locked_at: @user.locked_at,
        unlock_token_sent_at: @user.unlock_token.present? ? @user.updated_at : nil,
        two_factor_enabled: false # TODO: Phase 5 - 2FA実装
      }
    end

    # パスワード有効期限までの日数
    def password_expiration_days
      return nil unless @user.password_changed_at
      
      expires_at = @user.password_changed_at + 90.days
      days_remaining = (expires_at.to_date - Date.current).to_i
      
      [days_remaining, 0].max
    end

    # ============================================
    # ビューヘルパー
    # ============================================

    # パスワード強度インジケーター
    helper_method :password_strength_class
    def password_strength_class(days_remaining)
      return 'text-danger' if days_remaining.nil? || days_remaining <= 7
      return 'text-warning' if days_remaining <= 30
      'text-success'
    end

    # IPアドレスの表示形式
    helper_method :format_ip_address
    def format_ip_address(ip)
      return I18n.t("messages.unknown") if ip.blank?
      
      # プライバシー保護のため一部マスク
      if ip.include?('.')
        # IPv4
        parts = ip.split('.')
        "#{parts[0]}.#{parts[1]}.***.***"
      else
        # IPv6
        parts = ip.split(':')
        "#{parts[0]}:#{parts[1]}:****:****"
      end
    end

    # ============================================
    # セキュリティチェック
    # ============================================

    # パスワード変更権限の確認
    def can_change_password?
      # 本人のみ変更可能
      true
    end

    # メールアドレス変更権限の確認
    def can_change_email?
      # 管理者承認が必要な場合はfalse
      # TODO: Phase 5 - 管理者承認フロー
      !@user.manager?
    end
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 二要素認証設定
#    - TOTP設定・QRコード生成
#    - バックアップコード管理
#
# 2. 🟡 通知設定
#    - メール通知のON/OFF
#    - 通知タイミングのカスタマイズ
#
# 3. 🟢 アクセスログ
#    - 詳細なアクセス履歴表示
#    - 不審なアクセスの検知