# ジョブ処理システム設計書（Sidekiq）

**最終更新**: 2025年5月28日  
**バージョン**: 1.0  
**ステータス**: 実装済み・拡張中

## 1. 概要

StockRxのジョブ処理システムは、Sidekiqを基盤として非同期処理・定期実行・バックグラウンドタスクを管理するシステムです。高可用性・スケーラビリティ・監視性を重視した設計となっています。

### 主要コンポーネント
- **Sidekiq**: バックグラウンドジョブ処理エンジン
- **Redis**: ジョブキュー・進捗管理
- **ActionCable**: リアルタイム進捗通知
- **ProgressNotifier**: 進捗追跡ライブラリ
- **SecurityMonitor**: ジョブセキュリティ監視

## 2. アーキテクチャ

### 2.1 ジョブ基底クラス

```ruby
# app/jobs/application_job.rb
class ApplicationJob < ActiveJob::Base
  include Sidekiq::Worker
  
  # グローバル設定
  sidekiq_options retry: 3, backtrace: true
  
  # 共通エラーハンドリング
  rescue_from StandardError do |exception|
    log_error(exception)
    notify_error(exception) if should_notify?(exception)
    raise exception # 再スローしてSidekiqのリトライ機構を利用
  end
  
  # 実行前フック
  before_perform do |job|
    log_job_start(job)
    set_job_context(job)
  end
  
  # 実行後フック
  after_perform do |job|
    log_job_completion(job)
    clear_job_context
  end
  
  private
  
  def log_error(exception)
    Rails.logger.error({
      job_class: self.class.name,
      job_id: job_id,
      error_class: exception.class.name,
      error_message: exception.message,
      backtrace: exception.backtrace.first(10)
    }.to_json)
  end
  
  def notify_error(exception)
    # TODO: Slack/Teams通知実装
    AdminMailer.job_error_notification(
      job_class: self.class.name,
      error: exception
    ).deliver_later
  end
end
```

### 2.2 進捗追跡システム

```ruby
# app/lib/progress_notifier.rb
module ProgressNotifier
  extend ActiveSupport::Concern
  
  included do
    attr_accessor :progress_channel, :total_items, :processed_items
  end
  
  def initialize_progress(channel, total)
    @progress_channel = channel
    @total_items = total
    @processed_items = 0
    
    notify_progress(status: 'started')
  end
  
  def update_progress(increment = 1)
    @processed_items += increment
    percentage = (@processed_items.to_f / @total_items * 100).round(2)
    
    notify_progress(
      status: 'processing',
      current: @processed_items,
      total: @total_items,
      percentage: percentage
    )
  end
  
  def complete_progress(message = nil)
    notify_progress(
      status: 'completed',
      message: message,
      total: @total_items,
      processed: @processed_items
    )
  end
  
  def fail_progress(error_message)
    notify_progress(
      status: 'failed',
      error: error_message,
      processed: @processed_items
    )
  end
  
  private
  
  def notify_progress(data)
    return unless @progress_channel
    
    ActionCable.server.broadcast(
      @progress_channel,
      data.merge(
        job_id: job_id,
        timestamp: Time.current.iso8601
      )
    )
  end
end
```

## 3. ジョブ実装パターン

### 3.1 インポートジョブパターン

```ruby
# app/jobs/import_inventories_job.rb
class ImportInventoriesJob < ApplicationJob
  include ProgressNotifier
  
  queue_as :imports
  sidekiq_options retry: 3, dead: true, backtrace: true
  
  # タイムアウト設定
  sidekiq_options timeout: 30.minutes
  
  def perform(file_path, admin_id, options = {})
    admin = Admin.find(admin_id)
    Current.admin = admin
    
    # セキュリティチェック
    validate_file_security(file_path)
    
    # 進捗初期化
    csv_data = CSV.read(file_path, headers: true)
    initialize_progress("import_#{admin_id}", csv_data.size)
    
    # バッチ処理
    process_in_batches(csv_data, options[:batch_size] || 100)
    
    # 完了処理
    complete_progress("#{@processed_items}件のインポートが完了しました")
    cleanup_file(file_path)
    
  rescue StandardError => e
    fail_progress(e.message)
    raise
  end
  
  private
  
  def process_in_batches(csv_data, batch_size)
    csv_data.each_slice(batch_size).with_index do |batch, index|
      ActiveRecord::Base.transaction do
        batch.each do |row|
          process_row(row)
          update_progress
        end
      end
      
      # バッチ間でGCを実行
      GC.start if index % 10 == 0
    end
  end
  
  def validate_file_security(file_path)
    # ファイルサイズチェック
    raise "File too large" if File.size(file_path) > 100.megabytes
    
    # パストラバーサル対策
    raise "Invalid file path" unless File.expand_path(file_path).start_with?(Rails.root.join('tmp'))
    
    # ファイル形式チェック
    raise "Invalid file type" unless File.extname(file_path).downcase == '.csv'
  end
end
```

