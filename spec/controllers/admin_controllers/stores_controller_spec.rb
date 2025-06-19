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
end
