# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# to prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.

# ============================================
# スレッド・ワーカー設定（環境別最適化）
# ============================================
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# 環境別ワーカー数設定
if Rails.env.production?
  # 本番環境: CPUコア数ベース
  workers ENV.fetch("WEB_CONCURRENCY", 2)

  # クラスターモード時の設定
  worker_timeout 30
  preload_app!

  # フォークされたワーカープロセス用のDB接続再確立
  on_worker_boot do
    ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
  end

  # シャットダウン時のクリーンアップ
  on_worker_shutdown do
    Rails.logger.info "Worker #{Process.pid} shutting down"
  end
elsif Rails.env.development?
  # 開発環境: 単一ワーカーで警告を無効化
  workers 0  # 単一プロセスモード
  silence_single_worker_warning if respond_to?(:silence_single_worker_warning)
else
  # テスト環境等: 最小リソース
  workers 0
end

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Bind to all interfaces in development for Docker compatibility
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 3000)}"

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# ============================================
# エラーハンドリング・セキュリティ設定
# ============================================
# TODO: 運用監視強化 - ログ・通知連携（優先度：高）
# REF: README.md - エラーハンドリング関連
# TODO: 以下の機能を段階的に実装
# 1. 構造化ログ出力（JSON形式）
#    - エラータイプ別の詳細分類
#    - リクエスト情報（IP、User-Agent等）
#    - パフォーマンスメトリクス
# 2. アラート・通知システム
#    - Slack/Teams通知
#    - メール通知（緊急時）
#    - Dashboard連携
# 3. セキュリティ強化
#    - 異常アクセスパターンの検出
#    - レート制限・DDoS対策
#    - 不正リクエストの自動ブロック
# ============================================

# SSL/HTTPSエラーの対策（開発環境）
# ブラウザが誤ってHTTPSでアクセスした場合のエラーを軽減
lowlevel_error_handler do |error, env|
  begin
    # エラー詳細のログ記録
    error_details = {
      error_class: error.class.name,
      error_message: error.message,
      request_method: env["REQUEST_METHOD"],
      request_path: env["REQUEST_PATH"] || env["PATH_INFO"],
      remote_addr: env["REMOTE_ADDR"],
      user_agent: env["HTTP_USER_AGENT"],
      timestamp: Time.current.iso8601
    }

    # SSL関連エラーの特別処理
    if error.message.to_s.include?("SSL") ||
       error.message.to_s.include?("TLS") ||
       error.message.to_s.include?("certificate")

      Rails.logger.warn "SSL接続エラー検知: ブラウザがHTTPS（https://localhost:3000）でアクセスしている可能性があります。HTTP（http://localhost:3000）を使用してください。"

      # 構造化ログ出力
      Rails.logger.warn({
        event: "ssl_connection_error",
        suggestion: "Use HTTP instead of HTTPS for development",
        **error_details
      }.to_json)

      # 開発環境では簡易的なHTTP リダイレクト応答
      if Rails.env.development?
        [
          400,
          {
            "Content-Type" => "text/plain; charset=utf-8",
            "X-Error-Type" => "SSL-Connection-Error"
          },
          [ "SSL Error: Please use HTTP (not HTTPS) for development server\nURL: http://localhost:#{ENV.fetch('PORT', 3000)}" ]
        ]
      else
        # 本番環境では標準エラーハンドリング
        [ 500, { "Content-Type" => "text/plain" }, [ "Internal Server Error" ] ]
      end

    # その他のエラー（標準エラーハンドリング）
    else
      Rails.logger.error({
        event: "lowlevel_server_error",
        **error_details
      }.to_json)

      # TODO: 本番環境での通知システム連携
      # if Rails.env.production?
      #   AlertManager.notify_error(error, env)
      # end

      # 標準エラーレスポンス
      [ 500, { "Content-Type" => "text/plain" }, [ "Internal Server Error" ] ]
    end

  rescue => handler_error
    # エラーハンドラー自体のエラー対策
    Rails.logger.error "Error in lowlevel_error_handler: #{handler_error.message}"
    [ 500, { "Content-Type" => "text/plain" }, [ "Internal Server Error" ] ]
  end
end

# ============================================
# パフォーマンス・監視設定
# ============================================
# TODO: パフォーマンス監視強化（優先度：中）
# 1. メトリクス収集
#    - レスポンス時間統計
#    - スループット監視
#    - メモリ使用量追跡
# 2. アラート設定
#    - 応答時間劣化検知
#    - メモリリーク検出
#    - エラー率増加通知
# 3. 最適化提案
#    - 自動チューニング機能
#    - 設定推奨値の提案
# ============================================

# 開発環境での詳細情報出力
if Rails.env.development?
  # サーバー起動時の情報表示
  on_booted do
    puts "\n" + "="*60
    puts "  🚀 StockRx サーバー起動完了"
    puts "="*60
    puts "  HTTP: http://localhost:#{ENV.fetch('PORT', 3000)}"
    puts "  注意: HTTPS（https://）は使用しないでください"
    puts "  ヘルスチェック: make diagnose"
    puts "  Sidekiq Web UI: http://localhost:#{ENV.fetch('PORT', 3000)}/admin/sidekiq"
    puts "="*60 + "\n"
  end

  # 統計情報の表示（30秒間隔）
  stats_print_interval = 30
end

# 本番環境でのセキュリティ強化設定
if Rails.env.production?
  # タイムアウト設定
  worker_timeout 60
  worker_boot_timeout 30

  # プロセス管理
  worker_shutdown_timeout 15

  # TODO: 本番環境セキュリティ強化
  # - SSL/TLS 強制化
  # - セキュリティヘッダー設定
  # - レート制限実装
  # - 侵入検知システム連携
end

# ============================================
# TODO: ログ・監視システム統合（優先度：高）
# ============================================
# 1. 構造化ログ統合
#    - JSON形式での詳細ログ出力
#    - ログレベル別の処理分岐
#    - ELK Stack / Splunk 連携準備
#
# 2. APM（Application Performance Monitoring）統合
#    - New Relic / Datadog 連携
#    - カスタムメトリクス定義
#    - 分散トレーシング対応
#
# 3. ヘルスチェック・診断機能強化
#    - 詳細ヘルスチェックエンドポイント
#    - 依存サービス監視
#    - 自動復旧メカニズム
#
# 4. 災害復旧・高可用性対応
#    - グレースフルシャットダウン
#    - ローリングデプロイメント対応
#    - フェイルオーバー機能

# ============================================
# TODO: セキュリティ強化（優先度：高）
# ============================================
# 1. アクセス制御
#    - IP制限・地理的制限
#    - レート制限（DDoS対策）
#    - 認証・認可強化
#
# 2. 通信セキュリティ
#    - SSL/TLS設定強化
#    - HSTS（HTTP Strict Transport Security）
#    - セキュリティヘッダー設定
#
# 3. 監査・コンプライアンス
#    - アクセスログ詳細化
#    - セキュリティイベント記録
#    - コンプライアンス報告機能