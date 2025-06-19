# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::StoreInventoriesController, type: :controller do
  # CLAUDE.md準拠: 管理者用店舗在庫コントローラーの包括的テスト
  # メタ認知: 複雑な検索フィルタリングとエクスポート機能の品質保証
  # 横展開: 他の管理者系コントローラーでも同様のテストパターン適用

  let(:admin) { create(:admin) }
  let(:store) { create(:store) }
  let(:inventory) { create(:inventory) }
  let!(:store_inventory) { create(:store_inventory, store: store, inventory: inventory, quantity: 100) }

  before { sign_in admin }

  describe 'GET #index' do
    context 'basic functionality' do
      it 'returns success' do
        get :index
        expect(response).to have_http_status(:success)
      end

      it 'assigns store inventories' do
        get :index
        expect(assigns(:store_inventories)).to include(store_inventory)
      end

      it 'renders index template' do
        get :index
        expect(response).to render_template(:index)
      end
    end

    context 'with search filters' do
      before do
        @medicine = create(:inventory, name: 'Aspirin 100mg')
        @equipment = create(:inventory, name: 'Surgical Gloves')
        @supply = create(:inventory, name: 'Office Paper')

        @med_inv = create(:store_inventory, store: store, inventory: @medicine, quantity: 50)
        @equip_inv = create(:store_inventory, store: store, inventory: @equipment, quantity: 0)
        @supply_inv = create(:store_inventory, store: store, inventory: @supply, quantity: 200)
      end

      it 'filters by search query' do
        get :index, params: { q: 'Aspirin' }

        inventories = assigns(:store_inventories)
        expect(inventories).to include(@med_inv)
        expect(inventories).not_to include(@equip_inv, @supply_inv)
      end

      it 'filters by store' do
        other_store = create(:store)
        other_inventory = create(:store_inventory, store: other_store)

        get :index, params: { store_id: store.id }

        inventories = assigns(:store_inventories)
        expect(inventories).to include(store_inventory)
        expect(inventories).not_to include(other_inventory)
      end

      it 'filters by category' do
        get :index, params: { category: '医薬品' }

        inventories = assigns(:store_inventories)
        expect(inventories).to include(@med_inv)
        expect(inventories).not_to include(@equip_inv, @supply_inv)
      end

      it 'filters by stock status' do
        get :index, params: { stock_status: 'out_of_stock' }

        inventories = assigns(:store_inventories)
        expect(inventories).to include(@equip_inv)
        expect(inventories).not_to include(@med_inv, @supply_inv)
      end

      it 'filters by multiple criteria' do
        get :index, params: {
          store_id: store.id,
          category: '医薬品',
          stock_status: 'available'
        }

        inventories = assigns(:store_inventories)
        expect(inventories).to include(@med_inv)
        expect(inventories.count).to eq(1)
      end
    end

    context 'with sorting' do
      before do
        @item_a = create(:inventory, name: 'AAA Item')
        @item_z = create(:inventory, name: 'ZZZ Item')
        @inv_a = create(:store_inventory, store: store, inventory: @item_a, quantity: 10)
        @inv_z = create(:store_inventory, store: store, inventory: @item_z, quantity: 90)
      end

      it 'sorts by inventory name' do
        get :index, params: { sort: 'inventory_name', direction: 'asc' }

        inventories = assigns(:store_inventories)
        names = inventories.map { |si| si.inventory.name }
        expect(names).to eq(names.sort)
      end

      it 'sorts by quantity' do
        get :index, params: { sort: 'quantity', direction: 'desc' }

        inventories = assigns(:store_inventories)
        quantities = inventories.map(&:quantity)
        expect(quantities).to eq(quantities.sort.reverse)
      end

      it 'sorts by stock ratio' do
        get :index, params: { sort: 'stock_ratio', direction: 'asc' }

        expect(assigns(:store_inventories)).to be_present
      end
    end

    context 'export functionality' do
      it 'exports to CSV' do
        get :index, params: { format: :csv }

        expect(response.content_type).to include('text/csv')
        expect(response.headers['Content-Disposition']).to include('store_inventories')
      end

      it 'exports to XLSX' do
        get :index, params: { format: :xlsx }

        expect(response.content_type).to include('spreadsheetml')
        expect(response.headers['Content-Disposition']).to include('.xlsx')
      end

      it 'exports to JSON' do
        get :index, params: { format: :json }

        expect(response.content_type).to include('application/json')
        json = JSON.parse(response.body)
        expect(json).to have_key('store_inventories')
        expect(json).to have_key('metadata')
      end

      it 'includes filtered results in export' do
        low_stock = create(:store_inventory, store: store, quantity: 5, safety_stock_level: 10)

        get :index, params: { stock_status: 'low_stock', format: :csv }

        csv_content = response.body
        expect(csv_content).to include(low_stock.inventory.name)
        expect(csv_content).not_to include(store_inventory.inventory.name)
      end
    end
  end

  describe 'GET #show' do
    it 'returns success' do
      get :show, params: { id: store_inventory.id }
      expect(response).to have_http_status(:success)
    end

    it 'assigns the store inventory' do
      get :show, params: { id: store_inventory.id }
      expect(assigns(:store_inventory)).to eq(store_inventory)
    end

    it 'loads related data' do
      batch = create(:batch, inventory: inventory)
      log = create(:inventory_log, inventory: inventory, store: store)

      get :show, params: { id: store_inventory.id }

      expect(assigns(:batches)).to include(batch)
      expect(assigns(:recent_activities)).to include(log)
    end

    it 'calculates statistics' do
      get :show, params: { id: store_inventory.id }

      stats = assigns(:statistics)
      expect(stats).to include(
        :turnover_rate,
        :days_of_stock,
        :value_on_hand
      )
    end
  end

  describe 'GET #new' do
    it 'returns success' do
      get :new
      expect(response).to have_http_status(:success)
    end

    it 'assigns new store inventory' do
      get :new
      expect(assigns(:store_inventory)).to be_a_new(StoreInventory)
    end

    it 'loads stores and inventories for selection' do
      get :new

      expect(assigns(:stores)).to include(store)
      expect(assigns(:inventories)).to include(inventory)
    end
  end

  describe 'POST #create' do
    context 'with valid params' do
      let(:new_inventory) { create(:inventory) }
      let(:valid_params) do
        {
          store_inventory: {
            store_id: store.id,
            inventory_id: new_inventory.id,
            quantity: 50,
            safety_stock_level: 20,
            maximum_stock_level: 100
          }
        }
      end

      it 'creates a new store inventory' do
        expect {
          post :create, params: valid_params
        }.to change(StoreInventory, :count).by(1)
      end

      it 'redirects to show page' do
        post :create, params: valid_params
        expect(response).to redirect_to(admin_store_inventory_path(StoreInventory.last))
      end

      it 'sets success flash message' do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end

      it 'creates initial inventory log' do
        expect {
          post :create, params: valid_params
        }.to change(InventoryLog, :count).by(1)

        log = InventoryLog.last
        expect(log.operation_type).to eq('initial_setup')
        expect(log.delta).to eq(50)
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          store_inventory: {
            store_id: store.id,
            inventory_id: nil,
            quantity: -10
          }
        }
      end

      it 'does not create store inventory' do
        expect {
          post :create, params: invalid_params
        }.not_to change(StoreInventory, :count)
      end

      it 'renders new template' do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
      end

      it 'assigns errors' do
        post :create, params: invalid_params
        expect(assigns(:store_inventory).errors).not_to be_empty
      end
    end
  end

  describe 'GET #edit' do
    it 'returns success' do
      get :edit, params: { id: store_inventory.id }
      expect(response).to have_http_status(:success)
    end

    it 'assigns the store inventory' do
      get :edit, params: { id: store_inventory.id }
      expect(assigns(:store_inventory)).to eq(store_inventory)
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      let(:update_params) do
        {
          id: store_inventory.id,
          store_inventory: {
            quantity: 150,
            safety_stock_level: 30
          }
        }
      end

      it 'updates the store inventory' do
        patch :update, params: update_params

        store_inventory.reload
        expect(store_inventory.quantity).to eq(150)
        expect(store_inventory.safety_stock_level).to eq(30)
      end

      it 'creates adjustment log' do
        expect {
          patch :update, params: update_params
        }.to change(InventoryLog, :count).by(1)

        log = InventoryLog.last
        expect(log.operation_type).to eq('adjustment')
        expect(log.delta).to eq(50) # 150 - 100
      end

      it 'redirects to show page' do
        patch :update, params: update_params
        expect(response).to redirect_to(admin_store_inventory_path(store_inventory))
      end
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          id: store_inventory.id,
          store_inventory: {
            quantity: -50
          }
        }
      end

      it 'does not update store inventory' do
        original_quantity = store_inventory.quantity
        patch :update, params: invalid_params

        store_inventory.reload
        expect(store_inventory.quantity).to eq(original_quantity)
      end

      it 'renders edit template' do
        patch :update, params: invalid_params
        expect(response).to render_template(:edit)
      end
    end
  end

  describe 'DELETE #destroy' do
    it 'soft deletes the store inventory' do
      delete :destroy, params: { id: store_inventory.id }

      store_inventory.reload
      expect(store_inventory.deleted_at).not_to be_nil
    end

    it 'creates deletion log' do
      expect {
        delete :destroy, params: { id: store_inventory.id }
      }.to change(InventoryLog, :count).by(1)

      log = InventoryLog.last
      expect(log.operation_type).to eq('deleted')
    end

    it 'redirects to index' do
      delete :destroy, params: { id: store_inventory.id }
      expect(response).to redirect_to(admin_store_inventories_path)
    end
  end

  describe 'POST #transfer' do
    let(:target_store) { create(:store) }
    let(:transfer_params) do
      {
        id: store_inventory.id,
        transfer: {
          to_store_id: target_store.id,
          quantity: 20,
          reason: 'Stock balancing'
        }
      }
    end

    context 'with valid transfer' do
      it 'creates inter-store transfer' do
        expect {
          post :transfer, params: transfer_params
        }.to change(InterStoreTransfer, :count).by(1)

        transfer = InterStoreTransfer.last
        expect(transfer.from_store).to eq(store)
        expect(transfer.to_store).to eq(target_store)
        expect(transfer.quantity).to eq(20)
      end

      it 'redirects with success message' do
        post :transfer, params: transfer_params

        expect(response).to redirect_to(admin_store_inventory_path(store_inventory))
        expect(flash[:notice]).to include('Transfer initiated')
      end
    end

    context 'with invalid transfer' do
      it 'fails when quantity exceeds available' do
        transfer_params[:transfer][:quantity] = 200

        post :transfer, params: transfer_params

        expect(response).to redirect_to(admin_store_inventory_path(store_inventory))
        expect(flash[:alert]).to include('Insufficient quantity')
      end

      it 'fails without target store' do
        transfer_params[:transfer][:to_store_id] = nil

        post :transfer, params: transfer_params

        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'GET #analytics' do
    before do
      # アナリティクス用のテストデータ
      create_list(:inventory_log, 10,
        inventory: inventory,
        store: store,
        created_at: 1.week.ago,
        operation_type: 'ship',
        delta: -5
      )

      create_list(:inventory_log, 5,
        inventory: inventory,
        store: store,
        created_at: 1.day.ago,
        operation_type: 'receive',
        delta: 10
      )
    end

    it 'returns success' do
      get :analytics
      expect(response).to have_http_status(:success)
    end

    it 'generates movement statistics' do
      get :analytics

      stats = assigns(:movement_stats)
      expect(stats).to include(
        :total_received,
        :total_shipped,
        :net_change,
        :turnover_rate
      )
    end

    it 'identifies trending items' do
      get :analytics

      expect(assigns(:trending_items)).to be_an(Array)
      expect(assigns(:slow_moving_items)).to be_an(Array)
    end

    it 'calculates store performance metrics' do
      get :analytics

      metrics = assigns(:store_performance)
      expect(metrics).to be_a(Hash)
      expect(metrics[store.id]).to include(
        :stock_value,
        :turnover_rate,
        :stockout_incidents
      )
    end
  end

  describe 'POST #bulk_update' do
    let(:item1) { create(:store_inventory, store: store, quantity: 10) }
    let(:item2) { create(:store_inventory, store: store, quantity: 20) }

    let(:bulk_params) do
      {
        store_inventories: {
          item1.id.to_s => { quantity: 15, safety_stock_level: 5 },
          item2.id.to_s => { quantity: 25, safety_stock_level: 10 }
        }
      }
    end

    it 'updates multiple inventories' do
      post :bulk_update, params: bulk_params

      item1.reload
      item2.reload

      expect(item1.quantity).to eq(15)
      expect(item1.safety_stock_level).to eq(5)
      expect(item2.quantity).to eq(25)
      expect(item2.safety_stock_level).to eq(10)
    end

    it 'creates logs for all updates' do
      expect {
        post :bulk_update, params: bulk_params
      }.to change(InventoryLog, :count).by(2)
    end

    it 'handles validation errors' do
      bulk_params[:store_inventories][item1.id.to_s][:quantity] = -10

      post :bulk_update, params: bulk_params

      item1.reload
      expect(item1.quantity).to eq(10) # 変更されない
      expect(flash[:alert]).to be_present
    end
  end

  describe 'security' do
    context 'without authentication' do
      before { sign_out admin }

      it 'redirects to login' do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context 'authorization' do
      it 'includes security headers' do
        get :index

        expect(response.headers['X-Frame-Options']).to eq('SAMEORIGIN')
        expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      end
    end
  end

  describe 'performance' do
    before do
      create_list(:store_inventory, 50, store: store)
    end

    it 'uses includes to avoid N+1' do
      expect {
        get :index
      }.to make_database_queries(count: 5..10)
    end

    it 'paginates results' do
      get :index

      inventories = assigns(:store_inventories)
      expect(inventories).to respond_to(:current_page)
      expect(inventories.count).to be <= 25
    end
  end
end
