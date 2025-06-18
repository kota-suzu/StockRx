# frozen_string_literal: true

module StoreControllers
  # 店舗ユーザー用メール認証コントローラー
  # ============================================================================
  # CLAUDE.md準拠: 一時パスワード認証システム実装
  #
  # 用途:
  # - 一時パスワードのリクエスト処理
  # - 一時パスワードによるログイン処理
  # - セキュリティログと監査機能
  # - レート制限とブルートフォース対策
  #
  # 設計方針:
  # - EmailAuthService経由でのビジネスロジック実行
  # - SecurityComplianceManagerでのセキュリティ管理
  # - 横展開: SessionsControllerのパターン踏襲
  # - メタ認知: UXとセキュリティのバランス最適化
  # ============================================================================
  class EmailAuthController < BaseController
    include RateLimitable
    
    # 認証チェックをスキップ（認証前の操作のため）
    skip_before_action :authenticate_store_user!
    skip_before_action :ensure_store_active
    
    # 店舗の事前確認
    before_action :set_store_from_params
    before_action :check_store_active, except: [:request_temp_password]
    before_action :validate_rate_limits, only: [:request_temp_password, :verify_temp_password]
    
    # CSRFトークン検証をスキップ（APIモード対応）
    skip_before_action :verify_authenticity_token, only: [:request_temp_password, :verify_temp_password], if: :json_request?
    
    # レイアウト設定
    layout "store_auth"

    # ============================================
    # アクション
    # ============================================

    # 一時パスワードリクエストフォーム表示
    def new
      # 店舗が指定されていない場合は店舗選択画面へ
      redirect_to store_selection_path and return unless @store
      
      @email_auth_request = EmailAuthRequest.new(store_id: @store.id)
    end

    # 一時パスワードリクエスト処理
    def request_temp_password
      unless @store
        respond_to_request_error(
          I18n.t("email_auth.errors.store_selection_required"),
          :store_selection_required
        )
        return
      end

      # パラメータ検証
      email = params.dig(:email_auth_request, :email) || params[:email]
      
      unless email.present?
        respond_to_request_error(
          I18n.t("email_auth.errors.email_required"),
          :email_required
        )
        return
      end

      # ユーザー存在確認
      store_user = StoreUser.find_by(email: email, store_id: @store.id)
      
      unless store_user
        # セキュリティ: 存在しないユーザーでも同じレスポンスを返す（列挙攻撃対策）
        respond_to_request_success(email)
        return
      end

      # レート制限確認
      if rate_limit_exceeded?(email)
        respond_to_request_error(
          I18n.t("email_auth.errors.rate_limit_exceeded"),
          :rate_limit_exceeded
        )
        return
      end

      # EmailAuthServiceで一時パスワード生成・送信
      begin
        service = EmailAuthService.new
        result = service.generate_and_send_temp_password(
          store_user,
          admin_id: nil, # 店舗ユーザーからのリクエストのためnill
          request_metadata: {
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            requested_at: Time.current
          }
        )

        if result[:success]
          track_rate_limit_action!(email) # 成功時もレート制限カウント
          respond_to_request_success(email)
        else
          respond_to_request_error(
            result[:error] || I18n.t("email_auth.errors.generation_failed"),
            :generation_failed
          )
        end

      rescue StandardError => e
        Rails.logger.error "一時パスワード生成エラー: #{e.message}"
        respond_to_request_error(
          I18n.t("email_auth.errors.system_error"),
          :system_error
        )
      end
    end

    # 一時パスワード検証フォーム表示
    def verify_form
      redirect_to store_selection_path and return unless @store
      
      @temp_password_verification = TempPasswordVerification.new(store_id: @store.id)
    end

    # 一時パスワード検証・ログイン処理
    def verify_temp_password
      unless @store
        respond_to_verification_error(
          I18n.t("email_auth.errors.store_selection_required"),
          :store_selection_required
        )
        return
      end

      # パラメータ検証
      verification_params = params.require(:temp_password_verification).permit(:email, :temp_password)
      
      unless verification_params[:email].present? && verification_params[:temp_password].present?
        respond_to_verification_error(
          I18n.t("email_auth.errors.missing_parameters"),
          :missing_parameters
        )
        return
      end

      # ユーザー存在確認
      store_user = StoreUser.find_by(email: verification_params[:email], store_id: @store.id)
      
      unless store_user
        track_rate_limit_action!(verification_params[:email]) # 失敗時レート制限カウント
        respond_to_verification_error(
          I18n.t("email_auth.errors.invalid_credentials"),
          :invalid_credentials
        )
        return
      end

      # 一時パスワード検証
      begin
        service = EmailAuthService.new
        result = service.authenticate_with_temp_password(
          store_user,
          verification_params[:temp_password],
          request_metadata: {
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            verified_at: Time.current
          }
        )

        if result[:success]
          # 認証成功 - 通常のログイン処理
          sign_in_store_user(store_user, result[:temp_password])
        else
          track_rate_limit_action!(verification_params[:email]) # 失敗時レート制限カウント
          respond_to_verification_error(
            result[:error] || I18n.t("email_auth.errors.invalid_credentials"),
            :invalid_credentials
          )
        end

      rescue StandardError => e
        Rails.logger.error "一時パスワード検証エラー: #{e.message}"
        respond_to_verification_error(
          I18n.t("email_auth.errors.system_error"),
          :system_error
        )
      end
    end

    private

    # ============================================
    # レスポンス処理
    # ============================================

    def respond_to_request_success(email)
      masked_email = mask_email(email)
      
      respond_to do |format|
        format.html do
          redirect_to verify_form_store_email_auth_path(store_slug: @store.slug),
                      notice: I18n.t("email_auth.messages.temp_password_sent", email: masked_email)
        end
        format.json do
          render json: {
            success: true,
            message: I18n.t("email_auth.messages.temp_password_sent", email: masked_email),
            next_step: "verify_temp_password"
          }, status: :ok
        end
      end
    end

    def respond_to_request_error(message, error_code)
      respond_to do |format|
        format.html do
          @email_auth_request = EmailAuthRequest.new(store_id: @store&.id)
          flash.now[:alert] = message
          render :new, status: :unprocessable_entity
        end
        format.json do
          render json: {
            success: false,
            error: message,
            error_code: error_code
          }, status: :unprocessable_entity
        end
      end
    end

    def respond_to_verification_success
      respond_to do |format|
        format.html do
          redirect_to store_root_path,
                      notice: I18n.t("email_auth.messages.login_successful")
        end
        format.json do
          render json: {
            success: true,
            message: I18n.t("email_auth.messages.login_successful"),
            redirect_url: store_root_path
          }, status: :ok
        end
      end
    end

    def respond_to_verification_error(message, error_code)
      respond_to do |format|
        format.html do
          @temp_password_verification = TempPasswordVerification.new(store_id: @store&.id)
          flash.now[:alert] = message
          render :verify_form, status: :unprocessable_entity
        end
        format.json do
          render json: {
            success: false,
            error: message,
            error_code: error_code
          }, status: :unprocessable_entity
        end
      end
    end

    # ============================================
    # 認証処理
    # ============================================

    def sign_in_store_user(store_user, temp_password)
      # Deviseのsign_inメソッドを使用
      sign_in(store_user, scope: :store_user)
      
      # セッション情報設定
      session[:current_store_id] = store_user.store_id
      session[:signed_in_at] = Time.current
      session[:login_method] = "temp_password"
      session[:temp_password_id] = temp_password.id

      # ログイン履歴記録
      log_temp_password_login(store_user, temp_password)
      
      # TODO: 🟡 Phase 2重要 - 一時パスワードログイン後の強制パスワード変更
      # 優先度: 中（セキュリティ要件）
      # 実装内容:
      #   - 一時パスワードログイン後は必ずパスワード変更画面へリダイレクト
      #   - パスワード変更完了まで他画面アクセス制限
      #   - セッションフラグでの状態管理
      # 期待効果: セキュリティコンプライアンス向上、パスワード管理強化

      respond_to_verification_success
    end

    # ============================================
    # 店舗管理
    # ============================================

    def set_store_from_params
      store_slug = params[:store_slug] || 
                   params.dig(:email_auth_request, :store_slug) || 
                   params.dig(:temp_password_verification, :store_slug)

      if store_slug.present?
        @store = Store.active.find_by(slug: store_slug)
        unless @store
          redirect_to store_selection_path,
                      alert: I18n.t("errors.messages.store_not_found")
        end
      end
    end

    def check_store_active
      return unless @store

      unless @store.active?
        redirect_to store_selection_path,
                    alert: I18n.t("errors.messages.store_inactive")
      end
    end

    # ============================================
    # レート制限
    # ============================================

    def validate_rate_limits
      email = extract_email_from_params
      
      if email.present? && rate_limit_exceeded?(email)
        respond_to do |format|
          format.html do
            redirect_to new_store_email_auth_path(store_slug: @store.slug),
                        alert: I18n.t("email_auth.errors.rate_limit_exceeded")
          end
          format.json do
            render json: {
              success: false,
              error: I18n.t("email_auth.errors.rate_limit_exceeded"),
              error_code: :rate_limit_exceeded
            }, status: :too_many_requests
          end
        end
      end
    end

    def rate_limit_exceeded?(email)
      # EmailAuthServiceのレート制限チェックを活用
      begin
        service = EmailAuthService.new
        !service.rate_limit_check(email, request.remote_ip)
      rescue => e
        Rails.logger.warn "レート制限チェックエラー: #{e.message}"
        false # エラー時は制限しない（サービス継続性重視）
      end
    end

    def track_rate_limit_action!(email)
      # レート制限カウンターを増加
      # 実装はEmailAuthServiceに委譲
      service = EmailAuthService.new
      service.increment_rate_limit_counter(email, request.remote_ip)
    rescue => e
      Rails.logger.warn "レート制限カウント失敗: #{e.message}"
    end

    # ============================================
    # レート制限設定（RateLimitableモジュール用）
    # ============================================

    def rate_limited_actions
      [:request_temp_password, :verify_temp_password]
    end

    def rate_limit_key_type
      :email_auth
    end

    def rate_limit_identifier
      email = extract_email_from_params
      "#{@store&.id}:#{email}:#{request.remote_ip}"
    end

    # ============================================
    # ユーティリティ
    # ============================================

    def extract_email_from_params
      params.dig(:email_auth_request, :email) || 
      params.dig(:temp_password_verification, :email) || 
      params[:email]
    end

    def json_request?
      request.format.json?
    end

    def mask_email(email)
      return "[NO_EMAIL]" if email.blank?
      return "[INVALID_EMAIL]" unless email.include?("@")
      
      local, domain = email.split("@", 2)
      
      case local.length
      when 1
        "#{local.first}***@#{domain}"
      when 2
        "#{local.first}*@#{domain}"
      else
        "#{local.first}***#{local.last}@#{domain}"
      end
    end

    def log_temp_password_login(store_user, temp_password)
      AuditLog.log_action(
        store_user,
        "temp_password_login",
        "#{store_user.name}（#{store_user.email}）が一時パスワードでログインしました",
        {
          store_id: store_user.store_id,
          store_name: store_user.store.name,
          store_slug: store_user.store.slug,
          login_method: "temp_password",
          temp_password_id: temp_password.id,
          session_id: session.id,
          generated_at: temp_password.created_at,
          expires_at: temp_password.expires_at
        }
      )
    rescue => e
      Rails.logger.error "一時パスワードログイン監査ログ記録失敗: #{e.message}"
    end
  end
