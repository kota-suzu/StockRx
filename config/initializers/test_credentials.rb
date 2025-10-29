# frozen_string_literal: true

# Test environment credentials configuration
# This file provides test-specific credential handling to avoid decryption errors
# in the test environment where master.key might not be available

if Rails.env.test?
  # Monkey patch Rails credentials to return test values without decryption
  module Rails
    class Application
      class Credentials
        # Override the credentials method to provide test values
        def credentials
          @test_credentials ||= ActiveSupport::OrderedOptions.new.tap do |config|
            # Devise test secret key
            config.devise = ActiveSupport::OrderedOptions.new
            config.devise.secret_key = "test-devise-secret-key-for-testing-only-" + ("a" * 88)

            # GitHub OAuth test credentials (non-functional test values)
            config.github = ActiveSupport::OrderedOptions.new
            config.github.client_id = "test-github-client-id"
            config.github.client_secret = "test-github-client-secret"

            # Security encryption keys for testing
            config.security = ActiveSupport::OrderedOptions.new
            config.security.encryption_keys = ActiveSupport::OrderedOptions.new
            config.security.encryption_keys.database_encryption = Base64.strict_encode64(SecureRandom.bytes(32))
            config.security.encryption_keys.job_arguments = Base64.strict_encode64(SecureRandom.bytes(32))
            config.security.encryption_keys.log_encryption = Base64.strict_encode64(SecureRandom.bytes(32))
            config.security.encryption_keys.session_encryption = Base64.strict_encode64(SecureRandom.bytes(32))

            # Any other test credentials can be added here
            config.secret_key_base = "test-secret-key-base-" + SecureRandom.hex(64)
          end
        end

        # Override dig method to work with test credentials
        def dig(*keys)
          credentials.dig(*keys)
        end
      end
    end
  end

  # Alternative approach: Override the credentials accessor method
  Rails.application.singleton_class.prepend(Module.new do
    def credentials
      @test_credentials_instance ||= Rails::Application::Credentials.new
      @test_credentials_instance.credentials
    end
  end)
end
