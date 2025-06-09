# frozen_string_literal: true

require "rails_helper"

# TODO: 🟢 推奨改善（Phase 3）- API v1テストの完全化
# 場所: spec/requests/api/v1/inventories_spec.rb
# 問題: エラーレスポンス形式の統一
# 解決策: 標準エラーレスポンス形式の実装
# 推定工数: 1週間
#
# 具体的な修正内容:
# 1. API エラーレスポンスの標準化（JSON Schema準拠）
# 2. 認証・認可エラーの統一的な処理
# 3. バリデーションエラーの詳細情報の一貫性確保
# 4. HTTP ステータスコードの適切な使用法の統一
# 5. OpenAPI（Swagger）仕様書の自動生成対応

RSpec.describe "Api::V1::Inventories", type: :request do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
  end

  let(:valid_attributes) do
    {
      name: "API Test Medicine",
      category: "prescription",
      unit: "錠",
      quantity: 100,
      minimum_stock: 10,
      price: 1500
    }
  end

  let(:invalid_attributes) do
    {
      name: "",
      category: "invalid",
      quantity: -10
    }
  end

  let(:headers) do
    { "Accept" => "application/json", "Content-Type" => "application/json" }
  end

  # TODO: ベストプラクティス - 共通のヘルパーメソッド
  # APIレスポンス構造の検証を共通化
  def parse_api_response(response)
    JSON.parse(response.body)
  end

  def expect_successful_response(response, status = :ok)
    expect(response).to have_http_status(status)
    expect(response.content_type).to match(/application\/json/)

    json = parse_api_response(response)
    expect(json["success"]).to be true
    expect(json["data"]).to be_present
    expect(json["message"]).to be_present
    expect(json["errors"]).to be_an(Array)
    expect(json["metadata"]).to be_a(Hash)

    json
  end

  def expect_error_response(response, status, expected_error_type = nil)
    expect(response).to have_http_status(status)
    expect(response.content_type).to match(/application\/json/)

    json = parse_api_response(response)
    expect(json["success"]).to be false
    expect(json["data"]).to be_nil
    expect(json["message"]).to be_present
    expect(json["errors"]).to be_an(Array)
    expect(json["metadata"]).to be_a(Hash)

    if expected_error_type
      expect(json["metadata"]["type"]).to eq(expected_error_type)
    end

    json
  end

  describe "GET /api/v1/inventories" do
    # TODO: テストアイソレーション強化（優先度：高）
    # 他のテストの影響を受けないよう、各テストで独立したデータセットを使用

    it "returns all inventories" do
      # テスト前にクリーンアップしてアイソレーション確保
      Inventory.destroy_all

      # このテスト専用のデータを作成
      api_test_inventories = create_list(:inventory, 3, name: "API Test Item")

      get api_v1_inventories_path, headers: headers

      json = expect_successful_response(response)

      # ApiResponse構造でのデータアクセス
      inventories_data = json["data"]
      expect(inventories_data.size).to eq(3)

      # データの整合性も確認
      inventory_names = inventories_data.map { |item| item["name"] }
      expect(inventory_names).to all(include("API Test Item"))

      # メタデータの検証
      expect(json["metadata"]["pagination"]).to be_present
      expect(json["metadata"]["search"]).to be_present
    end
  end

  describe "GET /api/v1/inventories/:id" do
    context "when the inventory exists" do
      let(:inventory) { create(:inventory) }

      it "returns the inventory" do
        get api_v1_inventory_path(inventory), headers: headers

        json = expect_successful_response(response)

        # ApiResponse構造でのデータアクセス
        inventory_data = json["data"]
        expect(inventory_data["id"]).to eq(inventory.id)
        expect(inventory_data["name"]).to eq(inventory.name)
      end
    end

    context "when the inventory does not exist" do
      it "returns 404 with proper error format" do
        get api_v1_inventory_path(id: "non-existent"), headers: headers

        json = expect_error_response(response, :not_found, "not_found")

        # エラーメッセージの検証
        expect(json["message"]).to include("見つかりません")
      end
    end
  end

  describe "POST /api/v1/inventories" do
    context "with valid parameters" do
      it "creates a new inventory" do
        expect {
          post api_v1_inventories_path,
               params: { inventory: valid_attributes }.to_json,
               headers: headers
        }.to change(Inventory, :count).by(1)

        json = expect_successful_response(response, :created)

        # ApiResponse構造でのデータアクセス
        inventory_data = json["data"]
        expect(inventory_data["name"]).to eq(valid_attributes[:name])
      end
    end

    context "with invalid parameters" do
      it "returns validation error" do
        post api_v1_inventories_path,
             params: { inventory: invalid_attributes }.to_json,
             headers: headers

        json = expect_error_response(response, :unprocessable_entity, "validation_error")

        # バリデーションエラーの詳細確認
        expect(json["errors"]).not_to be_empty
      end
    end

    context "with missing required parameter" do
      it "returns bad request" do
        post api_v1_inventories_path,
             params: { wrong_root: valid_attributes }.to_json,
             headers: headers

        json = expect_error_response(response, :bad_request)

        # パラメータ不足エラーの確認（実際のメッセージに合わせる）
        expect(json["message"]).to include("param is missing")
      end
    end
  end

  describe "PUT /api/v1/inventories/:id" do
    let(:inventory) { create(:inventory) }
    let(:new_attributes) { { name: "Updated Medicine Name" } }

    context "with valid parameters" do
      it "updates the inventory" do
        put api_v1_inventory_path(inventory),
            params: { inventory: new_attributes }.to_json,
            headers: headers

        json = expect_successful_response(response)

        # ApiResponse構造でのデータアクセス
        inventory_data = json["data"]
        expect(inventory_data["name"]).to eq(new_attributes[:name])

        inventory.reload
        expect(inventory.name).to eq(new_attributes[:name])
      end
    end

    context "with invalid parameters" do
      it "returns validation error" do
        put api_v1_inventory_path(inventory),
            params: { inventory: { name: "" } }.to_json,
            headers: headers

        json = expect_error_response(response, :unprocessable_entity, "validation_error")

        # バリデーションエラーの詳細確認
        expect(json["errors"]).not_to be_empty
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        put api_v1_inventory_path(id: "non-existent"),
            params: { inventory: new_attributes }.to_json,
            headers: headers

        json = expect_error_response(response, :not_found, "not_found")
      end
    end
  end

  describe "DELETE /api/v1/inventories/:id" do
    # TODO: テストアイソレーション強化（優先度：高）
    # 削除テスト専用のInventoryを作成し、他のテストの影響を排除
    let!(:test_inventory) { create(:inventory, name: "DELETE_TEST_ITEM_#{SecureRandom.hex(4)}") }

    context "when the inventory exists" do
      it "deletes the inventory" do
        # テスト前の状態確認
        initial_count = Inventory.count

        expect {
          delete api_v1_inventory_path(test_inventory), headers: headers
        }.to change(Inventory, :count).by(-1)

        # 204 No Contentレスポンスの検証
        expect(response).to have_http_status(:no_content)

        # 204レスポンスの場合、ボディが空の可能性があるため条件分岐
        if response.body.present? && !response.body.strip.empty?
          json = parse_api_response(response)
          expect(json["success"]).to be true
          expect(json["data"]).to be_nil
          expect(json["message"]).to include("削除されました")
        else
          # 空のボディの場合はHTTPステータスコードのみ確認
          # これはRESTの標準的な204 No Contentレスポンス
          Rails.logger.info "204 No Content with empty body (standard REST response)"
        end

        # 削除されたことを確認
        expect(Inventory.find_by(id: test_inventory.id)).to be_nil
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        delete api_v1_inventory_path(id: "non-existent"), headers: headers

        json = expect_error_response(response, :not_found, "not_found")
      end
    end
  end

  # TODO: 追加テストケース（横展開確認）
  # 1. ページネーション機能のテスト
  # 2. 並び替え機能のテスト
  # 3. フィルタリング機能のテスト
  # 4. レート制限テスト
  # 5. 楽観的ロック競合テスト

  describe "Additional API Features (TODO)" do
    # TODO: 🔴 緊急 - Phase 1（推定1-2日） - ページネーション機能テスト
    # 優先度: 高（API利用者にとって必須機能）
    # 実装内容:
    # - Kaminari gemベースのページネーション実装
    # - メタデータ（total_count, total_pages, current_page）の返却
    # - per_page パラメータでの件数制御（デフォルト: 25, 最大: 100）
    # - レスポンス例: { "data": [...], "meta": { "current_page": 1, "total_pages": 5, "total_count": 120 } }
    # 横展開確認: 他のAPIエンドポイント（/batches, /inventory_logs）でも同様実装
    context "pagination" do
      pending "implements pagination parameter tests"
      # it "returns paginated results with correct metadata"
      # it "handles page and per_page parameters correctly"
      # it "returns proper pagination metadata"
      # it "validates page parameter bounds (min: 1)"
      # it "validates per_page parameter bounds (min: 1, max: 100)"
      # it "handles invalid page parameters gracefully"
    end

    # TODO: 🔴 緊急 - Phase 1（推定1-2日） - 検索・フィルタリング機能テスト
    # 優先度: 高（在庫検索は基本機能）
    # 実装内容:
    # - 商品名による部分一致検索（大文字小文字無視）
    # - ステータス別フィルタリング（active, inactive, discontinued）
    # - 価格範囲検索（min_price, max_price）
    # - 数量範囲検索（min_quantity, max_quantity）
    # - 複数条件の AND/OR 組み合わせ
    # - SQLインジェクション対策（パラメータバリデーション）
    # 横展開確認: web版検索機能（InventorySearchForm）との整合性確保
    context "search and filtering" do
      pending "implements search parameter tests"
      # it "filters by name parameter"
      # it "filters by status parameter"
      # it "filters by price range"
      # it "combines multiple filters correctly"
      # it "handles empty search results gracefully"
      # it "validates search parameter safety (XSS, SQLi prevention)"
    end

    # TODO: 🟡 重要 - Phase 2（推定1日） - 並び替え機能テスト
    # 優先度: 中（ユーザビリティ向上）
    # 実装内容:
    # - ソート可能フィールド（name, price, quantity, updated_at, created_at）
    # - ソート方向（asc, desc）
    # - デフォルトソート（updated_at desc）
    # - 複数フィールドソート（例: name asc, price desc）
    # - 不正フィールド指定時のエラーハンドリング
    # 横展開確認: web版ソート機能（BaseSearchForm）との一貫性
    context "sorting" do
      pending "implements sorting parameter tests"
      # it "sorts by different fields"
      # it "handles sort direction correctly"
      # it "defaults to appropriate sorting"
      # it "validates sortable fields"
      # it "handles invalid sort parameters gracefully"
    end

    # TODO: 🟢 推奨 - Phase 3（推定2-3日） - 高度API機能
    # 優先度: 低（機能拡張・将来対応）
    # 実装内容:
    # - バルク操作API（一括更新、一括削除）
    # - エクスポート機能（CSV, Excel形式）
    # - リアルタイム更新（WebSocket/Server-Sent Events）
    # - API レート制限とクォータ管理
    # - APIバージョニング（v2 準備）
    #
    # context "bulk operations" do
    #   pending "implements bulk update/delete operations"
    # end
    #
    # context "real-time updates" do
    #   pending "implements WebSocket/SSE integration"
    # end
    #
    # context "export functionality" do
    #   pending "implements CSV/Excel export"
    # end
  end
end
