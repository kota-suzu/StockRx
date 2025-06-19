# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::InventoriesController, type: :controller do
  # CLAUDE.md準拠: 店舗在庫コントローラーの包括的テスト
  # メタ認知: 認証ベースの分岐と複雑なフィルタリングロジックの品質保証
  # 横展開: 他の店舗系コントローラーでも同様のテストパターン適用

  let(:store) { create(:store) }
  let(:store_user) { create(:store_user, store: store) }
  let(:other_store) { create(:store) }
  let(:other_store_user) { create(:store_user, store: other_store) }
  let(:admin) { create(:admin) }
  let(:inventory1) { create(:inventory, name: "アスピリン錠100mg", sku: "MED001", manufacturer: "薬品メーカーA", price: 500) }
  let(:inventory2) { create(:inventory, name: "デジタル血圧計", sku: "DEV001", manufacturer: "医療機器メーカーB", price: 15000) }
  let(:inventory3) { create(:inventory, name: "マスク50枚入り", sku: "SUP001", manufacturer: "消耗品メーカーC", price: 200) }
  let!(:store_inventory1) { create(:store_inventory, store: store, inventory: inventory1, quantity: 100, safety_stock_level: 20) }
  let!(:store_inventory2) { create(:store_inventory, store: store, inventory: inventory2, quantity: 5, safety_stock_level: 10) }
  let!(:store_inventory3) { create(:store_inventory, store: store, inventory: inventory3, quantity: 0, safety_stock_level: 50) }

  before do
    # StoreControllers::BaseControllerの認証をモック化
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:store_user_signed_in?).and_return(true)
    allow(controller).to receive(:current_store_user).and_return(store_user)
  end

  describe 'GET #index' do
    context 'without authentication' do
      it 'allows public access' do
        get :index
        expect(response).to have_http_status(:ok)
      end

      it 'shows limited inventory information' do
        get :index
        expect(assigns(:inventories)).to be_present
        expect(response).to render_template(:index)
      end

      it 'does not show sensitive information' do
        get :index
        expect(response.body).not_to include('価格')
        expect(response.body).not_to include('原価')
      end
    end

    context 'with store user authentication' do
      before { sign_in store_user }

      it 'shows store-specific inventory' do
        other_store = create(:store)
        create(:store_inventory, store: other_store)

        get :index

        inventories = assigns(:inventories)
        expect(inventories.all? { |inv| inv.store_id == store.id }).to be true
      end

      it 'includes detailed information' do
        get :index
        expect(response.body).to include('在庫数')
        expect(response.body).to include('安全在庫')
      end

      it 'allows CSV export' do
        get :index, format: :csv

        expect(response.content_type).to include('text/csv')
        expect(response.headers['Content-Disposition']).to include('inventory_report')
      end
    end

    context 'with admin authentication' do
      before { sign_in admin }

      it 'shows all stores inventory' do
        other_store = create(:store)
        create(:store_inventory, store: other_store)

        get :index

        inventories = assigns(:inventories)
        expect(inventories.map(&:store_id).uniq.size).to be > 1
      end

      it 'includes admin-only actions' do
        get :index
        expect(response.body).to include('編集')
        expect(response.body).to include('削除')
      end

      it 'shows cost information' do
        get :index
        expect(response.body).to include('原価')
        expect(response.body).to include('利益率')
      end
    end

    context 'with filters' do
      before do
        sign_in store_user
        # フィルタ用のテストデータ
        @low_stock = create(:store_inventory, store: store, quantity: 5, safety_stock_level: 10)
        @out_of_stock = create(:store_inventory, store: store, quantity: 0)
        @overstocked = create(:store_inventory, store: store, quantity: 1000, safety_stock_level: 100)
      end

      it 'filters by stock status' do
        get :index, params: { stock_status: 'low' }

        inventories = assigns(:inventories)
        expect(inventories).to include(@low_stock)
        expect(inventories).not_to include(@overstocked)
      end

      it 'filters by search query' do
        searchable = create(:inventory, name: 'Special Product')
        create(:store_inventory, store: store, inventory: searchable)

        get :index, params: { q: 'Special' }

        inventories = assigns(:inventories)
        expect(inventories.map(&:inventory).map(&:name)).to include('Special Product')
      end

      it 'filters by category' do
        categorized = create(:inventory, name: 'Medicine ABC')
        create(:store_inventory, store: store, inventory: categorized)

        get :index, params: { category: '医薬品' }

        inventories = assigns(:inventories)
        names = inventories.map(&:inventory).map(&:name)
        expect(names).to include('Medicine ABC')
      end

      it 'combines multiple filters' do
        get :index, params: {
          stock_status: 'low',
          q: 'test',
          category: '医薬品'
        }

        expect(response).to have_http_status(:ok)
        inventories = assigns(:inventories)
        expect(inventories).to be_a(ActiveRecord::Relation)
      end
    end

    context 'with sorting' do
      before do
        sign_in store_user
        create(:store_inventory, store: store, quantity: 50, inventory: create(:inventory, name: 'AAA'))
        create(:store_inventory, store: store, quantity: 150, inventory: create(:inventory, name: 'ZZZ'))
      end

      it 'sorts by name ascending' do
        get :index, params: { sort: 'name', direction: 'asc' }

        names = assigns(:inventories).map(&:inventory).map(&:name)
        expect(names).to eq(names.sort)
      end

      it 'sorts by quantity descending' do
        get :index, params: { sort: 'quantity', direction: 'desc' }

        quantities = assigns(:inventories).map(&:quantity)
        expect(quantities).to eq(quantities.sort.reverse)
      end

      it 'sorts by stock ratio' do
        get :index, params: { sort: 'stock_ratio' }

        expect(assigns(:inventories)).to be_present
      end
    end

    context 'with pagination' do
      before do
        sign_in store_user
        create_list(:store_inventory, 30, store: store)
      end

      it 'paginates results' do
        get :index, params: { page: 1 }

        inventories = assigns(:inventories)
        expect(inventories.size).to be <= 25
      end

      it 'shows different results on different pages' do
        get :index, params: { page: 1 }
        page1_ids = assigns(:inventories).map(&:id)

        get :index, params: { page: 2 }
        page2_ids = assigns(:inventories).map(&:id)

        expect(page1_ids & page2_ids).to be_empty
      end
    end

    context 'CSV export' do
      before { sign_in store_user }

      it 'exports filtered results' do
        low_stock = create(:store_inventory, store: store, quantity: 5, safety_stock_level: 10)

        get :index, params: { stock_status: 'low' }, format: :csv

        csv_content = response.body
        expect(csv_content).to include(low_stock.inventory.name)
        expect(csv_content).not_to include(store_inventory.inventory.name)
      end

      it 'includes appropriate headers for role' do
        get :index, format: :csv

        headers = CSV.parse(response.body).first
        expect(headers).to include('商品名', '在庫数', '安全在庫数')
        expect(headers).not_to include('原価') # 店舗ユーザーには非表示
      end

      it 'includes cost data for admin' do
        sign_out store_user
        sign_in admin

        get :index, format: :csv

        headers = CSV.parse(response.body).first
        expect(headers).to include('原価', '在庫金額')
      end
    end
  end

  describe 'GET #show' do
    context 'without authentication' do
      it 'requires authentication' do
        get :show, params: { id: store_inventory.id }
        expect(response).to redirect_to(new_store_user_session_path)
      end
    end

    context 'with store user authentication' do
      before { sign_in store_user }

      it 'shows inventory details for own store' do
        get :show, params: { id: store_inventory.id }

        expect(response).to have_http_status(:ok)
        expect(assigns(:store_inventory)).to eq(store_inventory)
      end

      it 'denies access to other store inventory' do
        other_store_inventory = create(:store_inventory)

        get :show, params: { id: other_store_inventory.id }

        expect(response).to have_http_status(:forbidden)
      end

      it 'shows batch information' do
        batch = create(:batch, inventory: inventory, quantity: 50)

        get :show, params: { id: store_inventory.id }

        expect(response.body).to include(batch.lot_code)
      end

      it 'shows recent transactions' do
        log = create(:inventory_log, inventory: inventory, store: store)

        get :show, params: { id: store_inventory.id }

        expect(assigns(:recent_logs)).to include(log)
      end
    end

    context 'with admin authentication' do
      before { sign_in admin }

      it 'can access any store inventory' do
        other_store_inventory = create(:store_inventory)

        get :show, params: { id: other_store_inventory.id }

        expect(response).to have_http_status(:ok)
      end

      it 'shows additional admin information' do
        get :show, params: { id: store_inventory.id }

        expect(response.body).to include('調整履歴')
        expect(response.body).to include('監査ログ')
      end
    end
  end

  describe 'POST #adjust_stock' do
    context 'without authentication' do
      it 'requires authentication' do
        post :adjust_stock, params: {
          id: store_inventory.id,
          adjustment: { quantity: 10, reason: 'Found items' }
        }

        expect(response).to redirect_to(new_store_user_session_path)
      end
    end

    context 'with store user authentication' do
      before { sign_in store_user }

      it 'allows positive adjustment' do
        expect {
          post :adjust_stock, params: {
            id: store_inventory.id,
            adjustment: { quantity: 10, reason: 'Found items' }
          }
        }.to change { store_inventory.reload.quantity }.by(10)

        expect(response).to redirect_to(store_inventory_path(store_inventory))
        expect(flash[:notice]).to be_present
      end

      it 'allows negative adjustment' do
        expect {
          post :adjust_stock, params: {
            id: store_inventory.id,
            adjustment: { quantity: -5, reason: 'Damaged items' }
          }
        }.to change { store_inventory.reload.quantity }.by(-5)
      end

      it 'requires reason for adjustment' do
        post :adjust_stock, params: {
          id: store_inventory.id,
          adjustment: { quantity: 10, reason: '' }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to be_present
      end

      it 'prevents adjustment below zero' do
        post :adjust_stock, params: {
          id: store_inventory.id,
          adjustment: { quantity: -200, reason: 'Over adjustment' }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(store_inventory.reload.quantity).to eq(100)
      end

      it 'creates inventory log' do
        expect {
          post :adjust_stock, params: {
            id: store_inventory.id,
            adjustment: { quantity: 10, reason: 'Test adjustment' }
          }
        }.to change { InventoryLog.count }.by(1)

        log = InventoryLog.last
        expect(log.operation_type).to eq('adjustment')
        expect(log.delta).to eq(10)
        expect(log.note).to include('Test adjustment')
      end

      it 'denies adjustment for other store' do
        other_inventory = create(:store_inventory)

        post :adjust_stock, params: {
          id: other_inventory.id,
          adjustment: { quantity: 10, reason: 'Unauthorized' }
        }

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with admin authentication' do
      before { sign_in admin }

      it 'can adjust any store inventory' do
        other_inventory = create(:store_inventory, quantity: 50)

        expect {
          post :adjust_stock, params: {
            id: other_inventory.id,
            adjustment: { quantity: 20, reason: 'Admin adjustment' }
          }
        }.to change { other_inventory.reload.quantity }.by(20)
      end

      it 'logs admin information' do
        post :adjust_stock, params: {
          id: store_inventory.id,
          adjustment: { quantity: 10, reason: 'Admin check' }
        }

        log = InventoryLog.last
        expect(log.user).to eq(admin)
        expect(log.metadata['admin_action']).to be true
      end
    end
  end

  describe 'POST #transfer_request' do
    let(:target_store) { create(:store) }
    let!(:target_inventory) { create(:store_inventory, store: target_store, inventory: inventory, quantity: 50) }

    context 'with store user authentication' do
      before { sign_in store_user }

      it 'creates transfer request' do
        expect {
          post :transfer_request, params: {
            id: store_inventory.id,
            transfer: {
              to_store_id: target_store.id,
              quantity: 20,
              reason: 'Low stock at target'
            }
          }
        }.to change { InterStoreTransfer.count }.by(1)

        transfer = InterStoreTransfer.last
        expect(transfer.from_store).to eq(store)
        expect(transfer.to_store).to eq(target_store)
        expect(transfer.quantity).to eq(20)
        expect(transfer.status).to eq('pending')
      end

      it 'validates transfer quantity' do
        post :transfer_request, params: {
          id: store_inventory.id,
          transfer: {
            to_store_id: target_store.id,
            quantity: 200,
            reason: 'Too much'
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash[:alert]).to include('在庫不足')
      end

      it 'requires reason' do
        post :transfer_request, params: {
          id: store_inventory.id,
          transfer: {
            to_store_id: target_store.id,
            quantity: 20,
            reason: ''
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'notifies target store' do
        expect {
          post :transfer_request, params: {
            id: store_inventory.id,
            transfer: {
              to_store_id: target_store.id,
              quantity: 20,
              reason: 'Stock needed'
            }
          }
        }.to have_enqueued_job(ActionMailer::MailDeliveryJob)
      end
    end
  end

  describe 'GET #low_stock_report' do
    before do
      sign_in store_user
      create(:store_inventory, store: store, quantity: 5, safety_stock_level: 10)
      create(:store_inventory, store: store, quantity: 0, safety_stock_level: 5)
      create(:store_inventory, store: store, quantity: 100, safety_stock_level: 50)
    end

    it 'shows only low stock items' do
      get :low_stock_report

      low_stock_items = assigns(:low_stock_items)
      expect(low_stock_items.count).to eq(2)
      expect(low_stock_items.all? { |item| item.quantity <= item.safety_stock_level }).to be true
    end

    it 'orders by urgency' do
      get :low_stock_report

      items = assigns(:low_stock_items)
      # 在庫切れが最初に来るべき
      expect(items.first.quantity).to eq(0)
    end

    it 'includes reorder suggestions' do
      get :low_stock_report

      expect(assigns(:reorder_suggestions)).to be_present
    end
  end

  describe 'security headers' do
    before { sign_in store_user }

    it 'includes security headers in responses' do
      get :index

      expect(response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end
  end

  describe 'performance' do
    before do
      sign_in store_user
      create_list(:store_inventory, 100, store: store)
    end

    it 'uses includes to avoid N+1 queries' do
      expect {
        get :index
      }.to make_database_queries(count: 10..15) # 適切な範囲でクエリ数を制限
    end

    it 'completes index action quickly' do
      start_time = Time.current
      get :index
      duration = Time.current - start_time

      expect(duration).to be < 1.0 # 1秒以内
    end
  end
end
