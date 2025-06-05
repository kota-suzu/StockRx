# frozen_string_literal: true

module Security
  class SecurityConfig
    include Singleton

    # ============================================
    # Struct定義：型安全な設定管理（ベストプラクティス）
    # ============================================

    # 異常アクセスパターンの閾値設定
    # Type-safe struct with validation and comprehensive documentation
    SuspiciousThreshold = Struct.new(
      :rapid_requests,      # Integer: 1分間の最大リクエスト数
      :failed_logins,       # Integer: 連続ログイン失敗許可数
      :unique_user_agents,  # Integer: 同一IPからの異なるUser-Agent数上限
      :request_size,        # Integer: リクエストサイズ上限（bytes）
      :response_time        # Numeric: レスポンス時間上限（seconds）
    ) do
      # デフォルト値の提供（環境変数対応）
      def self.default
        new(
          ENV.fetch("SECURITY_RAPID_REQUESTS_THRESHOLD", 100).to_i,
          ENV.fetch("SECURITY_FAILED_LOGINS_THRESHOLD", 5).to_i,
          ENV.fetch("SECURITY_UNIQUE_USER_AGENTS_THRESHOLD", 10).to_i,
          ENV.fetch("SECURITY_REQUEST_SIZE_THRESHOLD", 10.megabytes).to_i,
          ENV.fetch("SECURITY_RESPONSE_TIME_THRESHOLD", 30.seconds).to_f
        )
      end

      # バリデーション機能（ベストプラクティス）
      def validate!
        raise ArgumentError, "rapid_requests must be positive integer" unless rapid_requests.is_a?(Integer) && rapid_requests > 0
        raise ArgumentError, "failed_logins must be positive integer" unless failed_logins.is_a?(Integer) && failed_logins > 0
        raise ArgumentError, "unique_user_agents must be positive integer" unless unique_user_agents.is_a?(Integer) && unique_user_agents > 0
        raise ArgumentError, "request_size must be positive integer" unless request_size.is_a?(Integer) && request_size > 0
        raise ArgumentError, "response_time must be positive number" unless response_time.is_a?(Numeric) && response_time > 0
        self
      end

      # 設定値の詳細情報取得
      def to_h
        {
          rapid_requests: "#{rapid_requests} requests/minute",
          failed_logins: "#{failed_logins} attempts",
          unique_user_agents: "#{unique_user_agents} different agents",
          request_size: "#{request_size / 1.megabyte}MB",
          response_time: "#{response_time}s"
        }
      end
    end

    # ブロック期間設定（分単位）
    # Enhanced struct with environment variable support and validation
    BlockDuration = Struct.new(
      :suspicious_ip,    # Integer: 疑わしいIPのブロック期間（分）
      :brute_force,      # Integer: ブルートフォース攻撃のブロック期間（分）
      :sql_injection,    # Integer: SQLインジェクション試行のブロック期間（分）
      :path_traversal,   # Integer: パストラバーサル攻撃のブロック期間（分）
      :critical_threat,  # Integer: 重大な脅威のブロック期間（分）
      :high_threat       # Integer: 高レベル脅威のブロック期間（分）
    ) do
      # デフォルト値の提供（環境変数対応）
      def self.default_minutes
        new(
          ENV.fetch("SECURITY_BLOCK_SUSPICIOUS_IP", 60).to_i,
          ENV.fetch("SECURITY_BLOCK_BRUTE_FORCE", 120).to_i,
          ENV.fetch("SECURITY_BLOCK_SQL_INJECTION", 1440).to_i,
          ENV.fetch("SECURITY_BLOCK_PATH_TRAVERSAL", 720).to_i,
          ENV.fetch("SECURITY_BLOCK_CRITICAL_THREAT", 1440).to_i,
          ENV.fetch("SECURITY_BLOCK_HIGH_THREAT", 120).to_i
        )
      end

      # バリデーション機能
      def validate!
        each_pair do |key, value|
          unless value.is_a?(Integer) && value > 0
            raise ArgumentError, "#{key} must be positive integer, got: #{value.inspect}"
          end
        end
        self
      end

      # 設定値の詳細情報取得
      def to_h
        {
          suspicious_ip: "#{suspicious_ip} minutes (#{suspicious_ip / 60.0} hours)",
          brute_force: "#{brute_force} minutes (#{brute_force / 60.0} hours)",
          sql_injection: "#{sql_injection} minutes (#{sql_injection / 60.0} hours)",
          path_traversal: "#{path_traversal} minutes (#{path_traversal / 60.0} hours)",
          critical_threat: "#{critical_threat} minutes (#{critical_threat / 60.0} hours)",
          high_threat: "#{high_threat} minutes (#{high_threat / 60.0} hours)"
        }
      end

      # 動的アクセス対応（ハッシュスタイル）
      def [](key)
        case key.to_sym
        when :suspicious_ip then suspicious_ip
        when :brute_force then brute_force
        when :sql_injection then sql_injection
        when :path_traversal then path_traversal
        when :critical_threat then critical_threat
        when :high_threat then high_threat
        else
          raise ArgumentError, "Unknown block duration key: #{key}"
        end
      end
    end

    attr_reader :thresholds, :block_durations

    def initialize
      load_configuration
    end

    # 設定の再読み込み（テスト用）
    def reload!
      clear_cached_values
      load_configuration
      self
    end

    # Redis キープレフィックス設定（強化版）
    def redis_keys
      @redis_keys ||= begin
        prefix = ENV.fetch("REDIS_KEY_PREFIX", "stockrx")
        {
          request_count: "#{prefix}:request_count",
          failed_logins: "#{prefix}:failed_logins",
          login_attempts: "#{prefix}:login_attempts",
          blocked: "#{prefix}:blocked",
          stats_requests: "#{prefix}:stats:requests",
          stats_ip: "#{prefix}:stats:ip"
        }.freeze
      end
    end

    # 監視対象外IPアドレスリスト（環境変数対応）
    def whitelist_ips
      @whitelist_ips ||= begin
        default_ips = [ "127.0.0.1", "::1" ]
        env_ips = ENV["SECURITY_WHITELIST_IPS"]&.split(",")&.map(&:strip) || []
        (default_ips + env_ips).uniq.freeze
      end
    end

    # ログレベル設定
    def log_levels
      @log_levels ||= {
        info: :successful_login,
        warn: :failed_login,
        error: :brute_force_detected,
        fatal: :critical_threat_detected
      }.freeze
    end

    # 設定情報の可視化（デバッグ・監視用）
    def inspect_configuration
      {
        thresholds: @thresholds.to_h,
        block_durations: @block_durations.to_h,
        redis_keys: redis_keys,
        whitelist_ips: whitelist_ips,
        log_levels: log_levels
      }
    end

    # 設定の妥当性チェック
    def valid?
      @thresholds.validate! && @block_durations.validate!
      true
    rescue ArgumentError
      false
    end

    # クラスメソッド：テスト用のインスタンス再読み込み
    def self.reload!
      @instance&.reload!
      @instance
    end

    private

    def load_configuration
      @thresholds = SuspiciousThreshold.default.validate!.freeze
      @block_durations = BlockDuration.default_minutes.validate!.freeze
    rescue ArgumentError => e
      Rails.logger.error "SecurityConfig initialization failed: #{e.message}"
      raise SecurityConfigurationError, "Invalid security configuration: #{e.message}"
    end

    def clear_cached_values
      @thresholds = nil
      @block_durations = nil
      @redis_keys = nil
      @whitelist_ips = nil
      @log_levels = nil
    end
  end

  # カスタム例外クラス
  class SecurityConfigurationError < StandardError; end
end
