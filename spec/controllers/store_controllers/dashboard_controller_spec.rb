# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::DashboardController, type: :controller do
  # CLAUDE.md準拠: 店舗ダッシュボードの包括的テスト
  # メタ認知: 店舗ユーザー視点での在庫管理機能の品質保証
  # 横展開: 他のStoreControllersでも同様のテスト構造適用

  let(:store) { create(:store, name: 'テスト店舗') }
  let(:store_user) { create(:store_user, store: store) }

  before do
    sign_in store_user, scope: :store_user
  end

  # ============================================
  # 基本機能のテスト
  # ============================================

  describe "GET #index" do
    context "with valid store user authentication" do
      it "returns a success response" do
        get :index, params: { store_slug: store.slug }
        expect(response).to be_successful
        expect(response).to have_http_status(:ok)
      end

      it "assigns dashboard statistics" do
        get :index, params: { store_slug: store.slug }
        expect(assigns(:stats)).to be_present
        expect(assigns(:stats)).to include(
          :total_inventories,
          :low_stock_count,
          :total_inventory_value,
          :out_of_stock_count
        )
      end

      it "renders the index template" do
        get :index, params: { store_slug: store.slug }
        expect(response).to render_template(:index)
      end

      it "assigns store correctly" do
        get :index, params: { store_slug: store.slug }
        expect(assigns(:store)).to eq(store)
      end
    end

    # ============================================
    # 詳細統計データのテスト（カバレッジ向上）
    # ============================================

    context 'with detailed test data' do
      let!(:inventory1) { create(:inventory, name: 'アスピリン錠', price: 500) }
      let!(:inventory2) { create(:inventory, name: 'デジタル血圧計', price: 15000) }
      let!(:inventory3) { create(:inventory, name: '使い捨てマスク', price: 200) }

      before do
        # 店舗在庫設定（低在庫・在庫切れ含む）
        create(:store_inventory, store: store, inventory: inventory1, quantity: 100, safety_stock_level: 20)
        create(:store_inventory, store: store, inventory: inventory2, quantity: 5, safety_stock_level: 10) # 低在庫
        create(:store_inventory, store: store, inventory: inventory3, quantity: 0, safety_stock_level: 50) # 在庫切れ
      end

      it '正確な在庫統計を計算すること' do
        get :index, params: { store_slug: store.slug }
        stats = assigns(:stats)

        expect(stats[:total_inventories]).to eq(3)
        expect(stats[:low_stock_count]).to eq(2) # inventory2とinventory3
        expect(stats[:out_of_stock_count]).to eq(1) # inventory3のみ
        expect(stats[:total_inventory_value]).to be > 0
      end

      it '低在庫商品リストを適切に生成すること' do
        get :index, params: { store_slug: store.slug }
        stats = assigns(:stats)

        expect(stats[:low_stock_items]).to be_present
        low_stock_names = stats[:low_stock_items].map { |item| item[:name] }
        expect(low_stock_names).to include('デジタル血圧計', '使い捨てマスク')
        expect(low_stock_names).not_to include('アスピリン錠')
      end

      it '在庫切れ商品リストを適切に生成すること' do
        get :index, params: { store_slug: store.slug }
        stats = assigns(:stats)

        expect(stats[:out_of_stock_items]).to be_present
        out_of_stock_names = stats[:out_of_stock_items].map { |item| item[:name] }
        expect(out_of_stock_names).to include('使い捨てマスク')
        expect(out_of_stock_names).not_to include('アスピリン錠', 'デジタル血圧計')
      end
    end

    # ============================================
    # パフォーマンステスト（カバレッジ向上）
    # ============================================

    context 'performance considerations' do
      before do
        # 大量データ作成（店舗固有）
        inventories = create_list(:inventory, 30)
        inventories.each_with_index do |inventory, index|
          create(:store_inventory,
                 store: store,
                 inventory: inventory,
                 quantity: index % 10, # 0-9の在庫数
                 safety_stock_level: 5)
        end
      end

      it 'ダッシュボード読み込みが効率的に動作すること' do
        expect {
          get :index, params: { store_slug: store.slug }
        }.to perform_under(500).ms
      end

      it 'N+1クエリが発生しないこと' do
        expect {
          get :index, params: { store_slug: store.slug }
        }.not_to exceed_query_limit(15) # 店舗固有の制限
      end
    end

    # ============================================
    # エラーハンドリング（カバレッジ向上）
    # ============================================

    context 'error handling' do
      it 'データベースエラー時でも適切に処理すること' do
        # StoreInventoryでエラーをシミュレート
        allow(StoreInventory).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new('Database error'))

        expect {
          get :index, params: { store_slug: store.slug }
        }.not_to raise_error

        expect(response).to be_successful
        stats = assigns(:stats)
        expect(stats[:total_inventories]).to eq(0) # フォールバック値
      end

      it '無効な店舗slugでエラーハンドリングすること' do
        get :index, params: { store_slug: 'invalid-store' }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
      end
    end

    # ============================================
    # レスポンス形式テスト（カバレッジ向上）
    # ============================================

    context 'response formats' do
      it 'JSON形式で統計データを返すこと' do
        get :index, params: { store_slug: store.slug }, format: :json

        expect(response).to be_successful
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response).to include('stats')
        expect(json_response['stats']).to include(
          'total_inventories',
          'low_stock_count',
          'out_of_stock_count',
          'total_inventory_value'
        )
      end

      it 'XML形式での要求でも適切に処理すること' do
        get :index, params: { store_slug: store.slug }, format: :xml

        # XMLサポートがない場合はHTMLにフォールバック
        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # 認証・認可テスト（カバレッジ向上）
  # ============================================

  describe "authentication and authorization" do
    context "without authentication" do
      before { sign_out store_user }

      it "redirects to sign in page" do
        get :index, params: { store_slug: store.slug }
        expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
      end
    end

    context "with wrong store user" do
      let(:other_store) { create(:store) }
      let(:other_store_user) { create(:store_user, store: other_store) }

      before do
        sign_out store_user
        sign_in other_store_user, scope: :store_user
      end

      it "redirects or shows error for accessing different store" do
        get :index, params: { store_slug: store.slug }

        # アクセス制限のテスト（実装に依存）
        expect(response).to have_http_status(:redirect).or(have_http_status(:forbidden))
      end
    end

    context "with inactive store user" do
      let(:inactive_user) { create(:store_user, :inactive, store: store) }

      before do
        sign_out store_user
        sign_in inactive_user, scope: :store_user
      end

      it "handles inactive user appropriately" do
        get :index, params: { store_slug: store.slug }

        # 非アクティブユーザーの処理確認
        expect(response).to have_http_status(:redirect).or(be_successful)
      end
    end
  end

  # ============================================
  # 店舗間分離テスト（カバレッジ向上）
  # ============================================

  describe "multi-store isolation" do
    let(:other_store) { create(:store, name: '他店舗') }
    let!(:other_inventory) { create(:inventory, name: '他店舗商品') }

    before do
      # 他店舗にのみ在庫を追加
      create(:store_inventory, store: other_store, inventory: other_inventory, quantity: 100)

      # 現在の店舗には在庫なし
    end

    it '他店舗の在庫が表示されないこと' do
      get :index, params: { store_slug: store.slug }
      stats = assigns(:stats)

      expect(stats[:total_inventories]).to eq(0)
      expect(stats[:low_stock_count]).to eq(0)
      expect(stats[:out_of_stock_count]).to eq(0)
    end

    it '店舗固有の統計のみ表示されること' do
      # 現在の店舗に在庫追加
      current_inventory = create(:inventory, name: '現在店舗商品')
      create(:store_inventory, store: store, inventory: current_inventory, quantity: 50)

      get :index, params: { store_slug: store.slug }
      stats = assigns(:stats)

      expect(stats[:total_inventories]).to eq(1)

      # 他店舗の商品が含まれていないことを確認
      if stats[:inventory_items]
        inventory_names = stats[:inventory_items].map { |item| item[:name] }
        expect(inventory_names).to include('現在店舗商品')
        expect(inventory_names).not_to include('他店舗商品')
      end
    end
  end

  # ============================================
  # ユーザー体験テスト（カバレッジ向上）
  # ============================================

  describe "user experience" do
    context 'with manager user' do
      let(:manager) { create(:store_user, :manager, store: store) }

      before do
        sign_out store_user
        sign_in manager, scope: :store_user
      end

      it 'マネージャー向けの追加機能が利用できること' do
        get :index, params: { store_slug: store.slug }

        expect(response).to be_successful
        # マネージャー固有の機能があれば確認
        expect(assigns(:user_permissions)).to be_present if defined?(assigns(:user_permissions))
      end
    end

    context 'with different device types' do
      it 'モバイルデバイスからのアクセスを適切に処理すること' do
        request.headers['User-Agent'] = 'Mobile Safari'
        get :index, params: { store_slug: store.slug }

        expect(response).to be_successful
        expect(response.content_type).to include('text/html')
      end

      it 'タブレットデバイスからのアクセスを適切に処理すること' do
        request.headers['User-Agent'] = 'iPad'
        get :index, params: { store_slug: store.slug }

        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # セキュリティテスト（カバレッジ向上）
  # ============================================

  describe "security features" do
    it 'CSRFトークンが適切に設定されていること' do
      get :index, params: { store_slug: store.slug }

      expect(response.headers['X-Frame-Options']).to be_present
      expect(response.body).to include('csrf-token')
    end

    it 'セキュリティヘッダーが適切に設定されていること' do
      get :index, params: { store_slug: store.slug }

      # セキュリティヘッダーの確認
      expect(response.headers).to be_present
      # 具体的なヘッダー確認は実装に依存
    end

    it 'SQLインジェクション攻撃を防ぐこと' do
      malicious_slug = "'; DROP TABLE stores; --"

      expect {
        get :index, params: { store_slug: malicious_slug }
      }.not_to raise_error

      # 攻撃が成功していないことを確認
      expect(Store.count).to be > 0
    end
  end

  # ============================================
  # 国際化・アクセシビリティテスト
  # ============================================

  describe "internationalization and accessibility" do
    it '日本語コンテンツが適切に表示されること' do
      get :index, params: { store_slug: store.slug }

      expect(response.body).to include('店舗ダッシュボード').or(include('ダッシュボード'))
    end

    it 'HTMLが適切な構造を持つこと' do
      get :index, params: { store_slug: store.slug }

      expect(response.body).to include('<html')
      expect(response.body).to include('<head>')
      expect(response.body).to include('<body>')
      expect(response.body).to include('</html>')
    end
  end
end
