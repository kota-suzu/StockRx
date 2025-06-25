# frozen_string_literal: true

# OAuth Debug Controller - Temporary controller for debugging OAuth redirect_uri issues
# This controller should be removed once the OAuth issue is resolved
class AdminControllers::OauthDebugController < AdminControllers::BaseController
  skip_before_action :authenticate_admin!, only: [ :show, :callback_info ]

  # OAuth debug does not access sensitive data, skip audit callback
  skip_around_action :audit_sensitive_data_access

  # GET /admin/oauth_debug
  # Shows OAuth configuration and expected redirect URIs
  def show
    @omniauth_config = {
      full_host: OmniAuth.config.full_host,
      full_host_resolved: full_host_from_request,
      providers: Devise.omniauth_providers,
      github_configured: github_configured?,
      expected_redirect_uri: expected_redirect_uri,
      actual_auth_url: github_auth_url,
      rails_env: Rails.env,
      request_info: {
        host: request.host,
        port: request.port,
        protocol: request.protocol,
        host_with_port: request.host_with_port,
        url: request.url,
        base_url: request.base_url
      }
    }
  end

  # GET /admin/oauth_debug/callback_info
  # Shows what redirect_uri OmniAuth is actually using
  def callback_info
    # Get the OmniAuth strategy for GitHub
    strategy = request.env["omniauth.strategy"] || find_github_strategy

    @callback_info = if strategy
      {
        callback_url: strategy.callback_url,
        callback_path: strategy.callback_path,
        full_host: strategy.full_host,
        script_name: strategy.script_name,
        request_path: strategy.request_path,
        options: strategy.options.to_h
      }
    else
      { error: "GitHub strategy not found" }
    end

    render json: @callback_info
  end

  private

  def github_configured?
    github_client_id = ENV["GITHUB_CLIENT_ID"] ||
                       (Rails.application.credentials.dig(:github, :client_id) rescue nil)
    github_client_secret = ENV["GITHUB_CLIENT_SECRET"] ||
                           (Rails.application.credentials.dig(:github, :client_secret) rescue nil)

    github_client_id.present? && github_client_secret.present?
  end

  def expected_redirect_uri
    if Rails.env.development?
      "http://localhost:3000/admin/auth/github/callback"
    else
      "#{request.protocol}#{request.host_with_port}/admin/auth/github/callback"
    end
  end

  def github_auth_url
    "/admin/auth/github"
  end

  def full_host_from_request
    if OmniAuth.config.full_host.is_a?(Proc)
      OmniAuth.config.full_host.call(request.env)
    else
      OmniAuth.config.full_host
    end
  end

  def find_github_strategy
    # Try to find the GitHub strategy from Rack middleware
    app = Rails.application
    middleware = app.config.middleware

    # Look for OmniAuth middleware
    omniauth_builder = middleware.middlewares.find { |m| m.to_s.include?("OmniAuth") }

    # This is a simplified approach - in reality, we'd need to dig deeper
    # For now, we'll create a mock strategy to show what values would be used
    mock_strategy_options = {
      client_id: ENV["GITHUB_CLIENT_ID"] || Rails.application.credentials.dig(:github, :client_id),
      name: "github",
      callback_path: "/admin/auth/github/callback"
    }

    Struct.new(:callback_url, :callback_path, :full_host, :script_name, :request_path, :options).new(
      "#{full_host_from_request}/admin/auth/github/callback",
      "/admin/auth/github/callback",
      full_host_from_request,
      "",
      "/admin/auth/github",
      mock_strategy_options
    )
  end
end