end

# ============================================
# フォームオブジェクト定義
# ============================================

# 一時パスワードリクエスト用フォームオブジェクト
class EmailAuthRequest
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  attribute :store_id, :integer
  attribute :store_slug, :string

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :store_id, presence: true

  def store
    @store ||= Store.find_by(id: store_id) if store_id
  end
end

# 一時パスワード検証用フォームオブジェクト
class TempPasswordVerification
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  attribute :temp_password, :string
  attribute :store_id, :integer
  attribute :store_slug, :string

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :temp_password, presence: true
  validates :store_id, presence: true

  def store
    @store ||= Store.find_by(id: store_id) if store_id
  end
end

# ============================================
# TODO: Phase 2以降の拡張予定
# ============================================
# 1. 🟡 一時パスワード後の強制パスワード変更
#    - パスワード変更完了まで他画面アクセス制限
#    - セッションフラグでの状態管理
#
# 2. 🟡 多要素認証統合
#    - SMS認証の追加選択肢
#    - TOTP認証の統合
#
# 3. 🟢 デバイス記憶機能
#    - 信頼されたデバイスからの一時パスワード省略
#    - デバイスフィンガープリンティング
#
# 4. 🟢 高度なセキュリティ機能
#    - 地理的位置チェック
#    - 行動パターン分析
#    - 異常検知アルゴリズム