# frozen_string_literal: true

module AdminControllers
  # 管理者画面用のベースコントローラ
  # 全ての管理者向けコントローラはこのクラスを継承する
  class BaseController < ApplicationController
    include ErrorHandlers
    include AdminAuthorization  # 🔒 権限チェック機能の統一
    include SecurityCompliance  # 🛡️ セキュリティコンプライアンス機能
    include DatabaseOptimization  # 🚀 データベース最適化機能

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
    # メタ認知: データ変更・詳細表示アクションのみ監査対象
    # 横展開: 一覧表示（index）は統計データのため監査対象外
    audit_sensitive_access :show, :edit, :update, :destroy

    # TODO: 🟡 Phase 3（中）- セキュリティポリシーの細分化
    # 優先度: 中（現在の一律適用は動作中）
    # 実装内容:
    #   - アクション別セキュリティレベル定義
    #   - 機密度に応じた監査粒度の調整
    #   - 表示専用コントローラーの自動判定
    # 理由: セキュリティオーバーヘッドの最適化
    # 期待効果: パフォーマンス向上、監査ログの品質向上
    # 工数見積: 1週間
    # 依存関係: セキュリティポリシー定義書の策定

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
