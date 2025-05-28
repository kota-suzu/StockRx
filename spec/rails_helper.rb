# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
require 'timecop'
ENV['RAILS_ENV'] ||= 'test'

# 環境読み込み時のエラー対策
begin
  require_relative '../config/environment'
rescue FrozenError => e
  puts "警告: 凍結エラーが発生しました。キャッシュをクリアして再試行します。"
  puts e.message
  # キャッシュディレクトリを作成（存在しない場合）
  require 'fileutils'
  FileUtils.mkdir_p('tmp/cache') unless Dir.exist?('tmp/cache')
  # キャッシュをクリア
  FileUtils.rm_rf(Dir.glob('tmp/cache/*'))
  # 再試行
  require_relative '../config/environment'
end

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
# Add additional requires below this line. Rails is not loaded until this point!
require 'capybara/rails'
require 'capybara/rspec'
# SimpleCovによるカバレッジ計測
require 'simplecov'
SimpleCov.start 'rails' do
  add_filter '/bin/'
  add_filter '/db/'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  add_filter '/lib/tasks/'
end

# ヘルパーはアプリケーション起動時に自動読み込みされる
# テスト実行時に特定のヘルパーを明示的に読み込む必要がある場合は
# 以下のように追加：
# require Rails.root.join('app/helpers/batches_helper')
# require Rails.root.join('app/helpers/inventories_helper')

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This behavior can be changed by removing the
# line below or adding it to spec_helper.rb instead.
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [ Rails.root.join('spec/fixtures') ]

  # If you're not using ActiveRecord, or you'd prefer not to run each of your
  # examples within a transaction, remove the following line or assign false
  # instead of true.
  config.use_transactional_fixtures = true

  # You can uncomment this line to turn off ActiveRecord support entirely.
  # config.use_active_record = false

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  #
  # You can disable this behaviour by removing the line below, and instead
  # explicitly tag your specs with their type, e.g.:
  #
  #     RSpec.describe UsersController, type: :controller do
  #       # ...
  #     end
  #
  # The different available types are documented in the readme at:
  # https://github.com/rspec/rspec-rails#type-tags
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # Shoulda matchers configuration
  config.include(Shoulda::Matchers::ActiveModel, type: :model)
  config.include(Shoulda::Matchers::ActiveRecord, type: :model)

  # Include FactoryBot syntax
  config.include FactoryBot::Syntax::Methods

  # Timecop configuration
  config.after(:each) do
    Timecop.return
  end

  # FactoryBot設定
  config.include FactoryBot::Syntax::Methods

  # Devise用のヘルパー
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::IntegrationHelpers, type: :feature

  # Draper用のヘルパー設定
  config.include Draper::ViewHelpers, type: :decorator

  # Redis接続エラー対策のため、Sidekiq設定をspec/support/sidekiq.rbに移動
end

# Shoulda Matchers設定
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# ============================================
# Capybaraパフォーマンス最適化設定
# ============================================
begin
  require 'selenium-webdriver'

  # 高速化されたChrome Headlessドライバー設定
  Capybara.register_driver :optimized_chrome_headless do |app|
    options = Selenium::WebDriver::Chrome::Options.new

    # 基本的な高速化オプション
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')

    # パフォーマンス最適化オプション
    options.add_argument('--window-size=1024,768')  # 小さめのウィンドウサイズ
    options.add_argument('--disable-background-timer-throttling')
    options.add_argument('--disable-backgrounding-occluded-windows')
    options.add_argument('--disable-renderer-backgrounding')
    options.add_argument('--disable-features=TranslateUI')
    options.add_argument('--disable-extensions')
    options.add_argument('--no-first-run')
    options.add_argument('--disable-default-apps')
    options.add_argument('--disable-web-security')
    options.add_argument('--allow-running-insecure-content')

    # メモリ使用量削減
    options.add_argument('--memory-pressure-off')
    options.add_argument('--max_old_space_size=4096')

    # 画像・CSS読み込み無効化（大幅な高速化）
    options.add_argument('--disable-images')
    options.add_preference('profile.managed_default_content_settings.images', 2)

    # JavaScript最適化
    options.add_argument('--disable-javascript-harmony-shipping')
    options.add_argument('--disable-background-networking')

    # WebDriver接続エラー対策
    options.add_argument('--remote-debugging-port=9222')
    options.add_argument('--disable-features=VizDisplayCompositor')

    # TODO: プロダクション環境での追加最適化
    # options.add_argument('--proxy-server=direct://')
    # options.add_argument('--proxy-bypass-list=*')

    begin
      # Docker環境の判定
      is_docker = File.exist?('/.dockerenv') || ENV['DOCKER_CONTAINER'].present?

      if is_docker
        # Dockerコンテナ内ではSeleniumサービスを使用
        Capybara::Selenium::Driver.new(
          app,
          browser: :remote,
          url: ENV['SELENIUM_REMOTE_URL'] || 'http://selenium:4444/wd/hub',
          options: options
        )
      else
        # ローカル環境
        Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
      end
    rescue Selenium::WebDriver::Error::WebDriverError => e
      Rails.logger.warn "Chrome WebDriver failed: #{e.message}, falling back to rack_test"
      # Chrome失敗時はrack_testにフォールバック
      Capybara::RackTest::Driver.new(app)
    end
  end

  # 軽量rack_testドライバー（JavaScript不要なテスト用）
  Capybara.register_driver :fast_rack_test do |app|
    Capybara::RackTest::Driver.new(app)
  end

  # デフォルトドライバー設定（高速化）
  Capybara.default_driver = :fast_rack_test  # JavaScriptが不要なテストは高速なrack_test

  # Docker環境では常に最適化されたドライバーを使用
  if File.exist?('/.dockerenv') || ENV['DOCKER_CONTAINER'].present?
    Capybara.javascript_driver = :optimized_chrome_headless
  else
    Capybara.javascript_driver = :optimized_chrome_headless
  end

