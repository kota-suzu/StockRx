# frozen_string_literal: true

source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0.2"
# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem "sprockets-rails"
# Use mysql as the database for Active Record
gem "mysql2", "~> 0.5"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Bootstrap 5 for modern responsive design
gem "bootstrap", "~> 5.3"         # Bootstrap CSS & JS framework
gem "sassc-rails", "~> 2.1"       # Sass compiler for Bootstrap
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
# Use CSV library (included in Ruby 3.4+)
gem "csv"

# Excel and PDF generation for monthly reports
gem "caxlsx", "~> 4.1"           # Excel生成（ActiveX Excel Library）
gem "caxlsx_rails", "~> 0.6"     # Rails統合
gem "rubyzip", "~> 2.3"          # ZIP形式対応（Excel内部形式）
gem "prawn", "~> 2.4"            # PDF生成ライブラリ
gem "prawn-table", "~> 0.2"      # PDF表組み機能
# Use Redis adapter to run Action Cable in production
gem "redis", ">= 4.0.1"

# Use Kredis to get higher-level data types in Redis [https://github.com/rails/kredis]
# gem "kredis"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Security vulnerability checking [https://github.com/rubysec/bundler-audit]
  gem "bundler-audit", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec for testing
  gem "rspec-rails", "~> 6.1.0"        # RSpecテストフレームワーク
  gem "factory_bot_rails"              # テストデータ作成
  gem "shoulda-matchers", "~> 6.0"     # RSpecマッチャー拡張
  gem "faker"                          # ダミーデータ生成
  gem "database_cleaner-active_record" # テスト間のDB掃除
  gem "rails-controller-testing"       # Controller testing helpers (assigns, etc.)

  # N+1問題検出
  gem "bullet"                         # N+1クエリ検出

  # デコレータパターン実装用
  gem "draper"                         # Decoratorパターン実装
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "timecop"

  # テストカバレッジ計測
  gem "simplecov", require: false      # コードカバレッジ計測
end

# 認証
gem "devise", "~> 4.9"            # Rails 7.1 / Hotwire 対応版
gem "devise-security", "~> 0.18"  # パスワード期限、強度検証機能など
gem "devise-i18n", "~> 1.12"      # 日本語対応

# OAuth認証（ソーシャルログイン）
gem "omniauth", "~> 2.1"          # OAuth認証フレームワーク
gem "omniauth-github", "~> 2.0"   # GitHub OAuth戦略
gem "omniauth-rails_csrf_protection", "~> 1.0"  # CSRF保護

# TODO: システム拡張時に必要に応じて有効化
# gem "devise-two-factor", "~> 5.1"  # 2要素認証（TOTP）
# gem "pagy", "~> 6.2"               # ページネーション
# gem "ransack"                      # 高度な検索機能
# gem "paper_trail"                  # モデル変更履歴管理
# gem "attr_encrypted"               # 属性の暗号化

gem "kaminari", "~> 1.2"            # ページネーション

# Background Job Processing
gem "sidekiq", "~> 7.2"
gem "sidekiq-scheduler", "~> 5.0"  # TODO: 将来の定期実行ジョブ用（月次レポート生成など）
gem "rack-protection", "~> 4.0"   # Sidekiq Web UI のセキュリティ強化

# TODO: 外部API連携機能（Ruby 3.x対応）- CLAUDE.md参照
# 外部API連携機能を完全に実装するため、以下のgemの追加が必要：
# gem "faraday", "~> 2.7"           # HTTPクライアント（Net::HTTPのモダンな代替）
# gem "faraday-retry", "~> 2.2"     # リトライ機能（タイムアウトエラー対応）
# gem "faraday-multipart", "~> 1.0" # マルチパート対応
# gem "circuit_breaker", "~> 1.1"   # サーキットブレーカーパターン実装
# TODO: 実装優先度
# - 高: 在庫同期、発注システム連携、HTTPクライアント実装
# - 中: 会計システム連携、価格同期
# - 低: 監視・アラート機能、高度な同期機能