### 3.2 定期実行ジョブパターン

```ruby
# app/jobs/expiry_check_job.rb
class ExpiryCheckJob < ApplicationJob
  queue_as :scheduled
  
  # 冪等性を保証
  sidekiq_options unique: :until_executed, unique_args: ->(args) { [] }
  
  def perform
    Rails.logger.info "Starting expiry check at #{Time.current}"
    
    # 期限切れチェック
    expired_count = check_expired_items
    
    # 期限間近チェック
    expiring_count = check_expiring_items
    
    # サマリー通知
    notify_summary(expired_count, expiring_count)
    
    # 次回実行をスケジュール（cron未使用の場合）
    self.class.set(wait: 1.day).perform_later unless using_cron?
  end
  
  private
  
  def check_expired_items
    expired_batches = Batch.expired.with_stock
    
    expired_batches.find_each do |batch|
      # TODO: 期限切れ処理の実装
      # - 在庫ステータス更新
      # - 通知送信
      # - 廃棄指示作成
      handle_expired_batch(batch)
    end
    
    expired_batches.count
  end
  
  def check_expiring_items
    notification_periods = [7, 30, 60, 90] # 日数
    total_count = 0
    
    notification_periods.each do |days|
      expiring_batches = Batch.expiring_within(days).not_notified_for(days)
      
      expiring_batches.find_each do |batch|
        # TODO: 期限通知の実装
        send_expiry_notification(batch, days)
        total_count += 1
      end
    end
    
    total_count
  end
end
```

### 3.3 外部連携ジョブパターン

```ruby
# app/jobs/external_api_sync_job.rb
class ExternalApiSyncJob < ApplicationJob
  queue_as :external
  
  # リトライ戦略
  sidekiq_options retry: 5
  sidekiq_retry_in do |count, exception|
    case exception
    when Net::ReadTimeout, Net::OpenTimeout
      (count ** 2) + 15 # 指数バックオフ
    when RateLimitError
      300 # 5分後にリトライ
    else
      60 # 1分後にリトライ
    end
  end
  
  def perform(sync_type, options = {})
    case sync_type
    when 'inventory_levels'
      sync_inventory_levels(options)
    when 'price_updates'
      sync_price_updates(options)
    when 'order_status'
      sync_order_status(options)
    else
      raise ArgumentError, "Unknown sync type: #{sync_type}"
    end
  end
  
  private
  
  def sync_inventory_levels(options)
    api_client = ExternalApiClient.new
    
    # ページネーション対応
    page = 1
    loop do
      response = api_client.fetch_inventory_levels(page: page, per_page: 100)
      
      # レート制限チェック
      check_rate_limit(response.headers)
      
      # データ処理
      process_inventory_data(response.body)
      
      break unless response.has_next_page?
      page += 1
    end
  end
  
  def check_rate_limit(headers)
    remaining = headers['X-RateLimit-Remaining'].to_i
    reset_time = Time.at(headers['X-RateLimit-Reset'].to_i)
    
    if remaining < 10
      wait_time = reset_time - Time.current
      raise RateLimitError, "Rate limit approaching, retry after #{wait_time} seconds"
    end
  end
end
```

## 4. キュー設計

### 4.1 キュー構成

```yaml
# config/sidekiq.yml
:concurrency: 10
:max_retries: 3

:queues:
  - [critical, 5]     # 重要度最高（認証、セキュリティ）
  - [imports, 3]      # インポート処理
  - [exports, 3]      # エクスポート処理
  - [notifications, 2] # 通知送信
  - [scheduled, 2]    # 定期実行
  - [external, 1]     # 外部API連携
  - [default, 1]      # その他
  - [low, 1]         # 優先度低

:schedule:
  expiry_check:
    cron: "0 2 * * *"  # 毎日午前2時
    class: ExpiryCheckJob
    queue: scheduled
    
  stock_alert:
    cron: "0 9 * * *"  # 毎日午前9時
    class: StockAlertJob
    queue: scheduled
    
  cleanup_old_logs:
    cron: "0 3 * * 0"  # 毎週日曜午前3時
    class: CleanupOldLogsJob
    queue: low
```

