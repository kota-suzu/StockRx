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
      'Content-Type' => 'application/json'
    }
  }

  # ============================================
  # 1. 基本的なAPIエラーハンドリング
  # ============================================

  describe "Basic API Error Responses" do
    describe "Resource not found" do
      it "存在しないリソースで404を返す" do
        get "/api/v1/inventories/999999", headers: api_headers

        expect(response).to have_http_status(404)
        json = JSON.parse(response.body)
        expect(json).to include("success" => false)
        expect(json["status_code"]).to eq(404)
      end
    end

    describe "Invalid JSON" do
      it "不正なJSONで400を返す" do
        post "/api/v1/inventories",
             params: '{"name": "Test", "quantity": }',  # 不正なJSON
             headers: api_headers

        expect(response).to have_http_status(400)
        json = JSON.parse(response.body)
        expect(json).to include("success" => false)
      end
    end

    describe "Validation errors" do
      it "バリデーションエラーで422を返す" do
        post "/api/v1/inventories",
             params: { inventory: { quantity: 10 } }.to_json,  # nameが欠落
             headers: api_headers

        expect(response).to have_http_status(422)
        json = JSON.parse(response.body)
        expect(json).to include("success" => false)
        expect(json["errors"]).to be_present
      end
    end
  end

  # ============================================
  # 2. エラーレスポンスの一貫性
  # ============================================

  describe "Error Response Consistency" do
    it "全エラーレスポンスが統一されたフォーマットに従う" do
      # 404エラー
      get "/api/v1/inventories/999999", headers: api_headers

      json = JSON.parse(response.body)
      expect(json).to include(
        "success" => false,
        "data" => nil,
        "message" => be_present,
        "errors" => be_a(Array),
        "metadata" => be_a(Hash),
        "status_code" => 404
      )

      # メタデータの確認
      expect(json["metadata"]).to include(
        "timestamp" => match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/),
        "request_id" => be_present,
        "version" => "v1"
      )
    end
  end

  # ============================================
  # 3. カスタムエラーハンドリング
  # ============================================

  describe "Custom Error Handling" do
    let(:inventory) { create(:inventory) }

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
      json = JSON.parse(response.body)
      expect(json).to include("success" => false)
      expect(json["status_code"]).to eq(409)
    end
  end

  # ============================================
  # 4. HTML/JSONフォーマット対応
  # ============================================

  describe "Content Type Handling" do
    it "HTMLリクエストには404ページを返す" do
      get "/inventories/999999", headers: { 'Accept' => 'text/html' }

      expect(response).to have_http_status(404)
      expect(response.content_type).to include("text/html")
    end

    it "JSONリクエストにはJSONエラーを返す" do
      get "/api/v1/inventories/999999", headers: { 'Accept' => 'application/json' }

      expect(response).to have_http_status(404)
      expect(response.content_type).to include("application/json")
    end
  end

  # ============================================
  # 5. セキュリティヘッダー
  # ============================================

  describe "Security Headers" do
    it "エラーレスポンスに適切なセキュリティヘッダーを含む" do
      get "/api/v1/inventories/999999", headers: api_headers

      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['X-Frame-Options']).to eq('DENY')
      expect(response.headers['X-XSS-Protection']).to eq('1; mode=block')
    end
  end

  private

  def json_response
    JSON.parse(response.body)
  end
end
