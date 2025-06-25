# Test Environment Setup Guide

## Overview

This guide explains how to configure the test environment to avoid Rails credentials decryption errors when running tests.

## Problem

When running tests, you might encounter:
```
ActiveSupport::MessageEncryptor::InvalidMessage
```

This happens because the test environment tries to decrypt `credentials.yml.enc` but the master key might not be available in CI/CD environments or fresh checkouts.

## Solutions

### Solution 1: Automatic Fallback (Recommended)

The application now includes automatic credential fallback mechanisms:

1. **Test Credentials Initializer** (`config/initializers/test_credentials.rb`)
   - Automatically provides test values in the test environment
   - No configuration needed

2. **Credentials Fallback** (`config/initializers/credentials_fallback.rb`)
   - Provides safe access to credentials with fallback values
   - Works in all environments

### Solution 2: Environment Variables

Copy the example file and customize:
```bash
cp .env.test.example .env.test
```

The test suite will use these environment variables when credentials are not available.

### Solution 3: Test Master Key

For CI/CD environments, you can set a test master key:
```bash
# In your CI configuration
export RAILS_MASTER_KEY=test-master-key-not-for-production-use
```

## How It Works

The credential fallback system follows this priority:

1. **Encrypted Credentials** (if master.key is available)
2. **Environment Variables** (e.g., `RAILS_DEVISE_SECRET_KEY`)
3. **Fallback Values** (deterministic test values)

### Safe Credentials Access

Instead of:
```ruby
Rails.application.credentials.dig(:github, :client_id)
```

The system now uses:
```ruby
Rails.application.safe_credentials.dig(:github, :client_id)
```

This prevents decryption errors and provides appropriate fallback values.

## CI/CD Configuration

### GitHub Actions

Add to your workflow:
```yaml
env:
  RAILS_ENV: test
  RAILS_MASTER_KEY: ${{ secrets.RAILS_TEST_MASTER_KEY }}
  # Or use individual secrets
  GITHUB_CLIENT_ID: test-client-id
  GITHUB_CLIENT_SECRET: test-client-secret
```

### Docker

In your `docker-compose.test.yml`:
```yaml
services:
  test:
    env_file:
      - .env.test
```

## Security Notes

- **Never use test credentials in production**
- Test values are deterministic to ensure consistent test runs
- Real credentials should only be in `credentials.yml.enc` for production
- Use strong, random values for production credentials

## Troubleshooting

### Still getting decryption errors?

1. Check that all initializers use `safe_credentials`:
   ```bash
   grep -r "Rails.application.credentials" config/initializers/
   ```

2. Ensure the test environment is properly detected:
   ```bash
   RAILS_ENV=test rails console
   > Rails.env.test?  # Should return true
   ```

3. Verify fallback is working:
   ```bash
   RAILS_ENV=test rails console
   > Rails.application.safe_credentials.dig(:devise, :secret_key)
   # Should return a value without errors
   ```

## Best Practices

1. **Use environment-specific credentials**
   - Production: Encrypted credentials with master key
   - Development: `.env` files or fallback values
   - Test: Fallback values or `.env.test`

2. **Don't commit sensitive data**
   - `.env*` files are gitignored (except `.env*.example`)
   - Never commit real API keys or secrets

3. **Document required credentials**
   - Keep `.env.test.example` updated
   - Document any new credential requirements

## Adding New Credentials

When adding new credentials:

1. Update `config/initializers/credentials_fallback.rb`:
   ```ruby
   def build_fallback_values
     {
       # ... existing values ...
       your_service: {
         api_key: ENV['YOUR_SERVICE_API_KEY'] || 'test-api-key'
       }
     }
   end
   ```

2. Update `.env.test.example`:
   ```
   YOUR_SERVICE_API_KEY=test-api-key
   ```

3. Use safe access in your code:
   ```ruby
   Rails.application.safe_credentials.dig(:your_service, :api_key)
   ```