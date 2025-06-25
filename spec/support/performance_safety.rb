# frozen_string_literal: true

# パフォーマンス測定セキュリティ強化（CLAUDE.md準拠）
# メタ認知: セキュリティと利便性のバランス最適化
# 横展開: 他のプロジェクトでも同様のセキュリティ対策適用可能

module PerformanceSafety
  # セキュリティ強化版メモリ測定
  def self.safe_memory_measurement(&block)
    return yield unless Rails.env.test? && ENV['SHOW_MEMORY'] == 'true'

    begin
      start_memory = safe_get_memory_usage
      result = yield
      end_memory = safe_get_memory_usage

      memory_diff = end_memory - start_memory
      Rails.logger.info "💾 Memory usage: #{memory_diff}KB"

      result
    rescue => e
      Rails.logger.warn "Memory measurement failed: #{e.message}"
      yield
    end
  end

  # エッジケース対応版テスト実行
  def self.safe_test_execution(test_count_limit: 10000, &block)
    if ENV['TEST_COUNT_CHECK'] == 'true'
      estimated_count = RSpec.world.example_count
      if estimated_count > test_count_limit
        Rails.logger.warn "Large test suite detected: #{estimated_count} tests"
        return yield if ENV['FORCE_LARGE_TESTS'] == 'true'

        raise "Test count exceeds limit: #{estimated_count} > #{test_count_limit}"
      end
    end

    yield
  end

  # 並行処理安全性チェック
  def self.check_concurrency_safety
    return true unless ENV['CHECK_CONCURRENCY'] == 'true'

    # プロセス間ロックファイルの確認
    lock_file = Rails.root.join('tmp', 'test_execution.lock')

    if File.exist?(lock_file)
      pid = File.read(lock_file).strip.to_i
      if process_running?(pid)
        Rails.logger.warn "Another test process detected: PID #{pid}"
        return false
      else
        File.delete(lock_file)
      end
    end

    # ロックファイル作成
    File.write(lock_file, Process.pid)

    at_exit { File.delete(lock_file) if File.exist?(lock_file) }
    true
  end

  private

  # セキュリティ強化: コマンドインジェクション対策
  def self.safe_get_memory_usage
    return 0 unless Rails.env.test?

    # プロセスIDのサニタイズ
    pid = Process.pid.to_i
    return 0 unless pid > 0 && pid < 999999

    # 安全なコマンド実行
    result = `ps -o rss= -p #{pid} 2>/dev/null`.strip
    memory_kb = result.to_i

    # 異常値チェック（10GBを超える場合は異常）
    memory_kb > 10_485_760 ? 0 : memory_kb
  rescue
    0
  end

  # プロセス存在チェック
  def self.process_running?(pid)
    return false unless pid > 0

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue
    false
  end
end

# RSpec統合
RSpec.configure do |config|
  config.before(:suite) do
    # 並行処理安全性チェック
    unless PerformanceSafety.check_concurrency_safety
      abort "Concurrent test execution detected. Use FORCE_CONCURRENT=true to override."
    end
  end

  # SAVEPOINT競合回避: database_cleanerとの競合を防ぐ
  config.around(:each) do |example|
    # database_cleanerが有効な場合はトランザクション管理を任せる
    begin
      db_cleaner_strategy = DatabaseCleaner[:active_record].strategy if defined?(DatabaseCleaner)
    rescue
      db_cleaner_strategy = :transaction  # デフォルト
    end

    if example.metadata[:use_database_cleaner] != false &&
       defined?(DatabaseCleaner) && db_cleaner_strategy == :transaction

      # database_cleanerに制御を委任
      example.run
    else
      # 独自のセーフティ機能を適用
      PerformanceSafety.safe_test_execution do
        PerformanceSafety.safe_memory_measurement do
          example.run
        end
      end
    end
  end
end

# TODO: Phase 2 - 高度なセキュリティ監視（推定1日）
# 優先度: 中（セキュリティ強化）
# 実装内容:
#   - リソース使用量の異常検知
#   - 悪意のあるテストコードの検出
#   - テスト実行環境の完全性検証
#   - セキュリティイベントログ記録
# 横展開確認:
#   - 本番環境セキュリティ監視との連携
#   - CI/CDパイプラインセキュリティ強化
#   - 他プロジェクトへのセキュリティベストプラクティス適用
