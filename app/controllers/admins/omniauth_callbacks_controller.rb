# frozen_string_literal: true

require "cgi"
require "securerandom"
require "ostruct"

# OmniAuth認証のコールバック処理を管理するコントローラー
# Devise::OmniauthCallbacksControllerを継承し、GitHub認証をカスタマイズ
class Admins::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  # GitHub認証成功時のコールバック処理
  def github
    # OmniAuthの標準フローではstateはOmniAuth側で自動管理されるため、
    # カスタムstate検証は不要（Deviseが自動で行う）

    # OmniAuthから認証情報を取得
    auth_hash = request.env["omniauth.auth"]

    # IPアドレスをauth_hashに追加（セキュリティ監査用）
    auth_hash.extra ||= OpenStruct.new
    auth_hash.extra.raw_info ||= OpenStruct.new
    auth_hash.extra.raw_info.request_ip = request.remote_ip

    # 認証情報からAdminを検索または作成
    @admin = Admin.from_omniauth(auth_hash)

    if @admin.persisted?
      # ログイン成功処理
      sign_in @admin, event: :authentication

      # 権限に応じた適切なリダイレクト先を決定
      redirect_path = after_github_sign_in_path(@admin)

      # フラッシュメッセージを設定
      if is_navigational_format?
        set_flash_message(:notice, :success, kind: "GitHub")
        flash[:notice] = "GitHubアカウントでログインしました。"
      end

      # 監査ログ記録
      log_authentication_event(@admin, "github", "success")

      # 適切な画面にリダイレクト
      redirect_to redirect_path
    else
      # アカウント作成失敗時の処理
      session["devise.github_data"] = auth_hash.except(:extra)

      # 詳細なエラーメッセージを生成
      error_message = github_error_message(@admin)

      # エラーログ記録
      Rails.logger.error "GitHub OAuth account creation failed: #{@admin.errors.full_messages.join(', ')}"

      # エラーメッセージと共にログイン画面へリダイレクト
      redirect_to new_admin_session_path, alert: error_message

      # 監査ログ記録
      log_authentication_event(nil, "github", "failure", auth_hash.info.email)
    end
  rescue StandardError => e
    # 例外発生時のエラーハンドリング
    Rails.logger.error "GitHub OAuth Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    redirect_to new_admin_session_path, alert: "GitHub認証中にエラーが発生しました。"
  end

  # OmniAuth認証失敗時の処理
  def failure
    # エラーメッセージを取得
    error_message = request.env["omniauth.error.type"].to_s.humanize

    # 監査ログ記録
    log_authentication_event(nil, "github", "failure", nil, error_message)

    redirect_to new_admin_session_path, alert: "GitHub認証に失敗しました: #{error_message}"
  end

  # OmniAuthプロバイダーへのパススルー処理
  # GET|POST /admin/auth/:provider
  # Deviseの標準OmniAuth処理を使用
  def passthru
    super
  end

  private

  # GitHub認証成功後のリダイレクト先を決定
  # @param admin [Admin] 認証されたAdminインスタンス
  # @return [String] リダイレクト先のパス
  def after_github_sign_in_path(admin)
    case admin.role
    when "headquarters_admin"
      # 本部管理者: 管理者ダッシュボード
      admin_dashboard_path
    when "store_manager"
      # 店舗管理者: 担当店舗のダッシュボード
      if admin.store
        store_dashboard_path(admin.store)
      else
        admin_dashboard_path
      end
    when "pharmacist", "store_user"
      # 薬剤師・店舗ユーザー: 店舗ダッシュボード
      if admin.store
        store_dashboard_path(admin.store)
      else
        # 店舗未設定の場合は権限不足エラー
        new_admin_session_path
      end
    else
      # 不明なロール: デフォルトダッシュボード
      admin_dashboard_path
    end
  rescue StandardError => e
    Rails.logger.error "Failed to determine redirect path: #{e.message}"
    admin_dashboard_path
  end

  # 認証イベントを監査ログに記録
  # @param admin [Admin, nil] 認証されたAdmin（失敗時はnil）
  # @param provider [String] 認証プロバイダー名
  # @param status [String] 認証結果（success/failure）
  # @param email [String, nil] 認証試行時のメールアドレス
  # @param error_message [String, nil] エラーメッセージ
  def log_authentication_event(admin, provider, status, email = nil, error_message = nil)
    # TODO: 🟡 Phase 3（中）- ComplianceAuditLog実装後に監査ログ記録機能を追加
    # 優先度: 中（セキュリティ要件）
    # 実装内容:
    #   ComplianceAuditLog.create!(
    #     user: admin,
    #     action: "authentication.#{provider}",
    #     status: status,
    #     details: {
    #       provider: provider,
    #       email: email || admin&.email,
    #       error: error_message,
    #       ip_address: request.remote_ip,
    #       user_agent: request.user_agent
    #     }
    #   )
    # 理由: OAuth認証の監査証跡を残すことでセキュリティ監査要件に対応
    # 期待効果: 不正アクセス検知、コンプライアンス要件充足
    # 工数見積: 0.5日
    # 依存関係: ComplianceAuditLogモデルの実装完了

    # 暫定的にRailsログに記録
    Rails.logger.info "OAuth Authentication: provider=#{provider}, status=#{status}, email=#{email || admin&.email}"
  end

  # GitHubアカウント作成失敗時のエラーメッセージを生成
  # @param admin [Admin] 作成に失敗したAdminインスタンス
  # @return [String] ユーザーフレンドリーなエラーメッセージ
  def github_error_message(admin)
    if admin.errors[:email].any?
      "このメールアドレスは既に登録されています。既存のアカウントでログインしてください。"
    elsif admin.errors[:store].any?
      "GitHubアカウントでの初回ログインが完了しました。店舗の設定が必要です。管理者に店舗の割り当てをご依頼ください。"
    elsif admin.errors[:role].any?
      "権限の設定に問題があります。システム管理者にお問い合わせください。"
    elsif admin.errors[:password].any?
      "パスワードの設定に問題があります。システム管理者にお問い合わせください。"
    else
      # 具体的なエラー内容をログに記録し、ユーザーには一般的なメッセージを表示
      Rails.logger.error "Unknown GitHub OAuth error: #{admin.errors.full_messages.join(', ')}"
      "アカウントの作成中に問題が発生しました。システム管理者にお問い合わせください。"
    end
  end

  # TODO: 🟢 Phase 4（推奨）- 他のOAuthプロバイダー対応
  # 優先度: 低（GitHub認証安定後）
  # 実装内容:
  #   def google_oauth2
  #     handle_oauth_callback("Google")
  #   end
  #
  #   def microsoft_graph
  #     handle_oauth_callback("Microsoft")
  #   end
  #
  #   private
  #
  #   def handle_oauth_callback(provider_name)
  #     # 共通のOAuth処理ロジック
  #   end
  # 理由: コードの重複を避け、保守性を向上
  # 期待効果: 新規プロバイダー追加時の実装コスト削減
  # 工数見積: 1日
  # 依存関係: GitHub認証の安定稼働
end
