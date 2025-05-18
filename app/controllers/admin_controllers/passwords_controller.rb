# frozen_string_literal: true

module AdminControllers
  # 管理者パスワードリセット処理用コントローラ
  class PasswordsController < Devise::PasswordsController
    layout "admin"

    # Chrome対応: POSTアクションでsign_inが機能しない問題への対応
    # https://github.com/heartcombo/devise/issues/5155
    skip_before_action :verify_authenticity_token, only: [ :create, :update ]

    # セキュリティ強化TODO: 代替策の検討
    # 現在のCSRF検証スキップは臨時対応。以下の方法で恒久対策を検討すべき:
    # 1. トークンベースのクロスサイトリクエスト保護に切り替え
    # 2. GETリクエストベースのエラーリダイレクトへの変更
    # 3. XHRリクエスト化とJSON応答の採用

    # Turbo対応: Rails 7でDeviseとTurboの互換性を確保
    # https://github.com/heartcombo/devise/issues/5439

    # TODO: 将来的な機能拡張
    # - パスワード有効期限の設定と管理（devise-securityと連携）
    # - パスワード変更履歴の記録
    # - パスワードリセットの通知強化（管理者や上位権限者への通知）
    # - パスワードポリシーの段階的な強化
    # - パスワードリセット試行の監視と制限
    # - パスワード使い回しチェック（HaveIBeenPwned APIとの連携）
    # - セキュリティイベントのログ記録と通知

    protected

    # パスワードリセット後のリダイレクト先
    def after_resetting_password_path_for(resource)
      admin_root_path
    end

    # パスワードリセットメール送信後のリダイレクト先
    def after_sending_reset_password_instructions_path_for(resource_name)
      new_admin_session_path
    end
  end
end
