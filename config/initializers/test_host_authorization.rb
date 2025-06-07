# frozen_string_literal: true

# テスト環境でHost Authorizationを無効化
if Rails.env.test?
  Rails.application.configure do
    config.hosts = [ "test.host", "localhost", "www.example.com", "127.0.0.1" ]
    config.host_authorization = { exclude: ->(request) { true } }
  end
end
