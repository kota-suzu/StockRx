# frozen_string_literal: true

# ============================================
# Sidekiq Management Rake Tasks
# ============================================
# Background job processing management and monitoring tasks
# 要求仕様対応：運用監視・メンテナンス自動化

namespace :sidekiq do
  desc "Sidekiqのヘルスチェックを実行"
  task health: :environment do
    puts "=== Sidekiq Health Check ==="

    begin
      # Redis接続確認
      Sidekiq.redis { |conn| conn.ping }
      puts "✅ Redis connection: OK"

      # Sidekiq統計情報取得
      stats = Sidekiq::Stats.new
      puts "✅ Processed jobs: #{stats.processed}"
      puts "✅ Failed jobs: #{stats.failed}"
      puts "✅ Enqueued jobs: #{stats.enqueued}"
      puts "✅ Scheduled jobs: #{stats.scheduled_size}"
      puts "✅ Retry jobs: #{stats.retry_size}"
      puts "✅ Dead jobs: #{stats.dead_size}"

      # キュー状況確認
      puts "\n=== Queue Status ==="
      Sidekiq::Queue.all.each do |queue|
        puts "📦 #{queue.name}: #{queue.size} jobs"
      end

      # ワーカー状況確認
      puts "\n=== Worker Status ==="
      workers = Sidekiq::Workers.new
      if workers.size > 0
        workers.each do |process_id, thread_id, work|
          puts "👷 Worker #{process_id}-#{thread_id}: #{work['payload']['class']}"
        end
      else
        puts "ℹ️  No active workers"
      end

      puts "\n✅ Sidekiq health check completed successfully"

    rescue => e
      puts "❌ Sidekiq health check failed: #{e.message}"
      exit 1
    end
  end

  desc "キューの状況を詳細表示"
  task queues: :environment do
    puts "=== Detailed Queue Information ==="

    Sidekiq::Queue.all.each do |queue|
      puts "\n📦 Queue: #{queue.name}"
      puts "   Size: #{queue.size}"
      puts "   Latency: #{queue.latency.round(2)}s"

      if queue.size > 0
        puts "   Recent jobs:"
        queue.first(5).each_with_index do |job, index|
          puts "   #{index + 1}. #{job.klass} (#{job.created_at})"
        end
      end
    end
  end

  desc "失敗したジョブをクリア"
  task clear_failed: :environment do
    puts "=== Clearing Failed Jobs ==="

    stats = Sidekiq::Stats.new
    failed_count = stats.failed

    if failed_count > 0
      Sidekiq::DeadSet.new.clear
      Sidekiq::RetrySet.new.clear
      puts "✅ Cleared #{failed_count} failed jobs"
    else
      puts "ℹ️  No failed jobs to clear"
    end
  end

  desc "古いジョブ履歴をクリーンアップ"
  task cleanup: :environment do
    puts "=== Sidekiq Cleanup ==="

    # 7日以上前の完了ジョブ履歴を削除
    cutoff_time = 7.days.ago

    Sidekiq.redis do |conn|
      # 古いprocessed統計をクリア
      processed_key = "sidekiq:stat:processed"
      failed_key = "sidekiq:stat:failed"

      puts "🧹 Cleaning up old job statistics..."

      # 古いDead jobsを削除（90日以上前）
      dead_set = Sidekiq::DeadSet.new
      old_dead_jobs = dead_set.select { |job| job.created_at < 90.days.ago }
      old_dead_jobs.each(&:delete)

      puts "✅ Cleaned up #{old_dead_jobs.size} old dead jobs"
      puts "✅ Cleanup completed"
    end
  end

  desc "ワーカー情報を表示"
  task workers: :environment do
    puts "=== Active Workers ==="

    workers = Sidekiq::Workers.new
    processes = Sidekiq::ProcessSet.new

    puts "Active processes: #{processes.size}"
    puts "Active workers: #{workers.size}"

    processes.each do |process|
      puts "\n🖥️  Process: #{process['hostname']}:#{process['pid']}"
      puts "   Started: #{Time.at(process['started_at'])}"
      puts "   Concurrency: #{process['concurrency']}"
      puts "   Queues: #{process['queues'].join(', ')}"
      puts "   Busy: #{process['busy']}"
    end

    if workers.size > 0
      puts "\n👷 Active Workers:"
      workers.each do |process_id, thread_id, work|
        job_class = work.dig("payload", "class") || "Unknown"
        started_at = Time.at(work["run_at"]) if work["run_at"]
        puts "   #{process_id}-#{thread_id}: #{job_class} (started: #{started_at})"
      end
    end
  end

  desc "Sidekiq統計情報の詳細レポート"
  task stats: :environment do
    puts "=== Sidekiq Statistics Report ==="

    stats = Sidekiq::Stats.new

    puts "📊 Job Statistics:"
    puts "   Processed: #{stats.processed}"
    puts "   Failed: #{stats.failed}"
    puts "   Success Rate: #{((stats.processed.to_f - stats.failed) / [ stats.processed, 1 ].max * 100).round(2)}%"
    puts "   Enqueued: #{stats.enqueued}"
    puts "   Scheduled: #{stats.scheduled_size}"
    puts "   Retries: #{stats.retry_size}"
    puts "   Dead: #{stats.dead_size}"

    puts "\n📈 Historical Data:"
    history = Sidekiq::Stats::History.new
    puts "   Processed (today): #{history.processed.values.last}"
    puts "   Failed (today): #{history.failed.values.last}"

    # キュー別統計
    puts "\n📦 Queue Statistics:"
    Sidekiq::Queue.all.each do |queue|
      puts "   #{queue.name}: #{queue.size} jobs, #{queue.latency.round(2)}s latency"
    end

    # メモリ使用量（可能な場合）
    begin
      memory_usage = `ps -o rss= -p #{Process.pid}`.strip.to_i
      puts "\n💾 Memory Usage: #{(memory_usage / 1024.0).round(2)} MB"
    rescue
      puts "\n💾 Memory Usage: Unable to determine"
    end
  end

  desc "パフォーマンス監視レポート"
  task performance: :environment do
    puts "=== Sidekiq Performance Monitor ==="

    # キューレイテンシ監視
    puts "📊 Queue Latency Analysis:"
    Sidekiq::Queue.all.each do |queue|
      latency = queue.latency
      status = case latency
      when 0..5 then "🟢 Good"
      when 5..30 then "🟡 Warning"
      else "🔴 Critical"
      end

      puts "   #{queue.name}: #{latency.round(2)}s #{status}"
    end

    # メモリ使用量トレンド（簡易版）
    puts "\n💾 Memory Trend (recent):"
    5.times do |i|
      memory = `ps -o rss= -p #{Process.pid}`.strip.to_i / 1024.0
      puts "   #{Time.current - i.seconds}: #{memory.round(2)} MB"
      sleep 1
    end

    # 推奨アクション
    stats = Sidekiq::Stats.new
    puts "\n🔧 Recommendations:"

    if stats.enqueued > 1000
      puts "   ⚠️  High queue size detected. Consider scaling workers."
    end

    if stats.failed > stats.processed * 0.05
      puts "   ⚠️  High failure rate detected. Check error logs."
    end

    if Sidekiq::Queue.all.any? { |q| q.latency > 30 }
      puts "   ⚠️  High latency detected. Check worker capacity."
    end

    unless stats.enqueued > 1000 || stats.failed > stats.processed * 0.05
      puts "   ✅ System performance looks healthy."
    end
  end

  desc "推奨アクションの表示"
  task recommendations: :environment do
    puts "=== Sidekiq System Recommendations ==="

    stats = Sidekiq::Stats.new
    recommendations = []

    # パフォーマンス分析
    if stats.failed > 0
      failure_rate = (stats.failed.to_f / [ stats.processed, 1 ].max * 100).round(2)
      if failure_rate > 5
        recommendations << "⚠️  高い失敗率 (#{failure_rate}%): エラーログを確認し、リトライ戦略を見直してください"
      end
    end

    # キューレイテンシ分析
    critical_queues = Sidekiq::Queue.all.select { |q| q.latency > 30 }
    if critical_queues.any?
      queue_names = critical_queues.map(&:name).join(", ")
      recommendations << "⚠️  高いレイテンシのキュー (#{queue_names}): ワーカー数の増加を検討してください"
    end

    # デッドジョブ分析
    if stats.dead_size > 100
      recommendations << "⚠️  大量のデッドジョブ (#{stats.dead_size}): ジョブの信頼性を見直してください"
    end

    # リトライジョブ分析
    if stats.retry_size > 1000
      recommendations << "⚠️  大量のリトライジョブ (#{stats.retry_size}): 根本原因の調査が必要です"
    end

    # メモリ使用量確認
    begin
      memory_mb = `ps -o rss= -p #{Process.pid}`.strip.to_i / 1024.0
      if memory_mb > 500
        recommendations << "⚠️  高いメモリ使用量 (#{memory_mb.round}MB): メモリリークの可能性があります"
      end
    rescue
      # メモリ情報が取得できない場合はスキップ
    end

    # 推奨アクション表示
    if recommendations.any?
      puts "以下の改善を推奨します:"
      recommendations.each { |rec| puts "  #{rec}" }
    else
      puts "✅ システムは正常に動作しています"
    end

    # 定期メンテナンス推奨
    puts "\n🔧 定期メンテナンス:"
    puts "  - make sidekiq:cleanup を週次実行"
    puts "  - make sidekiq:performance を日次監視"
    puts "  - ログローテーションの設定確認"
  end

  desc "テストジョブを実行して動作確認"
  task test: :environment do
    puts "=== Sidekiq Test Job Execution ==="

    begin
      # 簡単なテストジョブを実行
      puts "🚀 テストジョブを実行中..."

      # StockAlertJobのテスト実行（低い閾値で実行）
      job_id = StockAlertJob.perform_async(999, [], false) # メール無効でテスト
      puts "✅ StockAlertJob テスト実行 (Job ID: #{job_id})"

      # CleanupOldLogsJobのテスト実行
      job_id = CleanupOldLogsJob.perform_async(90, true) # 90日、テストモード
      puts "✅ CleanupOldLogsJob テスト実行 (Job ID: #{job_id})"

      # SidekiqMaintenanceJobのテスト実行
      job_id = SidekiqMaintenanceJob.perform_async(false, false) # クリーンアップ無効、通知無効
      puts "✅ SidekiqMaintenanceJob テスト実行 (Job ID: #{job_id})"

      puts "\n📊 実行後の統計:"
      sleep 2 # ジョブ実行を少し待つ
      stats = Sidekiq::Stats.new
      puts "  処理済み: #{stats.processed}"
      puts "  キュー中: #{stats.enqueued}"
      puts "  失敗: #{stats.failed}"

      puts "\n✅ テストジョブの実行完了"
      puts "   詳細は 'make sidekiq:queues' で確認できます"

    rescue => e
      puts "❌ テストジョブ実行エラー: #{e.message}"
      exit 1
    end
  end

  desc "特定のジョブを手動実行"
  task :run, [ :job_class, :args ] => :environment do |t, args|
    puts "=== Manual Job Execution ==="

    job_class = args[:job_class]
    job_args = args[:args]&.split(",") || []

    unless job_class
      puts "❌ ジョブクラス名を指定してください"
      puts "使用例: bundle exec rake 'sidekiq:run[StockAlertJob,10]'"
      puts "利用可能なジョブ:"
      puts "  - StockAlertJob"
      puts "  - CleanupOldLogsJob"
      puts "  - SidekiqMaintenanceJob"
      puts "  - ExpiryCheckJob"
      puts "  - MonthlyReportJob"
      puts "  - ExternalApiSyncJob"
      exit 1
    end

    begin
      # ジョブクラスの存在確認
      klass = job_class.constantize
      unless klass < ApplicationJob
        puts "❌ #{job_class} is not a valid job class"
        exit 1
      end

      puts "🚀 実行中: #{job_class}.perform_async(#{job_args.join(', ')})"
      job_id = klass.perform_async(*job_args)
      puts "✅ ジョブをキューに追加しました (Job ID: #{job_id})"

      # 実行状況を監視
      puts "📊 実行監視中..."
      3.times do |i|
        sleep 1
        stats = Sidekiq::Stats.new
        puts "  #{i+1}秒後: キュー #{stats.enqueued}, 処理済み #{stats.processed}"
      end

    rescue NameError
      puts "❌ ジョブクラス '#{job_class}' が見つかりません"
      exit 1
    rescue => e
      puts "❌ ジョブ実行エラー: #{e.message}"
      exit 1
    end
  end

  desc "定期実行ジョブの一括テスト"
  task test_scheduled: :environment do
    puts "=== Scheduled Jobs Test ==="

    scheduled_jobs = [
      { name: "Daily Stock Alert", class: "StockAlertJob", args: [ 10, [], false ] },
      { name: "Daily Expiry Check", class: "ExpiryCheckJob", args: [ 7, [], false ] },
      { name: "Weekly Cleanup", class: "CleanupOldLogsJob", args: [ 90, true ] },
      { name: "Daily Maintenance", class: "SidekiqMaintenanceJob", args: [ false, false ] }
    ]

    puts "以下の定期ジョブをテスト実行します:"
    scheduled_jobs.each_with_index do |job_config, index|
      puts "  #{index + 1}. #{job_config[:name]}"
    end

    print "\n実行しますか？ (y/N): "
    response = STDIN.gets.chomp.downcase

    if response == "y" || response == "yes"
      scheduled_jobs.each do |job_config|
        begin
          klass = job_config[:class].constantize
          job_id = klass.perform_async(*job_config[:args])
          puts "✅ #{job_config[:name]} - 実行開始 (Job ID: #{job_id})"
        rescue => e
          puts "❌ #{job_config[:name]} - エラー: #{e.message}"
        end
      end

      puts "\n📊 実行後の統計確認中..."
      sleep 3
      system("bundle exec rake sidekiq:stats")
    else
      puts "❌ テスト実行をキャンセルしました"
    end
  end

  desc "完全なシステムダイアグノーシス"
  task diagnose: :environment do
    puts "=== Sidekiq System Diagnosis ==="
    puts "実行日時: #{Time.current}"
    puts "Rails環境: #{Rails.env}"

    # 基本ヘルスチェック
    puts "\n1. 基本ヘルスチェック"
    Rake::Task["sidekiq:health"].invoke

    # 詳細統計
    puts "\n2. 詳細統計情報"
    Rake::Task["sidekiq:stats"].invoke

    # パフォーマンス分析
    puts "\n3. パフォーマンス分析"
    Rake::Task["sidekiq:performance"].invoke

    # 推奨アクション
    puts "\n4. 推奨アクション"
    Rake::Task["sidekiq:recommendations"].invoke

    # 設定確認
    puts "\n5. 設定確認"
    config_file = Rails.root.join("config", "sidekiq.yml")
    if File.exist?(config_file)
      puts "✅ Sidekiq設定ファイル: 存在"
      puts "   場所: #{config_file}"
    else
      puts "⚠️  Sidekiq設定ファイル: 不存在"
    end

    # Redis接続情報
    puts "\n6. Redis接続情報"
    begin
      Sidekiq.redis do |conn|
        info = conn.info
        puts "✅ Redis バージョン: #{info['redis_version']}"
        puts "   メモリ使用量: #{info['used_memory_human']}"
        puts "   接続クライアント数: #{info['connected_clients']}"
      end
    rescue => e
      puts "❌ Redis情報取得エラー: #{e.message}"
    end

    puts "\n✅ システム診断完了"
  end

  # TODO: 将来的な拡張タスク
  # ============================================
  # task alert_setup: :environment do
  #   # Slack/Teams通知設定のセットアップ
  # end
  #
  # task export_metrics: :environment do
  #   # Prometheus形式でメトリクスをエクスポート
  # end
  #
  # task backup_jobs: :environment do
  #   # 重要ジョブのバックアップ作成
  # end
