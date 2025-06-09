# frozen_string_literal: true

# ============================================
# HTTP Request Parameter Filtering
# ============================================
# Be sure to restart your server when you modify this file.
#
# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
#
# Note: ActiveJob引数のフィルタリングは config/initializers/secure_job_logging.rb で設定

Rails.application.config.filter_parameters += [
  # ============================================
  # 基本的な機密情報パターン（部分マッチ）
  # ============================================
  :passw,          # password, passwd, etc.
  :secret,         # secret_key, client_secret, etc.
  :token,          # access_token, api_token, etc.
  :_key,           # api_key, private_key, etc.
  :crypt,          # encrypted, bcrypt, etc.
  :salt,           # password_salt, etc.
  :certificate,    # ssl_certificate, etc.
  :otp,            # one_time_password, etc.
  :ssn,            # social_security_number, etc.

  # ============================================
  # 個人情報関連（GDPR対応）
  # ============================================
  :email,          # email_address, user_email, etc.
  :phone,          # phone_number, mobile_phone, etc.
  :address,        # home_address, billing_address, etc.
  :birth,          # birth_date, date_of_birth, etc.
  :credit_card,    # credit_card_number, etc.
  :bank_account,   # bank_account_number, etc.

  # ============================================
  # 認証・認可関連
  # ============================================
  :auth,           # authorization, auth_token, etc.
  :session,        # session_id, session_key, etc.
  :csrf,           # csrf_token, etc.
  :bearer,         # bearer_token, etc.
  :oauth,          # oauth_token, oauth_secret, etc.

  # ============================================
  # 外部サービス連携
  # ============================================
  :stripe,         # stripe_secret_key, etc.
  :paypal,         # paypal_client_secret, etc.
  :aws,            # aws_access_key_id, etc.
  :github,         # github_token, etc.
  :slack,          # slack_bot_token, etc.

  # ============================================
  # システム・インフラ関連
  # ============================================
  :database,       # database_password, database_url, etc.
  :redis,          # redis_password, etc.
  :master_key,     # rails master.key, etc.
  :encryption     # encryption_key, etc.
]

# ============================================
# 開発環境での設定確認
# ============================================
if Rails.env.development?
  Rails.application.config.after_initialize do
    filtered_count = Rails.application.config.filter_parameters.size
    Rails.logger.info "[ParameterFiltering] #{filtered_count} parameter patterns configured for HTTP request filtering"
  end
end

# ============================================
# 将来の拡張予定（TODO）
# ============================================
#
# 1. 動的パターン追加機能
#    - 運用中の新しいパターン追加対応
#    - 組織固有のパターン学習機能
#
# 2. フィルタリング精度向上
#    - 誤検出の削減
#    - コンテキストを考慮した判定
#
# 3. 国際化対応
#    - 多言語での機密情報キーワード検出
#    - 地域別コンプライアンス要件対応
