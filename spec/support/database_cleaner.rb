# frozen_string_literal: true

# データベースクリーンアップ戦略（CLAUDE.md準拠）
# メタ認知: テスト間の独立性確保とパフォーマンス最適化のバランス
# 横展開: 他のRailsプロジェクトでも同様のクリーンアップ戦略適用可能

require 'database_cleaner/active_record'

# DatabaseCleaner設定 (新しいAPI使用)
DatabaseCleaner[:active_record].strategy = :transaction

RSpec.configure do |config|
  # トランザクション戦略による高速化
  config.use_transactional_fixtures = true

  # データベースクリーンアップ設定（最適化版）
  config.before(:suite) do
    # テスト開始前にデータベースを一度だけクリーンアップ
    if ENV['CLEAN_DB_ON_START'] == 'true'
      DatabaseCleaner[:active_record].clean_with(:truncation)
    end
  end

  config.before(:each) do
    # 通常はトランザクション戦略（高速）
    DatabaseCleaner[:active_record].strategy = :transaction

    # MySQLトランザクション競合対策
    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      # トランザクション分離レベルを READ COMMITTED に設定
      ActiveRecord::Base.connection.execute('SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED')
      # ロック待機タイムアウトを短縮（デッドロック早期検出）
      ActiveRecord::Base.connection.execute('SET SESSION innodb_lock_wait_timeout = 5')
      # 外部キーチェックを無効化（テスト環境のみ）
      ActiveRecord::Base.connection.execute('SET SESSION foreign_key_checks = 0')
    end

    DatabaseCleaner[:active_record].start
  rescue => e
    Rails.logger.warn "DatabaseCleaner開始警告: #{e.message}"
    DatabaseCleaner[:active_record].start
  end

  config.before(:each, type: :feature) do
    # フィーチャーテストのみtruncation戦略
    DatabaseCleaner[:active_record].strategy = :truncation
    DatabaseCleaner[:active_record].start
  end

  config.before(:each, js: true) do
    # JavaScriptテストのみtruncation戦略
    DatabaseCleaner[:active_record].strategy = :truncation
    DatabaseCleaner[:active_record].start
  end

  config.after(:each) do
    # テスト後のクリーンアップ
    DatabaseCleaner[:active_record].clean
  end

  config.after(:suite) do
    # テストスイート終了後の最終クリーンアップ
    DatabaseCleaner[:active_record].clean_with(:truncation) if ENV['CLEAN_DB_ON_END'] == 'true'
  end

  # FactoryBotとの連携最適化
  config.before(:each) do
    # FactoryBotシーケンスの最適化
    unless ENV['DISABLE_FACTORY_RESET'] == 'true'
      FactoryBot.reload if defined?(FactoryBot)
    end
  end

  # MySQLデッドロック対策（2025年6月25日追加）
  config.around(:each) do |example|
    # デッドロック発生時の再試行機能
    retry_count = 0
    max_retries = 3

    begin
      example.run
    rescue ActiveRecord::StatementInvalid, ActiveRecord::Deadlocked => e
      # SAVEPOINT関連エラーの特別処理
      if e.message.include?('SAVEPOINT') ||
         e.message.include?('does not exist') ||
         e.message.include?('Table definition has changed') ||
         e.message.include?('Lock wait timeout exceeded') ||
         e.message.include?('Deadlock found') ||
         e.is_a?(ActiveRecord::Deadlocked)

        retry_count += 1
        if retry_count <= max_retries
          puts "MySQLトランザクションエラー (#{retry_count}/#{max_retries}): #{e.message}"

          # SAVEPOINT問題の場合は特別な処理
          if e.message.include?('SAVEPOINT') || e.message.include?('does not exist')
            puts "SAVEPOINT問題を検出 - トランザクション完全リセット実行中"

            # 全トランザクションをロールバック
            begin
              ActiveRecord::Base.connection.rollback_db_transaction while ActiveRecord::Base.connection.transaction_open?
            rescue => rollback_error
              puts "ロールバック警告: #{rollback_error.message}"
            end

            # 接続プールを完全リセット
            ActiveRecord::Base.connection_pool.disconnect!
            ActiveRecord::Base.connection_pool.clear_reloadable_connections!
            ActiveRecord::Base.establish_connection
          end

          # DatabaseCleanerのクリーンアップ
          begin
            DatabaseCleaner[:active_record].clean
          rescue => cleanup_error
            puts "DatabaseCleaner警告: #{cleanup_error.message}"
          end

          # スキーマキャッシュクリアとリトライ
          ActiveRecord::Base.connection.schema_cache.clear! if ActiveRecord::Base.connection.respond_to?(:schema_cache)

          sleep(0.1 * retry_count)  # 指数バックオフ
          retry
        else
          puts "MySQLトランザクションエラー: 最大再試行回数に達しました - #{e.message}"
          raise e
        end
      else
        raise e
      end
    end
  end
end

# TODO: Phase 2 - より高度なクリーンアップ戦略（推定1日）
# 優先度: 中（さらなる高速化）
# 実装内容:
#   - テーブル別選択的クリーンアップ
#   - テストタイプ別最適化戦略
#   - 並列実行時の排他制御
#   - クリーンアップパフォーマンス監視
# 横展開確認:
#   - CI環境での最適化設定
#   - 大規模データでの検証
#   - メモリリーク防止機能
