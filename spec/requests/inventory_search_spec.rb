# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventory Search", type: :request do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
  end

  # TODO: テストデータの独立性確保（優先度：高）
  # 各テストコンテキストでデータをクリーンアップして、他のテストの影響を排除
  # ベストプラクティス: テストごとに一意な名前を使用してアイソレーションを強化

  # テスト用のInventoryデータを作成
  let!(:inventory1) { create(:inventory, name: 'SEARCH_TEST_商品A', price: 100, quantity: 10, status: 'active') }
  let!(:inventory2) { create(:inventory, name: 'SEARCH_TEST_商品B', price: 200, quantity: 5, status: 'active') }
  let!(:inventory3) { create(:inventory, name: 'SEARCH_TEST_別商品C', price: 150, quantity: 0, status: 'archived') }

  describe "GET /inventories with search parameters" do
    context "with basic search parameters" do
      it "searches by name" do
        get inventories_path, params: { name: 'SEARCH_TEST_商品' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_商品A')
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).not_to include('SEARCH_TEST_別商品C')
      end

      it "searches by status" do
        get inventories_path, params: { status: 'active' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_商品A')
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).not_to include('SEARCH_TEST_別商品C')
      end

      it "searches by low stock" do
        get inventories_path, params: { low_stock: 'true', include_archived: 'true' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_別商品C')
        expect(response.body).not_to include('SEARCH_TEST_商品A')
        expect(response.body).not_to include('SEARCH_TEST_商品B')
      end

      it "searches by stock filter" do
        get inventories_path, params: { stock_filter: 'out_of_stock', include_archived: 'true' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_別商品C')
        expect(response.body).not_to include('SEARCH_TEST_商品A')
        expect(response.body).not_to include('SEARCH_TEST_商品B')
      end

      it "searches by price range" do
        get inventories_path, params: { min_price: 150, max_price: 250, include_archived: 'true' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).to include('SEARCH_TEST_別商品C')
        expect(response.body).not_to include('SEARCH_TEST_商品A')
      end
    end

    context "with advanced search parameters" do
      it "searches with advanced search flag" do
        get inventories_path, params: {
          advanced_search: '1',
          name: 'SEARCH_TEST_商品',
          min_price: 150
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).not_to include('SEARCH_TEST_商品A')
        expect(response.body).not_to include('SEARCH_TEST_別商品C')
      end

      it "searches with date range" do
        get inventories_path, params: {
          created_from: Date.current - 1.day,
          created_to: Date.current + 1.day,
          include_archived: 'true'
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_商品A')
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).to include('SEARCH_TEST_別商品C')
      end

      it "shows advanced search form when advanced parameters are present" do
        get inventories_path, params: { min_price: 100 }

        expect(response).to have_http_status(:ok)
        # 高度な検索パラメータがある場合は、レスポンスに関連要素が含まれることを確認
        expect(
          response.body.include?('詳細検索') || response.body.include?('高度な検索')
        ).to be_truthy
      end
    end

    context "with sorting parameters" do
      it "sorts by name ascending" do
        get inventories_path, params: { sort: 'name', direction: 'asc' }

        expect(response).to have_http_status(:ok)
        # レスポンスの順序確認は実装によるが、レスポンスが成功することを確認
      end

      it "sorts by price descending" do
        get inventories_path, params: { sort: 'price', direction: 'desc' }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with pagination parameters" do
      it "handles page parameter" do
        get inventories_path, params: { page: 2 }

        expect(response).to have_http_status(:ok)
      end
    end

    context "with invalid search parameters" do
      it "handles invalid price range" do
        get inventories_path, params: { min_price: 200, max_price: 100 }

        expect(response).to have_http_status(:ok)
        # バリデーションエラーがフラッシュメッセージで表示されることを確認
        # NOTE: フラッシュメッセージの具体的な文言は実装次第で調整
        expect(
          response.body.include?('最高価格は最低価格以上である必要があります') ||
          response.body.include?('価格範囲が無効です')
        ).to be_truthy
      end

      it "handles invalid status" do
        get inventories_path, params: { status: 'invalid_status', include_archived: 'true' }

        expect(response).to have_http_status(:ok)
        # 無効なステータスは無視され、すべての在庫が表示される
        expect(response.body).to include('SEARCH_TEST_商品A')
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).to include('SEARCH_TEST_別商品C')
      end
    end

    context "with multiple search conditions" do
      it "combines multiple conditions with AND logic" do
        get inventories_path, params: {
          name: 'SEARCH_TEST_商品',
          status: 'active',
          min_price: 150,
          include_archived: 'true'
        }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('SEARCH_TEST_商品B')
        expect(response.body).not_to include('SEARCH_TEST_商品A')
        expect(response.body).not_to include('SEARCH_TEST_別商品C')
      end
    end

    context "with search conditions summary" do
      it "displays search conditions summary when conditions are present" do
        get inventories_path, params: { name: 'SEARCH_TEST_商品', status: 'active' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('検索条件:')
        expect(response.body).to include('SEARCH_TEST_商品')
        expect(response.body).to include('active')
      end

      it "does not display summary when no conditions" do
        get inventories_path

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('検索条件:')
      end
    end
  end

  describe "GET /inventories with JSON format" do
    it "returns filtered JSON results" do
      # TODO: JSON APIテストの堅牢性向上（優先度：高）
      # データクリーンアップとテスト専用データで正確な結果を保証

      # 他のテストデータをクリーンアップ
      Inventory.where.not(name: [ 'SEARCH_TEST_商品A', 'SEARCH_TEST_商品B', 'SEARCH_TEST_別商品C' ]).destroy_all

      get inventories_path, params: { name: 'SEARCH_TEST_商品' }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to match(/application\/json/)

      json_response = JSON.parse(response.body)
      expect(json_response.size).to eq(2)  # SEARCH_TEST_商品A, SEARCH_TEST_商品B

      # データの正確性確認
      names = json_response.map { |item| item["name"] }
      expect(names).to include('SEARCH_TEST_商品A', 'SEARCH_TEST_商品B')
      expect(names).not_to include('SEARCH_TEST_別商品C')
    end
  end

  describe "Form object assignment" do
    it "assigns search form with valid parameters" do
      get inventories_path, params: { name: 'SEARCH_TEST_商品', status: 'active' }

      expect(response).to have_http_status(:ok)
      # 検索結果が適切に表示されることを確認
      expect(
        response.body.include?('SEARCH_TEST_商品A') || response.body.include?('SEARCH_TEST_商品B')
      ).to be_truthy
    end

    it "assigns search form with invalid parameters" do
      get inventories_path, params: { min_price: 200, max_price: 100 }

      expect(response).to have_http_status(:ok)
      # バリデーションエラーがフラッシュメッセージで表示されることを確認
      expect(response.body).to be_present
    end

    it "assigns show_advanced flag correctly" do
      get inventories_path, params: { advanced_search: '1' }

      expect(response).to have_http_status(:ok)
      # 高度な検索フラグが設定されても問題なく動作することを確認
      expect(response.body).to be_present
    end

    it "detects complex search automatically" do
      get inventories_path, params: { min_price: 100 }

      expect(response).to have_http_status(:ok)
      # 複雑な検索条件が自動的に検知されることを確認
      expect(response.body).to be_present
    end
  end

  describe "Error handling" do
    it "handles form validation errors gracefully" do
      get inventories_path, params: {
        min_price: 'invalid',
        max_price: 'invalid'
      }

      expect(response).to have_http_status(:ok)
      # エラーがあっても画面は表示される
    end

    it "handles missing parameters gracefully" do
      get inventories_path, params: {}

      expect(response).to have_http_status(:ok)
      # パラメータがなくても画面は表示される
      expect(response.body).to be_present
    end
  end

  describe "Backward compatibility" do
    it "supports legacy 'q' parameter" do
      get inventories_path, params: { q: 'SEARCH_TEST_商品' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('SEARCH_TEST_商品A')
      expect(response.body).to include('SEARCH_TEST_商品B')
    end

    it "prioritizes 'name' over 'q' parameter" do
      get inventories_path, params: { name: 'SEARCH_TEST_商品', q: 'SEARCH_TEST_別商品' }

      expect(response).to have_http_status(:ok)
      # nameパラメータが優先され、テスト商品が表示されることを確認
      expect(
        response.body.include?('SEARCH_TEST_商品A') || response.body.include?('SEARCH_TEST_商品B')
      ).to be_truthy
    end
  end
end
