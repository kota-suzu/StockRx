# frozen_string_literal: true

require 'rails_helper'

# CLAUDE.md準拠: セキュリティ実装の動作確認テスト
RSpec.describe "Security Implementation Validation", type: :controller do
  describe AdminControllers::InventoriesController do
    controller(AdminControllers::InventoriesController) do
      # テスト用のアクションを追加
      def test_sanitization
        # inventory_params_with_sanitizationのテスト
        sanitized_params = inventory_params_with_sanitization(params)
        render json: sanitized_params
      end
    end

    let(:admin) { create(:admin) }

    before do
      sign_in admin
      routes.draw { post "test_sanitization" => "admin_controllers/inventories#test_sanitization" }
    end

    describe "parameter sanitization" do
      it "文字列パラメータをサニタイズする" do
        post :test_sanitization, params: {
          inventory: {
            name: "  Test Product <script>alert('xss')</script>  ",
            sku: "SKU-123   \n\t  ",
            manufacturer: "Test Corp" * 50  # 長い文字列
          }
        }

        result = JSON.parse(response.body)

        # HTMLエスケープされる
        expect(result["name"]).to include("&lt;script&gt;")
        expect(result["name"]).not_to include("<script>")

        # 空白文字が正規化される
        expect(result["sku"]).to eq("SKU-123")

        # 文字列長が制限される
        expect(result["manufacturer"].length).to be <= 100
      end

      it "数値パラメータを検証する" do
        post :test_sanitization, params: {
          inventory: {
            name: "Test",
            quantity: "-100",  # 負の値
            price: "abc123"    # 不正な値
          }
        }

        # ArgumentError が発生してリダイレクトされる
        expect(response).to redirect_to(admin_inventories_path)
        expect(flash[:alert]).to include("負の数は入力できません")
      end
    end
  end

  describe StoreControllers::InventoriesController do
    controller(StoreControllers::InventoriesController) do
      def test_search_sanitization
        query = sanitize_search_query(params[:q])
        render json: { sanitized: query }
      end

      def test_sort_sanitization
        column = sanitize_sort_column(params[:sort],
          %w[inventories.name inventories.quantity])
        direction = sanitize_sort_direction(params[:direction])

        render json: { column: column, direction: direction }
      end
    end

    let(:store) { create(:store) }
    let(:store_user) { create(:store_user, store: store) }

    before do
      sign_in store_user
      allow(controller).to receive(:current_store).and_return(store)

      routes.draw do
        get "test_search" => "store_controllers/inventories#test_search_sanitization"
        get "test_sort" => "store_controllers/inventories#test_sort_sanitization"
      end
    end

    describe "search query sanitization" do
      it "SQLワイルドカードをエスケープする" do
        get :test_search_sanitization, params: { q: "Test%_Product" }

        result = JSON.parse(response.body)
        # % と _ がエスケープされる
        expect(result["sanitized"]).to eq("Test\\%\\_Product")
      end

      it "長いクエリを切り詰める" do
        long_query = "a" * 200
        get :test_search_sanitization, params: { q: long_query }

        result = JSON.parse(response.body)
        expect(result["sanitized"].length).to eq(100)
      end
    end

    describe "sort parameter sanitization" do
      it "許可されたカラムのみを受け入れる" do
        get :test_sort_sanitization, params: {
          sort: "inventories.secret_column",
          direction: "asc"
        }

        result = JSON.parse(response.body)
        # デフォルトカラムが返される
        expect(result["column"]).to eq("inventories.name")
        expect(result["direction"]).to eq("asc")
      end

      it "不正なソート順をデフォルトに変換する" do
        get :test_sort_sanitization, params: {
          sort: "inventories.name",
          direction: "random"
        }

        result = JSON.parse(response.body)
        expect(result["direction"]).to eq("asc")
      end
    end
  end

  describe "CSV Import Sanitization" do
    controller(AdminControllers::InventoriesController) do
      def test_csv_sanitization
        options = csv_import_params_with_sanitization(params)
        render json: options.except(:file)
      rescue ArgumentError => e
        render json: { error: e.message }, status: :bad_request
      end
    end

    let(:admin) { create(:admin) }

    before do
      sign_in admin
      routes.draw { post "test_csv" => "admin_controllers/inventories#test_csv_sanitization" }
    end

    it "CSVファイルパラメータを検証する" do
      csv_file = fixture_file_upload('test_inventory.csv', 'text/csv')

      post :test_csv_sanitization, params: {
        csv_file: csv_file,
        skip_invalid: "1",
        update_existing: "true",
        batch_size: "2000"
      }

      result = JSON.parse(response.body)

      expect(result["skip_invalid"]).to be true
      expect(result["update_existing"]).to be true
      expect(result["batch_size"]).to eq(2000)
      expect(result["filename"]).to eq("test_inventory.csv")
    end

    it "大きすぎるファイルを拒否する" do
      csv_file = fixture_file_upload('test_inventory.csv', 'text/csv')
      allow(csv_file).to receive(:size).and_return(11.megabytes)

      post :test_csv_sanitization, params: { csv_file: csv_file }

      result = JSON.parse(response.body)
      expect(response).to have_http_status(:bad_request)
      expect(result["error"]).to include("ファイルサイズが大きすぎます")
    end

    it "不正なファイル形式を拒否する" do
      exe_file = fixture_file_upload('malicious.exe', 'application/x-executable')

      post :test_csv_sanitization, params: { csv_file: exe_file }

      result = JSON.parse(response.body)
      expect(response).to have_http_status(:bad_request)
      expect(result["error"]).to include("CSVファイルを選択してください")
    end
  end

  describe "Integration Test" do
    let(:admin) { create(:admin) }

    before { sign_in admin }

    it "実際のcreateアクションでパラメータサニタイゼーションが動作する" do
      post :create, params: {
        inventory: {
          name: "<b>Test Product</b>",
          quantity: "100",
          price: "1000.50",
          status: "active",
          sku: "  SKU-001  ",
          manufacturer: "Test Company"
        }
      }

      inventory = Inventory.last

      # HTMLがエスケープされている
      expect(inventory.name).to include("&lt;b&gt;")
      expect(inventory.name).not_to include("<b>")

      # 数値が正しく変換されている
      expect(inventory.quantity).to eq(100)
      expect(inventory.price).to eq(1000.5)

      # 空白が除去されている
      expect(inventory.sku).to eq("SKU-001")
    end
  end
end
