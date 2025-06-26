# frozen_string_literal: true

# CLAUDE.md準拠: API認証テストヘルパー
# メタ認知: テストの可読性向上と認証ロジックの一元化
# 横展開: 全APIテストで統一的な認証方法を提供

module ApiHelpers
  # JWTトークン生成（モック実装）
  def generate_api_token(user, expires_at: 1.hour.from_now)
    JWT.encode(
      {
        user_id: user.id,
        user_type: user.class.name,
        exp: expires_at.to_i
      },
      Rails.application.secret_key_base
    )
  end

  # APIリクエスト用のヘッダー生成
  def api_headers(user = nil)
    headers = {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }

    if user
      headers['Authorization'] = "Bearer #{generate_api_token(user)}"
    end

    headers
  end

  # JSONレスポンスの解析
  def json_response
    JSON.parse(response.body)
  end

  # レート制限のモック
  def mock_rate_limit_exceeded
    allow_any_instance_of(ApplicationController).to receive(:rate_limited?).and_return(true)
  end

  # APIクォータのモック
  def mock_api_quota_exceeded
    # ApiQuotaServiceクラスが存在しない場合のための仮実装
    error_class = Class.new(StandardError) do
      def initialize(message = "API quota exceeded")
        super(message)
      end
    end

    stub_const("ApiQuotaExceededError", error_class)

    service_class = Class.new do
      def check_quota!
        raise ApiQuotaExceededError.new("Monthly API quota exceeded")
      end
    end

    stub_const("ApiQuotaService", service_class)
  end
end

# RSpecに含める
RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
