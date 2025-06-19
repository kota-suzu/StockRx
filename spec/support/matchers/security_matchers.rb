# frozen_string_literal: true

# セキュアな属性を持つことを確認するマッチャー
RSpec::Matchers.define :have_secure_attribute do |attribute|
  match do |model|
    # 属性が暗号化されているか確認
    model.respond_to?("#{attribute}_encrypted") || 
    model.class.attribute_names.include?("encrypted_#{attribute}")
  end

  failure_message do |model|
    "expected #{model.class} to have secure attribute :#{attribute}, but it doesn't"
  end
end

# レート制限が実装されているか確認するマッチャー
RSpec::Matchers.define :implement_rate_limiting do
  match do |controller|
    # Rack::Attackまたは同様の機能が設定されているか確認
    controller.class.ancestors.any? { |a| a.to_s.include?("RateLimiting") } ||
    controller.class.instance_methods.include?(:check_rate_limit)
  end

  failure_message do |controller|
    "expected #{controller.class} to implement rate limiting, but it doesn't"
  end
end

# CSRFトークンが必要か確認するマッチャー
RSpec::Matchers.define :require_csrf_token do
  match do |response|
    response.body.include?('csrf-token') || 
    response.headers['X-CSRF-Token'].present?
  end

  failure_message do |response|
    "expected response to require CSRF token, but it doesn't"
  end
end

# SQLインジェクション対策が適用されているか確認するマッチャー
RSpec::Matchers.define :be_sql_injection_safe do
  match do |query_method|
    # Arel.sql()でラップされているか、プレースホルダーを使用しているか確認
    query_method.to_s.include?('Arel.sql') || 
    query_method.to_s.match(/\?|:\w+/)
  end

  failure_message do |query_method|
    "expected query method to be SQL injection safe, but it uses raw SQL without protection"
  end
end

# XSS対策が適用されているか確認するマッチャー
RSpec::Matchers.define :be_xss_safe do |content|
  match do |rendered_output|
    # HTMLエスケープされているか確認
    dangerous_patterns = ['<script>', 'javascript:', 'onerror=', 'onclick=']
    dangerous_patterns.none? { |pattern| rendered_output.include?(pattern) }
  end

  failure_message do |rendered_output|
    "expected output to be XSS safe, but it contains unescaped dangerous content"
  end
end

# 認証が必要か確認するマッチャー
RSpec::Matchers.define :require_authentication do
  match do |response|
    [401, 302].include?(response.status) && 
    (response.location&.include?('sign_in') || response.body.include?('sign_in'))
  end

  failure_message do |response|
    "expected response to require authentication (401 or redirect to sign_in), but got #{response.status}"
  end
end

# 認可が正しく実装されているか確認するマッチャー
RSpec::Matchers.define :enforce_authorization do |expected_role|
  match do |controller|
    controller.class.instance_methods.include?(:"authorize_#{expected_role}!") ||
    controller.class.before_actions.any? { |cb| cb.filter.to_s.include?('authorize') }
  end

  failure_message do |controller|
    "expected #{controller.class} to enforce authorization for #{expected_role}, but it doesn't"
  end
end

# セキュリティヘッダーが設定されているか確認するマッチャー
RSpec::Matchers.define :have_security_headers do
  match do |response|
    required_headers = [
      'X-Frame-Options',
      'X-Content-Type-Options',
      'X-XSS-Protection',
      'Strict-Transport-Security'
    ]
    
    required_headers.all? { |header| response.headers[header].present? }
  end

  failure_message do |response|
    missing_headers = ['X-Frame-Options', 'X-Content-Type-Options', 'X-XSS-Protection', 'Strict-Transport-Security']
      .select { |h| response.headers[h].blank? }
    
    "expected response to have security headers, but missing: #{missing_headers.join(', ')}"
  end
end