# frozen_string_literal: true

module AdminControllers
  # GitHubソーシャルログイン処理用コントローラ
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    layout "admin"

    # CSRF保護: omniauth-rails_csrf_protection gemにより自動対応
    # skip_before_action :verify_authenticity_token は不要

    # GitHubからのOAuth callback処理
    def github
      @admin = Admin.from_omniauth(request.env["omniauth.auth"])

      if @admin.persisted?
        # GitHub認証成功: ログイン処理とリダイレクト
        sign_in_and_redirect @admin, event: :authentication
        set_flash_message(:notice, :success, kind: "GitHub") if is_navigational_format?

        # TODO: 🟢 Phase 4（推奨）- ログイン通知機能
        # 優先度: 低（セキュリティ強化時）
        # 実装内容: 新規GitHubログイン時のメール・Slack通知
        # 理由: セキュリティ意識向上、不正アクセス早期発見
        # 期待効果: セキュリティインシデントの予防・早期対応
        # 工数見積: 1-2日
        # 依存関係: メール送信機能、Slack API統合

      else
        # GitHub認証失敗: エラーメッセージと再ログイン画面
        session["devise.github_data"] = request.env["omniauth.auth"].except(:extra)
        redirect_to new_admin_session_path, alert: @admin.errors.full_messages.join("\n")

        # TODO: 🟡 Phase 3（中）- OAuth認証失敗のログ記録・監視
        # 優先度: 中（セキュリティ監視強化）
        # 実装内容: 認証失敗ログの構造化記録、異常パターン検知
        # 理由: セキュリティインシデントの早期発見、攻撃パターン分析
        # 期待効果: セキュリティ脅威の可視化、防御力向上
        # 工数見積: 1日
        # 依存関係: ログ監視システム構築
      end
    end

    # OAuth認証エラー時の処理（GitHub側でキャンセル等）
    def failure
      redirect_to new_admin_session_path, alert: "GitHub認証に失敗しました。再度お試しください。"

      # セキュリティログ記録（機密情報を含む詳細は除外）
      Rails.logger.warn "OAuth authentication failed - Error type: #{failure_error_type}"

      # TODO: 🟡 Phase 3（中）- OAuth失敗理由の詳細分析・ユーザー案内
      # 優先度: 中（ユーザー体験向上）
      # 実装内容: 失敗理由別のユーザー案内メッセージ、復旧手順提示
      # 理由: ユーザーの困惑軽減、サポート工数削減
      # 期待効果: 認証成功率向上、ユーザー満足度向上
      # 工数見積: 1日
      # 依存関係: なし
    end

    protected

    # ログイン後のリダイレクト先（SessionsControllerと同じ）
    def after_omniauth_failure_path_for(scope)
      new_admin_session_path
    end

    # OAuth認証後のリダイレクト先
    def after_sign_in_path_for(resource)
      admin_root_path
    end

    private

    # OAuth失敗理由を取得
    def failure_message
      request.env["omniauth.error"] || "Unknown error"
    end

    # セキュリティログ用の安全なエラータイプ識別子を取得
    def failure_error_type
      error = request.env["omniauth.error"]
      case error&.class&.name
      when "OmniAuth::Strategies::OAuth2::CallbackError"
        "callback_error"
      when "OAuth2::Error"
        "oauth2_error"
      when "Timeout::Error"
        "timeout_error"
      else
        "unknown_error"
      end
    end
  end
end
