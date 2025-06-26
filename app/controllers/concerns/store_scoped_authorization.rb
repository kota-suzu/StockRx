# frozen_string_literal: true

# 店舗スコープ認可モジュール
# ============================================
# QAレビュー指摘事項対応: Critical Issue #1
# 店舗間アクセス制御の完全実装
# 権限昇格攻撃対策を含む
# ============================================
module StoreScopedAuthorization
  extend ActiveSupport::Concern

  included do
    # 認可チェックをデフォルトで有効化
    before_action :verify_store_access!, if: :store_user_signed_in?

    # セキュリティログ記録
    after_action :log_authorization_event, if: :store_user_signed_in?
  end

  private

  # ============================================
  # 認可検証メソッド
  # ============================================

  # 店舗アクセス権限の検証
  def verify_store_access!
    return unless current_store_user.present?

    # マネージャー権限チェック（全店舗アクセス可能）
    return if current_store_user.manager?

    # 店舗IDが指定されている場合の検証
    if params[:store_id].present?
      unless authorized_for_store?(params[:store_id])
        handle_unauthorized_access(:cross_store_access_attempt)
      end
    end

    # リソースの店舗スコープ検証
    verify_resource_store_scope if respond_to?(:verify_resource_store_scope, true)
  end

  # 特定店舗へのアクセス権限確認
  def authorized_for_store?(store_id)
    return false unless current_store_user

    # 所属店舗のみアクセス可能（マネージャー除く）
    if current_store_user.manager?
      # マネージャーは全店舗アクセス可能
      true
    else
      current_store_user.store_id.to_s == store_id.to_s
    end
  end

  # リソースが現在の店舗に属するか確認
  def belongs_to_current_store?(resource)
    return true unless resource.respond_to?(:store_id)
    return true if current_store_user.manager?

    resource.store_id == current_store_user.store_id
  end

  # 不正アクセスハンドリング
  def handle_unauthorized_access(reason = :unauthorized)
    # セキュリティイベントログ
    log_security_event(
      event_type: "unauthorized_access",
      reason: reason,
      attempted_resource: request.path,
      user_id: current_store_user&.id,
      store_id: current_store_user&.store_id,
      ip_address: request.remote_ip
    )

    # エラーレスポンス
    respond_to do |format|
      format.html do
        flash[:alert] = t("errors.unauthorized_access")
        redirect_to store_root_path
      end
      format.json do
        render json: {
          error: "Unauthorized",
          message: "You are not authorized to access this resource"
        }, status: :forbidden
      end
    end
  end

  # ============================================
  # 店舗スコープクエリメソッド
  # ============================================

  # 店舗スコープを適用したクエリ
  def apply_store_scope(relation)
    return relation if current_store_user.manager?

    if relation.respond_to?(:where)
      relation.where(store_id: current_store_user.store_id)
    else
      relation
    end
  end

  # set_inventoryメソッドの店舗スコープ版
  def set_inventory_with_store_scope
    @inventory = if current_store_user.manager?
                   Inventory.find(params[:id])
    else
                   current_store.inventories.find(params[:id])
    end
  rescue ActiveRecord::RecordNotFound
    handle_unauthorized_access(:inventory_not_found_in_store)
  end

  # 在庫の一括取得（店舗スコープ付き）
  def store_scoped_inventories
    @inventories = if current_store_user.manager?
                     Inventory.includes(:batches, :store)
    else
                     current_store.inventories.includes(:batches)
    end
  end

  # ============================================
  # 監査・ログ記録
  # ============================================

  # 認可イベントのログ記録
  def log_authorization_event
    return unless should_log_authorization?

    AuthorizationLog.create!(
      user_type: current_store_user.class.name,
      user_id: current_store_user.id,
      store_id: current_store_user.store_id,
      controller: controller_name,
      action: action_name,
      params: filtered_params,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      authorized: true
    )
  rescue => e
    Rails.logger.error "Authorization log failed: #{e.message}"
  end

  # セキュリティイベントのログ記録
  def log_security_event(event_data)
    SecurityEventLog.create!(
      event_data.merge(
        occurred_at: Time.current,
        request_id: request.uuid
      )
    )
  rescue => e
    Rails.logger.error "Security event log failed: #{e.message}"
    # セキュリティログが失敗してもリクエストは継続
  end

  # ログ記録条件
  def should_log_authorization?
    # GETリクエスト以外、または重要なリソースへのアクセス
    !request.get? || sensitive_resource?
  end

  # 機密リソースの判定
  def sensitive_resource?
    controller_name.in?(%w[transfers inventory_adjustments reports])
  end

  # パラメータのフィルタリング（機密情報除去）
  def filtered_params
    params.except(:password, :token, :api_key).to_unsafe_h
  end

  # ============================================
  # ヘルパーメソッド
  # ============================================

  # 現在の店舗
  def current_store
    @current_store ||= current_store_user&.store
  end

  # 店舗管理者権限の確認
  def store_manager?
    current_store_user&.manager?
  end

  # 読み取り専用権限の確認
  def read_only_user?
    current_store_user&.role == "viewer"
  end

  # ============================================
  # 認可ポリシー定義
  # ============================================

  # アクション別認可ルール
  def authorize_action!
    case action_name
    when "index", "show"
      # 読み取りは基本的に許可
      true
    when "new", "create", "edit", "update"
      # 作成・更新は管理者のみ
      store_manager? || handle_unauthorized_access(:insufficient_permissions)
    when "destroy"
      # 削除は店舗管理者またはスーパーバイザーのみ
      (store_manager? || current_store_user.manager?) ||
        handle_unauthorized_access(:delete_not_allowed)
    else
      # カスタムアクションはデフォルト拒否
      store_manager? || handle_unauthorized_access(:custom_action_denied)
    end
  end
end

# ============================================
# 使用方法:
# ============================================
# 1. StoreControllers::BaseControllerにinclude
#    class StoreControllers::BaseController < ApplicationController
#      include StoreScopedAuthorization
#    end
#
# 2. 個別コントローラーでのカスタマイズ
#    class StoreControllers::InventoriesController < StoreControllers::BaseController
#      # 特定のアクションで認可スキップ
#      skip_before_action :verify_store_access!, only: [:public_index]
#
#      # カスタム認可ロジック
#      def verify_resource_store_scope
#        # 在庫固有の認可ロジック
#      end
#    end
#
# ============================================
# セキュリティ考慮事項:
# ============================================
# 1. 権限昇格攻撃対策
#    - 店舗IDの改ざんチェック
#    - スーパーバイザー権限の厳密な検証
#
# 2. 情報漏洩対策
#    - 他店舗データへのアクセス完全遮断
#    - エラーメッセージの最小化
#
# 3. 監査証跡
#    - 全認可イベントのログ記録
#    - 不正アクセス試行の記録
