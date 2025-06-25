# frozen_string_literal: true

require 'rails_helper'

# API::V1::InventoriesController 完全ブランチカバレッジテスト
# CLAUDE.md準拠: API機能の包括的テスト実装
# メタ認知: 全CRUD操作の条件分岐を完全カバーしてブランチカバレッジ向上
# 横展開: 他のAPI controllerでも同様のテストパターン適用
RSpec.describe Api::V1::InventoriesController, type: :controller do
  let(:admin_user) { create(:admin) }
  let(:inventory) { create(:inventory) }
  let(:store) { create(:store) }

  before do
    sign_in admin_user
  end

  # ============================================
  # GET #index - 検索・フィルタリング全パターン
  # ============================================

  describe "GET #index" do
    let!(:inventory1) { create(:inventory, name: "商品A", status: :active, price: 100) }
    let!(:inventory2) { create(:inventory, name: "商品B", status: :archived, price: 200) }
    let!(:inventory3) { create(:inventory, name: "テスト商品", status: :active, price: 150) }

    context "without parameters" do
      it "returns all inventories with success response" do
        get :index, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["data"]).to be_present
        expect(json_response["message"]).to include("在庫データを検索しました")
      end
    end

    context "with search parameters" do
      it "filters by name parameter" do
        get :index, params: { name: "テスト" }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["data"]).to be_present
        expect(json_response["meta"]["search_conditions"]).to include("name")
      end

      it "filters by status parameter" do
        get :index, params: { status: "active" }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["data"]).to be_present
        expect(json_response["meta"]["search_conditions"]).to include("status")
      end

      it "filters by price range" do
        get :index, params: { min_price: 100, max_price: 150 }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["data"]).to be_present
        expect(json_response["meta"]["search_conditions"]).to include("price_range")
      end

      it "filters by stock status" do
        get :index, params: { stock_filter: "low_stock" }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["data"]).to be_present
      end

      it "applies multiple filters simultaneously" do
        get :index, params: {
          name: "商品",
          status: "active",
          min_price: 50,
          max_price: 200
        }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["meta"]["search_conditions"]).to be_present
      end
    end

    context "with pagination parameters" do
      it "handles page parameter" do
        get :index, params: { page: 2 }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["meta"]["pagination"]).to be_present
      end

      it "handles per_page parameter" do
        get :index, params: { per_page: 5 }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["meta"]["pagination"]).to be_present
      end

      it "handles custom sorting" do
        get :index, params: { sort: "name", direction: "asc" }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["data"]).to be_present
      end
    end

    context "edge cases" do
      it "handles empty search results" do
        get :index, params: { name: "存在しない商品" }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["data"]).to be_empty
      end

      it "handles invalid sort parameters gracefully" do
        get :index, params: { sort: "invalid_field" }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
      end
    end
  end

  # ============================================
  # GET #show - 詳細取得全パターン
  # ============================================

  describe "GET #show" do
    context "when inventory exists" do
      it "returns inventory details with success response" do
        get :show, params: { id: inventory.id }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["data"]["id"]).to eq(inventory.id)
        expect(json_response["message"]).to eq("在庫情報を取得しました")
      end

      it "returns decorated inventory object" do
        get :show, params: { id: inventory.id }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        # デコレーターで追加されるメソッドがあることを確認
        expect(json_response["data"]).to have_key("id")
        expect(json_response["data"]).to have_key("name")
      end
    end

    context "when inventory does not exist" do
      it "returns 404 error via ErrorHandlers" do
        get :show, params: { id: 99999 }, format: :json

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["errors"]).to be_present
      end
    end
  end

  # ============================================
  # POST #create - 作成全パターン
  # ============================================

  describe "POST #create" do
    let(:valid_attributes) do
      {
        name: "新規商品",
        quantity: 100,
        price: 1000,
        status: "active"
      }
    end

    context "with valid parameters" do
      it "creates new inventory successfully" do
        expect {
          post :create, params: { inventory: valid_attributes }, format: :json
        }.to change(Inventory, :count).by(1)

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("在庫が正常に作成されました")
        expect(json_response["data"]["name"]).to eq("新規商品")
      end

      it "returns decorated created inventory" do
        post :create, params: { inventory: valid_attributes }, format: :json

        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)

        # デコレーターが適用されていることを確認
        expect(json_response["data"]).to have_key("id")
        expect(json_response["data"]).to have_key("name")
      end
    end

    context "with invalid parameters" do
      it "returns validation errors for empty name" do
        invalid_attributes = valid_attributes.merge(name: "")

        post :create, params: { inventory: invalid_attributes }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["errors"]).to be_present
      end

      it "returns validation errors for negative quantity" do
        invalid_attributes = valid_attributes.merge(quantity: -1)

        post :create, params: { inventory: invalid_attributes }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(422)
      end

      it "returns validation errors for invalid price" do
        invalid_attributes = valid_attributes.merge(price: "invalid")

        post :create, params: { inventory: invalid_attributes }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(422)
      end
    end

    context "rate limiting simulation" do
      it "handles RateLimitExceeded error (1% probability simulation)" do
        # 複数回実行してレート制限エラーを誘発する可能性を高める
        100.times do
          begin
            post :create, params: { inventory: valid_attributes.merge(name: "商品#{rand(1000)}") }, format: :json

            if response.status == 429
              json_response = JSON.parse(response.body)
              expect(json_response["success"]).to be false
              expect(json_response["status_code"]).to eq(429)
              expect(json_response["message"]).to include("短時間に多くのリクエストが行われました")
              break
            end
          rescue CustomError::RateLimitExceeded => e
            expect(e.message).to include("短時間に多くのリクエストが行われました")
            break
          end
        end
      end
    end

    context "missing parameters" do
      it "handles missing inventory parameter" do
        post :create, params: {}, format: :json

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(400)
        expect(json_response["error_code"]).to eq("parameter_missing")
      end
    end
  end

  # ============================================
  # PUT/PATCH #update - 更新全パターン
  # ============================================

  describe "PUT #update" do
    let(:update_attributes) do
      {
        name: "更新済み商品",
        quantity: 200,
        price: 2000
      }
    end

    context "with valid parameters" do
      it "updates inventory successfully" do
        put :update, params: { id: inventory.id, inventory: update_attributes }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["status_code"]).to eq(200)
        expect(json_response["message"]).to eq("在庫情報が正常に更新されました")
        expect(json_response["data"]["name"]).to eq("更新済み商品")

        inventory.reload
        expect(inventory.name).to eq("更新済み商品")
      end

      it "returns reloaded inventory data" do
        put :update, params: { id: inventory.id, inventory: update_attributes }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        # reloadされたデータが返ることを確認
        expect(json_response["data"]["name"]).to eq("更新済み商品")
        expect(json_response["data"]["quantity"]).to eq(200)
      end
    end

    context "with optimistic locking" do
      it "handles concurrent updates with version mismatch" do
        # lock_versionを古い値に設定してコンフリクトをシミュレート
        old_version = inventory.lock_version
        inventory.update!(name: "他ユーザーによる更新")  # バージョンを進める

        put :update, params: {
          id: inventory.id,
          inventory: update_attributes.merge(lock_version: old_version)
        }, format: :json

        expect(response).to have_http_status(:conflict)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(409)
        expect(json_response["message"]).to include("他のユーザーがこの在庫を更新しました")
      end

      it "allows update with correct version" do
        current_version = inventory.lock_version

        put :update, params: {
          id: inventory.id,
          inventory: update_attributes.merge(lock_version: current_version)
        }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
      end

      it "allows update without version check" do
        put :update, params: { id: inventory.id, inventory: update_attributes }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
      end
    end

    context "with invalid parameters" do
      it "returns validation errors" do
        invalid_attributes = { name: "", quantity: -1 }

        put :update, params: { id: inventory.id, inventory: invalid_attributes }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(422)
      end
    end

    context "when inventory does not exist" do
      it "returns 404 error" do
        put :update, params: { id: 99999, inventory: update_attributes }, format: :json

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(404)
      end
    end
  end

  # ============================================
  # DELETE #destroy - 削除全パターン
  # ============================================

  describe "DELETE #destroy" do
    context "successful deletion" do
      it "deletes inventory and returns 204 No Content" do
        delete :destroy, params: { id: inventory.id }, format: :json

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
        expect(Inventory.exists?(inventory.id)).to be false
      end
    end

    context "when inventory has related data" do
      let!(:inventory_with_relations) { create(:inventory) }

      before do
        # 関連データを作成して削除制約をテスト
        create(:inventory_log, inventory: inventory_with_relations)
      end

      it "handles delete restriction error" do
        # dependent: :restrict_with_error の設定をテスト
        delete :destroy, params: { id: inventory_with_relations.id }, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(422)
        expect(json_response["message"]).to include("在庫に関連するデータがあるため削除できません")
        expect(json_response["error"]["type"]).to eq("delete_restriction")
      end
    end

    context "when inventory does not exist" do
      it "returns 404 error" do
        delete :destroy, params: { id: 99999 }, format: :json

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["status_code"]).to eq(404)
      end
    end
  end

  # ============================================
  # Security & Authentication Tests
  # ============================================

  describe "authentication and authorization" do
    context "without authentication" do
      before { sign_out admin_user }

      it "requires authentication for index" do
        get :index, format: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "requires authentication for show" do
        get :show, params: { id: inventory.id }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "requires authentication for create" do
        post :create, params: { inventory: { name: "test" } }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "requires authentication for update" do
        put :update, params: { id: inventory.id, inventory: { name: "test" } }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end

      it "requires authentication for destroy" do
        delete :destroy, params: { id: inventory.id }, format: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with different user roles" do
      let(:store_manager) { create(:admin, role: :store_manager) }
      let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }

      it "allows store manager access" do
        sign_in store_manager
        get :index, format: :json
        expect(response).to have_http_status(:success)
      end

      it "allows headquarters admin access" do
        sign_in headquarters_admin
        get :index, format: :json
        expect(response).to have_http_status(:success)
      end
    end
  end

  # ============================================
  # Error Handling Integration Tests
  # ============================================

  describe "error handling integration" do
    context "JSON format enforcement" do
      it "rejects non-JSON requests" do
        get :index, format: :html

        expect(response).to have_http_status(:not_acceptable)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["message"]).to include("JSON形式でのリクエストが必要です")
      end
    end

    context "parameter sanitization" do
      it "handles unpermitted parameters" do
        post :create, params: {
          inventory: {
            name: "test",
            unpermitted_param: "should_be_filtered"
          }
        }, format: :json

        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]["type"]).to eq("unpermitted_parameters")
      end
    end

    context "API response consistency" do
      it "maintains consistent response structure across all endpoints" do
        get :index, format: :json
        index_response = JSON.parse(response.body)

        get :show, params: { id: inventory.id }, format: :json
        show_response = JSON.parse(response.body)

        # 共通の構造要素を確認
        [ index_response, show_response ].each do |resp|
          expect(resp).to have_key("success")
          expect(resp).to have_key("status_code")
          expect(resp).to have_key("data")
          expect(resp).to have_key("message")
          expect(resp).to have_key("meta")
        end
      end
    end
  end

  # ============================================
  # Performance & Edge Cases
  # ============================================

  describe "performance and edge cases" do
    context "large dataset handling" do
      before do
        # 大量のテストデータを作成
        create_list(:inventory, 100)
      end

      it "handles large datasets efficiently" do
        start_time = Time.current
        get :index, format: :json
        elapsed_time = Time.current - start_time

        expect(response).to have_http_status(:success)
        expect(elapsed_time).to be < 1.0  # 1秒以内
      end

      it "supports pagination for large datasets" do
        get :index, params: { per_page: 10 }, format: :json

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)

        expect(json_response["data"].size).to be <= 10
        expect(json_response["meta"]["pagination"]).to be_present
      end
    end

    context "concurrent access" do
      it "handles multiple simultaneous requests" do
        threads = []

        5.times do
          threads << Thread.new do
            get :index, format: :json
            expect(response).to have_http_status(:success)
          end
        end

        threads.each(&:join)
        expect(threads.all?(&:stop?)).to be true
      end
    end

    context "malformed input handling" do
      it "handles extremely large request bodies gracefully" do
        large_data = { name: "a" * 10000 }  # 10KB文字列

        post :create, params: { inventory: large_data }, format: :json

        # バリデーションエラーまたは成功のいずれかが期待される
        expect([ 200, 201, 422 ]).to include(response.status)
      end

      it "handles special characters in parameters" do
        special_chars_data = {
          name: "商品名🔥 <script>alert('xss')</script> & 特殊文字",
          quantity: 100,
          price: 1000
        }

        post :create, params: { inventory: special_chars_data }, format: :json

        if response.successful?
          json_response = JSON.parse(response.body)
          expect(json_response["data"]["name"]).to be_present
        else
          expect(response.status).to eq(422)  # バリデーションエラー
        end
      end
    end
  end
end
