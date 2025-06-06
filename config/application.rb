require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module App
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.2

    # Rails 8対応: Zeitwerk設定
    # add_autoload_paths_to_load_pathはRails 8で削除されたため使用しない
    # 代わりに、libディレクトリのeager loadingを設定

    # 全例外をRoutes配下で処理するよう設定
    config.exceptions_app = self.routes

    # lib配下の自動読み込み設定 (Rails 8対応)
    # Rails 8では、libディレクトリはデフォルトでは自動読み込みされない
    # eager_load_pathsに追加して、production環境でのeager loadingを有効にする
    config.paths.add "lib", eager_load: true
    
    # 特定のサブディレクトリを除外
    config.eager_load_paths -= ["#{config.root}/lib/assets", "#{config.root}/lib/tasks"]

    # ============================================
    # 国際化・地域化設定
    # ============================================
    # Locale Setting
    config.i18n.default_locale = :ja
    config.i18n.available_locales = [ :ja, :en ]
    config.i18n.fallbacks = [ I18n.default_locale ]
    config.time_zone = "Tokyo"
    
    # Rails 8.1 対応: タイムゾーン保持設定
    config.active_support.to_time_preserves_timezone = :zone

    # ============================================
    # バックグラウンドジョブ処理設定
    # ============================================
    # Sidekiqアダプターを使用（Redis経由でバックグラウンドジョブ処理）
    config.active_job.queue_adapter = :sidekiq

    # ============================================
    # セキュリティ設定（基本）
    # ============================================
    # TODO: セキュリティ強化設定（優先度：最高）
    # 1. CSRF Protection 強化
    #    config.force_ssl = true  # 本番環境でHTTPS強制
    #    config.ssl_options = { redirect: { exclude: ->(request) { request.path.start_with?('/health') } } }
    #
    # 2. セキュリティヘッダー設定
    #    config.force_ssl = Rails.env.production?
    #    config.session_store :cookie_store, {
    #      key: '_stockrx_session',
    #      secure: Rails.env.production?,
    #      httponly: true,
    #      same_site: :lax
    #    }
    #
    # 3. Content Security Policy (CSP)
    #    config.content_security_policy do |policy|
    #      policy.default_src :self, :https
    #      policy.script_src  :self, :https, :unsafe_inline, :unsafe_eval
    #      policy.style_src   :self, :https, :unsafe_inline
    #    end

    # ============================================
    # TODO: ログ・監視設定（優先度：高）
    # ============================================
    # 1. 構造化ログ設定
    #    - JSON形式でのログ出力
    #    - ログレベル別の詳細制御
    #    - 外部ログシステム連携準備
    #    if Rails.env.production?
    #      config.log_formatter = proc do |severity, datetime, progname, message|
    #        {
    #          timestamp: datetime.iso8601,
    #          level: severity,
    #          progname: progname,
    #          message: message,
    #          environment: Rails.env,
    #          application: 'StockRx'
    #        }.to_json + "\n"
    #      end
    #    end
    #
    # 2. パフォーマンス監視
    #    - スロークエリ検出
    #    - メモリ使用量監視
    #    - レスポンス時間追跡
    #    config.active_record.slow_query_threshold = 1.0  # 1秒以上のクエリを記録
    #
    # 3. 監査ログ設定
    #    - ユーザー操作ログ
    #    - データ変更履歴
    #    - セキュリティイベント記録

    # ============================================
    # TODO: パフォーマンス最適化（優先度：高）
    # ============================================
    # 1. キャッシュ設定
    #    - Fragment キャッシュの最適化
    #    - Redis キャッシュストア設定
    #    - CDN 連携設定
    #    config.cache_store = :redis_cache_store, {
    #      url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/1'),
    #      expires_in: 1.hour,
    #      race_condition_ttl: 10.seconds
    #    }
    #
    # 2. アセット最適化
    #    - 画像・CSS・JS の最適化
    #    - Gzip 圧縮設定
    #    - ブラウザキャッシュ最適化
    #    config.assets.gzip = true
    #    config.public_file_server.headers = {
    #      'Cache-Control' => 'public, max-age=2592000',  # 30日
    #      'Expires' => 30.days.from_now.to_formatted_s(:rfc822)
    #    }
    #
    # 3. データベース最適化
    #    - 接続プール設定
    #    - クエリ最適化
    #    - インデックス戦略

    # ============================================
    # TODO: バックグラウンドジョブ最適化（優先度：高）
    # ============================================
    # 1. キュー戦略の最適化
    #    config.active_job.default_queue_name = :default
    #    config.active_job.queue_name_prefix = Rails.env.production? ? 'stockrx_production' : 'stockrx_development'
    #    config.active_job.queue_name_delimiter = '_'
    #
    # 2. エラーハンドリング強化
    #    - リトライ戦略の詳細設定
    #    - 失敗通知システム
    #    - デッドレターキュー管理
    #    config.active_job.retry_jitter = 0.15
    #
    # 3. パフォーマンス監視
    #    - ジョブ実行時間監視
    #    - キュー長監視
    #    - 失敗率統計

    # ============================================
    # TODO: API設定・外部連携（優先度：中）
    # ============================================
    # 1. CORS設定（API提供時）
    #    config.middleware.insert_before 0, Rack::Cors do
    #      allow do
    #        origins '*'  # 本番では具体的なドメインを指定
    #        resource '*',
    #          headers: :any,
    #          methods: [:get, :post, :put, :patch, :delete, :options, :head],
    #          credentials: true
    #      end
    #    end
    #
    # 2. レート制限設定
    #    - API呼び出し制限
    #    - DDoS対策
    #    - 認証ベースの制限
    #
    # 3. 外部API連携設定
    #    - タイムアウト設定
    #    - リトライ戦略
    #    - フォールバック処理

    # ============================================
    # TODO: 高可用性・スケーラビリティ（優先度：中）
    # ============================================
    # 1. セッション管理最適化
    #    - Redis セッションストア
    #    - 分散セッション対応
    #    - セッション有効期限管理
    #    config.session_store :redis_session_store, {
    #      key: '_stockrx_session',
    #      redis: {
    #        url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/2'),
    #        expire_after: 120.minutes
    #      }
    #    }
    #
    # 2. ファイルストレージ設定
    #    - クラウドストレージ連携
    #    - CDN設定
    #    - ファイル暗号化
    #    config.active_storage.variant_processor = :image_processing
    #
    # 3. 負荷分散対応
    #    - ヘルスチェック最適化
    #    - グレースフルシャットダウン
    #    - ローリングデプロイメント対応

    # ============================================
    # TODO: 開発・運用効率化（優先度：中）
    # ============================================
    # 1. 開発環境最適化
    #    - ホットリロード設定
    #    - デバッグツール統合
    #    - テスト実行最適化
    #    if Rails.env.development?
    #      config.file_watcher = ActiveSupport::EventedFileUpdateChecker
    #      config.reload_classes_only_on_change = false
    #    end
    #
    # 2. CI/CD連携設定
    #    - テスト環境設定
    #    - 自動デプロイ設定
    #    - 品質チェック統合
    #
    # 3. ドキュメント自動生成
    #    - API ドキュメント
    #    - コードドキュメント
    #    - 運用手順書

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
