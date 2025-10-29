# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::TransfersController, type: :controller do
  # CLAUDE.md準拠: 店舗間移動機能の包括的テスト
  # メタ認知: 在庫移動は重要なビジネスロジック - セキュリティと整合性が最重要
  # 横展開: 他の在庫関連コントローラーでも同様のテストパターン適用

  let!(:source_store) { create(:store, :pharmacy, slug: 'source-pharmacy') }
  let!(:destination_store) { create(:store, :warehouse, slug: 'destination-warehouse') }
  let!(:another_store) { create(:store, :pharmacy, slug: 'another-pharmacy') }
  let!(:inactive_store) { create(:store, slug: 'inactive-store', active: false) }

  let!(:store_user) { create(:store_user, store: source_store, role: 'manager') }
  let!(:staff_user) { create(:store_user, store: source_store, role: 'staff') }
  let!(:another_store_user) { create(:store_user, store: another_store) }

  let!(:inventory) { create(:inventory, name: 'Test Medicine A') }
  let!(:inventory_b) { create(:inventory, name: 'Test Medicine B') }

  let!(:source_inventory) { create(:store_inventory, store: source_store, inventory: inventory, quantity: 100, reserved_quantity: 10) }
  let!(:destination_inventory) { create(:store_inventory, store: destination_store, inventory: inventory, quantity: 50) }

  let!(:transfer) { create(:inter_store_transfer,
                          source_store: source_store,
                          destination_store: destination_store,
                          inventory: inventory,
                          quantity: 20,
                          requested_by: store_user,
                          status: 'pending') }

  before do
    sign_in store_user, scope: :store_user
    allow(controller).to receive(:current_store).and_return(source_store)
    allow(controller).to receive(:current_store_user).and_return(store_user)
  end

  describe "認証・認可テスト" do
    context "未認証ユーザー" do
      before { sign_out store_user }

      it "ログインページにリダイレクトする" do
        get :index
        expect(response).to redirect_to(new_store_user_session_path)
      end
    end

    context "異なる店舗のユーザー" do
      before do
        sign_in another_store_user, scope: :store_user
        allow(controller).to receive(:current_store).and_return(another_store)
        allow(controller).to receive(:current_store_user).and_return(another_store_user)
      end

      it "自店舗に関連する移動のみアクセス可能" do
        get :index
        transfers = assigns(:transfers)
        expect(transfers).to be_empty
      end
    end

    context "非アクティブ店舗のユーザー" do
      let!(:inactive_user) { create(:store_user, store: inactive_store) }

      before do
        sign_in inactive_user, scope: :store_user
        allow(controller).to receive(:current_store).and_return(inactive_store)
        allow(controller).to receive(:current_store_user).and_return(inactive_user)
      end

      it "アクセスを拒否する" do
        get :index
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # ============================================
  # index アクション包括的テスト
  # ============================================

  describe 'GET #index' do
    let!(:outgoing_transfer) { create(:inter_store_transfer, source_store: source_store, destination_store: destination_store, inventory: inventory) }
    let!(:incoming_transfer) { create(:inter_store_transfer, source_store: destination_store, destination_store: source_store, inventory: inventory) }
    let!(:unrelated_transfer) { create(:inter_store_transfer, source_store: another_store, destination_store: destination_store, inventory: inventory) }

    before { get :index }

    it "成功レスポンスを返す" do
      expect(response).to have_http_status(:success)
    end

    it "自店舗に関連する移動のみ取得する" do
      transfers = assigns(:transfers)
      expect(transfers).to include(outgoing_transfer, incoming_transfer, transfer)
      expect(transfers).not_to include(unrelated_transfer)
    end

    it "作成日時の降順でソートされる" do
      transfers = assigns(:transfers)
      expect(transfers.first.created_at).to be >= transfers.last.created_at
    end

    it "移動カウントが設定される" do
      counts = assigns(:transfer_counts)
      expect(counts).to include(:all, :outgoing, :incoming, :pending, :in_transit, :completed)
      expect(counts[:all]).to be >= 3
    end

    context "ページネーション" do
      before do
        create_list(:inter_store_transfer, 25, source_store: source_store, destination_store: destination_store, inventory: inventory)
      end

      it "ページごとに20件表示される" do
        get :index
        transfers = assigns(:transfers)
        expect(transfers.size).to eq(20)
      end

      it "2ページ目が正常に表示される" do
        get :index, params: { page: 2 }
        expect(response).to have_http_status(:success)
        transfers = assigns(:transfers)
        expect(transfers.size).to be > 0
      end
    end

    context "検索・フィルタリング" do
      it "在庫名での検索が可能" do
        get :index, params: { q: { inventory_name_cont: 'Test Medicine' } }
        transfers = assigns(:transfers)
        transfers.each do |t|
          expect(t.inventory.name).to include('Test Medicine')
        end
      end

      it "ステータスでのフィルタリングが可能" do
        get :index, params: { q: { status_eq: 'pending' } }
        transfers = assigns(:transfers)
        transfers.each do |t|
          expect(t.status).to eq('pending')
        end
      end

      it "移動方向でのフィルタリングが可能" do
        get :index, params: { q: { direction_eq: 'outgoing' } }
        transfers = assigns(:transfers)
        transfers.each do |t|
          expect(t.source_store_id).to eq(source_store.id)
        end
      end

      it "日付範囲でのフィルタリングが可能" do
        yesterday = 1.day.ago.to_date
        get :index, params: { q: { requested_at_gteq: yesterday } }
        transfers = assigns(:transfers)
        transfers.each do |t|
          expect(t.requested_at.to_date).to be >= yesterday
        end
      end
    end

    context "N+1クエリ防止" do
      before do
        create_list(:inter_store_transfer, 5, source_store: source_store, destination_store: destination_store, inventory: inventory)
      end

      it "効率的なクエリでデータを取得する" do
        expect {
          get :index
        }.not_to exceed_query_limit(10)
      end
    end
  end

  # ============================================
  # show アクション包括的テスト
  # ============================================

  describe 'GET #show' do
    context "有効な移動ID" do
      before { get :show, params: { id: transfer.id } }

      it "成功レスポンスを返す" do
        expect(response).to have_http_status(:success)
      end

      it "移動データが設定される" do
        expect(assigns(:transfer)).to eq(transfer)
      end

      it "タイムラインイベントが構築される" do
        timeline = assigns(:timeline_events)
        expect(timeline).to be_an(Array)
        expect(timeline.first[:event]).to eq('requested')
      end

      it "在庫情報が読み込まれる" do
        expect(assigns(:source_inventory)).to eq(source_inventory)
        expect(assigns(:destination_inventory)).to eq(destination_inventory)
      end
    end

    context "無効な移動ID" do
      it "404エラーが発生する" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "他店舗の移動" do
      let!(:other_transfer) { create(:inter_store_transfer, source_store: another_store, destination_store: destination_store, inventory: inventory) }

      it "アクセスできない" do
        expect {
          get :show, params: { id: other_transfer.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # new アクション包括的テスト
  # ============================================

  describe 'GET #new' do
    before { get :new }

    it "成功レスポンスを返す" do
      expect(response).to have_http_status(:success)
    end

    it "新しい移動オブジェクトが作成される" do
      transfer = assigns(:transfer)
      expect(transfer).to be_a_new(InterStoreTransfer)
      expect(transfer.source_store).to eq(source_store)
      expect(transfer.requested_by).to eq(store_user)
    end

    it "利用可能な在庫が設定される" do
      inventories = assigns(:available_inventories)
      expect(inventories).to include(source_inventory)
      inventories.each do |si|
        expect(si.quantity).to be > si.reserved_quantity
      end
    end

    it "送付先店舗が設定される" do
      stores = assigns(:destination_stores)
      expect(stores).to include(destination_store)
      expect(stores).not_to include(source_store) # 自店舗は除外
      expect(stores).not_to include(inactive_store) # 非アクティブ店舗は除外
    end

    context "在庫がない場合" do
      before do
        source_inventory.update!(quantity: 0)
        get :new
      end

      it "利用可能な在庫が空になる" do
        inventories = assigns(:available_inventories)
        expect(inventories).to be_empty
      end
    end
  end

  # ============================================
  # create アクション包括的テスト
  # ============================================

  describe 'POST #create' do
    let(:valid_params) do
      {
        inter_store_transfer: {
          destination_store_id: destination_store.id,
          inventory_id: inventory.id,
          quantity: 10,
          priority: 'normal',
          reason: 'Stock replenishment',
          notes: 'Test transfer',
          requested_delivery_date: 3.days.from_now.to_date
        }
      }
    end

    context "有効なパラメータ" do
      it "移動が作成される" do
        expect {
          post :create, params: valid_params
        }.to change(InterStoreTransfer, :count).by(1)
      end

      it "在庫が予約される" do
        expect {
          post :create, params: valid_params
        }.to change { source_inventory.reload.reserved_quantity }.by(10)
      end

      it "移動詳細ページにリダイレクトする" do
        post :create, params: valid_params
        created_transfer = InterStoreTransfer.last
        expect(response).to redirect_to(store_transfer_path(created_transfer))
      end

      it "成功メッセージが表示される" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end

      it "適切な初期値が設定される" do
        post :create, params: valid_params
        created_transfer = InterStoreTransfer.last
        expect(created_transfer.source_store).to eq(source_store)
        expect(created_transfer.requested_by).to eq(store_user)
        expect(created_transfer.status).to eq('pending')
        expect(created_transfer.requested_at).to be_present
      end
    end

    context "無効なパラメータ" do
      let(:invalid_params) do
        {
          inter_store_transfer: {
            destination_store_id: nil,
            inventory_id: inventory.id,
            quantity: -1
          }
        }
      end

      it "移動が作成されない" do
        expect {
          post :create, params: invalid_params
        }.not_to change(InterStoreTransfer, :count)
      end

      it "newテンプレートが再表示される" do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "フォーム用データが再読み込みされる" do
        post :create, params: invalid_params
        expect(assigns(:available_inventories)).to be_present
        expect(assigns(:destination_stores)).to be_present
      end
    end

    context "在庫不足の場合" do
      let(:insufficient_params) do
        valid_params.tap do |params|
          params[:inter_store_transfer][:quantity] = 1000 # 在庫より多い
        end
      end

      it "移動が作成されない" do
        expect {
          post :create, params: insufficient_params
        }.not_to change(InterStoreTransfer, :count)
      end
    end

    context "レート制限" do
      before do
        allow(controller).to receive(:rate_limited?).and_return(true)
      end

      it "レート制限エラーが発生する" do
        post :create, params: valid_params
        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end

  # ============================================
  # cancel アクション包括的テスト
  # ============================================

  describe 'DELETE #cancel' do
    context "キャンセル可能な移動" do
      before do
        allow(transfer).to receive(:can_be_cancelled_by?).and_return(true)
        allow(transfer).to receive(:cancel_by!).and_return(true)
      end

      it "移動がキャンセルされる" do
        expect(transfer).to receive(:cancel_by!).with(store_user)
        delete :cancel, params: { id: transfer.id }
      end

      it "在庫予約が解除される" do
        original_reserved = source_inventory.reserved_quantity
        delete :cancel, params: { id: transfer.id }
        expect(source_inventory.reload.reserved_quantity).to be < original_reserved
      end

      it "移動一覧ページにリダイレクトする" do
        delete :cancel, params: { id: transfer.id }
        expect(response).to redirect_to(store_transfers_path)
      end

      it "成功メッセージが表示される" do
        delete :cancel, params: { id: transfer.id }
        expect(flash[:notice]).to be_present
      end
    end

    context "キャンセル不可能な移動" do
      before do
        allow(transfer).to receive(:can_be_cancelled_by?).and_return(false)
      end

      it "移動詳細ページにリダイレクトする" do
        delete :cancel, params: { id: transfer.id }
        expect(response).to redirect_to(store_transfer_path(transfer))
      end

      it "エラーメッセージが表示される" do
        delete :cancel, params: { id: transfer.id }
        expect(flash[:alert]).to be_present
      end
    end

    context "キャンセル処理失敗" do
      before do
        allow(transfer).to receive(:can_be_cancelled_by?).and_return(true)
        allow(transfer).to receive(:cancel_by!).and_return(false)
      end

      it "移動詳細ページにリダイレクトする" do
        delete :cancel, params: { id: transfer.id }
        expect(response).to redirect_to(store_transfer_path(transfer))
      end

      it "エラーメッセージが表示される" do
        delete :cancel, params: { id: transfer.id }
        expect(flash[:alert]).to be_present
      end
    end
  end

  # ============================================
  # プライベートメソッドテスト
  # ============================================

  describe 'private methods' do
    describe '#set_transfer' do
      context "有効なID" do
        it "移動データを設定する" do
          controller.params = { id: transfer.id }
          controller.send(:set_transfer)
          expect(assigns(:transfer)).to eq(transfer)
        end
      end

      context "アクセス権限のないID" do
        let!(:other_transfer) { create(:inter_store_transfer, source_store: another_store, destination_store: destination_store, inventory: inventory) }

        it "RecordNotFoundが発生する" do
          controller.params = { id: other_transfer.id }
          expect {
            controller.send(:set_transfer)
          }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end

    describe '#ensure_can_cancel' do
      before { controller.instance_variable_set(:@transfer, transfer) }

      context "キャンセル可能な場合" do
        before { allow(transfer).to receive(:can_be_cancelled_by?).and_return(true) }

        it "処理が継続される" do
          expect(controller).not_to receive(:redirect_to)
          controller.send(:ensure_can_cancel)
        end
      end

      context "キャンセル不可能な場合" do
        before { allow(transfer).to receive(:can_be_cancelled_by?).and_return(false) }

        it "移動詳細ページにリダイレクトする" do
          expect(controller).to receive(:redirect_to).with(
            store_transfer_path(transfer),
            alert: I18n.t("errors.messages.insufficient_permissions")
          )
          controller.send(:ensure_can_cancel)
        end
      end
    end
  end

  # ============================================
  # ヘルパーメソッドテスト
  # ============================================

  describe 'helper methods' do
    describe '#transfer_direction_icon' do
      context "出庫移動" do
        it "出庫アイコンを返す" do
          result = controller.transfer_direction_icon(transfer)
          expect(result[:icon_class]).to include('arrow-right')
          expect(result[:title]).to eq('出庫')
        end
      end

      context "入庫移動" do
        let!(:incoming_transfer) { create(:inter_store_transfer, source_store: destination_store, destination_store: source_store, inventory: inventory) }

        it "入庫アイコンを返す" do
          result = controller.transfer_direction_icon(incoming_transfer)
          expect(result[:icon_class]).to include('arrow-left')
          expect(result[:title]).to eq('入庫')
        end
      end
    end

    describe '#priority_badge' do
      it "緊急優先度のバッジを返す" do
        result = controller.priority_badge('urgent')
        expect(result[:text]).to eq('緊急')
        expect(result[:class]).to include('bg-danger')
      end

      it "高優先度のバッジを返す" do
        result = controller.priority_badge('high')
        expect(result[:text]).to eq('高')
        expect(result[:class]).to include('bg-warning')
      end

      it "通常優先度のバッジを返す" do
        result = controller.priority_badge('normal')
        expect(result[:text]).to eq('通常')
        expect(result[:class]).to include('bg-secondary')
      end

      it "低優先度のバッジを返す" do
        result = controller.priority_badge('low')
        expect(result[:text]).to eq('低')
        expect(result[:class]).to include('bg-light')
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe 'セキュリティテスト' do
    context "SQLインジェクション防止" do
      it "検索パラメータを安全に処理する" do
        malicious_query = "'; DROP TABLE inter_store_transfers; --"

        expect {
          get :index, params: { q: { inventory_name_cont: malicious_query } }
        }.not_to raise_error

        expect(InterStoreTransfer.count).to be > 0
      end
    end

    context "パラメータ改ざん防止" do
      it "不正なパラメータを拒否する" do
        malicious_params = {
          inter_store_transfer: {
            destination_store_id: destination_store.id,
            inventory_id: inventory.id,
            quantity: 10,
            status: 'approved', # 通常は設定できない
            approved_by: 'attacker'
          }
        }

        post :create, params: malicious_params
        created_transfer = InterStoreTransfer.last
        expect(created_transfer.status).to eq('pending') # 初期値のまま
        expect(created_transfer.approved_by).to be_nil
      end
    end

    context "権限昇格防止" do
      before do
        sign_in staff_user, scope: :store_user
        allow(controller).to receive(:current_store_user).and_return(staff_user)
      end

      it "一般スタッフも移動申請可能" do
        post :create, params: {
          inter_store_transfer: {
            destination_store_id: destination_store.id,
            inventory_id: inventory.id,
            quantity: 5
          }
        }
        expect(response).to have_http_status(:redirect)
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'パフォーマンステスト' do
    context "大量データでのレスポンス" do
      before do
        create_list(:inter_store_transfer, 100, source_store: source_store, destination_store: destination_store, inventory: inventory)
      end

      it "大量移動履歴でも効率的に処理する" do
        start_time = Time.current
        get :index
        elapsed = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed).to be < 1000 # 1秒以内
      end

      it "ページネーションで応答時間を制御する" do
        expect {
          get :index
        }.not_to exceed_query_limit(15)
      end
    end

    context "複雑な検索クエリ" do
      before do
        create_list(:inter_store_transfer, 50, source_store: source_store, destination_store: destination_store, inventory: inventory)
      end

      it "複数条件検索でも効率的" do
        expect {
          get :index, params: {
            q: {
              inventory_name_cont: 'Test',
              status_eq: 'pending',
              direction_eq: 'outgoing',
              requested_at_gteq: 1.week.ago.to_date
            }
          }
        }.not_to exceed_query_limit(12)
      end
    end
  end

  # ============================================
  # エラーハンドリングテスト
  # ============================================

  describe 'エラーハンドリング' do
    context "データベース接続エラー" do
      before do
        allow(InterStoreTransfer).to receive(:where).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "適切にエラーを処理する" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "在庫予約エラー" do
      before do
        allow_any_instance_of(StoreInventory).to receive(:increment!).and_raise(ActiveRecord::RecordInvalid)
      end

      it "予約失敗時にロールバックする" do
        expect {
          post :create, params: {
            inter_store_transfer: {
              destination_store_id: destination_store.id,
              inventory_id: inventory.id,
              quantity: 10
            }
          }
        }.not_to change(InterStoreTransfer, :count)
      end
    end

    context "無効な日付パラメータ" do
      it "日付解析エラーを適切に処理する" do
        expect {
          get :index, params: { q: { requested_at_gteq: 'invalid-date' } }
        }.not_to raise_error

        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # 国際化対応テスト
  # ============================================

  describe '国際化対応' do
    context "日本語環境" do
      before { I18n.locale = :ja }

      it "日本語メッセージを表示する" do
        post :create, params: {
          inter_store_transfer: {
            destination_store_id: destination_store.id,
            inventory_id: inventory.id,
            quantity: 10
          }
        }
        expect(flash[:notice]).to be_present
      end
    end

    context "英語環境" do
      before { I18n.locale = :en }

      it "英語環境でも正常動作する" do
        expect {
          get :index
        }.not_to raise_error
        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # レート制限テスト
  # ============================================

  describe 'レート制限' do
    it "制限対象アクションを正しく設定する" do
      limited_actions = controller.send(:rate_limited_actions)
      expect(limited_actions).to include(:create)
      expect(limited_actions).not_to include(:index, :show)
    end

    it "適切なレート制限キーを生成する" do
      key_type = controller.send(:rate_limit_key_type)
      expect(key_type).to eq(:transfer_request)
    end

    it "ユーザー固有の識別子を生成する" do
      identifier = controller.send(:rate_limit_identifier)
      expect(identifier).to eq("store_user:#{store_user.id}")
    end
  end
end
