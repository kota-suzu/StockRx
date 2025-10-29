# frozen_string_literal: true

# Rails 8 + OmniAuth 2.x 互換性設定
Rails.application.config.to_prepare do
  # OmniAuth設定（Rails 8対応）
  OmniAuth.config.allowed_request_methods = [ :post, :get ]
  OmniAuth.config.silence_get_warning = true
  OmniAuth.config.logger = Rails.logger

  # 開発環境での明示的なホスト設定
  if Rails.env.development?
    # 開発環境では明示的にhttp://localhost:3000を使用
    OmniAuth.config.full_host = "http://localhost:3000"
  else
    # 本番環境では動的に取得
    OmniAuth.config.full_host = lambda do |env|
      scheme = env["rack.url_scheme"]
      host = env["HTTP_HOST"]
      "#{scheme}://#{host}"
    end
  end
end

# OmniAuth Builderを使用してGitHub戦略を追加
# Rails.application.config.middleware.use OmniAuth::Builder do
#   # この設定は不要（Deviseが自動的に処理）
#   # ただし、Rails 8での互換性のため残す
# end
# ↑ コメントアウト: Deviseが自動的にOmniAuthミドルウェアを管理するため、重複を避ける