### 4.2 キュー選択戦略

```ruby
class JobQueueSelector
  QUEUE_RULES = {
    # ジョブクラス => キュー名
    'ImportInventoriesJob' => :imports,
    'ExportInventoriesJob' => :exports,
    'AdminMailer' => :notifications,
    'ExternalApiSyncJob' => :external
  }.freeze
  
  def self.select_queue(job_class)
    QUEUE_RULES[job_class.to_s] || :default
  end
  
  def self.select_by_priority(priority)
    case priority
    when :critical then :critical
    when :high then :default
    when :normal then :default
    when :low then :low
    else :default
    end
  end
end
```

## 5. 監視・ロギング

### 5.1 ジョブメトリクス

```ruby
# app/lib/job_metrics.rb
module JobMetrics
  extend ActiveSupport::Concern
  
  included do
    around_perform :measure_performance
  end
  
  def measure_performance
    start_time = Time.current
    memory_before = GetProcessMem.new.mb
    
    yield
    
    duration = Time.current - start_time
    memory_after = GetProcessMem.new.mb
    memory_used = memory_after - memory_before
    
    log_metrics(duration, memory_used)
    alert_if_slow(duration)
    alert_if_memory_high(memory_used)
  end
  
  private
  
  def log_metrics(duration, memory_used)
    Rails.logger.info({
      job_metrics: {
        job_class: self.class.name,
        job_id: job_id,
        duration_seconds: duration.round(2),
        memory_mb: memory_used.round(2),
        queue: queue_name,
        timestamp: Time.current.iso8601
      }
    }.to_json)
  end
  
  def alert_if_slow(duration)
    threshold = self.class.slow_job_threshold || 300 # 5分
    return unless duration > threshold
    
    # TODO: アラート送信
    Rails.logger.warn "Slow job detected: #{self.class.name} took #{duration}s"
  end
end
```

### 5.2 エラー監視

```ruby
# app/jobs/concerns/error_monitoring.rb
module ErrorMonitoring
  extend ActiveSupport::Concern
  
  included do
    rescue_from StandardError do |exception|
      handle_job_error(exception)
      raise exception # Sidekiqのリトライを有効化
    end
  end
  
  private
  
  def handle_job_error(exception)
    error_context = {
      job_class: self.class.name,
      job_id: job_id,
      arguments: arguments,
      queue: queue_name,
      retry_count: executions,
      error_class: exception.class.name,
      error_message: exception.message,
      backtrace: exception.backtrace.first(20)
    }
    
    # ログ記録
    Rails.logger.error(error_context.to_json)
    
    # エラー通知
    notify_error_to_admins(exception, error_context) if should_notify?(exception)
    
    # Sentryへの送信（実装時）
    # TODO: Sentry.capture_exception(exception, extra: error_context)
  end
  
  def should_notify?(exception)
    # 一時的なエラーは通知しない
    !transient_error?(exception) && executions >= 2
  end
  
  def transient_error?(exception)
    [
      Net::ReadTimeout,
      Redis::TimeoutError,
      ActiveRecord::LockWaitTimeout
    ].any? { |klass| exception.is_a?(klass) }
  end
end
```

## 6. セキュリティ考慮事項

### 6.1 ジョブ引数の検証

```ruby
class SecureJobBase < ApplicationJob
  before_perform :validate_arguments
  before_perform :check_permissions
  
  private
  
  def validate_arguments
    # ID の検証
    arguments.each do |arg|
      if arg.is_a?(Integer) && arg.to_s.match?(/\A\d+\z/)
        next
      elsif arg.is_a?(String)
        # SQLインジェクション対策
        raise ArgumentError if arg.match?(/[';--]/)
      elsif arg.is_a?(Hash)
        validate_hash_arguments(arg)
      end
    end
  end
  
  def check_permissions
    return unless respond_to?(:required_permission)
    
    admin_id = arguments.find { |arg| arg.is_a?(Integer) }
    admin = Admin.find_by(id: admin_id)
    
    unless admin&.has_permission?(required_permission)
      raise SecurityError, "Insufficient permissions for job execution"
    end
  end
end
```

