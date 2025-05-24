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
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

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
# 開発環境向けエラーハンドリング設定
# ============================================
# TODO: 運用監視強化 - ログ・通知連携
# REF: README.md - エラーハンドリング関連
# ============================================

# SSL/HTTPSエラーの対策（開発環境）
# ブラウザが誤ってHTTPSでアクセスした場合のエラーを軽減
lowlevel_error_handler do |error|
  if error.message.include?("SSL connection")
    Rails.logger.warn "SSL接続エラー検知: ブラウザがHTTPS（https://localhost:3000）でアクセスしている可能性があります。HTTP（http://localhost:3000）を使用してください。"
  end

  # デフォルトのエラーハンドリングに委譲
  true
end

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
    puts "="*60 + "\n"
  end

  # 統計情報の表示
  stats_print_interval = 30
end
