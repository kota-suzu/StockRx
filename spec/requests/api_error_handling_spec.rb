# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "API Error Handling", type: :request do
  # CLAUDE.md準拠: API層のエラーハンドリング包括的テスト
  # メタ認知: RESTful API設計原則に基づいたエラーレスポンスの一貫性
  # 横展開: 全APIエンドポイントで統一的なエラー処理パターン

  let(:admin) { create(:admin) }
  let(:api_headers) {
    {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{generate_api_token(admin)}"
    }
  }

  # ============================================
  # 1. 認証・認可エラー
  # ============================================

  describe "Authentication and Authorization Errors" do
    describe "Missing authentication" do
      it "認証なしアクセスで401を返す" do
        get "/api/v1/inventories", headers: { 'Accept' => 'application/json' }

        expect(response).to have_http_status(401)
        expect(json_response).to include(
          "status" => "error",
          "code" => "unauthorized",
          "message" => "認証が必要です"
        )
      end

      it "ヘッダー形式が正しいJSONレスポンスを返す" do
        get "/api/v1/inventories", headers: { 'Accept' => 'application/json' }

        expect(response.headers['Content-Type']).to include('application/json')
        expect(response.headers['X-Request-Id']).to be_present
      end
    end

    describe "Invalid token" do
      it "無効なトークンで401を返す" do
        headers = api_headers.merge('Authorization' => 'Bearer invalid_token')
        get "/api/v1/inventories", headers: headers

        expect(response).to have_http_status(401)
        expect(json_response).to include(
          "status" => "error",
          "code" => "invalid_token",
          "message" => "トークンが無効です"
        )
      end

      it "期限切れトークンで401を返す" do
        expired_token = generate_api_token(admin, expires_at: 1.hour.ago)
        headers = api_headers.merge('Authorization' => "Bearer #{expired_token}")

        get "/api/v1/inventories", headers: headers

        expect(response).to have_http_status(401)
        expect(json_response).to include(
          "status" => "error",
          "code" => "token_expired",
          "message" => "トークンの有効期限が切れています"
        )
      end
    end

    describe "Insufficient permissions" do
      let(:store_user) { create(:store_user) }
      let(:store_api_headers) {
        {
          'Accept' => 'application/json',
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{generate_api_token(store_user)}"
        }
      }

      it "権限不足で403を返す" do
        # 店舗ユーザーが管理者APIにアクセス
        post "/api/v1/admin/stores",
             params: { store: { name: "New Store" } }.to_json,
             headers: store_api_headers

        expect(response).to have_http_status(403)
        expect(json_response).to include(
          "status" => "error",
          "code" => "forbidden",
          "message" => "この操作を実行する権限がありません"
        )
      end
    end
  end

  # ============================================
  # 2. リクエスト検証エラー
  # ============================================

  describe "Request Validation Errors" do
    describe "Invalid JSON" do
      it "不正なJSONで400を返す" do
        post "/api/v1/inventories",
             params: '{"name": "Test", "quantity": }',  # 不正なJSON
             headers: api_headers

        expect(response).to have_http_status(400)
        expect(json_response).to include(
          "status" => "error",
          "code" => "invalid_json",
          "message" => "リクエストのJSONが不正です"
        )
      end

      it "詳細なパースエラー情報を含む" do
        post "/api/v1/inventories",
             params: '{"unclosed": "string}',
             headers: api_headers

        expect(json_response["meta"]).to include(
          "parse_error" => be_present,
          "error_position" => be_a(Integer)
        )
      end
    end

    describe "Missing required parameters" do
      it "必須パラメータ欠落で422を返す" do
        post "/api/v1/inventories",
             params: { inventory: { quantity: 10 } }.to_json,  # nameが欠落
             headers: api_headers

        expect(response).to have_http_status(422)
        expect(json_response).to include(
          "status" => "error",
          "code" => "validation_error",
          "errors" => include(
            "name" => [ "を入力してください" ]
          )
        )
      end

      it "複数のバリデーションエラーを構造化して返す" do
        post "/api/v1/inventories",
             params: {
               inventory: {
                 name: "",
                 quantity: -5,
                 price: "not_a_number"
               }
             }.to_json,
             headers: api_headers

        expect(response).to have_http_status(422)
        errors = json_response["errors"]
        expect(errors).to include(
          "name" => [ "を入力してください" ],
          "quantity" => [ "は0以上の値にしてください" ],
          "price" => [ "は数値で入力してください" ]
        )
      end
    end

    describe "Invalid data types" do
      it "型が不正なパラメータで422を返す" do
        post "/api/v1/inventories",
             params: {
               inventory: {
                 name: [ "配列は無効" ],  # 文字列であるべき
                 quantity: "10個",      # 数値であるべき
                 price: true           # 数値であるべき
               }
             }.to_json,
             headers: api_headers

        expect(response).to have_http_status(422)
        expect(json_response["errors"]).to be_present
      end
    end
  end

  # ============================================
  # 3. リソース関連エラー
  # ============================================

  describe "Resource Errors" do
    describe "Resource not found" do
      it "存在しないリソースで404を返す" do
        get "/api/v1/inventories/999999", headers: api_headers

        expect(response).to have_http_status(404)
        expect(json_response).to include(
          "status" => "error",
          "code" => "resource_not_found",
          "message" => "リソースが見つかりません",
          "meta" => include(
            "resource_type" => "Inventory",
            "resource_id" => "999999"
          )
        )
      end
    end

    describe "Resource conflicts" do
      let(:inventory) { create(:inventory) }

      it "重複作成で409を返す" do
        create(:inventory, sku: "UNIQUE123")

        post "/api/v1/inventories",
             params: {
               inventory: {
                 name: "Duplicate",
                 sku: "UNIQUE123",  # 重複
                 quantity: 10,
                 price: 1000
               }
             }.to_json,
             headers: api_headers

        expect(response).to have_http_status(409)
        expect(json_response).to include(
          "status" => "error",
          "code" => "conflict",
          "message" => "リソースが競合しています"
        )
      end

      it "楽観的ロック競合で409を返す" do
        # lock_versionを含めて更新
        put "/api/v1/inventories/#{inventory.id}",
            params: {
              inventory: {
                quantity: 100,
                lock_version: inventory.lock_version - 1  # 古いバージョン
              }
            }.to_json,
            headers: api_headers

        expect(response).to have_http_status(409)
        expect(json_response).to include(
          "status" => "error",
          "code" => "stale_object",
          "message" => "リソースが他のユーザーによって更新されています"
        )
      end
    end
  end

  # ============================================
  # 4. レート制限とクォータ
  # ============================================

  describe "Rate Limiting and Quotas" do
    describe "Request rate limits" do
      it "レート制限超過で429を返す" do
        # 短時間に大量リクエスト
        10.times do
          get "/api/v1/inventories", headers: api_headers
        end

        get "/api/v1/inventories", headers: api_headers

        expect(response).to have_http_status(429)
        expect(json_response).to include(
          "status" => "error",
          "code" => "too_many_requests",
          "message" => "リクエスト頻度が制限を超えています"
        )

        # Retry-Afterヘッダーの確認
        expect(response.headers['Retry-After']).to be_present
        expect(response.headers['X-RateLimit-Limit']).to eq("10")
        expect(response.headers['X-RateLimit-Remaining']).to eq("0")
      end
    end

    describe "Quota exceeded" do
      it "月間APIクォータ超過で429を返す" do
        # ユーザーのクォータを使い切った状態をシミュレート
        allow_any_instance_of(ApiQuotaService).to receive(:check_quota!)
          .and_raise(ApiQuotaExceededError)

        get "/api/v1/inventories", headers: api_headers

        expect(response).to have_http_status(429)
        expect(json_response).to include(
          "status" => "error",
          "code" => "quota_exceeded",
          "message" => "月間APIクォータを超過しました",
          "meta" => include(
            "quota_reset_at" => be_present,
            "upgrade_url" => be_present
          )
        )
      end
    end
  end

  # ============================================
  # 5. データフォーマットとコンテンツネゴシエーション
  # ============================================

  describe "Content Negotiation Errors" do
    describe "Unsupported media type" do
      it "サポートされないContent-Typeで415を返す" do
        post "/api/v1/inventories",
             params: "<inventory><name>Test</name></inventory>",
             headers: api_headers.merge('Content-Type' => 'application/xml')

        expect(response).to have_http_status(415)
        expect(json_response).to include(
          "status" => "error",
          "code" => "unsupported_media_type",
          "message" => "Content-Type 'application/xml' はサポートされていません"
        )
      end
    end

    describe "Not acceptable" do
      it "受け入れ不可能なAcceptヘッダーで406を返す" do
        get "/api/v1/inventories",
            headers: api_headers.merge('Accept' => 'application/xml')

        expect(response).to have_http_status(406)
        expect(json_response).to include(
          "status" => "error",
          "code" => "not_acceptable",
          "message" => "要求された形式でレスポンスを生成できません"
        )
      end
    end
  end

  # ============================================
  # 6. ペイロードサイズとタイムアウト
  # ============================================

  describe "Payload and Timeout Errors" do
    describe "Payload too large" do
      it "大きすぎるリクエストボディで413を返す" do
        large_data = "x" * (10.megabytes + 1)

        post "/api/v1/inventories/bulk_import",
             params: { data: large_data }.to_json,
             headers: api_headers

        expect(response).to have_http_status(413)
        expect(json_response).to include(
          "status" => "error",
          "code" => "payload_too_large",
          "message" => "リクエストボディが大きすぎます",
          "meta" => include(
            "max_size" => "10MB",
            "received_size" => be_present
          )
        )
      end
    end

    describe "Request timeout" do
      it "処理タイムアウトで504を返す" do
        allow_any_instance_of(Api::V1::InventoriesController)
          .to receive(:index).and_raise(Rack::Timeout::RequestTimeoutError)

        get "/api/v1/inventories", headers: api_headers

        expect(response).to have_http_status(504)
        expect(json_response).to include(
          "status" => "error",
          "code" => "gateway_timeout",
          "message" => "リクエストの処理がタイムアウトしました"
        )
      end
    end
  end

  # ============================================
  # 7. バッチ処理とトランザクションエラー
  # ============================================

  describe "Batch Processing Errors" do
    describe "Partial failures" do
      it "バッチ処理で部分的失敗を報告する" do
        items = [
          { name: "Valid Item 1", quantity: 10, price: 1000 },
          { name: "", quantity: 20, price: 2000 },  # 無効
          { name: "Valid Item 2", quantity: -5, price: 3000 },  # 無効
          { name: "Valid Item 3", quantity: 30, price: 4000 }
        ]

        post "/api/v1/inventories/batch",
             params: { inventories: items }.to_json,
             headers: api_headers

        expect(response).to have_http_status(207)  # Multi-Status
        expect(json_response).to include(
          "status" => "partial_success",
          "summary" => include(
            "total" => 4,
            "succeeded" => 2,
            "failed" => 2
          ),
          "results" => include(
            include("index" => 0, "status" => "success", "id" => be_present),
            include("index" => 1, "status" => "error", "errors" => include("name")),
            include("index" => 2, "status" => "error", "errors" => include("quantity")),
            include("index" => 3, "status" => "success", "id" => be_present)
          )
        )
      end
    end

    describe "Transaction rollback" do
      it "トランザクション内エラーで全体をロールバック" do
        items = [
          { name: "Item 1", quantity: 10, price: 1000 },
          { name: "Item 2", quantity: 20, price: 2000 }
        ]

        # 2番目のアイテム保存時にエラーを発生させる
        allow_any_instance_of(Inventory).to receive(:save!).and_wrap_original do |method, *args|
          if subject.name == "Item 2"
            raise ActiveRecord::RecordInvalid.new(subject)
          else
            method.call(*args)
          end
        end

        expect {
          post "/api/v1/inventories/batch_transaction",
               params: { inventories: items }.to_json,
               headers: api_headers
        }.not_to change(Inventory, :count)

        expect(response).to have_http_status(422)
        expect(json_response).to include(
          "status" => "error",
          "code" => "transaction_failed",
          "message" => "トランザクション処理に失敗しました"
        )
      end
    end
  end

  # ============================================
  # 8. 非同期処理とコールバック
  # ============================================

  describe "Async Processing Errors" do
    describe "Job enqueueing failures" do
      it "ジョブキュー登録失敗で503を返す" do
        allow(ImportInventoriesJob).to receive(:perform_later)
          .and_raise(Redis::CannotConnectError)

        post "/api/v1/inventories/import",
             params: { file_url: "https://example.com/data.csv" }.to_json,
             headers: api_headers

        expect(response).to have_http_status(503)
        expect(json_response).to include(
          "status" => "error",
          "code" => "service_unavailable",
          "message" => "一時的にサービスを利用できません",
          "meta" => include(
            "retry_after" => be_present
          )
        )
      end
    end

    describe "Webhook failures" do
      it "Webhook通知失敗を記録する" do
        webhook = create(:webhook_endpoint,
          url: "https://customer.example.com/webhook",
          events: [ "inventory.created" ]
        )

        stub_request(:post, webhook.url).to_return(status: 500)

        post "/api/v1/inventories",
             params: {
               inventory: {
                 name: "Test Item",
                 quantity: 10,
                 price: 1000
               }
             }.to_json,
             headers: api_headers

        expect(response).to have_http_status(201)

        # Webhook失敗が記録される
        webhook_log = WebhookLog.last
        expect(webhook_log.status).to eq("failed")
        expect(webhook_log.response_code).to eq(500)
      end
    end
  end

  # ============================================
  # 9. データ整合性エラー
  # ============================================

  describe "Data Integrity Errors" do
    describe "Foreign key violations" do
      it "存在しない関連で422を返す" do
        post "/api/v1/inventories",
             params: {
               inventory: {
                 name: "Test Item",
                 quantity: 10,
                 price: 1000,
                 store_id: 999999  # 存在しない
               }
             }.to_json,
             headers: api_headers

        expect(response).to have_http_status(422)
        expect(json_response).to include(
          "status" => "error",
          "code" => "validation_error",
          "errors" => include(
            "store" => [ "が見つかりません" ]
          )
        )
      end
    end

    describe "Unique constraint violations" do
      it "ユニーク制約違反で409を返す" do
        existing = create(:inventory, sku: "UNIQUE-SKU-123")

        post "/api/v1/inventories",
             params: {
               inventory: {
                 name: "Another Item",
                 sku: "UNIQUE-SKU-123",  # 重複
                 quantity: 10,
                 price: 1000
               }
             }.to_json,
             headers: api_headers

        expect(response).to have_http_status(409)
        expect(json_response["errors"]).to include(
          "sku" => [ "はすでに存在します" ]
        )
      end
    end
  end

  # ============================================
  # 10. エラーレスポンスの一貫性
  # ============================================

  describe "Error Response Consistency" do
    it "全エラーレスポンスが統一されたフォーマットに従う" do
      # 様々なエラーを発生させる
      error_endpoints = [
        { method: :get, path: "/api/v1/inventories/999999", expected_status: 404 },
        { method: :post, path: "/api/v1/inventories", params: {}, expected_status: 422 },
        { method: :get, path: "/api/v1/inventories", headers: {}, expected_status: 401 }
      ]

      error_endpoints.each do |endpoint|
        headers = endpoint[:headers] || api_headers
        params = endpoint[:params]

        if endpoint[:method] == :get
          get endpoint[:path], headers: headers
        else
          post endpoint[:path], params: params.to_json, headers: headers
        end

        expect(response).to have_http_status(endpoint[:expected_status])

        # 共通フィールドの存在確認
        expect(json_response).to include(
          "status" => "error",
          "code" => be_present,
          "message" => be_present
        )

        # メタデータの構造確認
        if json_response["meta"]
          expect(json_response["meta"]).to include(
            "timestamp" => match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/),
            "request_id" => be_present
          )
        end
      end
    end

    it "エラー時もCORSヘッダーを含む" do
      get "/api/v1/inventories/999999", headers: api_headers

      expect(response.headers['Access-Control-Allow-Origin']).to be_present
      expect(response.headers['Access-Control-Allow-Methods']).to be_present
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def generate_api_token(user, expires_at: 1.hour.from_now)
    # JWTトークン生成のモック
    JWT.encode(
      {
        user_id: user.id,
        exp: expires_at.to_i
      },
      Rails.application.secret_key_base
    )
  end
end
