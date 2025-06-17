# frozen_string_literal: true

require "rails_helper"

RSpec.describe StoreInventoriesController, type: :controller do
  let(:store) { create(:store, active: true) }
  let(:inactive_store) { create(:store, active: false) }
  let(:inventory) { create(:inventory, status: :active) }
  let(:archived_inventory) { create(:inventory, status: :archived) }
  
  before do
    # 店舗在庫を作成
    create(:store_inventory, store: store, inventory: inventory, quantity: 50)
    create(:store_inventory, store: store, inventory: archived_inventory, quantity: 30)
  end

  describe "GET #index" do
    context "正常系" do
      it "アクティブな店舗の在庫一覧を表示できる" do
        get :index, params: { store_id: store.id }
        
        expect(response).to have_http_status(:success)
        expect(assigns(:store)).to eq(store)
        expect(assigns(:store_inventories)).to be_present
      end

      it "アーカイブされた在庫は除外される" do
        get :index, params: { store_id: store.id }
        
        inventories = assigns(:store_inventories).map { |si| si.inventory }
        expect(inventories).to include(inventory)
        expect(inventories).not_to include(archived_inventory)
      end

      it "ページネーションが機能する" do
        # 追加の在庫を作成
        30.times do
          inv = create(:inventory, status: :active)
          create(:store_inventory, store: store, inventory: inv)
        end

        get :index, params: { store_id: store.id, page: 2 }
        
        expect(response).to have_http_status(:success)
        expect(assigns(:store_inventories).current_page).to eq(2)
      end

      it "ソート機能が動作する" do
        inventory_a = create(:inventory, name: "A商品", status: :active)
        inventory_z = create(:inventory, name: "Z商品", status: :active)
        create(:store_inventory, store: store, inventory: inventory_a)
        create(:store_inventory, store: store, inventory: inventory_z)

        get :index, params: { store_id: store.id, sort: "inventories.name", direction: "desc" }
        
        names = assigns(:store_inventories).map { |si| si.inventory.name }
        expect(names.first).to eq("Z商品")
      end

      it "JSON形式でレスポンスを返す" do
        get :index, params: { store_id: store.id }, format: :json
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json).to have_key("store")
        expect(json).to have_key("inventories")
        expect(json).to have_key("statistics")
      end
    end

    context "異常系" do
      it "存在しない店舗の場合リダイレクトされる" do
        get :index, params: { store_id: 999999 }
        
        expect(response).to redirect_to(stores_path)
        expect(flash[:alert]).to eq("指定された店舗が見つかりません")
      end

      it "非アクティブな店舗の場合アクセスできない" do
        get :index, params: { store_id: inactive_store.id }
        
        expect(response).to redirect_to(stores_path)
        expect(flash[:alert]).to eq("この店舗は現在利用できません")
      end
    end

    context "レート制限" do
      it "1分間に60回を超えるリクエストは拒否される" do
        # 60回リクエストを送信
        60.times do
          get :index, params: { store_id: store.id }
        end
        
        # 61回目のリクエスト
        get :index, params: { store_id: store.id }
        
        expect(response).to redirect_to(stores_path)
        expect(flash[:alert]).to include("リクエスト数が制限を超えました")
      end
    end
  end

  describe "GET #search" do
    let(:matching_inventory) { create(:inventory, name: "テスト薬品", sku: "TEST001", status: :active) }
    
    before do
      create(:store_inventory, store: store, inventory: matching_inventory)
    end

    context "正常系" do
      it "商品名で検索できる" do
        get :search, params: { store_id: store.id, q: "テスト" }, format: :json
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["count"]).to eq(1)
        expect(json["items"].first["name"]).to eq("テスト薬品")
      end

      it "SKUで検索できる" do
        get :search, params: { store_id: store.id, q: "TEST001" }, format: :json
        
        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["count"]).to eq(1)
      end

      it "最大20件までの結果を返す" do
        # 25件の在庫を作成
        25.times do |i|
          inv = create(:inventory, name: "検索対象#{i}", status: :active)
          create(:store_inventory, store: store, inventory: inv)
        end

        get :search, params: { store_id: store.id, q: "検索対象" }, format: :json
        
        json = JSON.parse(response.body)
        expect(json["items"].count).to eq(20)
      end
    end

    context "異常系" do
      it "検索キーワードが空の場合エラーを返す" do
        get :search, params: { store_id: store.id, q: "" }, format: :json
        
        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("検索キーワードを入力してください")
      end

      it "SQLインジェクション対策が機能する" do
        get :search, params: { store_id: store.id, q: "'; DROP TABLE inventories; --" }, format: :json
        
        expect(response).to have_http_status(:success)
        # テーブルが削除されていないことを確認
        expect(Inventory.count).to be > 0
      end
    end
  end

  # TODO: Phase 3 - より詳細なセキュリティテストの追加
  #   - XSS対策のテスト
  #   - CSRF対策のテスト
  #   - 機密情報のマスキング確認
  
  # TODO: Phase 4 - パフォーマンステストの追加
  #   - N+1クエリの検出
  #   - 大量データでの応答時間測定
  #   - キャッシュ効果の検証
end