### 6.2 ファイル処理のセキュリティ

```ruby
module SecureFileProcessing
  MAX_FILE_SIZE = 100.megabytes
  ALLOWED_EXTENSIONS = %w[.csv .xlsx .json].freeze
  UPLOAD_PATH = Rails.root.join('tmp', 'uploads')
  
  def validate_file_security(file_path)
    # パストラバーサル対策
    safe_path = File.expand_path(file_path)
    unless safe_path.start_with?(UPLOAD_PATH.to_s)
      raise SecurityError, "Invalid file path"
    end
    
    # ファイルサイズチェック
    if File.size(safe_path) > MAX_FILE_SIZE
      raise SecurityError, "File too large"
    end
    
    # 拡張子チェック
    unless ALLOWED_EXTENSIONS.include?(File.extname(safe_path).downcase)
      raise SecurityError, "Invalid file type"
    end
    
    # ファイル内容の検証
    validate_file_content(safe_path)
  end
  
  def validate_file_content(file_path)
    # マジックナンバーチェック
    File.open(file_path, 'rb') do |file|
      header = file.read(8)
      
      case File.extname(file_path).downcase
      when '.csv'
        # CSVは特定のマジックナンバーがないため、内容を検証
        validate_csv_content(file_path)
      when '.xlsx'
        # Excelファイルのマジックナンバー
        unless header.start_with?("PK\x03\x04")
          raise SecurityError, "Invalid Excel file"
        end
      end
    end
  end
end
```

## 7. パフォーマンス最適化

### 7.1 バッチ処理最適化

```ruby
class BatchProcessor
  include Sidekiq::Worker
  
  def perform(model_class, method_name, ids)
    # find_eachでメモリ効率的に処理
    model_class.constantize
               .where(id: ids)
               .find_each(batch_size: 100) do |record|
      
      process_record(record, method_name)
      
      # 定期的にGCを実行
      GC.start if processed_count % 1000 == 0
    end
  end
  
  private
  
  def process_record(record, method_name)
    # コネクションプールの効率的な利用
    ActiveRecord::Base.connection_pool.with_connection do
      record.public_send(method_name)
    end
  rescue StandardError => e
    # エラーは記録するが処理は継続
    log_processing_error(record, e)
  end
end
```

### 7.2 メモリ管理

```ruby
module MemoryManagement
  extend ActiveSupport::Concern
  
  included do
    before_perform :check_memory_usage
    after_perform :cleanup_memory
  end
  
  private
  
  def check_memory_usage
    current_memory = GetProcessMem.new.mb
    
    if current_memory > memory_limit
      Rails.logger.warn "High memory usage: #{current_memory}MB"
      
      # 必要に応じてジョブを遅延
      raise MemoryError, "Memory limit exceeded" if current_memory > critical_memory_limit
    end
  end
  
  def cleanup_memory
    # 大きなオブジェクトの解放
    @large_objects&.clear
    
    # 明示的なGC実行（必要な場合）
    GC.start if should_run_gc?
  end
  
  def memory_limit
    500 # MB
  end
  
  def critical_memory_limit
    800 # MB
  end
end
```

## 8. テスト戦略

### 8.1 ジョブテスト

```ruby
# spec/jobs/import_inventories_job_spec.rb
require 'rails_helper'

RSpec.describe ImportInventoriesJob, type: :job do
  include ActiveJob::TestHelper
  
  let(:admin) { create(:admin) }
  let(:file_path) { Rails.root.join('spec/fixtures/files/valid_inventory.csv') }
  
  describe '#perform' do
    it 'imports inventory data successfully' do
      expect {
        described_class.perform_now(file_path.to_s, admin.id)
      }.to change(Inventory, :count).by(10)
    end
    
    it 'broadcasts progress updates' do
      expect {
        described_class.perform_now(file_path.to_s, admin.id)
      }.to have_broadcasted_to("import_#{admin.id}")
        .at_least(3).times # start, progress, complete
    end
    
    it 'handles errors gracefully' do
      allow(CSV).to receive(:read).and_raise(CSV::MalformedCSVError)
      
      expect {
        described_class.perform_now(file_path.to_s, admin.id)
      }.to raise_error(CSV::MalformedCSVError)
      
      expect(ActionCable.server)
        .to have_received(:broadcast)
        .with("import_#{admin.id}", hash_including(status: 'failed'))
    end
  end
  
  describe 'retry behavior' do
    it 'retries on transient errors' do
      allow_any_instance_of(described_class)
        .to receive(:process_row)
        .and_raise(ActiveRecord::LockWaitTimeout)
      
      expect {
        perform_enqueued_jobs do
          described_class.perform_later(file_path.to_s, admin.id)
        end
      }.to raise_error(ActiveRecord::LockWaitTimeout)
      
      expect(described_class).to have_been_enqueued.exactly(3).times
    end
  end
end
```

