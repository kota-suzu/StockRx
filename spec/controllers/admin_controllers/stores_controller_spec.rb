# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::StoresController, type: :controller do
  # CLAUDE.md準拠: 店舗管理コントローラーの包括的テスト
  # メタ認知: 権限管理と複雑な分岐ロジックのBranch Coverage向上
  # 横展開: 他の管理系コントローラーでも同様のテストパターン適用

  let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }
  let(:store_admin) { create(:admin, role: :store_admin) }
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }

  let(:valid_attributes) {
    {
      name: "新店舗",
      code: "NEW001",
      store_type: "pharmacy",
      region: "関東",
      address: "東京都新宿区...",
      phone: "03-1234-5678",
      email: "new@example.com",
      manager_name: "山田太郎",
      active: true
    }
  }

  let(:invalid_attributes) {
    {
      name: "",
      code: "",
      store_type: "invalid",
      email: "invalid-email"
    }
  }

  # ============================================
  # 共通のサポートメソッド
  # ============================================

  def setup_store_with_data(store)
    # 在庫データ
    inventory1 = create(:inventory)
    inventory2 = create(:inventory)
    create(:store_inventory, store: store, inventory: inventory1,
           quantity: 5, safety_stock_level: 10) # 低在庫
    create(:store_inventory, store: store, inventory: inventory2,
           quantity: 100, safety_stock_level: 20) # 正常在庫

    # 移動データ
    create(:inter_store_transfer, source_store: store, status: :pending)
    create(:inter_store_transfer, destination_store: store, status: :approved)
  end

  # ============================================
  # 本部管理者のテスト
  # ============================================

  describe "本部管理者としてのアクセス" do
    before do
      sign_in headquarters_admin
    end

    describe "GET #index" do
      before do
        create_list(:store, 3, active: true)
        create(:store, active: false)
      end

      it "成功レスポンスを返す" do
        get :index
        expect(response).to be_successful
      end

      it "アクティブな店舗のみを取得する" do
        get :index
        expect(assigns(:stores).count).to eq(3)
        expect(assigns(:stores).all?(&:active?)).to be true
      end

      it "統計情報を計算する" do
        expect(controller).to receive(:calculate_store_overview_stats).and_return({})
        get :index
        expect(assigns(:stats)).to be_present
      end

      it "検索パラメータがある場合はフィルタリングを適用する" do
        expect(controller).to receive(:apply_store_filters)
        get :index, params: { search: "test" }
      end

      it "ページネーションを適用する" do
        get :index, params: { page: 2 }
        expect(assigns(:stores)).to respond_to(:current_page)
      end
    end

    describe "GET #show" do
      before do
        setup_store_with_data(store)
      end

      it "成功レスポンスを返す" do
        get :show, params: { id: store.id }
        expect(response).to be_successful
      end

      it "店舗在庫をページネーション付きで読み込む" do
        get :show, params: { id: store.id }
        expect(assigns(:store_inventories)).to be_present
        expect(assigns(:store_inventories)).to respond_to(:current_page)
      end

      it "店舗統計を計算する" do
        expect(controller).to receive(:calculate_store_detailed_stats).with(store).and_return({})
        get :show, params: { id: store.id }
        expect(assigns(:store_stats)).to be_present
      end

      it "最近の移動履歴を読み込む" do
        expect(controller).to receive(:load_recent_transfers).with(store).and_return([])
        get :show, params: { id: store.id }
        expect(assigns(:recent_transfers)).to be_present
      end

      it "関連データを適切にincludesする" do
        get :show, params: { id: store.id }
        store_inventories = assigns(:store_inventories)
        # includesが効いているか確認
        expect(store_inventories.first.association(:inventory)).to be_loaded
      end
    end

    describe "GET #new" do
      it "成功レスポンスを返す" do
        get :new
        expect(response).to be_successful
      end

      it "新しいStoreインスタンスを作成する" do
        get :new
        expect(assigns(:store)).to be_a_new(Store)
      end
    end

    describe "GET #edit" do
      it "成功レスポンスを返す" do
        get :edit, params: { id: store.id }
        expect(response).to be_successful
      end

      it "関連データを含む店舗を読み込む" do
        get :edit, params: { id: store.id }
        expect(assigns(:store).association(:store_inventories)).to be_loaded
        expect(assigns(:store).association(:admins)).to be_loaded
      end
    end

    describe "POST #create" do
      context "有効なパラメータの場合" do
        it "新しい店舗を作成する" do
          expect {
            post :create, params: { store: valid_attributes }
          }.to change(Store, :count).by(1)
        end

        it "作成した店舗にリダイレクトする" do
          post :create, params: { store: valid_attributes }
          expect(response).to redirect_to(admin_store_path(Store.last))
          expect(flash[:notice]).to include("正常に作成されました")
        end
      end

      context "無効なパラメータの場合" do
        it "店舗を作成しない" do
          expect {
            post :create, params: { store: invalid_attributes }
          }.not_to change(Store, :count)
        end

        it "newテンプレートを再表示する" do
          post :create, params: { store: invalid_attributes }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:new)
        end
      end
    end

    describe "PATCH #update" do
      let(:new_attributes) {
        {
          name: "更新された店舗名",
          manager_name: "新しい管理者"
        }
      }

      context "有効なパラメータの場合" do
        it "店舗を更新する" do
          patch :update, params: { id: store.id, store: new_attributes }
          store.reload
          expect(store.name).to eq("更新された店舗名")
          expect(store.manager_name).to eq("新しい管理者")
        end

        it "更新した店舗にリダイレクトする" do
          patch :update, params: { id: store.id, store: new_attributes }
          expect(response).to redirect_to(admin_store_path(store))
          expect(flash[:notice]).to include("正常に更新されました")
        end
      end

      context "無効なパラメータの場合" do
        it "店舗を更新しない" do
          original_name = store.name
          patch :update, params: { id: store.id, store: invalid_attributes }
          store.reload
          expect(store.name).to eq(original_name)
        end

        it "editテンプレートを再表示する" do
          patch :update, params: { id: store.id, store: invalid_attributes }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:edit)
        end
      end
    end

    describe "DELETE #destroy" do
      let!(:store_to_delete) { create(:store) }

      context "削除可能な店舗の場合" do
        it "店舗を削除する" do
          expect {
            delete :destroy, params: { id: store_to_delete.id }
          }.to change(Store, :count).by(-1)
        end

        it "店舗一覧にリダイレクトする" do
          delete :destroy, params: { id: store_to_delete.id }
          expect(response).to redirect_to(admin_stores_path)
          expect(flash[:notice]).to include("正常に削除されました")
        end
      end

      context "管理者が紐付いている場合" do
        before do
          create(:admin, store: store_to_delete)
        end

        it "店舗を削除しない" do
          expect {
            delete :destroy, params: { id: store_to_delete.id }
          }.not_to change(Store, :count)
        end

        it "管理者関連のエラーメッセージを表示する" do
          delete :destroy, params: { id: store_to_delete.id }
          expect(response).to redirect_to(admin_stores_path)
          expect(flash[:alert]).to include("管理者アカウントが紐付けられている")
        end
      end

      context "在庫データが存在する場合" do
        before do
          inventory = create(:inventory)
          create(:store_inventory, store: store_to_delete, inventory: inventory)
        end

        it "店舗を削除しない" do
          expect {
            delete :destroy, params: { id: store_to_delete.id }
          }.not_to change(Store, :count)
        end

        it "在庫関連のエラーメッセージを表示する" do
          delete :destroy, params: { id: store_to_delete.id }
          expect(response).to redirect_to(admin_stores_path)
          expect(flash[:alert]).to include("在庫データが存在する")
        end
      end

      context "移動履歴が存在する場合" do
        before do
          create(:inter_store_transfer, source_store: store_to_delete)
        end

        it "店舗を削除しない" do
          expect {
            delete :destroy, params: { id: store_to_delete.id }
          }.not_to change(Store, :count)
        end

        it "移動履歴関連のエラーメッセージを表示する" do
          delete :destroy, params: { id: store_to_delete.id }
          expect(response).to redirect_to(admin_stores_path)
          expect(flash[:alert]).to include("移動履歴が記録されている")
        end
      end

      context "予期しないエラーが発生した場合" do
        before do
          allow_any_instance_of(Store).to receive(:destroy).and_raise(StandardError, "Unexpected error")
        end

        it "一般的なエラーメッセージを表示する" do
          delete :destroy, params: { id: store_to_delete.id }
          expect(response).to redirect_to(admin_stores_path)
          expect(flash[:alert]).to eq("削除中にエラーが発生しました。")
        end
      end
    end

    describe "GET #dashboard" do
      before do
        setup_store_with_data(store)
      end

      it "成功レスポンスを返す" do
        get :dashboard, params: { id: store.id }
        expect(response).to be_successful
      end

      it "ダッシュボード統計を計算する" do
        expect(controller).to receive(:calculate_store_dashboard_stats).with(store).and_return({})
        get :dashboard, params: { id: store.id }
        expect(assigns(:dashboard_stats)).to be_present
      end

      it "低在庫アイテムを取得する" do
        get :dashboard, params: { id: store.id }
        low_stock_items = assigns(:low_stock_items)
        expect(low_stock_items).to be_present
        expect(low_stock_items.count).to eq(1)
      end

      it "保留中の移動申請を取得する" do
        get :dashboard, params: { id: store.id }
        pending_transfers = assigns(:pending_transfers)
        expect(pending_transfers).to be_present
        expect(pending_transfers.all?(&:pending?)).to be true
      end

      it "週次パフォーマンスを計算する" do
        expect(controller).to receive(:calculate_weekly_performance).with(store).and_return({})
        get :dashboard, params: { id: store.id }
        expect(assigns(:weekly_performance)).to be_present
      end
    end
  end

  # ============================================
  # 店舗管理者のテスト
  # ============================================

  describe "店舗管理者としてのアクセス" do
    before do
      store_admin.update!(store: store)
      sign_in store_admin
    end

    describe "GET #index" do
      it "アクセスは許可されるが、店舗作成権限確認が必要" do
        get :index
        expect(response).to be_successful
      end
    end

    describe "GET #show" do
      context "自店舗の場合" do
        it "成功レスポンスを返す" do
          get :show, params: { id: store.id }
          expect(response).to be_successful
        end
      end

      context "他店舗の場合" do
        it "権限エラーでリダイレクトする" do
          get :show, params: { id: other_store.id }
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to include("権限がありません")
        end
      end
    end

    describe "GET #new" do
      it "権限エラーでリダイレクトする" do
        get :new
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ実行可能")
      end
    end

    describe "POST #create" do
      it "権限エラーでリダイレクトする" do
        post :create, params: { store: valid_attributes }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ実行可能")
      end
    end

    describe "GET #edit" do
      context "自店舗の場合" do
        it "成功レスポンスを返す" do
          get :edit, params: { id: store.id }
          expect(response).to be_successful
        end
      end

      context "他店舗の場合" do
        it "権限エラーでリダイレクトする" do
          get :edit, params: { id: other_store.id }
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to include("権限がありません")
        end
      end
    end

    describe "PATCH #update" do
      context "自店舗の場合" do
        it "店舗を更新できる" do
          patch :update, params: { id: store.id, store: { manager_name: "新管理者" } }
          expect(response).to redirect_to(admin_store_path(store))
          expect(store.reload.manager_name).to eq("新管理者")
        end
      end

      context "他店舗の場合" do
        it "権限エラーでリダイレクトする" do
          patch :update, params: { id: other_store.id, store: { manager_name: "新管理者" } }
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to include("権限がありません")
        end
      end
    end

    describe "DELETE #destroy" do
      it "権限エラーでリダイレクトする" do
        delete :destroy, params: { id: store.id }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ実行可能")
      end
    end

    describe "GET #dashboard" do
      context "自店舗の場合" do
        it "成功レスポンスを返す" do
          get :dashboard, params: { id: store.id }
          expect(response).to be_successful
        end
      end

      context "他店舗の場合" do
        it "権限エラーでリダイレクトする" do
          get :dashboard, params: { id: other_store.id }
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to include("権限がありません")
        end
      end
    end
  end

  # ============================================
  # プライベートメソッドのテスト
  # ============================================

  describe "private methods" do
    before do
      sign_in headquarters_admin
    end

    describe "#set_store" do
      it "showアクションでは基本データのみ読み込む" do
        get :show, params: { id: store.id }
        loaded_store = assigns(:store)
        expect(loaded_store.association(:store_inventories)).not_to be_loaded
      end

      it "editアクションでは関連データを含めて読み込む" do
        get :edit, params: { id: store.id }
        loaded_store = assigns(:store)
        expect(loaded_store.association(:store_inventories)).to be_loaded
        expect(loaded_store.association(:admins)).to be_loaded
      end

      it "dashboardアクションでは関連データを含めて読み込む" do
        get :dashboard, params: { id: store.id }
        loaded_store = assigns(:store)
        expect(loaded_store.association(:outgoing_transfers)).to be_loaded
        expect(loaded_store.association(:incoming_transfers)).to be_loaded
      end
    end

    describe "#handle_destroy_error" do
      it "エラーメッセージ付きでリダイレクトする" do
        controller.instance_variable_set(:@store, store)
        controller.send(:handle_destroy_error, "テスト店舗", "カスタムエラーメッセージ")

        expect(response).to redirect_to(admin_stores_path)
        expect(flash[:alert]).to eq("カスタムエラーメッセージ")
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe "edge cases" do
    before do
      sign_in headquarters_admin
    end

    describe "存在しない店舗へのアクセス" do
      it "RecordNotFoundエラーを発生させる" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe "ページネーションの境界値" do
      before do
        create_list(:store, 25, active: true)
      end

      it "ページ2を正しく処理する" do
        get :index, params: { page: 2 }
        expect(assigns(:stores).count).to eq(5) # 20 per page, so 5 on page 2
      end

      it "存在しないページ番号でもエラーにならない" do
        get :index, params: { page: 999 }
        expect(response).to be_successful
        expect(assigns(:stores)).to be_empty
      end
    end
  end

  # ============================================
  # パフォーマンス・N+1クエリテスト
  # ============================================

  describe "performance tests" do
    before do
      sign_in headquarters_admin
    end

    describe "N+1 query prevention" do
      context "index action" do
        it "多数の店舗でのN+1クエリ防止" do
          create_list(:store, 10, active: true)

          expect {
            get :index
          }.not_to exceed_query_limit(15) # Counter Cache活用で制限
        end

        it "統計計算でのクエリ最適化" do
          stores = create_list(:store, 5, active: true)
          stores.each do |store|
            create_list(:store_inventory, 3, store: store)
            create_list(:inter_store_transfer, 2, source_store: store)
          end

          expect {
            get :index
          }.not_to exceed_query_limit(20) # 統計計算含むクエリ制限
        end
      end

      context "show action optimization" do
        it "店舗詳細表示でのN+1クエリ防止" do
          inventory1 = create(:inventory)
          inventory2 = create(:inventory)
          create(:store_inventory, store: store, inventory: inventory1)
          create(:store_inventory, store: store, inventory: inventory2)

          expect {
            get :show, params: { id: store.id }
          }.not_to exceed_query_limit(8) # includes使用で制限
        end

        it "最近の移動履歴読み込み最適化" do
          create_list(:inter_store_transfer, 5, source_store: store)
          create_list(:inter_store_transfer, 3, destination_store: store)

          expect {
            get :show, params: { id: store.id }
          }.not_to exceed_query_limit(10) # 移動履歴のincludes最適化
        end
      end

      context "dashboard action optimization" do
        it "ダッシュボード表示でのCounter Cache活用" do
          setup_store_with_data(store)

          expect {
            get :dashboard, params: { id: store.id }
          }.not_to exceed_query_limit(12) # Counter Cache使用で高速化
        end

        it "低在庫アイテム取得最適化" do
          inventories = create_list(:inventory, 8)
          inventories.each do |inventory|
            create(:store_inventory, 
                   store: store, 
                   inventory: inventory,
                   quantity: 5,
                   safety_stock_level: 10)
          end

          expect {
            get :dashboard, params: { id: store.id }
          }.not_to exceed_query_limit(8) # JOIN使用で最適化
        end
      end
    end

    describe "bulk operations performance" do
      it "大量店舗でのindex表示パフォーマンス" do
        create_list(:store, 50, active: true)

        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 800 # 800ms以内
      end

      it "検索・フィルタリング機能のパフォーマンス" do
        stores = create_list(:store, 30, active: true)
        target_store = stores.first

        start_time = Time.current
        get :index, params: { search: target_store.name[0..2] }
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 400 # 400ms以内
      end

      it "統計計算の重い処理でのパフォーマンス" do
        stores = create_list(:store, 20, active: true)
        stores.each do |s|
          create_list(:store_inventory, 5, store: s)
          create_list(:inter_store_transfer, 3, source_store: s)
        end

        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 1000 # 1秒以内
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "認証なしアクセス" do
      before { sign_out :admin }

      it "index画面への認証なしアクセスは拒否される" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "dashboard画面への認証なしアクセスは拒否される" do
        get :dashboard, params: { id: store.id }
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "権限エスカレーション防止" do
      before do
        sign_in store_admin
        store_admin.update!(store: store)
      end

      it "店舗管理者は他店舗のデータにアクセスできない" do
        get :show, params: { id: other_store.id }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("権限がありません")
      end

      it "店舗管理者は本部機能（店舗作成）にアクセスできない" do
        post :create, params: { store: valid_attributes }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ")
      end

      it "店舗管理者は他店舗の削除はできない" do
        delete :destroy, params: { id: other_store.id }
        expect(response).to redirect_to(admin_root_path)
      end
    end

    context "XSS防止" do
      before { sign_in headquarters_admin }

      let(:xss_attributes) do
        {
          name: "<script>alert('XSS')</script>悪意のある店舗",
          code: "EVIL001",
          store_type: "pharmacy",
          region: "関東",
          manager_name: "<img src=x onerror=alert('XSS')>管理者",
          active: true
        }
      end

      it "店舗名のXSSスクリプトはエスケープされる" do
        post :create, params: { store: xss_attributes }
        created_store = Store.last
        expect(created_store.name).not_to include("<script>")
        expect(created_store.name).to include("悪意のある店舗")
      end

      it "管理者名のXSSスクリプトはエスケープされる" do
        post :create, params: { store: xss_attributes }
        created_store = Store.last
        expect(created_store.manager_name).not_to include("<img")
        expect(created_store.manager_name).to include("管理者")
      end
    end

    context "Mass Assignment防止" do
      before { sign_in headquarters_admin }

      it "許可されていないパラメータは無視される" do
        malicious_params = valid_attributes.merge(
          id: 999,
          created_at: 1.year.ago,
          internal_secret: "SECRET_DATA"
        )

        post :create, params: { store: malicious_params }
        created_store = Store.last

        expect(created_store.name).to eq(valid_attributes[:name])
        expect(created_store.code).to eq(valid_attributes[:code])
        # 許可されていないパラメータは設定されない
        expect(created_store.created_at).to be > 1.hour.ago
      end
    end

    context "SQL Injection防止" do
      before { sign_in headquarters_admin }

      it "検索パラメータでのSQL Injection防止" do
        malicious_search = "'; DROP TABLE stores; --"
        create(:store, name: "安全な店舗")

        expect {
          get :index, params: { search: malicious_search }
        }.not_to raise_error

        expect(Store.count).to be > 0 # テーブルが削除されていない
      end

      it "フィルタパラメータでのSQL Injection防止" do
        malicious_filter = "pharmacy'; DROP TABLE stores; --"

        expect {
          get :index, params: { filter: malicious_filter }
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # エラーハンドリングテスト
  # ============================================

  describe "error handling" do
    before { sign_in headquarters_admin }

    context "データベース接続エラー" do
      before do
        allow(Store).to receive(:active).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "適切にエラーハンドリングされる" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "メモリ不足エラー" do
      before do
        allow(controller).to receive(:calculate_store_overview_stats).and_raise(NoMemoryError)
      end

      it "メモリエラーは適切に伝播される" do
        expect {
          get :index
        }.to raise_error(NoMemoryError)
      end
    end

    context "複雑な統計計算でのタイムアウト" do
      before do
        allow(controller).to receive(:calculate_store_detailed_stats)
          .and_raise(ActiveRecord::QueryCanceled, "Query timeout")
      end

      it "クエリタイムアウトエラーを適切に処理する" do
        expect {
          get :show, params: { id: store.id }
        }.to raise_error(ActiveRecord::QueryCanceled)
      end
    end
  end

  # ============================================
  # APIレスポンス互換性テスト
  # ============================================

  describe "API compatibility" do
    before { sign_in headquarters_admin }

    context "JSON APIレスポンス（将来実装準備）" do
      it "index画面のJSON対応準備" do
        create_list(:store, 3)
        
        # TODO: Phase 4 - JSON API実装時のテスト
        get :index, format: :html
        expect(response).to be_successful
        expect(assigns(:stores)).to be_present
      end

      it "show画面のJSON対応準備" do
        # TODO: Phase 4 - JSON API実装時のテスト
        get :show, params: { id: store.id }, format: :html
        expect(response).to be_successful
        expect(assigns(:store)).to be_present
      end
    end
  end

  # ============================================
  # 統計計算ロジックテスト
  # ============================================

  describe "statistics calculation" do
    before { sign_in headquarters_admin }

    describe "overview statistics" do
      before do
        # テストデータセットアップ
        stores = create_list(:store, 3, active: true)
        create(:store, active: false) # 非アクティブ店舗
        
        stores.each_with_index do |s, index|
          inventory = create(:inventory, price: 1000)
          create(:store_inventory, 
                 store: s, 
                 inventory: inventory,
                 quantity: (index + 1) * 10,
                 safety_stock_level: 5)
        end

        create_list(:inter_store_transfer, 2, status: :pending)
        create_list(:inter_store_transfer, 3, status: :completed, 
                    completed_at: Date.current.beginning_of_day)
      end

      it "統計情報を正しく計算する" do
        get :index
        stats = assigns(:stats)

        expect(stats[:total_stores]).to eq(3) # アクティブ店舗のみ
        expect(stats[:total_inventories]).to eq(3)
        expect(stats[:total_inventory_value]).to eq(60000) # (10+20+30) * 1000
        expect(stats[:pending_transfers]).to eq(2)
        expect(stats[:completed_transfers_today]).to eq(3)
      end
    end

    describe "store detailed statistics" do
      before do
        setup_store_with_data(store)
      end

      it "店舗詳細統計を正しく計算する" do
        get :show, params: { id: store.id }
        stats = assigns(:store_stats)

        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:total_items)
        expect(stats).to have_key(:total_value)
        expect(stats).to have_key(:low_stock_count)
      end
    end

    describe "dashboard statistics" do
      before do
        setup_store_with_data(store)
      end

      it "ダッシュボード統計を正しく計算する" do
        get :dashboard, params: { id: store.id }
        stats = assigns(:dashboard_stats)

        expect(stats).to be_a(Hash)
        expect(stats).to have_key(:inventory_turnover_rate)
        expect(stats).to have_key(:transfers_completed_today)
      end
    end
  end

  # ============================================
  # 検索・フィルタリング機能テスト
  # ============================================

  describe "search and filtering" do
    before do
      sign_in headquarters_admin
      @pharmacy_store = create(:store, name: "薬局A", store_type: :pharmacy, region: "東京")
      @warehouse_store = create(:store, name: "倉庫B", store_type: :warehouse, region: "大阪")
      @headquarters_store = create(:store, name: "本社C", store_type: :headquarters, region: "東京")
    end

    context "名前検索" do
      it "部分マッチで店舗を検索できる" do
        get :index, params: { search: "薬局" }
        expect(assigns(:stores)).to include(@pharmacy_store)
        expect(assigns(:stores)).not_to include(@warehouse_store)
      end

      it "大文字小文字を区別しない検索" do
        get :index, params: { search: "YAKKYOKU" }
        # TODO: 実装によっては文字化けやローマ字検索対応が必要
        expect(response).to be_successful
      end
    end

    context "タイプフィルター" do
      it "薬局のみフィルタリングできる" do
        get :index, params: { filter: "pharmacy" }
        expect(assigns(:stores)).to include(@pharmacy_store)
        expect(assigns(:stores)).not_to include(@warehouse_store)
      end

      it "倉庫のみフィルタリングできる" do
        get :index, params: { filter: "warehouse" }
        expect(assigns(:stores)).to include(@warehouse_store)
        expect(assigns(:stores)).not_to include(@pharmacy_store)
      end
    end

    context "地域検索" do
      it "地域で店舗を絞り込める" do
        get :index, params: { search: "東京" }
        stores = assigns(:stores)
        expect(stores).to include(@pharmacy_store, @headquarters_store)
        expect(stores).not_to include(@warehouse_store)
      end
    end

    context "低在庫フィルター" do
      before do
        inventory = create(:inventory)
        create(:store_inventory,
               store: @pharmacy_store,
               inventory: inventory,
               quantity: 3,
               safety_stock_level: 10) # 低在庫
        create(:store_inventory,
               store: @warehouse_store,
               inventory: inventory,
               quantity: 50,
               safety_stock_level: 10) # 正常在庫
      end

      it "低在庫店舗のみフィルタリングできる" do
        get :index, params: { filter: "low_stock" }
        expect(assigns(:stores)).to include(@pharmacy_store)
        expect(assigns(:stores)).not_to include(@warehouse_store)
      end
    end
  end
end
