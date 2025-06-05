# frozen_string_literal: true

module Security
  class LoginTracker
    attr_reader :config, :storage, :event_handler

    def initialize(
      config: SecurityConfig.instance,
      storage: nil,
      event_handler: nil
    )
      @config = config
      @storage = storage || SecurityStorage.new
      @event_handler = event_handler || SecurityEventHandler.new
    end

    def track_login_attempt(ip_address, email, success:, user_agent: nil)
      context = build_login_context(ip_address, email, user_agent)

      if success
        handle_successful_login(context)
      else
        handle_failed_login(context)
      end
    end

    def is_login_blocked?(ip_address)
      storage.is_blocked?(ip_address)
    end

    def get_failed_count(ip_address, email)
      storage.get_failed_login_count(ip_address, email)
    end

    def reset_failures(ip_address, email)
      storage.reset_failed_logins(ip_address, email)
    end

    private

    def handle_successful_login(context)
      ip_address = context[:ip_address]
      email = context[:email]

      # 失敗カウントをリセット
      storage.reset_failed_logins(ip_address, email)

      # 成功イベントを記録
      event_handler.handle_login_threat(:successful_login, context)
    end

    def handle_failed_login(context)
      ip_address = context[:ip_address]
      email = context[:email]

      # 失敗カウントを増加
      failed_count = storage.increment_failed_logins(ip_address, email)
      context[:failed_count] = failed_count

      # 閾値チェック
      if failed_count >= config.thresholds.failed_logins
        handle_brute_force_detection(context)
      else
        event_handler.handle_login_threat(:failed_login, context)
      end
    end

    def handle_brute_force_detection(context)
      # ブルートフォース攻撃として処理
      event_handler.handle_login_threat(:brute_force, context)
    end

    def build_login_context(ip_address, email, user_agent)
      {
        ip_address: ip_address,
        email: email,
        user_agent: user_agent,
        timestamp: Time.current.iso8601,
        source: "login_tracker"
      }
    end
  end
end
