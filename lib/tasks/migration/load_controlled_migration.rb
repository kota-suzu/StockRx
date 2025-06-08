# frozen_string_literal: true

require_relative "reversible_migration"

# LoadControlledMigration - 動的負荷制御を備えたマイグレーション
#
# システム負荷に応じてバッチサイズとスリープ時間を自動調整
# 本番環境での安全な大規模データ処理を実現
class LoadControlledMigration < ReversibleMigration
  # デフォルト設定
  DEFAULT_OPTIONS = {
    initial_batch_size: 1000,
    min_batch_size: 100,
    max_batch_size: 10_000,
    initial_sleep: 0.1,
    min_sleep: 0,
    max_sleep: 10,
    cpu_threshold: 70,
    memory_threshold: 80,
    query_time_threshold: 5, # 秒
    adjustment_factor: 0.2
  }.freeze

  def initialize(*)
    super
    @performance_metrics = []
    @current_batch_size = DEFAULT_OPTIONS[:initial_batch_size]
    @current_sleep_time = DEFAULT_OPTIONS[:initial_sleep]
    @options = DEFAULT_OPTIONS.dup
  end

  # ============================================
  # 設定メソッド
  # ============================================

  def configure_load_control(options = {})
    @options.merge!(options)
    @current_batch_size = @options[:initial_batch_size]
    @current_sleep_time = @options[:initial_sleep]
  end

  # ============================================
  # オーバーライドされた操作メソッド
  # ============================================

  def create_records(model_class, attributes_list, options = {})
    options = merge_with_dynamic_options(options)

    total_created = 0
    start_time = Time.current

    attributes_list.each_slice(@current_batch_size) do |batch|
      batch_start = Time.current

      # 親クラスのメソッドを呼び出し
      created_ids = super(model_class, batch, options) do |records|
        yield records if block_given?
      end

      batch_time = Time.current - batch_start
      total_created += created_ids.count

      # パフォーマンスメトリクスを記録
      record_performance_metrics(batch.size, batch_time)

      # 動的にバッチサイズとスリープ時間を調整
      adjust_processing_parameters(batch_time)

      # 進捗ログ
      log_progress(model_class, total_created, attributes_list.size, start_time)

      # 動的スリープ
      sleep(@current_sleep_time) if @current_sleep_time > 0
    end

    total_created
  end

  def update_records(model_class, conditions, updates, options = {})
    options = merge_with_dynamic_options(options)

    total_updated = 0
    start_time = Time.current
    total_count = model_class.where(conditions).count

    model_class.where(conditions).find_in_batches(batch_size: @current_batch_size) do |batch|
      batch_start = Time.current

      # 更新処理の実行
      update_count = process_batch_updates(batch, updates)
      total_updated += update_count

      batch_time = Time.current - batch_start

      # パフォーマンスメトリクスを記録
      record_performance_metrics(batch.size, batch_time)

      # 動的調整
      adjust_processing_parameters(batch_time)

      # 進捗ログ
      log_progress(model_class, total_updated, total_count, start_time)

      # 負荷制御
      apply_dynamic_load_control

      yield batch if block_given?
    end

    total_updated
  end

  def delete_records(model_class, conditions, options = {})
    options = merge_with_dynamic_options(options)

    total_deleted = 0
    start_time = Time.current
    total_count = model_class.where(conditions).count

    # 削除処理も同様に動的制御
    super(model_class, conditions, options) do |deleted_data|
      total_deleted += deleted_data.count
      log_progress(model_class, total_deleted, total_count, start_time)
      yield deleted_data if block_given?
    end

    total_deleted
  end

  # ============================================
  # パフォーマンス監視と調整
  # ============================================

  private

  def merge_with_dynamic_options(options)
    options.merge(
      batch_size: @current_batch_size,
      load_control: {
        sleep: @current_sleep_time,
        cpu_threshold: @options[:cpu_threshold],
        memory_threshold: @options[:memory_threshold]
      }
    )
  end

  def record_performance_metrics(batch_size, execution_time)
    metrics = {
      batch_size: batch_size,
      execution_time: execution_time,
      records_per_second: (batch_size / execution_time).round(2),
      cpu_usage: cpu_usage,
      memory_usage: memory_usage,
      timestamp: Time.current
    }

    @performance_metrics << metrics

    # 直近10バッチの平均を保持
    @performance_metrics = @performance_metrics.last(10)
  end

  def adjust_processing_parameters(batch_time)
    # クエリ時間が閾値を超えた場合
    if batch_time > @options[:query_time_threshold]
      decrease_batch_size
      increase_sleep_time
    elsif batch_time < @options[:query_time_threshold] * 0.5
      # クエリが十分高速な場合
      increase_batch_size
      decrease_sleep_time
    end

    # システム負荷に基づく調整
    if system_overloaded?
      decrease_batch_size
      increase_sleep_time
    end
  end

  def system_overloaded?
    cpu_usage > @options[:cpu_threshold] || memory_usage > @options[:memory_threshold]
  end

  def increase_batch_size
    @current_batch_size = [
      (@current_batch_size * (1 + @options[:adjustment_factor])).to_i,
      @options[:max_batch_size]
    ].min

    Rails.logger.info "Increased batch size to: #{@current_batch_size}"
  end

  def decrease_batch_size
    @current_batch_size = [
      (@current_batch_size * (1 - @options[:adjustment_factor])).to_i,
      @options[:min_batch_size]
    ].max

    Rails.logger.info "Decreased batch size to: #{@current_batch_size}"
  end

  def increase_sleep_time
    @current_sleep_time = [
      @current_sleep_time + 0.5,
      @options[:max_sleep]
    ].min

    Rails.logger.info "Increased sleep time to: #{@current_sleep_time}s"
  end

  def decrease_sleep_time
    @current_sleep_time = [
      @current_sleep_time - 0.1,
      @options[:min_sleep]
    ].max

    Rails.logger.info "Decreased sleep time to: #{@current_sleep_time}s"
  end

  def apply_dynamic_load_control
    # CPU使用率に基づく動的スリープ
    while cpu_usage > @options[:cpu_threshold]
      Rails.logger.info "CPU usage high (#{cpu_usage}%), applying throttle..."
      sleep(2)
    end

    # メモリ使用率に基づくGC実行
    if memory_usage > @options[:memory_threshold]
      Rails.logger.info "Memory usage high (#{memory_usage}%), running GC..."
      GC.start
      sleep(1)
    end

    # 基本スリープ
    sleep(@current_sleep_time) if @current_sleep_time > 0
  end

  def log_progress(model_class, current, total, start_time)
    return unless total > 0

    percentage = (current.to_f / total * 100).round(2)
    elapsed = Time.current - start_time
    rate = current / elapsed
    eta = total > current ? ((total - current) / rate).round : 0

    Rails.logger.info(
      "Progress: #{model_class.name} #{current}/#{total} (#{percentage}%) " \
      "Rate: #{rate.round(2)}/s ETA: #{eta}s " \
      "Batch: #{@current_batch_size} Sleep: #{@current_sleep_time}s"
    )
  end

  def process_batch_updates(batch, updates)
    # 更新前の状態を保存
    original_data = batch.map do |record|
      {
        id: record.id,
        attributes: record.attributes.slice(*updates.keys.map(&:to_s))
      }
    end

    # 更新実行
    updated_count = 0
    batch.each do |record|
      if record.update(updates)
        updated_count += 1
      else
        Rails.logger.error "Failed to update record: #{record.id}, errors: #{record.errors.full_messages}"
      end
    end

    # ロールバックデータを記録
    @rollback_data << {
      operation: :modified_records,
      model_class: batch.first.class.name,
      original_data: original_data,
      timestamp: Time.current
    }

    updated_count
  end

  # パフォーマンスレポートの生成
  def generate_performance_report
    return {} if @performance_metrics.empty?

    {
      average_batch_size: @performance_metrics.map { |m| m[:batch_size] }.sum.to_f / @performance_metrics.size,
      average_execution_time: @performance_metrics.map { |m| m[:execution_time] }.sum.to_f / @performance_metrics.size,
      average_records_per_second: @performance_metrics.map { |m| m[:records_per_second] }.sum.to_f / @performance_metrics.size,
      peak_cpu_usage: @performance_metrics.map { |m| m[:cpu_usage] }.max,
      peak_memory_usage: @performance_metrics.map { |m| m[:memory_usage] }.max,
      total_batches: @performance_metrics.size
    }
  end

  def log_success
    super

    # パフォーマンスレポートもログに出力
    report = generate_performance_report
    Rails.logger.info "Performance Report: #{report.to_json}" unless report.empty?
  end
end

# TODO: 次フェーズでの拡張予定
# 1. 機械学習による最適バッチサイズの予測
# 2. 過去の実行履歴に基づく初期パラメータの自動設定
# 3. 複数のデータベース接続プールの動的管理
# 4. キューイングシステムとの統合（Sidekiq、Resque等）
# 5. リアルタイムダッシュボードでの進捗可視化
