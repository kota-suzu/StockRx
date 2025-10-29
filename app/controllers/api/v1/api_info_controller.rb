# frozen_string_literal: true

module Api
  module V1
    # API情報・メタデータ提供コントローラー
    # CLAUDE.md準拠: API利用者向けの情報提供機能
    class ApiInfoController < Api::ApiController
      # ヘルスチェックとレート制限状況はAPIキー不要
      skip_before_action :check_rate_limit!, only: [ :health ]

      # API基本情報
      def show
        response = ApiResponse.success(
          {
            version: "v1",
            name: "StockRx API",
            description: "在庫管理システムのREST API",
            status: "active",
            documentation_url: "#{request.base_url}/api/docs",
            supported_formats: [ "json" ],
            authentication: {
              supported_methods: [ "API Key", "Bearer Token" ],
              required: false,
              header_names: [ "X-API-Key", "Authorization" ]
            },
            rate_limiting: {
              anonymous: ApiRateLimiter::LIMITS[:anonymous],
              authenticated: ApiRateLimiter::LIMITS[:authenticated]
            },
            endpoints: {
              inventories: "#{request.base_url}/api/v1/inventories",
              api_keys: "#{request.base_url}/api/v1/api_keys",
              documentation: "#{request.base_url}/api/docs"
            }
          },
          "API情報を取得しました"
        )

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # ヘルスチェック
      def health
        database_status = check_database_health
        redis_status = check_redis_health

        overall_status = database_status[:healthy] && redis_status[:healthy] ? "healthy" : "unhealthy"

        health_data = {
          status: overall_status,
          timestamp: Time.current.iso8601,
          version: Rails.application.class.module_parent_name,
          environment: Rails.env,
          uptime: uptime_info,
          services: {
            database: database_status,
            redis: redis_status,
            api: {
              healthy: true,
              response_time: "< 100ms"
            }
          }
        }

        status_code = overall_status == "healthy" ? 200 : 503

        response = if overall_status == "healthy"
          ApiResponse.success(health_data, "システムは正常に動作しています")
        else
          ApiResponse.error(
            "システムに問題があります",
            [],
            status_code,
            { type: "health_check_failed" }
          )
        end

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      # レート制限状況
      def rate_limit
        if api_authenticated?
          limiter = api_rate_limiter
          usage = limiter.usage_info

          rate_limit_data = {
            authenticated: true,
            user_type: api_authenticated_admin? ? "admin" : "store_user",
            current_usage: usage,
            limits: ApiRateLimiter::LIMITS[limiter.user_type],
            recommendations: generate_rate_limit_recommendations(usage)
          }
        else
          # 匿名ユーザーの場合は一般的な情報のみ
          rate_limit_data = {
            authenticated: false,
            user_type: "anonymous",
            limits: ApiRateLimiter::LIMITS[:anonymous],
            authentication_info: {
              message: "APIキーを使用すると制限が緩和されます",
              benefits: [
                "1時間あたり600リクエスト（10倍）",
                "分あたり60リクエスト（6倍）",
                "使用状況の詳細確認"
              ]
            }
          }
        end

        response = ApiResponse.success(rate_limit_data, "レート制限情報を取得しました")

        render json: response.to_h, status: response.status_code, headers: response.headers
      end

      private

      # データベースの健全性チェック
      def check_database_health
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          # 簡単なクエリを実行
          ActiveRecord::Base.connection.execute("SELECT 1")
          response_time = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

          {
            healthy: true,
            response_time: "#{response_time}ms",
            status: "connected"
          }
        rescue => e
          {
            healthy: false,
            error: e.message,
            status: "disconnected"
          }
        end
      end

      # Redisの健全性チェック
      def check_redis_health
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          # 簡単なRedis操作を実行
          Redis.current.ping
          response_time = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

          {
            healthy: true,
            response_time: "#{response_time}ms",
            status: "connected"
          }
        rescue => e
          {
            healthy: false,
            error: e.message,
            status: "disconnected"
          }
        end
      end

      # アップタイム情報
      def uptime_info
        # シンプルなアップタイム情報を返す（Rails 8対応）
        begin
          start_time = Time.current - Process.clock_gettime(Process::CLOCK_UPTIME)
          uptime_seconds = Process.clock_gettime(Process::CLOCK_UPTIME).to_i

          {
            seconds: uptime_seconds,
            human_readable: "#{uptime_seconds / 3600}時間#{(uptime_seconds % 3600) / 60}分#{uptime_seconds % 60}秒"
          }
        rescue => e
          # フォールバック情報
          {
            seconds: 0,
            human_readable: "不明"
          }
        end
      end

      # レート制限の推奨事項を生成
      def generate_rate_limit_recommendations(usage)
        recommendations = []

        hourly = usage[:hourly]
        minute = usage[:minute]

        # 時間別使用率をチェック
        hourly_usage_percent = (hourly[:used].to_f / hourly[:limit]) * 100
        minute_usage_percent = (minute[:used].to_f / minute[:limit]) * 100

        if hourly_usage_percent > 80
          recommendations << "時間別制限の80%を使用しています。リクエスト頻度を調整することをお勧めします。"
        end

        if minute_usage_percent > 70
          recommendations << "分別制限の70%を使用しています。リクエスト間隔を空けることをお勧めします。"
        end

        if hourly_usage_percent < 50 && minute_usage_percent < 50
          recommendations << "制限に余裕があります。必要に応じてリクエスト頻度を増やせます。"
        end

        recommendations << "バッチ処理には bulk エンドポイントの使用をお勧めします。"

        recommendations
      end
    end
  end
end
