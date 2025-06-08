# frozen_string_literal: true

# MigrationLock - 分散ロック機能
#
# 複数サーバー環境でマイグレーションの同時実行を防ぐ
# Redisベースの分散ロックまたはデータベースベースのロックを提供
class MigrationLock
  class LockError < StandardError; end
  class LockTimeoutError < LockError; end

  DEFAULT_TIMEOUT = 5.minutes
  DEFAULT_RETRY_COUNT = 3
  DEFAULT_RETRY_DELAY = 1

  class << self
    # ============================================
    # メインインターフェース
    # ============================================

    # ロックを取得してブロックを実行
    def with_lock(migration_name, options = {})
      timeout = options[:timeout] || DEFAULT_TIMEOUT
      retry_count = options[:retry_count] || DEFAULT_RETRY_COUNT
      retry_delay = options[:retry_delay] || DEFAULT_RETRY_DELAY

      lock_acquired = false
      attempts = 0
      monitor_thread = nil

      begin
        # ロック取得のリトライループ
        loop do
          attempts += 1
          lock_acquired = acquire_lock(migration_name, timeout)

          if lock_acquired
            break
          elsif attempts < retry_count
            Rails.logger.warn "Failed to acquire lock for #{migration_name}, retrying in #{retry_delay}s... (attempt #{attempts}/#{retry_count})"
            sleep(retry_delay)
          else
            raise LockTimeoutError, "Could not acquire lock for migration: #{migration_name} after #{attempts} attempts"
          end
        end

        Rails.logger.info "Lock acquired for migration: #{migration_name}"

        # ロック状態の監視を開始
        monitor_thread = start_lock_monitoring(migration_name, timeout)

        # ブロックを実行
        yield

      ensure
        # 監視スレッドを停止
        monitor_thread&.kill

        # ロックを解放
        if lock_acquired
          release_lock(migration_name)
          Rails.logger.info "Lock released for migration: #{migration_name}"
        end
      end
    end

    # 現在のロック状態を確認
    def locked?(migration_name)
      if redis_available?
        redis_locked?(migration_name)
      else
        database_locked?(migration_name)
      end
    end

    # ロック情報を取得
    def lock_info(migration_name)
      if redis_available?
        redis_lock_info(migration_name)
      else
        database_lock_info(migration_name)
      end
    end

    # 全てのアクティブなロックを取得
    def active_locks
      if redis_available?
        redis_active_locks
      else
        database_active_locks
      end
    end

    # 強制的にロックを解放（緊急時のみ使用）
    def force_release(migration_name)
      Rails.logger.warn "Force releasing lock for migration: #{migration_name}"

      if redis_available?
        redis_force_release(migration_name)
      else
        database_force_release(migration_name)
      end
    end

    private

    # ============================================
    # ロック取得・解放
    # ============================================

    def acquire_lock(migration_name, timeout)
      if redis_available?
        acquire_redis_lock(migration_name, timeout)
      else
        acquire_database_lock(migration_name, timeout)
      end
    end

    def release_lock(migration_name)
      if redis_available?
        release_redis_lock(migration_name)
      else
        release_database_lock(migration_name)
      end
    end

    # ============================================
    # Redisベースのロック実装
    # ============================================

    def redis_available?
      defined?(Redis) && Redis.current.ping == "PONG"
    rescue
      false
    end

    def acquire_redis_lock(migration_name, timeout)
      lock_key = redis_lock_key(migration_name)
      lock_value = generate_lock_value

      # SET NX EX を使用したアトミックなロック取得
      result = Redis.current.set(
        lock_key,
        lock_value.to_json,
        nx: true,
        ex: timeout.to_i
      )

      if result
        # ロック値をスレッドローカルに保存（解放時の検証用）
        Thread.current[:migration_locks] ||= {}
        Thread.current[:migration_locks][migration_name] = lock_value
      end

      result
    end

    def release_redis_lock(migration_name)
      lock_key = redis_lock_key(migration_name)
      lock_value = Thread.current[:migration_locks]&.[](migration_name)

      return false unless lock_value

      # Luaスクリプトを使用して安全にロックを解放
      # 自分が取得したロックのみを解放する
      lua_script = <<-LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("del", KEYS[1])
        else
          return 0
        end
      LUA

      result = Redis.current.eval(lua_script, keys: [ lock_key ], argv: [ lock_value.to_json ])

      # スレッドローカルからロック情報を削除
      Thread.current[:migration_locks].delete(migration_name)

      result == 1
    end

    def redis_locked?(migration_name)
      Redis.current.exists?(redis_lock_key(migration_name))
    end

    def redis_lock_info(migration_name)
      lock_key = redis_lock_key(migration_name)
      lock_data = Redis.current.get(lock_key)

      return nil unless lock_data

      info = JSON.parse(lock_data, symbolize_names: true)
      ttl = Redis.current.ttl(lock_key)

      info.merge(ttl_seconds: ttl)
    end

    def redis_active_locks
      pattern = "migration_lock:*"
      keys = Redis.current.keys(pattern)

      keys.map do |key|
        migration_name = key.sub("migration_lock:", "")
        lock_info(migration_name)
      end.compact
    end

    def redis_force_release(migration_name)
      Redis.current.del(redis_lock_key(migration_name))
    end

    def redis_lock_key(migration_name)
      "migration_lock:#{migration_name}"
    end

    # ============================================
    # データベースベースのロック実装
    # ============================================

    def acquire_database_lock(migration_name, timeout)
      # migration_locksテーブルが存在しない場合は作成
      ensure_migration_locks_table

      lock_record = MigrationLockRecord.find_or_initialize_by(
        migration_name: migration_name
      )

      # 既存のロックが期限切れかチェック
      if lock_record.persisted? && lock_record.expires_at < Time.current
        lock_record.destroy
        lock_record = MigrationLockRecord.new(migration_name: migration_name)
      end

      # 新規ロックの作成を試みる
      if lock_record.new_record?
        lock_value = generate_lock_value
        lock_record.assign_attributes(
          lock_value: lock_value.to_json,
          locked_at: Time.current,
          expires_at: Time.current + timeout,
          host: lock_value[:host],
          pid: lock_value[:pid]
        )

        begin
          lock_record.save!

          # ロック値をスレッドローカルに保存
          Thread.current[:migration_locks] ||= {}
          Thread.current[:migration_locks][migration_name] = lock_value

          true
        rescue ActiveRecord::RecordNotUnique
          false
        end
      else
        false
      end
    end

    def release_database_lock(migration_name)
      lock_value = Thread.current[:migration_locks]&.[](migration_name)
      return false unless lock_value

      # 自分が取得したロックのみを解放
      deleted_count = MigrationLockRecord.where(
        migration_name: migration_name,
        lock_value: lock_value.to_json
      ).delete_all

      # スレッドローカルからロック情報を削除
      Thread.current[:migration_locks].delete(migration_name)

      deleted_count > 0
    end

    def database_locked?(migration_name)
      MigrationLockRecord.where(migration_name: migration_name)
                        .where("expires_at > ?", Time.current)
                        .exists?
    end

    def database_lock_info(migration_name)
      record = MigrationLockRecord.find_by(
        migration_name: migration_name
      )

      return nil unless record && record.expires_at > Time.current

      lock_value = JSON.parse(record.lock_value, symbolize_names: true)
      lock_value.merge(
        locked_at: record.locked_at,
        expires_at: record.expires_at,
        ttl_seconds: (record.expires_at - Time.current).to_i
      )
    end

    def database_active_locks
      MigrationLockRecord.where("expires_at > ?", Time.current).map do |record|
        lock_info(record.migration_name)
      end
    end

    def database_force_release(migration_name)
      MigrationLockRecord.where(migration_name: migration_name).delete_all
    end

    # ============================================
    # ヘルパーメソッド
    # ============================================

    def generate_lock_value
      {
        host: Socket.gethostname,
        pid: Process.pid,
        thread_id: Thread.current.object_id,
        locked_at: Time.current.iso8601,
        rails_env: Rails.env
      }
    end

    def start_lock_monitoring(migration_name, timeout)
      Thread.new do
        loop do
          sleep(timeout / 3)

          # ロックの有効期限を延長
          if redis_available?
            extend_redis_lock(migration_name, timeout)
          else
            extend_database_lock(migration_name, timeout)
          end
        end
      rescue => e
        Rails.logger.error "Lock monitoring error: #{e.message}"
      end
    end

    def extend_redis_lock(migration_name, timeout)
      lock_key = redis_lock_key(migration_name)
      lock_value = Thread.current[:migration_locks]&.[](migration_name)

      return unless lock_value

      # 現在の値が自分のロックである場合のみ延長
      lua_script = <<-LUA
        if redis.call("get", KEYS[1]) == ARGV[1] then
          return redis.call("expire", KEYS[1], ARGV[2])
        else
          return 0
        end
      LUA

      Redis.current.eval(
        lua_script,
        keys: [ lock_key ],
        argv: [ lock_value.to_json, timeout.to_i ]
      )
    end

    def extend_database_lock(migration_name, timeout)
      lock_value = Thread.current[:migration_locks]&.[](migration_name)
      return unless lock_value

      MigrationLockRecord.where(
        migration_name: migration_name,
        lock_value: lock_value.to_json
      ).update_all(
        expires_at: Time.current + timeout
      )
    end

    def ensure_migration_locks_table
      return if MigrationLockRecord.table_exists?

      ActiveRecord::Base.connection.create_table :migration_locks do |t|
        t.string :migration_name, null: false
        t.text :lock_value, null: false
        t.string :host, null: false
        t.integer :pid, null: false
        t.datetime :locked_at, null: false
        t.datetime :expires_at, null: false

        t.index :migration_name, unique: true
        t.index :expires_at
      end
    end
  end

  # データベースベースのロック用モデル
  class MigrationLockRecord < ActiveRecord::Base
    self.table_name = "migration_locks"
  end if defined?(ActiveRecord::Base)
end

# TODO: 今後の拡張予定
# 1. Redisクラスター対応（Redlock アルゴリズム）
# 2. ロック待機キューの実装
# 3. デッドロック検出と自動解決
# 4. ロック取得の優先度設定
# 5. 分散トランザクションとの統合
