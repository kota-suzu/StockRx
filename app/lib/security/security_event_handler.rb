# frozen_string_literal: true

module Security
  class SecurityEventHandler
    attr_reader :config, :storage

    def initialize(config: SecurityConfig.instance, storage: nil)
      @config = config
      @storage = storage || SecurityStorage.new(config: @config)
    end

    def handle_threat(threat_type, context)
      severity = determine_severity_from_context(context)

      case severity
      when :critical
        handle_critical_threat(context)
      when :high
        handle_high_threat(context)
      when :medium
        handle_medium_threat(context)
      else
        log_security_event(:unknown_threat, context)
      end
    end

    def handle_login_threat(threat_type, context)
      case threat_type
      when :brute_force
        handle_brute_force_attack(context)
      when :successful_login
        handle_successful_login(context)
      when :failed_login
        handle_failed_login(context)
      else
        log_security_event(:unknown_login_threat, context)
      end
    end

    private

    def handle_critical_threat(context)
      ip_address = context[:ip]
      threats = context[:threats] || []

      duration = determine_block_duration(threats)
      storage.block_ip(ip_address, :critical_threat, duration)

      log_security_event(:critical_threat_blocked, context.merge(
        action_taken: "blocked",
        duration_minutes: duration
      ))

      notify_security_team(:critical_threat, context)
    end

    def handle_high_threat(context)
      ip_address = context[:ip]
      threats = context[:threats] || []

      duration = config.block_durations.high_threat
      storage.block_ip(ip_address, :high_threat, duration)

      log_security_event(:high_threat_blocked, context.merge(
        action_taken: "blocked",
        duration_minutes: duration
      ))

      notify_security_team(:high_threat, context)
    end

    def handle_medium_threat(context)
      log_security_event(:suspicious_activity, context.merge(
        action_taken: "logged"
      ))

      # 中レベル脅威は監視のみ（ブロックしない）
      notify_security_team(:medium_threat, context)
    end

    def handle_brute_force_attack(context)
      ip_address = context[:ip_address]
      duration = config.block_durations.brute_force

      storage.block_ip(ip_address, :brute_force, duration)

      log_security_event(:brute_force_blocked, context.merge(
        action_taken: "blocked",
        duration_minutes: duration
      ))

      notify_security_team(:brute_force_attack, context)
    end

    def handle_successful_login(context)
      ip_address = context[:ip_address]
      email = context[:email]

      # 失敗ログインカウントをリセット
      storage.reset_failed_logins(ip_address, email)

      log_security_event(:successful_login, context)
    end

    def handle_failed_login(context)
      log_security_event(:failed_login, context)

      # 失敗回数が閾値を超えた場合は別途通知
      failed_count = context[:failed_count] || 0
      if failed_count >= config.thresholds.failed_logins
        notify_security_team(:login_threshold_exceeded, context)
      end
    end

    def determine_severity_from_context(context)
      threats = context[:threats] || []
      return context[:severity] if context[:severity]

      return :critical if critical_threats?(threats)
      return :high if high_threats?(threats)
      :medium
    end

    def determine_block_duration(threats)
      return config.block_durations.sql_injection if threats.include?(:sql_injection)
      return config.block_durations.path_traversal if threats.include?(:path_traversal)
      config.block_durations.critical_threat
    end

    def critical_threats?(threats)
      threats.include?(:sql_injection) || threats.include?(:path_traversal)
    end

    def high_threats?(threats)
      threats.include?(:rapid_requests) && threats.length > 1
    end

    def log_security_event(event_type, details)
      log_level = determine_log_level(event_type)

      log_data = {
        event: "security_#{event_type}",
        timestamp: Time.current.iso8601,
        **details
      }

      case log_level
      when :fatal
        Rails.logger.fatal(log_data.to_json)
      when :error
        Rails.logger.error(log_data.to_json)
      when :warn
        Rails.logger.warn(log_data.to_json)
      else
        Rails.logger.info(log_data.to_json)
      end
    end

    def notify_security_team(notification_type, details)
      # TODO: 実際の通知システム（Slack、メール等）との連携（優先度：高）
      # REF: docs/development_plan.md - 監視・アラート機能
      # 実装予定サービス：
      # - AdminNotificationService.security_alert(notification_type, details)
      # - SlackNotificationService.send_alert(notification_type, details)
      # - EmailNotificationService.send_security_alert(notification_type, details)
      # - PagerDutyService.send_incident(notification_type, details) # 緒急時
      # - SentryService.capture_security_event(notification_type, details) # エラー追跡

      notification_data = {
        event: "security_notification",
        notification_type: notification_type,
        timestamp: Time.current.iso8601,
        **details
      }

      Rails.logger.warn(notification_data.to_json)
    end

    def determine_log_level(event_type)
      case event_type
      when :critical_threat_blocked, :critical_threat
        :fatal
      when :brute_force_blocked, :brute_force_detected, :high_threat_blocked
        :error
      when :failed_login, :suspicious_activity, :medium_threat
        :warn
      else
        :info
      end
    end
  end
end
