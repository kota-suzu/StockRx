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
    before_action :check_store_active, except: [ :request_temp_password ]
    before_action :validate_rate_limits, only: [ :request_temp_password, :verify_temp_password ]

    # CSRFトークン検証をスキップ（APIモード対応）
    skip_before_action :verify_authenticity_token, only: [ :request_temp_password, :verify_temp_password ], if: :json_request?

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
          "店舗が選択されていません",
          :store_selection_required
        )
        return
      end

      # パラメータ検証（複数の形式に対応）
      email = params[:email] || params.dig(:email_auth_request, :email)

      unless email.present?
        respond_to_request_error(
          "メールアドレスを入力してください",
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
          "一時パスワードの送信回数が制限を超えました。しばらくしてからお試しください。",
          :rate_limit_exceeded
        )
        return
      end

      # EmailAuthServiceで一時パスワード生成・送信
      begin
        Rails.logger.info "📧 [EmailAuth] Starting temp password generation for #{mask_email(email)}"

        service = EmailAuthService.new
        result = service.generate_and_send_temp_password(
          store_user,
          admin_id: nil, # 店舗ユーザーからのリクエストのためnil
          request_metadata: {
            ip_address: request.remote_ip,
            user_agent: request.user_agent,
            requested_at: Time.current
          }
        )

        Rails.logger.info "📧 [EmailAuth] Service result: success=#{result[:success]}, error=#{result[:error]}"

        if result[:success]
          Rails.logger.info "✅ [EmailAuth] Email sent successfully, proceeding to success response"
          track_rate_limit_action!(email) # 成功時もレート制限カウント
          respond_to_request_success(email)
        else
          Rails.logger.warn "❌ [EmailAuth] Email service returned failure: #{result[:error]}"
          error_message = case result[:error]
          when "rate_limit_exceeded"
            "一時パスワードの送信回数が制限を超えました。しばらくしてからお試しください。"
          when "email_delivery_failed"
            "メール送信に失敗しました。メールアドレスをご確認ください。"
          else
            "一時パスワードの生成に失敗しました。もう一度お試しください。"
          end

          respond_to_request_error(error_message, :generation_failed)
        end

      rescue StandardError => e
        Rails.logger.error "💥 [EmailAuth] Exception in request_temp_password: #{e.class.name}: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        respond_to_request_error(
          "システムエラーが発生しました。しばらくしてからお試しください。",
          :system_error
        )
      end
    end

    # 一時パスワード検証フォーム表示
    def verify_form
      redirect_to store_selection_path and return unless @store

      # CLAUDE.md準拠: セッションからメールアドレスを取得
      # メタ認知: ユーザーの再入力を不要にしてUX向上
      # セキュリティ: セッション有効期限チェックで安全性確保
      # 横展開: 他の多段階認証でも同様のセッション管理パターン
      email = session[:temp_password_email]
      expires_at = session[:temp_password_email_expires_at]

      # セッション有効期限チェック
      if email.blank? || expires_at.blank? || Time.current.to_i > expires_at
        # セッション期限切れまたは無効な場合
        session.delete(:temp_password_email)
        session.delete(:temp_password_email_expires_at)
        redirect_to store_email_auth_path(store_slug: @store.slug),
                    alert: "セッションの有効期限が切れました。もう一度メールアドレスを入力してください。"
        return
      end

      @temp_password_verification = TempPasswordVerification.new(
        store_id: @store.id,
        email: email
      )
      @masked_email = mask_email(email)
    end

    # 一時パスワード検証・ログイン処理
    def verify_temp_password
      unless @store
        respond_to_verification_error(
          "店舗が選択されていません",
          :store_selection_required
        )
        return
      end

      # パラメータ検証（複数の形式に対応）
      email = params[:email] || params.dig(:temp_password_verification, :email)
      temp_password = params[:temp_password] || params.dig(:temp_password_verification, :temp_password)

      unless email.present? && temp_password.present?
        respond_to_verification_error(
          "メールアドレスと一時パスワードを入力してください",
          :missing_parameters
        )
        return
      end

      # ユーザー存在確認
      store_user = StoreUser.find_by(email: email, store_id: @store.id)

      unless store_user
        track_rate_limit_action!(email) # 失敗時レート制限カウント
        respond_to_verification_error(
          "メールアドレスまたは一時パスワードが正しくありません",
          :invalid_credentials
        )
        return
      end

      # 一時パスワード検証
      begin
        service = EmailAuthService.new
        result = service.authenticate_with_temp_password(
          store_user,
          temp_password,
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
          track_rate_limit_action!(email) # 失敗時レート制限カウント

          error_message = case result[:reason]
          when "expired"
            "一時パスワードの有効期限が切れました。再度送信してください。"
          when "already_used"
            "この一時パスワードは既に使用されています。"
          when "locked"
            "試行回数が上限に達しました。新しい一時パスワードを要求してください。"
          else
            "メールアドレスまたは一時パスワードが正しくありません"
          end

          respond_to_verification_error(error_message, :invalid_credentials)
        end

      rescue StandardError => e
        Rails.logger.error "一時パスワード検証エラー: #{e.message}"
        respond_to_verification_error(
          "システムエラーが発生しました。しばらくしてからお試しください。",
          :system_error
        )
      end
    end

    private

    # ============================================
    # レスポンス処理
    # ============================================

    def respond_to_request_success(email)
      begin
        masked_email = mask_email(email)
        Rails.logger.info "🎭 [EmailAuth] Masked email: #{masked_email}"

        # CLAUDE.md準拠: セッションにメールアドレスを保存してUX向上
        # メタ認知: 一時パスワード検証画面で再入力不要にする
        # セキュリティ: セッションに保存することで安全に情報を保持
        # 横展開: 他の多段階認証フローでも同様のパターン適用可能
        session[:temp_password_email] = email
        session[:temp_password_email_expires_at] = 30.minutes.from_now.to_i
        Rails.logger.info "💾 [EmailAuth] Session data saved successfully"

        respond_to do |format|
          format.html do
            redirect_url = store_verify_temp_password_form_path(store_slug: @store.slug)
            Rails.logger.info "🔗 [EmailAuth] Redirecting to: #{redirect_url}"
            redirect_to redirect_url,
                        notice: "#{masked_email} に一時パスワードを送信しました"
          end
          format.json do
            json_response = {
              success: true,
              message: "一時パスワードを送信しました。メールをご確認ください。",
              masked_email: masked_email,
              next_step: "verify_temp_password",
              redirect_url: store_verify_temp_password_form_path(store_slug: @store.slug)
            }
            Rails.logger.info "📤 [EmailAuth] JSON response: #{json_response.except(:redirect_url).inspect}"
            render json: json_response, status: :ok
          end
        end
      rescue StandardError => e
        Rails.logger.error "💥 [EmailAuth] Error in respond_to_request_success: #{e.class.name}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        # フォールバック処理：メール送信は成功しているため、適切なメッセージを表示
        respond_to_request_error(
          "メール送信は完了しましたが、画面遷移中にエラーが発生しました。ブラウザを更新してお試しください。",
          :redirect_error
        )
      end
    end

    def respond_to_request_error(message, error_code)
      Rails.logger.warn "⚠️ [EmailAuth] Request error: #{error_code} - #{message}"

      respond_to do |format|
        format.html do
          @email_auth_request = EmailAuthRequest.new(store_id: @store&.id)
          flash.now[:alert] = message
          Rails.logger.info "🔄 [EmailAuth] Rendering error page with message: #{message}"
          render :new, status: :unprocessable_entity
        end
        format.json do
          json_error = {
            success: false,
            error: message,
            error_code: error_code
          }
          Rails.logger.info "📤 [EmailAuth] JSON error response: #{json_error.inspect}"
          status_code = error_code == :rate_limit_exceeded ? :too_many_requests : :unprocessable_entity
          render json: json_error, status: status_code
        end
      end
    end

    def respond_to_verification_success
      respond_to do |format|
        format.html do
          # 🔧 店舗ダッシュボードへリダイレクト
          redirect_to store_root_path,
                      notice: "ログインしました"
        end
        format.json do
          render json: {
            success: true,
            message: "ログインしました",
            redirect_url: store_root_path
          }, status: :ok
        end
      end
    end

    def respond_to_verification_error(message, error_code)
      respond_to do |format|
        format.html do
          # 🔧 パスコード専用フローのため、ログイン画面に戻す
          redirect_to new_store_user_session_path(store_slug: @store&.slug),
                      alert: message
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
      # CLAUDE.md準拠: 適切なpublicインターフェース使用
      # メタ認知: privateメソッド直接呼び出しから適切なカプセル化へ修正
      # 横展開: 他のコントローラーでも同様のパターン適用
      begin
        Rails.logger.info "📊 [EmailAuth] Recording rate limit for #{mask_email(email)}"

        service = EmailAuthService.new
        success = service.record_authentication_attempt(email, request.remote_ip)

        if success
          Rails.logger.info "✅ [EmailAuth] Rate limit recorded successfully"
        else
          Rails.logger.warn "⚠️ [EmailAuth] Rate limit recording failed but processing continues"
        end
      rescue => e
        Rails.logger.warn "💥 [EmailAuth] Rate limit count failed: #{e.class.name}: #{e.message}"
        # レート制限記録失敗は処理を止めない
      end
    end

    # ============================================
    # レート制限設定（RateLimitableモジュール用）
    # ============================================

    def rate_limited_actions
      [ :request_temp_password, :verify_temp_password ]
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
