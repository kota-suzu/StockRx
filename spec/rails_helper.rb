# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'

# 環境読み込み時のエラー対策
begin
  # Rails 7.2で既知の凍結配列問題対策
  ENV["DISABLE_BOOTSNAP"] = "1" if ENV["CI"] || ENV["RAILS_ENV"] == "test"
  ENV["RAILS_STRICT_AUTOLOAD"] = "0" if ENV["CI"] || ENV["RAILS_ENV"] == "test"

  # Zeitwerk関連の問題を未然に防ぐ
  if defined?(Rails) && Rails.respond_to?(:autoloaders) && Rails.autoloaders.respond_to?(:main)
    Rails.autoloaders.main.reload rescue nil
  end

  require_relative '../config/environment'
rescue FrozenError => e
  puts "警告: 凍結エラーが発生しました。キャッシュをクリアして再試行します。"
  puts e.message
  # キャッシュディレクトリを作成（存在しない場合）
  require 'fileutils'
  FileUtils.mkdir_p('tmp/cache') unless Dir.exist?('tmp/cache')
  # キャッシュを完全にクリア
  %w[bootsnap bootsnap-compile-cache bootsnap-load-path-cache].each do |dir|
    cache_dir = File.join('tmp/cache', dir)
    FileUtils.rm_rf(cache_dir) if Dir.exist?(cache_dir)
    FileUtils.mkdir_p(cache_dir)
    FileUtils.chmod(0777, cache_dir) rescue nil
  end

  # アプリケーション再起動を示すファイル
  FileUtils.touch('tmp/restart.txt')

  # 再試行（2回目も失敗する場合はエラーを通常通り発生させる）
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
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
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

  # FactoryBot設定
  config.include FactoryBot::Syntax::Methods

  # Devise用のヘルパー
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::IntegrationHelpers, type: :feature

  # Draper用のヘルパー設定
  config.include Draper::ViewHelpers, type: :decorator

  # DatabaseCleaner設定
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
  end

  config.before(:each, js: true) do
    DatabaseCleaner.strategy = :truncation
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end

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
  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")
end

# Shoulda Matchers設定
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

# Rails 7.2の凍結配列問題対策（CI環境で実行時）
if ENV["CI"] || ENV["RAILS_FROZEN_ARRAY_PATCH"]
  puts "Applying Rails 7.2 frozen array patch for CI test environment..."

  # モデルのロード順序を制御し、同じモデルが2回ロードされないようにする
  Rails.autoloaders.main.on_load(:Inventory) do |klass, _abspath|
    # Inventoryクラスの読み込み時に、すべてのメソッドがロードされるようにする
    klass.instance_methods(false).each do |method_name|
      puts "Eager loading Inventory##{method_name}" if ENV["DEBUG"]
      klass.method_defined?(method_name)
    end
  end if defined?(Rails.autoloaders) && Rails.autoloaders.respond_to?(:main)

  # 自動読み込み完了後のクリーンアップ
  RSpec.configure do |config|
    config.after(:suite) do
      # テスト実行後にbootsnapキャッシュを再生成
      if defined?(Bootsnap) && Bootsnap.respond_to?(:setup)
        puts "Regenerating Bootsnap cache after tests..."
        Bootsnap.setup(
          cache_dir: Rails.root.join("tmp/cache"),
          development_mode: false,
          load_path_cache: true,
          autoload_paths_cache: true,
          compile_cache_iseq: true,
          compile_cache_yaml: true
        )
      end
    end
  end
end

# TODO: 2025年7月のRails 7.3/8.0リリース後にこのパッチを見直す

# Capybaraのシステムテスト設定
Capybara.register_driver :chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--window-size=1400,1400')
  options.add_argument('--disable-gpu')
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

Capybara.javascript_driver = :chrome_headless
Capybara.default_driver = :chrome_headless
Capybara.app_host = "http://www.example.com"
Capybara.server_host = "0.0.0.0"
Capybara.server_port = 3001
