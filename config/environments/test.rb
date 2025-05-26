require "active_support/core_ext/integer/time"

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Zeitwerk関連の設定
  config.autoloader = :zeitwerk
  config.add_autoload_paths_to_load_path = false

  # パフォーマンス最適化：静的ファイル配信の軽量化
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.hour.to_i}" }

  # Show full error reports and disable caching.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :memory_store  # テスト用にメモリストアを使用（:null_storeより高速）

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Unlike controllers, the mailer instance doesn't have any context about the
  # incoming request so you'll need to provide the :host parameter yourself.
  config.action_mailer.default_url_options = { host: "www.example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # テスト環境で許可するホスト（Host Authorization対応）
  config.hosts << "www.example.com"
  config.hosts << "127.0.0.1"
  config.hosts << "localhost"
  # Capybaraテスト用のホスト許可
  config.hosts << "example.com"
  config.hosts << /.*\.example\.com/
  config.hosts << "0.0.0.0"
  # Docker環境対応
  config.hosts << "web"
  config.hosts << "stockrx-web-1"

  # TODO: 本番環境では厳格なHost制限を実装
  # config.hosts = [Rails.application.credentials.domain] if Rails.env.production?

  # TODO: パフォーマンス最適化設定（優先度：高）
  # ログレベルをERRORに設定してテスト出力を軽量化
  config.log_level = :error

  # TODO: 並列テスト実行の最適化
  # config.active_support.test_order = :random
  # config.active_record.dump_schema_after_migration = false

  # TODO: アセット関連の最適化
  # config.assets.compile = false
  # config.assets.digest = false
  # config.assets.debug = false

  # Bulletの設定（テスト環境用）
  config.after_initialize do
    if defined?(Bullet)
      # パフォーマンス重視でBulletを軽量設定
      Bullet.enable = ENV.fetch("BULLET_ENABLED", "false") == "true"
      Bullet.bullet_logger = false  # ログ出力を無効化
      Bullet.raise = false  # 例外発生を無効化（テスト速度優先）

      # TODO: 本格的なN+1クエリ検証が必要な場合の設定
      # Bullet.raise = true
      # Bullet.bullet_logger = true
      # 特定のN+1クエリを無視する場合はここで設定
      # Bullet.add_safelist type: :n_plus_one_query, class_name: "Model", association: :association_name
    end
  end

  # TODO: テスト環境での追加最適化設定（優先度：中）
  # ============================================
  # 1. データベース最適化
  #    - テスト用のトランザクション設定
  #    - インデックス最適化
  #    - クエリキャッシュ有効化
  #
  # 2. ミドルウェア軽量化
  #    - 不要なミドルウェアの無効化
  #    - セッション処理の簡素化
  #    - ログ処理の最適化
  #
  # 3. メモリ使用量最適化
  #    - オブジェクトプーリング
  #    - ガベージコレクション調整
  #    - メモリキャッシュ戦略
  #
  # 4. 並列処理最適化
  #    - 並列テスト実行
  #    - プロセス間データ共有
  #    - リソース競合回避

  # TODO: Capybaraテスト最適化（優先度：高）
  # ============================================
  # 1. Selenium WebDriver設定
  #    - ヘッドレスモード有効化
  #    - ウィンドウサイズ最適化
  #    - タイムアウト短縮
  #
  # 2. JavaScriptテスト最適化
  #    - 不要なJavaScript無効化
  #    - CSS/画像読み込み無効化
  #    - ネットワーク待機時間短縮
  #
  # 3. Puma設定最適化
  #    - スレッド数調整
  #    - ワーカー数最適化
  #    - メモリ使用量制限

  # TODO: CI/CD環境での最適化（優先度：中）
  # ============================================
  # 並列実行設定
  # if ENV["CI"].present?
  #   config.active_record.dump_schema_after_migration = false
  #   config.active_support.test_order = :sorted
  #   config.log_level = :warn
  # end
end
