# frozen_string_literal: true

# Capybaraパフォーマンス最適化設定
module CapybaraPerformance
  # テスト高速化のための設定
  def self.configure!
    # 基本的なタイムアウト設定の最適化
    Capybara.configure do |config|
      # タイムアウトを短縮（デフォルト: 2秒）
      config.default_max_wait_time = 2

      # 要素を探す際の再試行間隔を短縮
      config.default_normalize_ws = true

      # アセットのプリコンパイルを無効化（開発環境のみ）
      config.automatic_reload = false if Rails.env.test?

      # サーバーエラー時の詳細表示を無効化（高速化）
      config.raise_server_errors = false
    end

    # データベースクリーナー戦略の最適化
    configure_database_cleaner!

    # 並列実行の設定
    configure_parallel_tests! if ENV['PARALLEL_WORKERS']

    # キャッシュの最適化
    configure_caching!
  end

  private

  def self.configure_database_cleaner!
    RSpec.configure do |config|
      # JSを使用しないテストではトランザクションを使用（高速）
      config.before(:each, type: :feature) do |example|
        if example.metadata[:js]
          # JSテストではtruncationを使用（遅いが必要）
          DatabaseCleaner.strategy = :truncation, {
            except: %w[ar_internal_metadata schema_migrations],
            pre_count: true, # 削除前のカウントを事前実行（高速化）
            reset_ids: false # IDリセットを無効化（高速化）
          }
        else
          # 非JSテストではトランザクションを使用（高速）
          DatabaseCleaner.strategy = :transaction
        end
      end

      config.before(:each, type: :feature) do
        DatabaseCleaner.start
      end

      config.after(:each, type: :feature) do
        DatabaseCleaner.clean
      end
    end
  end

  def self.configure_parallel_tests!
    # 並列実行時のポート設定
    test_number = ENV['TEST_ENV_NUMBER'].to_i
    Capybara.server_port = 3000 + test_number

    # WebDriverのポート設定
    Capybara.register_driver :parallel_chrome_headless do |app|
      options = Selenium::WebDriver::Chrome::Options.new

      # 基本的な高速化オプション
      options.add_argument('--headless=new') # 新しいheadlessモード（高速）
      options.add_argument('--no-sandbox')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--disable-gpu')
      options.add_argument('--disable-web-security')
      options.add_argument('--window-size=1280,800')

      # 並列実行用のポート設定
      options.add_argument("--remote-debugging-port=#{9222 + test_number}")

      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end

    Capybara.javascript_driver = :parallel_chrome_headless
  end

  def self.configure_caching!
    # テスト実行時のキャッシュ設定
    if Rails.env.test?
      # アセットキャッシュを有効化（初回以降高速化）
      Rails.application.config.assets.cache_store = :memory_store

      # ビューキャッシュを有効化
      Rails.application.config.action_controller.perform_caching = true
      Rails.application.config.cache_store = :memory_store
    end
  end
end

# RSpec設定に統合
RSpec.configure do |config|
  # E2Eテストの前処理最適化
  config.before(:suite) do
    # アセットのプリコンパイル（一度だけ実行）
    if ENV['PRECOMPILE_ASSETS'] != 'false'
      puts "アセットをプリコンパイル中..."
      system('RAILS_ENV=test bundle exec rails assets:precompile')
    end

    # データベースのクリーンアップ
    DatabaseCleaner.clean_with(:truncation) if defined?(DatabaseCleaner)
  end

  config.after(:suite) do
    # プリコンパイルしたアセットのクリーンアップ
    if ENV['CLEANUP_ASSETS'] != 'false'
      puts "アセットをクリーンアップ中..."
      system('RAILS_ENV=test bundle exec rails assets:clobber')
    end
  end

  # JSを使わないテストでは高速なドライバーを使用
  config.before(:each, type: :feature) do |example|
    unless example.metadata[:js]
      Capybara.current_driver = :rack_test
    end
  end

  # スクリーンショットを無効化（高速化）
  config.before(:each, type: :feature) do
    Capybara::Screenshot.autosave_on_failure = false if defined?(Capybara::Screenshot)
  end
end

# 設定を有効化
CapybaraPerformance.configure!
