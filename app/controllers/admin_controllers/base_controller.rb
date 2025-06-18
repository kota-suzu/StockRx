# frozen_string_literal: true

module AdminControllers
  # 管理者画面用のベースコントローラ
  # 全ての管理者向けコントローラはこのクラスを継承する
  class BaseController < ApplicationController
    include ErrorHandlers
    include AdminAuthorization  # 🔒 権限チェック機能の統一
    include SecurityCompliance  # 🛡️ セキュリティコンプライアンス機能

    # AdminControllers用ヘルパーのインクルード
    helper AdminControllers::ApplicationHelper

    before_action :authenticate_admin!
    layout "admin"

    # CSRFトークン検証を有効化
    protect_from_forgery with: :exception

    # 全ての管理者画面で共通のセットアップ処理
    before_action :set_admin_info

    # TODO: コントローラの命名規則
    # AdminControllersモジュール名はAdminモデルとの名前衝突を避けるために使用
    # 将来的な新しいモデル/コントローラの追加時にも同様の名前衝突に注意
    # コントローラモジュール名には「Controllers」サフィックスを使用して区別する
    # 例: UserモデルとUserControllersモジュールなど

    # TODO: エラーハンドリングとルーティングの注意点
    # 1. 認証関連ルート（Devise）はカスタムエラーハンドリングルートより先に定義する
    # 2. ワイルドカードルート（*path）は常に最後に定義する
    # 3. 新規コントローラ追加時はルーティング順序に注意する
    # 詳細は doc/error_handling_guide.md の「ルーティング順序の問題」を参照

    # ✅ セキュリティ機能強化（Phase 1完了）
    # - PCI DSS準拠の機密データ保護機能統合
    # - GDPR準拠の個人情報保護機能統合
    # - タイミング攻撃対策の自動適用
    # - 包括的な監査ログ記録機能

    # 機密データアクセス時の監査ログ記録を設定
    audit_sensitive_access :show, :edit, :update, :destroy

    # TODO: 将来的な機能拡張
    # - 管理者権限レベルによるアクセス制御（role-based authorization）
    # - 共通エラーハンドリング機能の実装
    # - 多言語対応の基盤整備

    private

    # 現在ログイン中の管理者情報をビューで参照できるよう設定
    def set_admin_info
      return unless admin_signed_in?

      @current_admin = current_admin
      # Currentクラスにadmin情報を設定
      Current.admin = current_admin
    end
  end
end
