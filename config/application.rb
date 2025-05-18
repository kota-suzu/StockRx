require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Zeitwerk関連のエラー修正
    config.add_autoload_paths_to_load_path = false

    # 全例外をRoutes配下で処理するよう設定
    config.exceptions_app = self.routes

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Locale Setting
    config.i18n.default_locale = :ja
    config.i18n.available_locales = [ :ja, :en ]
    config.i18n.fallbacks = [ I18n.default_locale ]
    config.time_zone = "Tokyo"
  end
end
