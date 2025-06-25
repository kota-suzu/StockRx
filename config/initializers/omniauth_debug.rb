# frozen_string_literal: true

# TEMPORARY: OAuth Debug Configuration
# This file logs OAuth redirect_uri for debugging purposes
# Remove this file after fixing the GitHub OAuth redirect_uri issue

if false # Rails.env.development? # 一時的に無効化
  # Enable debug logging for OmniAuth
  OmniAuth.config.logger = Logger.new(STDOUT)
  OmniAuth.config.logger.level = Logger::DEBUG

  # Add middleware to log OAuth requests
  Rails.application.config.middleware.use OmniAuth::Builder do
    # This will be called when building strategies
    on_failure do |env|
      Rails.logger.error "=== OmniAuth Failure ==="
      Rails.logger.error "Path: #{env['PATH_INFO']}"
      Rails.logger.error "Request URL: #{env['REQUEST_URI']}"
      Rails.logger.error "Error: #{env['omniauth.error']}"
      Rails.logger.error "Error Type: #{env['omniauth.error.type']}"
      Rails.logger.error "========================"
      OmniAuth.config.on_failure.call(env)
    end
  end

  # Monkey patch to log the redirect_uri
  module OmniAuth
    module Strategies
      class OAuth2
        alias_method :original_callback_url, :callback_url

        def callback_url
          url = original_callback_url
          Rails.logger.info "=== OmniAuth OAuth2 Debug ==="
          Rails.logger.info "Strategy: #{self.class.name}"
          Rails.logger.info "Callback URL being sent to provider: #{url}"
          Rails.logger.info "Full Host: #{full_host}"
          Rails.logger.info "Callback Path: #{callback_path}"
          Rails.logger.info "Script Name: #{script_name}"
          Rails.logger.info "============================="
          url
        end
      end
    end
  end
end
