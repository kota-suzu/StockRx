#!/usr/bin/env ruby
# frozen_string_literal: true

# ============================================
# ActiveJob ログ出力の実際の確認スクリプト
# ============================================
# 目的: 実際のログファイルで機密情報がフィルタリングされていることを確認

require_relative './config/environment'

class JobLogVerifier
  def initialize
    @results = {}
  end

  def run_verification
    puts "🔍 **ActiveJob ログ出力セキュリティ検証**"
    puts "=" * 60

    # ログファイルの場所を確認
    log_path = Rails.root.join("log", "development.log")
    puts "📄 ログファイル: #{log_path}"

    # ログをクリア
    clear_logs

    # テストジョブを実行
    run_test_jobs

    # ログを解析
    analyze_logs(log_path)

    # 結果を表示
    display_results
  end

  private

  def clear_logs
    log_path = Rails.root.join("log", "development.log")
    File.truncate(log_path, 0) if File.exist?(log_path)
    puts "📝 ログファイルをクリアしました"
  end

  def run_test_jobs
    puts "\n🧪 テストジョブを実行中..."

    # テスト1: 基本的な機密情報
    test_basic_sensitive_data

    # テスト2: API関連ジョブ
    test_api_job

    # テスト3: ファイルパス関連
    test_file_path_job

    puts "✅ 全テストジョブの実行が完了しました"
  end

  def test_basic_sensitive_data
    puts "  📋 基本機密情報テスト実行中..."

    # テスト用ジョブクラスを動的作成
    basic_test_job = Class.new(ApplicationJob) do
      def perform(public_data, sensitive_data)
        Rails.logger.info "Basic test job executing"
        Rails.logger.info "Public data: #{public_data}"
        # 意図的に機密情報をログ出力しようとする（フィルタリングされるはず）
      end
    end

    Object.const_set('BasicTestJob', basic_test_job) unless defined?(BasicTestJob)

    BasicTestJob.perform_now(
      'public_information',
      {
        api_token: 'test_secret_key_12345',
        password: 'super_secret_password_123',
        client_secret: 'test_abcdefghijk',
        user_email: 'confidential@company.internal'
      }
    )
  end

  def test_api_job
    puts "  🌐 API連携ジョブテスト実行中..."

    ExternalApiSyncJob.perform_now(
      'test_provider',
      'test_sync',
      {
        api_token: 'test_external_api_key_67890',
        webhook_secret: 'whsec_test_webhook_secret',
        credentials: {
          username: 'api_service_user',
          password: 'api_service_password_secret'
        }
      }
    )
  end

  def test_file_path_job
    puts "  📁 ファイルパステスト実行中..."

    # 管理者を取得
    admin = begin
      Admin.first || create_dummy_admin
    rescue
      create_dummy_admin
    end

    begin
      ImportInventoriesJob.perform_now(
        '/sensitive/path/to/import_file_secret.csv',
        admin.id,
        {
          admin_credentials: 'admin_access_token_secret',
          file_metadata: 'sensitive_file_information'
        }
      )
    rescue => e
      # ファイルが存在しないエラーは想定内
      Rails.logger.info "Expected file error in test: #{e.class.name}"
    end
  end

  def create_dummy_admin
    Class.new do
      def id; 999; end
      def email; 'test.admin@example.com'; end
    end.new
  end

  def analyze_logs(log_path)
    puts "\n📊 ログ解析中..."

    unless File.exist?(log_path)
      puts "❌ ログファイルが見つかりません: #{log_path}"
      return
    end

    log_content = File.read(log_path)
    puts "📏 ログサイズ: #{log_content.length}文字"

    # 検出テスト
    @results = {
      secrets_detected: detect_secrets_in_logs(log_content),
      filter_markers_found: detect_filter_markers(log_content),
      job_events_logged: detect_job_events(log_content)
    }
  end

  def detect_secrets_in_logs(content)
    secrets_found = []

    # 検出すべき機密情報パターン
    sensitive_patterns = [
      'test_secret_key_12345',
      'super_secret_password_123',
      'test_abcdefghijk',
      'confidential@company.internal',
      'test_external_api_key_67890',
      'whsec_test_webhook_secret',
      'api_service_password_secret',
      'admin_access_token_secret',
      '/sensitive/path/to/'
    ]

    sensitive_patterns.each do |pattern|
      if content.include?(pattern)
        secrets_found << pattern
        puts "⚠️  機密情報がログに検出されました: #{pattern[0..20]}..."
      end
    end

    secrets_found
  end

  def detect_filter_markers(content)
    markers = []
    filter_patterns = [ '[FILTERED]', '[SANITIZATION_FAILED]', '[FILTERED_KEY]' ]

    filter_patterns.each do |marker|
      count = content.scan(marker).length
      if count > 0
        markers << { marker: marker, count: count }
        puts "✅ フィルターマーカー検出: #{marker} (#{count}回)"
      end
    end

    markers
  end

  def detect_job_events(content)
    events = []
    job_events = [ 'job_started', 'job_completed', 'job_failed' ]

    job_events.each do |event|
      count = content.scan(event).length
      if count > 0
        events << { event: event, count: count }
        puts "📋 ジョブイベント検出: #{event} (#{count}回)"
      end
    end

    events
  end

  def display_results
    puts "\n" + "=" * 60
    puts "📊 **セキュリティ検証結果**"
    puts "=" * 60

    # セキュリティ評価
    security_score = calculate_security_score

    puts "\n🏆 **セキュリティスコア: #{security_score}%**"

    if security_score >= 90
      puts "🎉 **優秀！** セキュリティ対策が適切に機能しています"
      puts "✅ 機密情報の漏洩リスクは最小限です"
    elsif security_score >= 70
      puts "⚠️  **注意** 一部改善が必要です"
      puts "🔧 セキュリティ設定の見直しを推奨します"
    else
      puts "❌ **危険** セキュリティ対策に問題があります"
      puts "🚨 緊急でセキュリティ設定の修正が必要です"
    end

    puts "\n📈 **詳細結果:**"
    puts "  機密情報検出数: #{@results[:secrets_detected].length}件"
    puts "  フィルターマーカー: #{@results[:filter_markers_found].length}種類"
    puts "  ジョブイベント: #{@results[:job_events_logged].length}種類"

    # ログサンプル表示
    display_log_sample
  end

  def calculate_security_score
    base_score = 100

    # 機密情報が検出された場合は大幅減点
    secrets_penalty = @results[:secrets_detected].length * 20
    base_score -= secrets_penalty

    # フィルターマーカーがない場合は減点
    if @results[:filter_markers_found].empty?
      base_score -= 10
    end

    # ジョブイベントがログされていない場合は減点
    if @results[:job_events_logged].empty?
      base_score -= 5
    end

    [ base_score, 0 ].max
  end

  def display_log_sample
    puts "\n📝 **ログサンプル（最新20行）:**"
    puts "-" * 40

    log_path = Rails.root.join("log", "development.log")
    if File.exist?(log_path)
      lines = File.readlines(log_path).last(20)
      lines.each_with_index do |line, index|
        # 機密情報が含まれている行は強調表示
        prefix = @results[:secrets_detected].any? { |secret| line.include?(secret) } ? "🔴 " : "   "
        puts "#{prefix}#{index + 1}: #{line.chomp[0..100]}..."
      end
    else
      puts "ログファイルが見つかりません"
    end

    puts "-" * 40
  end
end

# 実行
if __FILE__ == $0
  verifier = JobLogVerifier.new
  verifier.run_verification
end
