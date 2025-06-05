# frozen_string_literal: true

module Security
  class SecurityConfig
    include Singleton

    # 異常アクセスパターンの閾値
    SuspiciousThreshold = Struct.new(
      :rapid_requests,
      :failed_logins,
      :unique_user_agents,
      :request_size,
      :response_time
    ) do
      def self.default
        new(
          100,            # 1分間のリクエスト数
          5,              # 連続ログイン失敗数
          10,             # 異なるUser-Agentの数（同一IP）
          10.megabytes,   # 異常に大きなリクエストサイズ
          30.seconds      # 異常に遅いレスポンス時間
        )
      end
    end

    # ブロック期間（分）
    BlockDuration = Struct.new(
      :suspicious_ip,
      :brute_force,
      :sql_injection,
      :path_traversal,
      :critical_threat,
      :high_threat
    ) do
      def self.default_minutes
        new(
          60,             # 疑わしいIP
          120,            # ブルートフォース攻撃
          1440,           # SQLインジェクション試行（24時間）
          720,            # パストラバーサル攻撃（12時間）
          1440,           # 重大な脅威（24時間）
          120             # 高レベル脅威（2時間）
        )
      end
    end

    attr_reader :thresholds, :block_durations

    def initialize
      @thresholds = SuspiciousThreshold.default.freeze
      @block_durations = BlockDuration.default_minutes.freeze
    end

    # Redis キープレフィックス設定
    def redis_keys
      @redis_keys ||= {
        request_count: "request_count",
        failed_logins: "failed_logins",
        login_attempts: "login_attempts",
        blocked: "blocked",
        stats_requests: "stats:requests",
        stats_ip: "stats:ip"
      }.freeze
    end

    # 監視対象外IPアドレスリスト
    def whitelist_ips
      @whitelist_ips ||= [
        "127.0.0.1",     # localhost
        "::1"           # IPv6 localhost
        # TODO: 環境設定から読み込み
      ].freeze
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
  end
end
