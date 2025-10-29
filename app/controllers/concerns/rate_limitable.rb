# frozen_string_literal: true

# レート制限機能を提供するConcern
# ============================================
# Phase 5-1: セキュリティ強化
# コントローラーにレート制限機能を追加
# ============================================
module RateLimitable
  extend ActiveSupport::Concern

  included do
    # レート制限が必要なアクションの前に実行
    before_action :check_rate_limit!, if: :rate_limit_required?
  end

  private

  # レート制限チェック
  def check_rate_limit!
    limiter = build_rate_limiter
    return if limiter.allowed?

    # レート制限に達した場合
    respond_to do |format|
      format.html do
        redirect_back(
          fallback_location: root_path,
          alert: rate_limit_message(limiter)
        )
      end
      format.json do
        render json: {
          error: "Rate limit exceeded",
          message: rate_limit_message(limiter),
          retry_after: limiter.time_until_unblock
        }, status: :too_many_requests
      end
    end
  end

  # レート制限が必要なアクションか
  def rate_limit_required?
    rate_limited_actions.include?(action_name.to_sym)
  end

  # レート制限対象のアクション（各コントローラーでオーバーライド）
  def rate_limited_actions
    []
  end

  # レート制限のキータイプ（各コントローラーでオーバーライド）
  def rate_limit_key_type
    :default
  end

  # レート制限の識別子
  def rate_limit_identifier
    # 優先順位: ユーザーID > セッションID > IPアドレス
    if defined?(current_admin) && current_admin
      "admin:#{current_admin.id}"
    elsif defined?(current_store_user) && current_store_user
      "store_user:#{current_store_user.id}"
    elsif session.id
      "session:#{session.id}"
    else
      "ip:#{request.remote_ip}"
    end
  end

  # レート制限インスタンスの構築
  def build_rate_limiter
    RateLimiter.new(rate_limit_key_type, rate_limit_identifier)
  end

  # レート制限メッセージ
  def rate_limit_message(limiter)
    minutes = (limiter.time_until_unblock / 60).ceil

    case rate_limit_key_type
    when :login
      "ログイン試行回数が上限に達しました。#{minutes}分後に再度お試しください。"
    when :password_reset
      "パスワードリセット要求が多すぎます。#{minutes}分後に再度お試しください。"
    when :email_auth
      "パスコード送信回数が上限に達しました。#{minutes}分後に再度お試しください。"
    when :api
      "API呼び出し回数が上限に達しました。#{minutes}分後に再度お試しください。"
    when :transfer_request
      "移動申請の回数が上限に達しました。#{minutes}分後に再度お試しください。"
    when :file_upload
      "ファイルアップロード回数が上限に達しました。#{minutes}分後に再度お試しください。"
    else
      "リクエスト回数が上限に達しました。#{minutes}分後に再度お試しください。"
    end
  end

  # アクション実行後のトラッキング
  def track_rate_limit_action!
    limiter = build_rate_limiter
    limiter.track!
  end

  # ============================================
  # ヘルパーメソッド
  # ============================================

  # 残り試行回数を取得
  def rate_limit_remaining
    limiter = build_rate_limiter
    limiter.remaining_attempts
  end

  # レート制限情報をレスポンスヘッダーに追加
  def set_rate_limit_headers
    limiter = build_rate_limiter

    response.headers["X-RateLimit-Limit"] = limiter.instance_variable_get(:@config)[:limit].to_s
    response.headers["X-RateLimit-Remaining"] = limiter.remaining_attempts.to_s

    if limiter.blocked?
      response.headers["X-RateLimit-Reset"] = (Time.current + limiter.time_until_unblock).to_i.to_s
    end
  end
end

# ============================================
# 使用例:
# ============================================
# class StoreControllers::SessionsController < Devise::SessionsController
#   include RateLimitable
#
#   private
#
#   def rate_limited_actions
#     [:create]  # ログインアクションのみ制限
#   end
#
#   def rate_limit_key_type
#     :login
#   end
#
#   def create
#     super do |resource|
#       if resource.nil? || !resource.persisted?
#         # ログイン失敗時にカウント
#         track_rate_limit_action!
#       end
#     end
#   end
# end
