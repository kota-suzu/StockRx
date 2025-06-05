# frozen_string_literal: true

module Security
  class SecurityStorage
    attr_reader :config

    def initialize(config: SecurityConfig.instance)
      @config = config
    end

    def increment_counter(key, expiry: 60)
      redis = get_redis_connection
      return 0 unless redis

      begin
        count = redis.incr(key)
        redis.expire(key, expiry) if count == 1
        count
      rescue => e
        Rails.logger.error "Storage increment error: #{e.message}"
        0
      end
    end

    def is_blocked?(ip_address)
      redis = get_redis_connection
      return false unless redis

      begin
        blocked_keys = redis.keys("#{config.redis_keys[:blocked]}:*:#{ip_address}")
        blocked_keys.any? { |key| redis.exists?(key) }
      rescue => e
        Rails.logger.error "Storage blocked check error: #{e.message}"
        false
      end
    end

    def block_ip(ip_address, reason, duration_minutes)
      redis = get_redis_connection
      return false unless redis

      begin
        block_key = "#{config.redis_keys[:blocked]}:#{reason}:#{ip_address}"
        block_data = build_block_data(reason, duration_minutes)

        redis.setex(block_key, duration_minutes * 60, block_data.to_json)
        true
      rescue => e
        Rails.logger.error "Storage block IP error: #{e.message}"
        false
      end
    end

    def delete_key(key)
      redis = get_redis_connection
      return false unless redis

      begin
        redis.del(key) > 0
      rescue => e
        Rails.logger.error "Storage delete error: #{e.message}"
        false
      end
    end

    def update_statistics(ip_address, user_agent, path)
      redis = get_redis_connection
      return unless redis

      begin
        update_hourly_stats
        update_ip_stats(ip_address)
      rescue => e
        Rails.logger.error "Storage statistics error: #{e.message}"
      end
    end

    def get_failed_login_count(ip_address, email)
      redis = get_redis_connection
      return 0 unless redis

      begin
        key = "#{config.redis_keys[:failed_logins]}:#{ip_address}:#{email}"
        redis.get(key).to_i
      rescue => e
        Rails.logger.error "Storage failed login count error: #{e.message}"
        0
      end
    end

    def reset_failed_logins(ip_address, email)
      key = "#{config.redis_keys[:failed_logins]}:#{ip_address}:#{email}"
      delete_key(key)
    end

    def increment_failed_logins(ip_address, email, expiry: 3600)
      key = "#{config.redis_keys[:failed_logins]}:#{ip_address}:#{email}"
      increment_counter(key, expiry: expiry)
    end

    private

    def get_redis_connection
      return mock_redis if Rails.env.test? && defined?(MockRedis)

      if Rails.env.test?
        return nil unless defined?(Redis)

        begin
          redis = Redis.current
          redis.ping
          return redis
        rescue => e
          Rails.logger.warn "Redis not available in test environment: #{e.message}"
          return nil
        end
      end

      begin
        if defined?(Sidekiq) && Sidekiq.redis_pool
          Sidekiq.redis { |conn| return conn }
        else
          Redis.current
        end
      rescue => e
        Rails.logger.warn "Redis connection failed: #{e.message}"
        nil
      end
    end

    def mock_redis
      @mock_redis ||= MockRedis.new if defined?(MockRedis)
    end

    def build_block_data(reason, duration_minutes)
      {
        blocked_at: Time.current.iso8601,
        reason: reason,
        duration_minutes: duration_minutes,
        blocked_until: (Time.current + duration_minutes.minutes).iso8601
      }
    end

    def update_hourly_stats
      hour_key = "#{config.redis_keys[:stats_requests]}:#{Time.current.strftime('%Y%m%d%H')}"
      count = increment_counter(hour_key, expiry: 25.hours.to_i)
      count
    end

    def update_ip_stats(ip_address)
      ip_key = "#{config.redis_keys[:stats_ip]}:#{ip_address}:#{Date.current.strftime('%Y%m%d')}"
      count = increment_counter(ip_key, expiry: 2.days.to_i)
      count
    end
  end
end
