# frozen_string_literal: true

module StoreControllers
  # 店舗コントローラーの基底クラス
  # ============================================
  # Phase 2: 店舗別ログインシステム
  # 全ての店舗コントローラーが継承する基底クラス
  # ============================================
  class BaseController < ApplicationController
    include StoreAuthenticatable

    # 基本的な認証とセキュリティチェック
    before_action :authenticate_store_user!
    before_action :ensure_store_active
    before_action :set_current_context
    
    # レイアウト設定
    layout 'store'

    # ============================================
    # 共通機能
    # ============================================

    private

    # 現在のコンテキストを設定（監査ログ用）
    def set_current_context
      Current.store_user = current_store_user
      Current.store = current_store
    end

    # 共通のリダイレクト処理
    def redirect_with_store_scope(path, options = {})
      redirect_to path, options
    end

    # ============================================
    # エラーハンドリング
    # ============================================

    # 権限エラー
    rescue_from CanCan::AccessDenied do |exception|
      respond_to do |format|
        format.html do
          redirect_to store_root_path, 
                      alert: I18n.t("errors.messages.access_denied")
        end
        format.json do
          render json: { error: exception.message }, status: :forbidden
        end
      end
    end

    # レコードが見つからない
    rescue_from ActiveRecord::RecordNotFound do |exception|
      respond_to do |format|
        format.html do
          redirect_to store_root_path, 
                      alert: I18n.t("errors.messages.record_not_found")
        end
        format.json do
          render json: { error: exception.message }, status: :not_found
        end
      end
    end

    # ============================================
    # 共通のビューヘルパー
    # ============================================

    # 店舗名を含むページタイトル生成
    def page_title(title)
      "#{title} - #{current_store.name}"
    end

    # 店舗スコープでのパスヘルパー
    def store_scoped_path(resource, action = :show)
      if resource.respond_to?(:store_id)
        send("store_#{resource.class.name.underscore}_path", resource)
      else
        super
      end
    end

    # ============================================
    # パフォーマンス最適化
    # ============================================

    # N+1問題を防ぐための共通includes
    def includes_for_index
      # 各コントローラーでオーバーライド可能
      []
    end

    # ページネーション設定
    def per_page
      params[:per_page] || 25
    end

    # ============================================
    # 監査ログ
    # ============================================

    # アクション実行後の監査ログ記録
    def log_action(action, resource, details = {})
      # TODO: Phase 3 - 監査ログ実装
      # AuditLog.create!(
      #   user: current_store_user,
      #   store: current_store,
      #   action: action,
      #   resource_type: resource.class.name,
      #   resource_id: resource.id,
      #   details: details,
      #   ip_address: request.remote_ip,
      #   user_agent: request.user_agent
      # )
    end
  end
end

# ============================================
# TODO: Phase 3以降の拡張予定
# ============================================
# 1. 🔴 アクティビティトラッキング
#    - ユーザー行動の詳細記録
#    - 異常検知アルゴリズム
#
# 2. 🟡 レート制限
#    - APIコール制限
#    - 大量データ操作の制限
#
# 3. 🟢 キャッシュ戦略
#    - 店舗単位のキャッシュ管理
#    - 権限ベースのキャッシュ制御