# frozen_string_literal: true

# API認証機能
# CLAUDE.md準拠: API用の認証・認可システム
module ApiAuthentication
  extend ActiveSupport::Concern
  
  included do
    attr_reader :current_api_key, :api_authenticated_admin, :api_authenticated_store_user
  end
  
  # APIキー認証を必須にする
  def authenticate_api_key!
    unless authenticate_api_key
      render_authentication_error
    end
  end
  
  # APIキー認証（オプショナル）
  def authenticate_api_key
    return false unless api_key_header.present?
    
    @current_api_key = ApiKey.active.find_by(key: api_key_header)
    
    if @current_api_key
      # 使用記録を更新
      @current_api_key.record_usage!(
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      
      # 認証されたユーザーを設定
      @api_authenticated_admin = @current_api_key.admin
      @api_authenticated_store_user = @current_api_key.store_user
      
      # Currentオブジェクトに設定
      Current.admin = @api_authenticated_admin if @api_authenticated_admin
      Current.store_user = @api_authenticated_store_user if @api_authenticated_store_user
      Current.api_key = @current_api_key
      
      true
    else
      false
    end
  end
  
  # 管理者認証が必要
  def authenticate_api_admin!
    authenticate_api_key!
    
    unless api_authenticated_admin?
      render_authorization_error("管理者権限が必要です")
    end
  end
  
  # 店舗ユーザー認証が必要
  def authenticate_api_store_user!
    authenticate_api_key!
    
    unless api_authenticated_store_user?
      render_authorization_error("店舗ユーザー権限が必要です")
    end
  end
  
  # 認証状態チェック
  def api_authenticated?
    current_api_key.present?
  end
  
  def api_authenticated_admin?
    api_authenticated_admin.present?
  end
  
  def api_authenticated_store_user?
    api_authenticated_store_user.present?
  end
  
  # 権限チェック
  def api_admin_can?(action, resource = nil)
    return false unless api_authenticated_admin?
    
    case action
    when :read
      true # 管理者は基本的に読み取り可能
    when :write, :create, :update
      api_authenticated_admin.can_manage_inventory?
    when :delete
      api_authenticated_admin.headquarters_admin? # 削除は本部管理者のみ
    else
      false
    end
  end
  
  def api_store_user_can?(action, resource = nil)
    return false unless api_authenticated_store_user?
    
    case action
    when :read
      true # 店舗ユーザーは基本的に読み取り可能
    when :write, :create, :update
      api_authenticated_store_user.can_manage_inventory?
    when :delete
      false # 店舗ユーザーは削除不可
    else
      false
    end
  end
  
  # Devise互換のヘルパーメソッド
  def current_admin
    api_authenticated_admin || super
  end
  
  def current_store_user
    api_authenticated_store_user || super
  end
  
  private
  
  # APIキーヘッダーを取得
  def api_key_header
    # Authorization: Bearer <api_key> 形式
    auth_header = request.headers["Authorization"]
    if auth_header&.start_with?("Bearer ")
      auth_header.sub("Bearer ", "")
    else
      # X-API-Key ヘッダー形式
      request.headers["X-API-Key"]
    end
  end
  
  # 認証エラーレスポンス
  def render_authentication_error
    response = ApiResponse.error(
      "認証が必要です",
      ["有効なAPIキーを提供してください"],
      401,
      { type: "authentication_required" }
    )
    
    render json: response.to_h, 
           status: response.status_code,
           headers: response.headers
  end
  
  # 認可エラーレスポンス
  def render_authorization_error(message = "この操作を行う権限がありません")
    response = ApiResponse.forbidden(message)
    
    render json: response.to_h,
           status: response.status_code, 
           headers: response.headers
  end
end