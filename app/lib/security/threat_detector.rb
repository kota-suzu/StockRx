# frozen_string_literal: true

module Security
  class ThreatDetector
    attr_reader :config, :storage

    # 既知の攻撃ツールのUser-Agentパターン
    SUSPICIOUS_USER_AGENTS = [
      /sqlmap/i, /nikto/i, /nmap/i, /masscan/i,
      /burpsuite/i, /owasp/i, /w3af/i,
      /bot/i, /crawler/i, /scanner/i,
      /<script>/i, /\'\s*OR\s*1=1/i
    ].freeze

    # SQLインジェクション攻撃のパターン
    SQL_INJECTION_PATTERNS = [
      /(\s|^)(select|insert|update|delete|drop|create|alter)\s/i,
      /(\s|^)(union|where|having|order\s+by)\s/i,
      /(\s|^)(and|or)\s+1\s*=\s*1/i,
      /\'[\s]*or[\s]*\'.*\'[\s]*=[\s]*\'/i,
      /\"\s*or\s*\"\s*=\s*\"/i,
      /-{2,}/,
      /\/\*.*\*\//
    ].freeze

    # パストラバーサル攻撃のパターン
    PATH_TRAVERSAL_PATTERNS = [
      /\.\.[\/\\]/,
      /%2e%2e[%2f%5c]/i,
      /\/(etc|proc|sys|var)\//i,
      /[\/\\](windows|winnt)[\/\\]/i,
      /\.(conf|passwd|shadow|key|pem)$/i
    ].freeze

    def initialize(config: SecurityConfig.instance, storage: nil)
      @config = config
      @storage = storage || SecurityStorage.new
    end

    def detect_threats(request)
      client_ip = extract_client_ip(request)
      
      # ホワイトリストIPの場合はスキップ
      return [] if whitelisted_ip?(client_ip)

      threats = []
      threats << :rapid_requests if rapid_requests?(client_ip)
      threats << :suspicious_user_agent if suspicious_user_agent?(request.user_agent)
      threats << :path_traversal if path_traversal?(request.path)
      threats << :sql_injection if sql_injection?(request)
      threats << :large_request if large_request?(request)

      threats
    end

    def determine_severity(threats)
      return :critical if critical_threats?(threats)
      return :high if high_threats?(threats)
      :medium
    end

    private

    def rapid_requests?(ip_address)
      count = storage.increment_counter(
        "#{config.redis_keys[:request_count]}:#{ip_address}",
        expiry: 60
      )
      count > config.thresholds.rapid_requests
    end

    def suspicious_user_agent?(user_agent)
      return true if user_agent.blank?
      SUSPICIOUS_USER_AGENTS.any? { |pattern| user_agent.match?(pattern) }
    end

    def path_traversal?(path)
      PATH_TRAVERSAL_PATTERNS.any? { |pattern| path.match?(pattern) }
    end

    def sql_injection?(request)
      content_to_check = build_content_string(request)
      SQL_INJECTION_PATTERNS.any? { |pattern| content_to_check.match?(pattern) }
    end

    def large_request?(request)
      content_length = request.content_length
      return false unless content_length
      content_length > config.thresholds.request_size
    end

    def build_content_string(request)
      query_string = request.query_string
      request_body = extract_request_body(request)
      [query_string, request_body, request.path].compact.join(" ")
    end

    def extract_request_body(request)
      return nil unless request.content_length && request.content_length > 0
      return nil if request.content_length > 1.megabyte

      begin
        request.body.read(1.megabyte)
      rescue => e
        Rails.logger.warn "Failed to read request body: #{e.message}"
        nil
      ensure
        request.body.rewind if request.body.respond_to?(:rewind)
      end
    end

    def extract_client_ip(request)
      request.env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
        request.env["HTTP_X_REAL_IP"] ||
        request.remote_ip
    end

    def whitelisted_ip?(ip_address)
      config.whitelist_ips.include?(ip_address)
    end

    def critical_threats?(threats)
      threats.include?(:sql_injection) || threats.include?(:path_traversal)
    end

    def high_threats?(threats)
      threats.include?(:rapid_requests) && threats.length > 1
    end
  end
end