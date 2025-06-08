# frozen_string_literal: true

# ReversibleMigration - 可逆的マイグレーション基盤クラス
#
# 設計書に基づいた完全なロールバック機能を持つマイグレーション基盤
# すべての操作を記録し、エラー時の自動ロールバックを保証
class ReversibleMigration < ActiveRecord::Migration[8.0]
  # ロールバックデータの初期化
  def initialize(*)
    super
    @rollback_data = []
    @execution_log = []
    @start_time = nil
  end

  # ============================================
  # 実行管理メソッド
  # ============================================

  def up
    @start_time = Time.current
    Rails.logger.info "Starting migration: #{self.class.name}"

    begin
      # トランザクション内で実行
      transaction_with_savepoint do
        execute_with_rollback_support
      end

      log_success
    rescue => e
      log_error(e)
      execute_rollback
      raise
    ensure
      cleanup_temp_data
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "このマイグレーションは up メソッドでロールバック可能です。down メソッドは使用しないでください。"
  end

  # ============================================
  # 可逆的操作メソッド
  # ============================================

  # レコードの作成（ロールバック可能）
  def create_records(model_class, attributes_list, options = {})
    created_ids = []

    attributes_list.each_slice(options[:batch_size] || 1000) do |batch|
      records = batch.map do |attrs|
        record = model_class.create!(attrs)
        created_ids << record.id
        record
      end

      # ロールバックデータを記録
      @rollback_data << {
        operation: :created_records,
        model_class: model_class.name,
        ids: records.map(&:id),
        timestamp: Time.current
      }

      yield records if block_given?
      apply_load_control(options[:load_control])
    end

    created_ids
  end

  # レコードの更新（ロールバック可能）
  def update_records(model_class, conditions, updates, options = {})
    modified_records = []

    model_class.where(conditions).find_in_batches(batch_size: options[:batch_size] || 1000) do |batch|
      # 更新前の状態を保存
      original_data = batch.map do |record|
        {
          id: record.id,
          attributes: record.attributes.slice(*updates.keys.map(&:to_s))
        }
      end

      # 更新実行
      batch.each do |record|
        record.update!(updates)
        modified_records << record
      end

      # ロールバックデータを記録
      @rollback_data << {
        operation: :modified_records,
        model_class: model_class.name,
        original_data: original_data,
        timestamp: Time.current
      }

      yield batch if block_given?
      apply_load_control(options[:load_control])
    end

    modified_records.count
  end

  # レコードの削除（ロールバック可能）
  def delete_records(model_class, conditions, options = {})
    deleted_data = []

    model_class.where(conditions).find_in_batches(batch_size: options[:batch_size] || 1000) do |batch|
      # 削除前の完全なデータを保存
      batch_data = batch.map do |record|
        {
          attributes: record.attributes,
          associations: extract_associations(record, options[:include_associations])
        }
      end

      # 削除実行
      batch.each(&:destroy!)
      deleted_data.concat(batch_data)

      # ロールバックデータを記録
      @rollback_data << {
        operation: :deleted_records,
        model_class: model_class.name,
        data: batch_data,
        timestamp: Time.current
      }

      yield batch_data if block_given?
      apply_load_control(options[:load_control])
    end

    deleted_data.count
  end

  # ============================================
  # ロールバック実行
  # ============================================

  def execute_rollback
    Rails.logger.warn "Executing rollback for migration: #{self.class.name}"

    @rollback_data.reverse_each do |entry|
      begin
        case entry[:operation]
        when :created_records
          rollback_created_records(entry)
        when :modified_records
          rollback_modified_records(entry)
        when :deleted_records
          rollback_deleted_records(entry)
        end
      rescue => e
        Rails.logger.error "Rollback failed for operation: #{entry[:operation]}, Error: #{e.message}"
        # ロールバックのロールバックは行わない（無限ループ防止）
        raise
      end
    end

    Rails.logger.info "Rollback completed successfully"
  end

  # ============================================
  # エラーハンドリングとリトライ
  # ============================================

  def with_retry(max_attempts: 3, backoff: :exponential)
    attempts = 0
    begin
      yield
    rescue => e
      attempts += 1
      if attempts < max_attempts && retryable_error?(e)
        sleep_time = calculate_backoff(attempts, backoff)
        Rails.logger.warn("Retrying after #{sleep_time}s: #{e.message}")
        sleep(sleep_time)
        retry
      else
        raise
      end
    end
  end

  # ============================================
  # データ整合性検証
  # ============================================

  def verify_data_integrity
    Rails.logger.info "Verifying data integrity..."

    # 外部キー制約の確認
    connection = ActiveRecord::Base.connection
    foreign_keys = connection.foreign_keys(:all)

    foreign_keys.each do |fk|
      invalid_count = connection.execute(<<-SQL).first[0]
        SELECT COUNT(*) FROM #{fk.from_table}
        LEFT JOIN #{fk.to_table} ON #{fk.from_table}.#{fk.column} = #{fk.to_table}.id
        WHERE #{fk.from_table}.#{fk.column} IS NOT NULL
        AND #{fk.to_table}.id IS NULL
      SQL

      if invalid_count.to_i > 0
        raise "Foreign key violation: #{fk.from_table}.#{fk.column} has #{invalid_count} invalid references"
      end
    end

    # カスタム整合性チェック（サブクラスでオーバーライド可能）
    run_custom_validations

    Rails.logger.info "Data integrity verified successfully"
  end

  protected

  # サブクラスで実装する実際のマイグレーション処理
  def execute_with_rollback_support
    raise NotImplementedError, "サブクラスで execute_with_rollback_support メソッドを実装してください"
  end

  # カスタム整合性チェック（サブクラスでオーバーライド可能）
  def run_custom_validations
    # デフォルトでは何もしない
  end

  private

  # ============================================
  # ロールバック処理の実装
  # ============================================

  def rollback_created_records(entry)
    model_class = entry[:model_class].constantize
    model_class.where(id: entry[:ids]).destroy_all
  end

  def rollback_modified_records(entry)
    model_class = entry[:model_class].constantize
    entry[:original_data].each do |data|
      record = model_class.find_by(id: data[:id])
      record&.update!(data[:attributes])
    end
  end

  def rollback_deleted_records(entry)
    model_class = entry[:model_class].constantize
    entry[:data].each do |data|
      # 関連レコードの復元も含む
      record = model_class.create!(data[:attributes])
      restore_associations(record, data[:associations]) if data[:associations]
    end
  end

  # ============================================
  # 負荷制御
  # ============================================

  def apply_load_control(options = {})
    return unless options

    # 基本的なスリープ時間
    if options[:sleep]
      sleep(options[:sleep])
    end

    # CPU使用率に基づく動的制御
    if options[:cpu_threshold]
      while cpu_usage > options[:cpu_threshold]
        Rails.logger.info "CPU usage high (#{cpu_usage}%), waiting..."
        sleep(5)
      end
    end

    # メモリ使用率に基づく動的制御
    if options[:memory_threshold]
      while memory_usage > options[:memory_threshold]
        Rails.logger.info "Memory usage high (#{memory_usage}%), waiting..."
        GC.start
        sleep(5)
      end
    end
  end

  # ============================================
  # ユーティリティメソッド
  # ============================================

  def transaction_with_savepoint(&block)
    ActiveRecord::Base.transaction(requires_new: true, &block)
  end

  def retryable_error?(error)
    # デッドロックや一時的な接続エラーはリトライ可能
    error.is_a?(ActiveRecord::Deadlocked) ||
    error.is_a?(ActiveRecord::ConnectionTimeoutError) ||
    (error.message.include?("Lock wait timeout") rescue false)
  end

  def calculate_backoff(attempt, strategy)
    case strategy
    when :exponential
      2 ** attempt
    when :linear
      attempt * 2
    else
      5 # デフォルト5秒
    end
  end

  def extract_associations(record, association_names)
    return nil unless association_names

    association_names.each_with_object({}) do |name, hash|
      association = record.association(name)
      hash[name] = association.target.attributes if association.loaded?
    end
  end

  def restore_associations(record, associations_data)
    associations_data.each do |name, attrs|
      record.send("#{name}=", record.association(name).klass.new(attrs))
    end
    record.save!
  end

  def cpu_usage
    # 簡易的なCPU使用率取得（本番環境では適切な監視ツールを使用）
    `ps -o %cpu= -p #{Process.pid}`.to_f
  end

  def memory_usage
    # 簡易的なメモリ使用率取得（本番環境では適切な監視ツールを使用）
    rss = `ps -o rss= -p #{Process.pid}`.to_i
    total = `sysctl -n hw.memsize`.to_i / 1024 rescue 8_000_000 # macOS
    (rss.to_f / total * 100).round(2)
  end

  def log_success
    execution_time = Time.current - @start_time
    Rails.logger.info "Migration completed: #{self.class.name} in #{execution_time.round(2)}s"

    @execution_log << {
      status: "success",
      migration: self.class.name,
      execution_time: execution_time,
      rollback_data_count: @rollback_data.count,
      timestamp: Time.current
    }
  end

  def log_error(error)
    Rails.logger.error "Migration failed: #{self.class.name}, Error: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")

    @execution_log << {
      status: "failed",
      migration: self.class.name,
      error: error.message,
      error_class: error.class.name,
      timestamp: Time.current
    }
  end

  def cleanup_temp_data
    # 一時データのクリーンアップ（必要に応じてサブクラスでオーバーライド）
    @rollback_data.clear
    @execution_log.clear
  end
end

# TODO: 以下の拡張機能は次フェーズで実装
# 1. マイグレーション実行状態の永続化（Redisまたはデータベース）
# 2. 分散ロック機能（複数サーバーでの同時実行防止）
# 3. 進捗状況のリアルタイム通知（ActionCable統合）
# 4. パフォーマンスメトリクスの収集とレポート
# 5. 自動ロールバックのしきい値設定（エラー率、実行時間など）
