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
# Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = Rails.root.join('spec/fixtures')

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
end

# Shoulda Matchers設定
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

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