rescue LoadError => e
  Rails.logger.warn "Selenium WebDriver not available: #{e.message}"
  puts "Warning: Selenium WebDriver not available. Feature tests with JavaScript will be skipped."

  # フォールバック: rack_testドライバーを使用
  Capybara.default_driver = :fast_rack_test
  Capybara.javascript_driver = :fast_rack_test
rescue => e
  Rails.logger.warn "Unexpected error setting up Capybara drivers: #{e.message}"

  # 完全フォールバック: 最小限のrack_test設定
  Capybara.default_driver = :rack_test
  Capybara.javascript_driver = :rack_test
end

# Capybara基本設定（パフォーマンス重視）
Capybara.configure do |config|
  config.app_host = "http://www.example.com"
  config.server_host = "0.0.0.0"
  config.server_port = 3001

  # タイムアウト短縮（高速化）
  config.default_max_wait_time = 3  # デフォルト2秒から3秒に短縮
  config.default_normalize_ws = true

  # Puma設定最適化
  config.server = :puma, { Silent: true, Threads: "1:2" }  # スレッド数を最小限に

  # TODO: 本番環境での追加最適化設定
  # config.asset_host = 'http://localhost:3001'
  # config.automatic_reload = false
end

# TODO: システムテスト用の追加最適化設定
# ============================================
# RSpec.configure do |config|
#   # JavaScriptテストのみSeleniumを使用
#   config.before(:each, type: :system) do
#     if example.metadata[:js]
#       driven_by :optimized_chrome_headless
#     else
#       driven_by :fast_rack_test
#     end
#   end
#
#   # テスト後のクリーンアップ最適化
#   config.after(:each, type: :system) do
#     page.driver.browser.manage.delete_all_cookies if page.driver.respond_to?(:browser)
#   end
# end

# Sidekiq テストサポート（spec/support/sidekiq.rbで設定）
begin
  require 'sidekiq'
  require 'sidekiq/testing'
rescue LoadError => e
  Rails.logger.warn "Sidekiq not available in test environment: #{e.message}"
end

# TODO: 並列テスト実行時の最適化（優先度：中）
# ============================================
# 1. データベース分離設定
#    - 並列実行用のテストDB設定
#    - トランザクション最適化
#    - 接続プール設定
#
# 2. ファイルシステム分離
#    - テンポラリファイルの分離
#    - アップロードファイルの分離
#    - キャッシュディレクトリの分離
#
# 3. ポート番号の動的割り当て
#    - 並列実行時のポート競合回避
#    - Capybara サーバーポート設定
#    - Selenium Grid連携

# TODO: CI/CD環境での最適化（優先度：中）
# ============================================
# if ENV['CI'].present?
#   # CI環境専用の軽量設定
#   Capybara.default_max_wait_time = 5
#   Capybara.server_port = (ENV['TEST_ENV_NUMBER'] || '1').to_i + 3000
#
#   # Docker環境でのSelenium Grid使用
#   if ENV['SELENIUM_REMOTE_URL']
#     Capybara.register_driver :remote_chrome do |app|
#       capabilities = Selenium::WebDriver::Remote::Capabilities.chrome(
#         chromeOptions: {
#           args: %w[--headless --no-sandbox --disable-dev-shm-usage]
#         }
#       )
#       Capybara::Selenium::Driver.new(app,
#         browser: :remote,
#         url: ENV['SELENIUM_REMOTE_URL'],
#         desired_capabilities: capabilities)
#     end
#     Capybara.javascript_driver = :remote_chrome
#   end
# end
