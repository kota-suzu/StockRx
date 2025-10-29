# frozen_string_literal: true

# コントローラーレベルのデータベース最適化機能
# ============================================
# CLAUDE.md準拠: パフォーマンス最適化 - N+1クエリ防止
# メタ認知: コントローラー全体で一貫した最適化戦略
# ============================================
module DatabaseOptimization
  extend ActiveSupport::Concern

  included do
    # Bulletによるクエリ監視（開発環境のみ）
    if defined?(Bullet) && Rails.env.development?
      around_action :detect_n_plus_one_queries
    end

    # クエリカウント監視
    before_action :init_query_counter
    after_action :log_query_performance
  end

  # クラスメソッド
  class_methods do
    # アクション別の最適化設定
    def optimize_queries_for(*actions, includes: [], preload: [], cache: false)
      before_action only: actions do
        @query_optimizations = {
          includes: includes,
          preload: preload,
          cache: cache
        }
      end
    end

    # バッチサイズの設定
    def set_batch_size(size)
      @default_batch_size = size
    end

    # キャッシュ戦略の設定
    def cache_strategy(strategy = :redis, expires_in: 5.minutes)
      @cache_strategy = strategy
      @cache_expires_in = expires_in
    end
  end

  protected

  # 最適化されたfind
  def optimized_find(model_class, id, associations: nil)
    associations ||= @query_optimizations&.dig(:includes) || []

    if associations.any?
      model_class.includes(associations).find(id)
    else
      model_class.find(id)
    end
  end

  # 最適化されたwhere
  def optimized_where(model_class, conditions, associations: nil)
    associations ||= @query_optimizations&.dig(:includes) || []
    scope = model_class.where(conditions)

    if associations.any?
      scope = scope.includes(associations)
    end

    scope
  end

  # バッチ処理
  def process_in_batches(scope, batch_size: nil)
    batch_size ||= self.class.instance_variable_get(:@default_batch_size) || 1000

    scope.find_in_batches(batch_size: batch_size) do |batch|
      # プリロード最適化
      optimize_batch_preloading(batch)
      yield batch
    end
  end

  # キャッシュ付き取得
  def cached_query(key, expires_in: nil, &block)
    expires_in ||= self.class.instance_variable_get(:@cache_expires_in) || 5.minutes

    Rails.cache.fetch(key, expires_in: expires_in) do
      result = yield
      # ActiveRecordオブジェクトの場合はto_aで配列化
      result.respond_to?(:to_a) ? result.to_a : result
    end
  end

  # クエリ数の取得
  def query_count
    @query_count || 0
  end

  # クエリ実行時間の取得
  def query_time
    @query_time || 0
  end

  private

  # N+1クエリ検出（Bullet使用）
  def detect_n_plus_one_queries
    Bullet.start_request
    yield
    Bullet.perform_out_of_channel_notifications
    Bullet.end_request
  end

  # クエリカウンターの初期化
  def init_query_counter
    @query_count = 0
    @query_time = 0
    @query_start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # ActiveRecordのクエリをカウント
    @query_subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)

      # SCHEMA関連のクエリは除外
      unless event.payload[:name]&.match?(/SCHEMA/)
        @query_count += 1
        @query_time += event.duration
      end
    end
  end

  # クエリパフォーマンスのログ出力
  def log_query_performance
    # サブスクライバーの解除
    ActiveSupport::Notifications.unsubscribe(@query_subscriber) if @query_subscriber

    # 実行時間の計算
    total_time = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @query_start_time) * 1000

    # パフォーマンスログ
    performance_data = {
      controller: controller_name,
      action: action_name,
      query_count: @query_count,
      query_time_ms: @query_time.round(2),
      total_time_ms: total_time.round(2),
      db_time_ratio: (@query_time / total_time * 100).round(2)
    }

    # 警告閾値の判定
    if @query_count > 50
      Rails.logger.warn("[DatabaseOptimization] High query count detected: #{performance_data}")
    elsif @query_time > 200
      Rails.logger.warn("[DatabaseOptimization] Slow queries detected: #{performance_data}")
    else
      Rails.logger.info("[DatabaseOptimization] Performance: #{performance_data}")
    end

    # レスポンスヘッダーに追加（開発環境のみ）
    if Rails.env.development?
      response.headers["X-Query-Count"] = @query_count.to_s
      response.headers["X-Query-Time"] = "#{@query_time.round(2)}ms"
      response.headers["X-Total-Time"] = "#{total_time.round(2)}ms"
    end
  end

  # バッチのプリロード最適化
  def optimize_batch_preloading(batch)
    preload_associations = @query_optimizations&.dig(:preload) || []

    if preload_associations.any?
      ActiveRecord::Associations::Preloader.new(
        records: batch,
        associations: preload_associations
      ).call
    end
  end

  # 動的なincludes判定
  def determine_includes_for_action
    case action_name
    when "index"
      # インデックスではCounter Cacheで十分
      []
    when "show"
      # 詳細画面では関連データが必要
      [ :batches, :inventory_logs ]
    when "edit", "update"
      # 編集画面では最小限
      [ :batches ]
    else
      []
    end
  end

  # クエリ最適化のベストプラクティス
  # ============================================
  # 1. Counter Cacheの活用
  #    - has_many関連の_countカラムを追加
  #    - 集計クエリを回避
  #
  # 2. 適切なincludes/preloadの使い分け
  #    - includes: LEFT OUTER JOIN（条件付き読み込み）
  #    - preload: 別クエリで読み込み（大量データ向け）
  #    - eager_load: INNER JOIN（結合条件あり）
  #
  # 3. インデックスの活用
  #    - 外部キーには必ずインデックス
  #    - 検索条件のカラムにインデックス
  #    - 複合インデックスの順序に注意
  #
  # 4. バッチ処理
  #    - find_each/find_in_batchesでメモリ効率化
  #    - 適切なバッチサイズ設定（デフォルト1000）
  # ============================================
end
