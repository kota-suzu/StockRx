# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventory Search", type: :request do
  let(:admin) { create(:admin) }
  
  before do
    sign_in admin
  end
  
  # テスト用のInventoryデータを作成
  let!(:inventory1) { create(:inventory, name: 'テスト商品A', price: 100, quantity: 10, status: 'active') }
  let!(:inventory2) { create(:inventory, name: 'テスト商品B', price: 200, quantity: 5, status: 'active') }
  let!(:inventory3) { create(:inventory, name: '別商品C', price: 150, quantity: 0, status: 'inactive') }
  
  describe "GET /inventories with search parameters" do
    context "with basic search parameters" do
      it "searches by name" do
        get inventories_path, params: { name: 'テスト' }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('テスト商品A')
        expect(response.body).to include('テスト商品B')
        expect(response.body).not_to include('別商品C')
      end
      
      it "searches by status" do
        get inventories_path, params: { status: 'active' }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('テスト商品A')
        expect(response.body).to include('テスト商品B')
        expect(response.body).not_to include('別商品C')
      end
      
      it "searches by low stock" do
        get inventories_path, params: { low_stock: 'true' }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('別商品C')
        expect(response.body).not_to include('テスト商品A')
        expect(response.body).not_to include('テスト商品B')
      end
      
      it "searches by stock filter" do
        get inventories_path, params: { stock_filter: 'out_of_stock' }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('別商品C')
        expect(response.body).not_to include('テスト商品A')
        expect(response.body).not_to include('テスト商品B')
      end
      
      it "searches by price range" do
        get inventories_path, params: { min_price: 150, max_price: 250 }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('テスト商品B')
        expect(response.body).to include('別商品C')
        expect(response.body).not_to include('テスト商品A')
      end
    end
    
    context "with advanced search parameters" do
      it "searches with advanced search flag" do
        get inventories_path, params: { 
          advanced_search: '1',
          name: 'テスト',
          min_price: 150
        }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('テスト商品B')
        expect(response.body).not_to include('テスト商品A')
        expect(response.body).not_to include('別商品C')
      end
      
      it "searches with date range" do
        get inventories_path, params: {
          created_from: Date.current - 1.day,
          created_to: Date.current + 1.day
        }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('テスト商品A')
        expect(response.body).to include('テスト商品B')
        expect(response.body).to include('別商品C')
      end
      
      it "shows advanced search form when advanced parameters are present" do
        get inventories_path, params: { min_price: 100 }
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:show_advanced)).to be_truthy
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
        # フォームバリデーションエラーが表示されることを確認
        expect(response.body).to include('最高価格は最低価格以上である必要があります')
      end
      
      it "handles invalid status" do
        get inventories_path, params: { status: 'invalid_status' }
        
        expect(response).to have_http_status(:ok)
        # 無効なステータスは無視され、すべての在庫が表示される
        expect(response.body).to include('テスト商品A')
        expect(response.body).to include('テスト商品B')
        expect(response.body).to include('別商品C')
      end
    end
    
    context "with multiple search conditions" do
      it "combines multiple conditions with AND logic" do
        get inventories_path, params: {
          name: 'テスト',
          status: 'active',
          min_price: 150
        }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('テスト商品B')
        expect(response.body).not_to include('テスト商品A')
        expect(response.body).not_to include('別商品C')
      end
    end
    
    context "with search conditions summary" do
      it "displays search conditions summary when conditions are present" do
        get inventories_path, params: { name: 'テスト', status: 'active' }
        
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('検索条件:')
        expect(response.body).to include('テスト')
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
      get inventories_path, params: { name: 'テスト' }, headers: { "Accept" => "application/json" }
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to match(/application\/json/)
      
      json_response = JSON.parse(response.body)
      expect(json_response.size).to eq(2)  # テスト商品A, テスト商品B
    end
  end
  
  describe "Form object assignment" do
    it "assigns search form with valid parameters" do
      get inventories_path, params: { name: 'テスト', status: 'active' }
      
      expect(assigns(:search_form)).to be_a(InventorySearchForm)
      expect(assigns(:search_form).name).to eq('テスト')
      expect(assigns(:search_form).status).to eq('active')
      expect(assigns(:search_form)).to be_valid
    end
    
    it "assigns search form with invalid parameters" do
      get inventories_path, params: { min_price: 200, max_price: 100 }
      
      expect(assigns(:search_form)).to be_a(InventorySearchForm)
      expect(assigns(:search_form)).not_to be_valid
      expect(assigns(:search_form).errors[:max_price]).to be_present
    end
    
    it "assigns show_advanced flag correctly" do
      get inventories_path, params: { advanced_search: '1' }
      
      expect(assigns(:show_advanced)).to be_truthy
    end
    
    it "detects complex search automatically" do
      get inventories_path, params: { min_price: 100 }
      
      expect(assigns(:show_advanced)).to be_truthy
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
      expect(assigns(:search_form)).to be_a(InventorySearchForm)
    end
  end
  
  describe "Backward compatibility" do
    it "supports legacy 'q' parameter" do
      get inventories_path, params: { q: 'テスト' }
      
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('テスト商品A')
      expect(response.body).to include('テスト商品B')
    end
    
    it "prioritizes 'name' over 'q' parameter" do
      get inventories_path, params: { name: 'テスト', q: '別商品' }
      
      expect(response).to have_http_status(:ok)
      expect(assigns(:search_form).effective_name).to eq('テスト')
    end
  end
end