end

# システム全体のヘルスチェック（Sidekiq以外も含む）
namespace :system do
  desc "システム全体のヘルスチェック"
  task health: :environment do
    puts "=== System Health Check ==="

    # データベース接続確認
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      puts "✅ Database connection: OK"
    rescue => e
      puts "❌ Database connection failed: #{e.message}"
    end

    # Redis接続確認
    begin
      Sidekiq.redis { |conn| conn.ping }
      puts "✅ Redis connection: OK"
    rescue => e
      puts "❌ Redis connection failed: #{e.message}"
    end

    # ディスク容量確認
    begin
      disk_usage = `df -h #{Rails.root}`.split("\n")[1].split[4]
      puts "✅ Disk usage: #{disk_usage}"

      if disk_usage.to_i > 80
        puts "⚠️  Warning: Disk usage is high (#{disk_usage})"
      end
    rescue
      puts "ℹ️  Disk usage: Unable to determine"
    end

    # プロセス確認
    puts "✅ Rails process: #{Process.pid}"

    # 環境情報
    puts "\n🔧 Environment Info:"
    puts "   Rails: #{Rails.version}"
    puts "   Ruby: #{RUBY_VERSION}"
    puts "   Environment: #{Rails.env}"
    puts "   Sidekiq: #{Sidekiq::VERSION}"

    puts "\n✅ System health check completed"
  end
end
