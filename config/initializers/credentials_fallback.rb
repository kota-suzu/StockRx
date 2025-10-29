# frozen_string_literal: true

# Credentials fallback configuration
# This provides a fallback mechanism for credentials when master.key is not available
# Useful for test environments, CI/CD pipelines, and containerized deployments

module CredentialsFallback
  extend ActiveSupport::Concern

  # Safely access credentials with fallback to environment variables or defaults
  def safe_credentials
    @safe_credentials ||= SafeCredentials.new(self)
  end

  class SafeCredentials
    def initialize(app)
      @app = app
      @fallback_values = build_fallback_values
    end

    def dig(*keys)
      # Try to get from actual credentials first
      begin
        value = @app.credentials.dig(*keys)
        return value if value
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, KeyError => e
        Rails.logger.debug "[Credentials] Failed to decrypt credentials: #{e.message}"
      end

      # Fallback to environment variable
      env_key = keys.map(&:to_s).join("_").upcase
      env_value = ENV["RAILS_#{env_key}"]
      return env_value if env_value

      # Fallback to predefined test/development values
      @fallback_values.dig(*keys)
    end

    private

    def build_fallback_values
      {
        devise: {
          secret_key: generate_fallback_key("devise-secret", 128)
        },
        github: {
          client_id: ENV["GITHUB_CLIENT_ID"] || "dummy-github-client-id",
          client_secret: ENV["GITHUB_CLIENT_SECRET"] || "dummy-github-client-secret"
        },
        security: {
          encryption_keys: {
            database_encryption: generate_base64_key(32),
            job_arguments: generate_base64_key(32),
            log_encryption: generate_base64_key(32),
            session_encryption: generate_base64_key(32)
          }
        },
        secret_key_base: generate_fallback_key("secret-key-base", 128)
      }.deep_transform_keys(&:to_sym).with_indifferent_access
    end

    def generate_fallback_key(prefix, length)
      # Generate a deterministic key based on the prefix and Rails environment
      # This ensures the same key is used across test runs
      key_seed = "#{prefix}-#{Rails.env}-fallback"
      Digest::SHA512.hexdigest(key_seed)[0, length]
    end

    def generate_base64_key(bytes)
      # Generate a deterministic base64 encoded key
      key_data = generate_fallback_key("encryption", bytes * 2)
      Base64.strict_encode64([ key_data ].pack("H*")[0, bytes])
    end
  end
end

# Apply the module to Rails::Application
Rails::Application.include(CredentialsFallback)

# Log the fallback status
Rails.application.config.after_initialize do
  if Rails.env.test? || Rails.env.development?
    begin
      # Try to access credentials to check if master.key is available
      Rails.application.credentials.secret_key_base
      Rails.logger.info "[Credentials] Using encrypted credentials (master.key found)"
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, KeyError => e
      Rails.logger.info "[Credentials] Using fallback credentials (master.key not found)"
      Rails.logger.debug "[Credentials] Fallback reason: #{e.message}"
    end
  end
end