### 8.2 統合テスト

```ruby
# spec/features/background_job_integration_spec.rb
require 'rails_helper'

RSpec.feature 'Background Job Integration', type: :feature do
  include ActiveJob::TestHelper
  
  scenario 'CSV import with real-time progress' do
    admin = create(:admin)
    sign_in admin
    
    visit admin_inventories_path
    click_link 'Import CSV'
    
    attach_file 'file', Rails.root.join('spec/fixtures/files/inventory.csv')
    
    perform_enqueued_jobs do
      click_button 'Start Import'
      
      # プログレスバーの確認
      expect(page).to have_css('.progress-bar')
      expect(page).to have_content('Processing...')
      
      # 完了待機
      expect(page).to have_content('Import completed', wait: 10)
    end
    
    # 結果確認
    expect(Inventory.count).to eq(100)
  end
end
```

## 9. 運用ガイド

### 9.1 Sidekiqダッシュボード

```ruby
# config/routes.rb
require 'sidekiq/web'
require 'sidekiq/cron/web'

Rails.application.routes.draw do
  authenticate :admin, ->(admin) { admin.super_admin? } do
    mount Sidekiq::Web => '/admin/sidekiq'
  end
end
```

### 9.2 監視項目

1. **キュー遅延**: 各キューの待機ジョブ数
2. **処理時間**: ジョブの平均・最大実行時間
3. **エラー率**: 失敗ジョブの割合
4. **メモリ使用量**: ワーカープロセスのメモリ
5. **Redis接続**: 接続プールの状態

### 9.3 トラブルシューティング

```ruby
# Sidekiqコンソールコマンド
# 特定のキューをクリア
Sidekiq::Queue.new('imports').clear

# 失敗ジョブの確認
Sidekiq::RetrySet.new.each do |job|
  puts "#{job.klass} - #{job.args} - #{job.error_message}"
end

# デッドジョブの復活
Sidekiq::DeadSet.new.each do |job|
  job.retry if job.klass == 'ImportInventoriesJob'
end

# ワーカーの状態確認
Sidekiq::Workers.new.each do |process_id, thread_id, work|
  puts "#{process_id} - #{work['queue']} - #{work['run_at']}"
end
```

## 10. ベストプラクティス

### 10.1 ジョブ設計の原則

1. **冪等性**: 同じジョブを複数回実行しても結果が同じ
2. **原子性**: トランザクション内で処理を完結
3. **非同期性**: UIをブロックしない設計
4. **監視性**: 進捗・エラーの可視化
5. **回復性**: エラー時の自動リトライ

### 10.2 実装チェックリスト

- [ ] ジョブクラスは ApplicationJob を継承
- [ ] 適切なキューを選択
- [ ] リトライ戦略を定義
- [ ] タイムアウトを設定
- [ ] 進捗通知を実装（長時間ジョブ）
- [ ] エラーハンドリングを実装
- [ ] セキュリティ検証を実装
- [ ] テストを作成
- [ ] ドキュメントを更新

## 11. 今後の拡張計画

### Phase 1: 安定性向上（実装中）
- [x] 基本的なリトライ機構
- [x] 進捗通知システム
- [ ] Sentry統合
- [ ] 詳細なメトリクス収集

### Phase 2: スケーラビリティ（計画中）
- [ ] 動的ワーカースケーリング
- [ ] 優先度ベースのキュー管理
- [ ] ジョブの分割・並列実行
- [ ] Redis Cluster対応

### Phase 3: 高度な機能（将来）
- [ ] ジョブの依存関係管理
- [ ] ワークフロー機能
- [ ] ジョブのスケジューリングUI
- [ ] カスタムリトライ戦略

## 12. 参考資料

- [Sidekiq Best Practices](https://github.com/mperham/sidekiq/wiki/Best-Practices)
- [Rails Background Jobs Guide](https://guides.rubyonrails.org/active_job_basics.html)
- [Redis Performance Tuning](https://redis.io/docs/management/optimization/)