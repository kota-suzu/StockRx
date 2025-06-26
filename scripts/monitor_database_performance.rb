#!/usr/bin/env ruby
# frozen_string_literal: true

# Team 6: データベースパフォーマンス監視スクリプト
# ===============================================
# 用途: リアルタイムでデータベースパフォーマンスを監視
# 実行: ruby scripts/monitor_database_performance.rb
# ===============================================

require 'bundler/setup'
require_relative '../config/environment'

class DatabasePerformanceMonitor
  ALERT_THRESHOLDS = {
    slow_query_time: 1.0,           # 1秒以上のクエリをアラート
    active_connections: 80,         # 80%以上の接続使用率でアラート
    deadlock_rate: 0.001,          # 0.1%以上のデッドロック率でアラート
    innodb_buffer_hit_rate: 95.0    # 95%未満のバッファヒット率でアラート
  }.freeze
  
  def initialize
    @connection = ActiveRecord::Base.connection
    @start_time = Time.current
  end
  
  def monitor(duration: 300) # デフォルト5分間監視
    puts "=" * 60
    puts "StockRx データベースパフォーマンス監視開始"
    puts "監視時間: #{duration}秒"
    puts "開始時刻: #{@start_time}"
    puts "=" * 60
    
    end_time = @start_time + duration.seconds
    
    while Time.current < end_time
      collect_and_display_metrics
      check_alerts
      sleep 10 # 10秒間隔で監視
    end
    
    puts "\n監視終了: #{Time.current}"
    generate_summary_report
  end
  
  private
  
  def collect_and_display_metrics
    metrics = collect_performance_metrics
    display_metrics(metrics)
  end
  
  def collect_performance_metrics
    {
      timestamp: Time.current,
      slow_queries: get_slow_query_count,
      active_connections: get_active_connections,
      max_connections: get_max_connections,
      innodb_metrics: get_innodb_metrics,
      table_metrics: get_table_metrics,
      index_usage: get_index_usage_stats
    }
  end
  
  def display_metrics(metrics)
    system('clear') # 画面をクリア
    
    puts "=" * 60
    puts "StockRx データベースパフォーマンス監視"
    puts "更新時刻: #{metrics[:timestamp].strftime('%Y-%m-%d %H:%M:%S')}"
    puts "=" * 60
    
    # 接続情報
    connection_usage = (metrics[:active_connections].to_f / metrics[:max_connections] * 100).round(2)
    puts "🔗 接続状況:"
    puts "  アクティブ接続: #{metrics[:active_connections]}/#{metrics[:max_connections]} (#{connection_usage}%)"
    
    # スロークエリ
    puts "\n⏱️  クエリパフォーマンス:"
    puts "  スロークエリ数: #{metrics[:slow_queries]} 件"
    
    # InnoDBメトリクス
    innodb = metrics[:innodb_metrics]
    if innodb[:buffer_hit_rate]
      puts "\n💾 InnoDBバッファプール:"
      puts "  ヒット率: #{innodb[:buffer_hit_rate]}%"
      puts "  読み込み要求: #{innodb[:buffer_pool_reads]}"
      puts "  ディスク読み込み: #{innodb[:buffer_pool_read_requests]}"
    end
    
    # テーブルメトリクス
    puts "\n📊 テーブル統計:"
    metrics[:table_metrics].each do |table_stat|
      puts "  #{table_stat[:table_name]}: #{table_stat[:row_count]} 行 (#{table_stat[:size_mb]} MB)"
    end
    
    # インデックス使用状況
    puts "\n🔍 インデックス使用状況:"
    metrics[:index_usage].each do |index_stat|
      puts "  #{index_stat[:table_name]}: #{index_stat[:index_usage_percent]}% のクエリでインデックス使用"
    end
  end
  
  def get_slow_query_count
    result = @connection.execute("SHOW GLOBAL STATUS LIKE 'Slow_queries'")
    result.first[1].to_i
  rescue
    0
  end
  
  def get_active_connections
    result = @connection.execute("SHOW STATUS LIKE 'Threads_connected'")
    result.first[1].to_i
  rescue
    0
  end
  
  def get_max_connections
    result = @connection.execute("SHOW VARIABLES LIKE 'max_connections'")
    result.first[1].to_i
  rescue
    100
  end
  
  def get_innodb_metrics
    metrics = {}
    
    # バッファプールヒット率
    begin
      pool_reads = @connection.execute("SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_reads'").first[1].to_f
      pool_read_requests = @connection.execute("SHOW GLOBAL STATUS LIKE 'Innodb_buffer_pool_read_requests'").first[1].to_f
      
      if pool_read_requests > 0
        hit_rate = ((pool_read_requests - pool_reads) / pool_read_requests * 100).round(2)
        metrics[:buffer_hit_rate] = hit_rate
        metrics[:buffer_pool_reads] = pool_reads.to_i
        metrics[:buffer_pool_read_requests] = pool_read_requests.to_i
      end
    rescue => e
      puts "InnoDBメトリクス取得エラー: #{e.message}"
    end
    
    metrics
  end
  
  def get_table_metrics
    # StockRxの主要テーブルの統計
    tables = %w[inventories store_inventories inventory_logs audit_logs inter_store_transfers]
    
    tables.map do |table|
      begin
        result = @connection.execute(<<-SQL)
          SELECT 
            '#{table}' as table_name,
            TABLE_ROWS as row_count,
            ROUND((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024, 2) as size_mb
          FROM information_schema.TABLES 
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '#{table}'
        SQL
        
        row = result.first
        {
          table_name: row[0],
          row_count: row[1].to_i,
          size_mb: row[2].to_f
        }
      rescue
        {
          table_name: table,
          row_count: 0,
          size_mb: 0.0
        }
      end
    end
  end
  
  def get_index_usage_stats
    # インデックス使用率の簡易計算
    tables = %w[inventories store_inventories audit_logs]
    
    tables.map do |table|
      begin
        # Handler_read_keyとHandler_read_rnd_nextの比率でインデックス使用率を推定
        key_reads = @connection.execute("SHOW GLOBAL STATUS LIKE 'Handler_read_key'").first[1].to_f
        rnd_reads = @connection.execute("SHOW GLOBAL STATUS LIKE 'Handler_read_rnd_next'").first[1].to_f
        
        total_reads = key_reads + rnd_reads
        index_usage_percent = total_reads > 0 ? (key_reads / total_reads * 100).round(2) : 0
        
        {
          table_name: table,
          index_usage_percent: index_usage_percent
        }
      rescue
        {
          table_name: table,
          index_usage_percent: 0
        }
      end
    end
  end
  
  def check_alerts
    metrics = collect_performance_metrics
    
    # 接続数アラート
    connection_usage = metrics[:active_connections].to_f / metrics[:max_connections] * 100
    if connection_usage > ALERT_THRESHOLDS[:active_connections]
      alert("高い接続使用率", "#{connection_usage}% (閾値: #{ALERT_THRESHOLDS[:active_connections]}%)")
    end
    
    # バッファヒット率アラート
    if metrics[:innodb_metrics][:buffer_hit_rate]
      hit_rate = metrics[:innodb_metrics][:buffer_hit_rate]
      if hit_rate < ALERT_THRESHOLDS[:innodb_buffer_hit_rate]
        alert("低いバッファヒット率", "#{hit_rate}% (閾値: #{ALERT_THRESHOLDS[:innodb_buffer_hit_rate]}%)")
      end
    end
  end
  
  def alert(type, message)
    timestamp = Time.current.strftime('%H:%M:%S')
    puts "\n🚨 [#{timestamp}] アラート: #{type} - #{message}"
  end
  
  def generate_summary_report
    puts "\n" + "=" * 60
    puts "監視サマリーレポート"
    puts "=" * 60
    
    puts "監視期間: #{@start_time.strftime('%H:%M:%S')} - #{Time.current.strftime('%H:%M:%S')}"
    
    # 最終的なメトリクスを表示
    final_metrics = collect_performance_metrics
    
    puts "\n📊 最終統計:"
    puts "  最大接続数: #{final_metrics[:max_connections]}"
    puts "  現在の接続数: #{final_metrics[:active_connections]}"
    puts "  スロークエリ数: #{final_metrics[:slow_queries]}"
    
    if final_metrics[:innodb_metrics][:buffer_hit_rate]
      puts "  バッファヒット率: #{final_metrics[:innodb_metrics][:buffer_hit_rate]}%"
    end
    
    puts "\n💡 推奨事項:"
    suggest_optimizations(final_metrics)
  end
  
  def suggest_optimizations(metrics)
    connection_usage = metrics[:active_connections].to_f / metrics[:max_connections] * 100
    
    if connection_usage > 70
      puts "  - 接続プール設定の見直しを検討してください"
    end
    
    if metrics[:innodb_metrics][:buffer_hit_rate] && metrics[:innodb_metrics][:buffer_hit_rate] < 95
      puts "  - InnoDBバッファプールサイズの増加を検討してください"
    end
    
    if metrics[:slow_queries] > 100
      puts "  - スロークエリの詳細分析と最適化を実施してください"
    end
    
    puts "  - 定期的なテーブル統計情報の更新を実施してください"
    puts "  - インデックス使用状況の詳細分析を実施してください"
  end
end

# スクリプト実行
if __FILE__ == $0
  monitor = DatabasePerformanceMonitor.new
  
  duration = ARGV[0]&.to_i || 300 # デフォルト5分
  puts "データベースパフォーマンス監視を#{duration}秒間実行します..."
  puts "Ctrl+Cで中断できます"
  
  begin
    monitor.monitor(duration: duration)
  rescue Interrupt
    puts "\n\n監視を中断しました"
  rescue => e
    puts "エラーが発生しました: #{e.message}"
    puts e.backtrace if ENV['DEBUG']
  end
end