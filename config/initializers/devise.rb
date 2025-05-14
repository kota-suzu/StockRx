# frozen_string_literal: true

# Assuming you have not yet modified this file, copy it to your config/initializers folder.
# Devise - Flexible authentication solution for Rails
# https://github.com/heartcombo/devise

Devise.setup do |config|
  # ==> Secret key
  # 本番環境では必ずRails.application.credentialsから取得するようにします
  config.secret_key = Rails.application.credentials.dig(:devise, :secret_key)

  # ==> Controller configuration
  config.parent_controller = "ApplicationController"

  # ==> Mailer Configuration
  config.mailer_sender = "no-reply@stockrx.example.com"
  config.mailer = "Devise::Mailer"
  config.parent_mailer = "ActionMailer::Base"

  # ==> ORM configuration
  require "devise/orm/active_record"

  # ==> Configuration for any authentication mechanism
  config.authentication_keys = [ :email ]
  config.request_keys = []
  config.case_insensitive_keys = [ :email ]
  config.strip_whitespace_keys = [ :email ]
  config.params_authenticatable = true
  config.http_authenticatable = false
  config.http_authenticatable_on_xhr = true
  config.http_authentication_realm = "Application"

  # ==> Configuration for :database_authenticatable
  config.stretches = Rails.env.test? ? 1 : 12

  # ==> Configuration for :confirmable
  config.allow_unconfirmed_access_for = 3.days
  config.confirm_within = 3.days
  config.reconfirmable = true
  config.confirmation_keys = [ :email ]

  # ==> Configuration for :rememberable
  config.remember_for = 2.weeks
  config.extend_remember_period = false
  config.rememberable_options = {}

  # ==> Configuration for :validatable
  config.password_length = 12..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/

  # ==> Configuration for :timeoutable
  config.timeout_in = 30.minutes

  # ==> Configuration for :lockable
  config.lock_strategy = :failed_attempts
  config.unlock_keys = [ :email ]
  config.unlock_strategy = :time
  config.maximum_attempts = 5
  config.unlock_in = 15.minutes

  # ==> Configuration for :recoverable
  config.reset_password_keys = [ :email ]
  config.reset_password_within = 6.hours
  config.sign_in_after_reset_password = true

  # ==> Configuration for :encryptable
  # config.encryptor = :sha512

  # ==> Scopes configuration
  # 管理者とユーザーで別々のビューを使用
  config.scoped_views = true
  config.default_scope = :admin
  config.sign_out_all_scopes = false

  # ==> Navigation configuration
  config.skip_session_storage = [ :http_auth ]
  config.navigational_formats = [ "*/*", :html, :turbo_stream ]

  # ==> Turbolinks configuration
  # config.clean_up_csrf_token_on_authentication = true

  # ==> Hotwire/Turbo compatibility:
  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  # ==> Warden configuration
  # config.warden do |manager|
  #   manager.intercept_401 = false
  #   manager.default_strategies(scope: :admin).unshift :some_external_strategy
  # end

  # ==> Mountable engine configurations
  # config.router_name = :my_engine
  # config.omniauth_path_prefix = '/my_engine/users/auth'

  # ==> Security Extension
  # パスワード強度検証を有効化
  config.password_complexity = { digit: 1, lower: 1, upper: 1, symbol: 1 }
end
