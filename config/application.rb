require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module StockRx
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Zeitwerk関連のエラー修正
    # Rails 6以降、Zeitwerkがデフォルトのオートローダーとなり、
    # この設定は通常不要または非推奨です。
    # Zeitwerkは`$LOAD_PATH`を直接操作しないため、`false`が推奨されます。
    # もし特定の理由で有効にしている場合は、その理由をコメントで残すことを推奨します。
    config.add_autoload_paths_to_load_path = false

    # --- オートロードパスの追加 ---
    # `config/initializers` でパスを操作すると、初期化完了後に
    # 設定オブジェクトがfreezeされた配列を変更しようとして FrozenError が発生する可能性があります。
    # そのため、パスの追加はここで行います。
    # カスタムバリデーター (例: app/validators/custom_validator.rb) を配置するディレクトリ
    config.paths.add "app/validators", eager_load: true
    # プロジェクト固有のライブラリ (例: app/lib/my_utility.rb) を配置するディレクトリ
    config.paths.add "app/lib", eager_load: true

    # 全例外をRoutes配下で処理するよう設定
    config.exceptions_app = self.routes

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `lib` ディレクトリ配下で、オートロード/イーガーロードの対象外としたい
    # サブディレクトリを指定します。
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # --- ロケール設定 ---
    config.i18n.default_locale = :ja
    config.i18n.available_locales = [ :ja, :en ]
    # 指定したロケールファイルが見つからない場合にフォールバックする言語を指定
    config.i18n.fallbacks = [ I18n.default_locale ]

    # --- タイムゾーン設定 ---
    config.time_zone = "Tokyo"
  end
end
