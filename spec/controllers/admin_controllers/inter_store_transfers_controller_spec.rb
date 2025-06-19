# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InterStoreTransfersController, type: :controller do
  # CLAUDE.md準拠: 店舗間移動管理機能のテスト品質向上
  # メタ認知: analytics機能のTypeError修正とデータ構造整合性確保
  # 横展開: 他の統計表示機能でも同様のテスト構造を適用

  let(:admin) { create(:admin) }
  let(:source_store) { create(:store, name: "本店") }
  let(:destination_store) { create(:store, name: "支店") }
  let(:inventory) { create(:inventory) }

  before do
    sign_in admin, scope: :admin
  end

  describe "GET #analytics" do
    context "with valid admin authentication" do
      it "returns a success response" do
        get :analytics
        expect(response).to be_successful
      end

      it "assigns analytics data with correct structure" do
        get :analytics

        expect(assigns(:analytics)).to be_present
        expect(assigns(:store_analytics)).to be_an(Array)
        expect(assigns(:trend_data)).to be_present
        expect(assigns(:period)).to be_present
      end

      it "handles store_analytics as array structure for view compatibility" do
        # 店舗とサンプルデータを作成
        create_list(:store, 3)

        get :analytics

        store_analytics = assigns(:store_analytics)
        expect(store_analytics).to be_an(Array)

        if store_analytics.any?
          store_data = store_analytics.first
          expect(store_data).to have_key(:store)
          expect(store_data).to have_key(:stats)
          expect(store_data[:stats]).to be_a(Hash)
        end
      end

      context "with period parameter" do
        it "accepts valid period parameter" do
          get :analytics, params: { period: 7 }
          expect(assigns(:period)).to eq(7.days.ago.to_date)
        end

        it "uses default period for invalid parameters" do
          get :analytics, params: { period: -1 }
          expect(assigns(:period)).to eq(30.days.ago.to_date)
        end

        it "uses default period for excessive parameters" do
          get :analytics, params: { period: 400 }
          expect(assigns(:period)).to eq(30.days.ago.to_date)
        end
      end

      context "with transfer data" do
        before do
          # テスト用の移動データを作成
          @transfer1 = create(:inter_store_transfer,
                             source_store: source_store,
                             destination_store: destination_store,
                             inventory: inventory,
                             status: :completed,
                             requested_at: 15.days.ago,
                             completed_at: 14.days.ago)

          @transfer2 = create(:inter_store_transfer,
                             source_store: destination_store,
                             destination_store: source_store,
                             inventory: inventory,
                             status: :pending,
                             requested_at: 5.days.ago)
        end

        it "calculates store analytics correctly" do
          get :analytics

          store_analytics = assigns(:store_analytics)
          expect(store_analytics).not_to be_empty

          # 各店舗のデータが正しい構造を持つことを確認
          store_analytics.each do |store_data|
            expect(store_data[:store]).to be_a(Store)
            stats = store_data[:stats]

            expect(stats).to include(:outgoing_count, :incoming_count,
                                   :outgoing_completed, :incoming_completed,
                                   :net_flow, :approval_rate, :efficiency_score)
            expect(stats[:outgoing_count]).to be_a(Integer)
            expect(stats[:incoming_count]).to be_a(Integer)
            expect(stats[:approval_rate]).to be_a(Numeric)
            expect(stats[:efficiency_score]).to be_a(Numeric)
          end
        end
      end
    end

    context "without authentication" do
      before { sign_out admin }

      it "redirects to sign in page" do
        get :analytics
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "when errors occur during calculation" do
      before do
        # エラーを発生させるためのモック
        allow(InterStoreTransfer).to receive(:transfer_analytics).and_raise(StandardError, "Test error")
      end

      it "handles errors gracefully and provides fallback data" do
        get :analytics

        expect(response).to be_successful
        expect(assigns(:analytics)).to eq({})
        expect(assigns(:store_analytics)).to eq([])
        expect(assigns(:trend_data)).to eq({})
        expect(flash.now[:alert]).to include("分析データの取得中にエラーが発生しました")
      end
    end
  end

  describe "private methods" do
    describe "#calculate_store_transfer_analytics" do
      let(:period) { 30.days.ago }

      context "with stores and transfers" do
        before do
          @stores = create_list(:store, 2)
          @transfers = create_list(:inter_store_transfer, 3,
                                  source_store: @stores.first,
                                  destination_store: @stores.last,
                                  requested_at: 15.days.ago)
        end

        it "returns array structure suitable for view" do
          analytics = controller.send(:calculate_store_transfer_analytics, period)

          expect(analytics).to be_an(Array)
          expect(analytics.length).to eq(Store.active.count)

          analytics.each do |store_data|
            expect(store_data).to have_key(:store)
            expect(store_data).to have_key(:stats)
            expect(store_data[:store]).to be_a(Store)
            expect(store_data[:stats]).to be_a(Hash)
          end
        end
      end
    end

    describe "#calculate_store_efficiency" do
      it "calculates efficiency score correctly" do
        # モックデータでのテスト
        outgoing = double("outgoing_transfers",
                         count: 10,
                         where: double(count: 8))
        incoming = double("incoming_transfers",
                         count: 5,
                         where: double(count: 4))

        efficiency = controller.send(:calculate_store_efficiency, outgoing, incoming)

        expect(efficiency).to be_a(Numeric)
        expect(efficiency).to be_between(0, 100)
      end

      it "handles zero transfers gracefully" do
        outgoing = double("outgoing_transfers", count: 0)
        incoming = double("incoming_transfers", count: 0)

        efficiency = controller.send(:calculate_store_efficiency, outgoing, incoming)
        expect(efficiency).to eq(0)
      end
    end

    # CLAUDE.md準拠: パフォーマンス最適化メソッドのテスト
    # メタ認知: システムリマインダーで確認された新機能のテスト実装
    # 横展開: 他のパフォーマンス最適化実装でも同様のテスト構造適用
    describe "performance optimization methods" do
      let(:sample_transfers) do
        [
          double("transfer", status: "completed", completed_at: 2.hours.ago, requested_at: 1.day.ago, inventory: double("inventory")),
          double("transfer", status: "approved", completed_at: nil, requested_at: 2.days.ago, inventory: double("inventory")),
          double("transfer", status: "pending", completed_at: nil, requested_at: 3.days.ago, inventory: double("inventory"))
        ]
      end

      describe "#calculate_store_efficiency_from_arrays" do
        it "calculates efficiency from transfer arrays" do
          outgoing = [ sample_transfers[0], sample_transfers[1] ]
          incoming = [ sample_transfers[2] ]

          efficiency = controller.send(:calculate_store_efficiency_from_arrays, outgoing, incoming)

          expect(efficiency).to be_a(Numeric)
          expect(efficiency).to be_between(0, 100)
        end

        it "handles empty arrays" do
          efficiency = controller.send(:calculate_store_efficiency_from_arrays, [], [])
          expect(efficiency).to eq(0)
        end
      end

      describe "#calculate_approval_rate_from_array" do
        it "calculates approval rate from transfer array" do
          rate = controller.send(:calculate_approval_rate_from_array, sample_transfers)

          expect(rate).to be_a(Numeric)
          expect(rate).to be_between(0, 100)
          # 3件中2件がapproved/completed
          expect(rate).to eq(66.7)
        end

        it "handles empty array" do
          rate = controller.send(:calculate_approval_rate_from_array, [])
          expect(rate).to eq(0)
        end
      end

      describe "#calculate_average_completion_time_from_array" do
        let(:completed_transfers) do
          [
            double("transfer", completed_at: 2.hours.ago, requested_at: 1.day.ago),
            double("transfer", completed_at: 1.hour.ago, requested_at: 12.hours.ago)
          ]
        end

        it "calculates average completion time from transfer array" do
          avg_time = controller.send(:calculate_average_completion_time_from_array, completed_transfers)

          expect(avg_time).to be_a(Numeric)
          expect(avg_time).to be > 0
        end

        it "handles transfers without completion time" do
          invalid_transfers = [ double("transfer", completed_at: nil, requested_at: 1.day.ago) ]
          avg_time = controller.send(:calculate_average_completion_time_from_array, invalid_transfers)

          expect(avg_time).to eq(0)
        end

        it "handles empty array" do
          avg_time = controller.send(:calculate_average_completion_time_from_array, [])
          expect(avg_time).to eq(0)
        end
      end

      describe "#calculate_most_transferred_items_from_array" do
        let(:inventory1) { double("inventory1", name: "商品A") }
        let(:inventory2) { double("inventory2", name: "商品B") }
        let(:transfers_with_items) do
          [
            double("transfer", inventory: inventory1),
            double("transfer", inventory: inventory1),
            double("transfer", inventory: inventory2),
            double("transfer", inventory: inventory1)
          ]
        end

        it "returns most transferred items from transfer array" do
          result = controller.send(:calculate_most_transferred_items_from_array, transfers_with_items)

          expect(result).to be_an(Array)
          expect(result.length).to be <= 3

          if result.any?
            top_item = result.first
            expect(top_item).to have_key(:inventory)
            expect(top_item).to have_key(:count)
            expect(top_item[:count]).to eq(3) # inventory1が3回
          end
        end

        it "handles empty array" do
          result = controller.send(:calculate_most_transferred_items_from_array, [])
          expect(result).to eq([])
        end
      end
    end
  end

  # TODO: 🟡 Phase 3（中）- 統合テスト強化
  # 優先度: 中（基本機能は動作確認済み）
  # 実装内容:
  #   - 大量データでのパフォーマンステスト
  #   - エッジケース（空データ、異常値）のテスト
  #   - セキュリティテスト（権限チェック）
  # 期待効果: 本番環境での安定性保証
  # 工数見積: 2-3日
  # 依存関係: テストデータ充実化、権限機能実装

  describe "performance considerations" do
    # TODO: 🟢 Phase 4（推奨）- N+1クエリ防止テスト
    # 優先度: 低（includes使用済み）
    # 実装内容: Bulletと連携したクエリ数監視
    # 理由: パフォーマンス回帰防止
    # 期待効果: レスポンス時間維持
    # 工数見積: 1日
    # 依存関係: Bullet gem設定

    it "loads analytics efficiently without excessive queries" do
      create_list(:store, 5)
      create_list(:inter_store_transfer, 10)

      expect { get :analytics }.not_to exceed_query_limit(20)
    end
  end

  # CLAUDE.md準拠: 原因となったNoMethodErrorの回帰防止テスト
  # メタ認知: edit_admin_inter_store_transfer_pathエラーの特化テスト
  # 横展開: 他のルーティングヘルパーでも同様のテスト実装
  describe "routing helpers validation" do
    it "edit_admin_inter_store_transfer_path exists and generates correct path" do
      transfer = create(:inter_store_transfer, source_store: source_store, destination_store: destination_store, inventory: inventory)

      # ルーティングヘルパーの存在確認
      expect(controller.helpers).to respond_to(:edit_admin_inter_store_transfer_path)

      # 正しいパス生成確認
      path = controller.helpers.edit_admin_inter_store_transfer_path(transfer)
      expect(path).to eq("/admin/transfers/#{transfer.id}/edit")
    end

    it "all inter_store_transfer routing helpers are available" do
      transfer = create(:inter_store_transfer, source_store: source_store, destination_store: destination_store, inventory: inventory)

      helpers = controller.helpers
      expect(helpers).to respond_to(:admin_inter_store_transfers_path)
      expect(helpers).to respond_to(:admin_inter_store_transfer_path)
      expect(helpers).to respond_to(:new_admin_inter_store_transfer_path)
      expect(helpers).to respond_to(:edit_admin_inter_store_transfer_path)

      # パス生成テスト
      expect(helpers.admin_inter_store_transfers_path).to eq("/admin/transfers")
      expect(helpers.admin_inter_store_transfer_path(transfer)).to eq("/admin/transfers/#{transfer.id}")
      expect(helpers.new_admin_inter_store_transfer_path).to eq("/admin/transfers/new")
      expect(helpers.edit_admin_inter_store_transfer_path(transfer)).to eq("/admin/transfers/#{transfer.id}/edit")
    end
  end

  # ============================================
  # CRUDアクションの包括的テスト
  # ============================================

  describe "CRUD actions" do
    let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }
    let(:store_admin) { create(:admin, role: :store_admin, store: source_store) }
    let(:valid_attributes) do
      {
        source_store_id: source_store.id,
        destination_store_id: destination_store.id,
        inventory_id: inventory.id,
        quantity: 10,
        priority: "normal",
        reason: "在庫補充のため",
        notes: "至急対応が必要",
        requested_delivery_date: 3.days.from_now
      }
    end
    let(:invalid_attributes) do
      {
        source_store_id: nil,
        destination_store_id: nil,
        inventory_id: nil,
        quantity: -1,
        reason: ""
      }
    end

    before do
      # 在庫データをセットアップ
      create(:store_inventory, 
             store: source_store, 
             inventory: inventory, 
             quantity: 100, 
             safety_stock_level: 20)
    end

    describe "GET #index" do
      before do
        sign_in headquarters_admin
        @transfers = create_list(:inter_store_transfer, 5,
                                source_store: source_store,
                                destination_store: destination_store,
                                inventory: inventory)
      end

      it "成功レスポンスを返す" do
        get :index
        expect(response).to be_successful
      end

      it "移動申請一覧をページネーション付きで取得する" do
        get :index
        expect(assigns(:transfers)).to be_present
        expect(assigns(:transfers)).to respond_to(:current_page)
      end

      it "統計情報を計算する" do
        get :index
        stats = assigns(:stats)
        expect(stats).to include(:total_transfers, :pending_count, :approved_count)
      end

      it "関連データを事前読み込みする" do
        get :index
        transfers = assigns(:transfers)
        first_transfer = transfers.first
        expect(first_transfer.association(:source_store)).to be_loaded
        expect(first_transfer.association(:destination_store)).to be_loaded
        expect(first_transfer.association(:inventory)).to be_loaded
      end

      context "フィルタリング" do
        before do
          create(:inter_store_transfer, 
                 source_store: source_store,
                 destination_store: destination_store,
                 inventory: inventory,
                 status: :pending)
          create(:inter_store_transfer,
                 source_store: source_store,
                 destination_store: destination_store,
                 inventory: inventory,
                 status: :completed)
        end

        it "ステータスでフィルタリングできる" do
          get :index, params: { status: "pending" }
          expect(assigns(:transfers).all?(&:pending?)).to be true
        end

        it "優先度でフィルタリングできる" do
          get :index, params: { priority: "urgent" }
          expect(response).to be_successful
        end

        it "店舗でフィルタリングできる" do
          get :index, params: { store_id: source_store.id }
          expect(response).to be_successful
        end

        it "検索でフィルタリングできる" do
          get :index, params: { search: inventory.name[0..2] }
          expect(response).to be_successful
        end
      end
    end

    describe "GET #show" do
      let(:transfer) { create(:inter_store_transfer,
                             source_store: source_store,
                             destination_store: destination_store,
                             inventory: inventory) }

      before { sign_in headquarters_admin }

      it "成功レスポンスを返す" do
        get :show, params: { id: transfer.id }
        expect(response).to be_successful
      end

      it "移動詳細情報を設定する" do
        get :show, params: { id: transfer.id }
        expect(assigns(:transfer)).to eq(transfer)
        expect(assigns(:transfer_history)).to be_present
        expect(assigns(:related_transfers)).to be_present
        expect(assigns(:transfer_analytics)).to be_present
      end
    end

    describe "GET #new" do
      before { sign_in headquarters_admin }

      it "成功レスポンスを返す" do
        get :new
        expect(response).to be_successful
      end

      it "新しいInterStoreTransferインスタンスを作成する" do
        get :new
        expect(assigns(:transfer)).to be_a_new(InterStoreTransfer)
        expect(assigns(:stores)).to be_present
        expect(assigns(:inventories)).to be_present
      end

      it "URLパラメータから初期値を設定する" do
        get :new, params: { 
          source_store_id: source_store.id,
          inventory_id: inventory.id 
        }
        
        transfer = assigns(:transfer)
        expect(transfer.source_store_id).to eq(source_store.id)
        expect(transfer.inventory_id).to eq(inventory.id)
        expect(transfer.requested_by).to eq(headquarters_admin)
        expect(transfer.priority).to eq("normal")
      end
    end

    describe "POST #create" do
      before { sign_in headquarters_admin }

      context "有効なパラメータの場合" do
        it "新しい移動申請を作成する" do
          expect {
            post :create, params: { inter_store_transfer: valid_attributes }
          }.to change(InterStoreTransfer, :count).by(1)
        end

        it "作成した移動申請にリダイレクトする" do
          post :create, params: { inter_store_transfer: valid_attributes }
          transfer = InterStoreTransfer.last
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:notice]).to include("正常に作成されました")
        end

        it "申請者と申請日時を設定する" do
          post :create, params: { inter_store_transfer: valid_attributes }
          transfer = InterStoreTransfer.last
          expect(transfer.requested_by).to eq(headquarters_admin)
          expect(transfer.requested_at).to be_present
        end
      end

      context "無効なパラメータの場合" do
        it "移動申請を作成しない" do
          expect {
            post :create, params: { inter_store_transfer: invalid_attributes }
          }.not_to change(InterStoreTransfer, :count)
        end

        it "newテンプレートを再表示する" do
          post :create, params: { inter_store_transfer: invalid_attributes }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:new)
          expect(assigns(:stores)).to be_present
          expect(assigns(:inventories)).to be_present
        end
      end
    end

    describe "GET #edit" do
      let(:transfer) { create(:inter_store_transfer,
                             source_store: source_store,
                             destination_store: destination_store,
                             inventory: inventory,
                             requested_by: headquarters_admin,
                             status: :pending) }

      before { sign_in headquarters_admin }

      it "成功レスポンスを返す" do
        get :edit, params: { id: transfer.id }
        expect(response).to be_successful
      end

      it "編集用データを設定する" do
        get :edit, params: { id: transfer.id }
        expect(assigns(:transfer)).to eq(transfer)
        expect(assigns(:stores)).to be_present
        expect(assigns(:inventories)).to be_present
      end
    end

    describe "PATCH #update" do
      let(:transfer) { create(:inter_store_transfer,
                             source_store: source_store,
                             destination_store: destination_store,
                             inventory: inventory,
                             requested_by: headquarters_admin,
                             status: :pending) }
      let(:new_attributes) { { quantity: 20, reason: "更新された理由" } }

      before { sign_in headquarters_admin }

      context "有効なパラメータの場合" do
        it "移動申請を更新する" do
          patch :update, params: { 
            id: transfer.id, 
            inter_store_transfer: new_attributes 
          }
          transfer.reload
          expect(transfer.quantity).to eq(20)
          expect(transfer.reason).to eq("更新された理由")
        end

        it "更新した移動申請にリダイレクトする" do
          patch :update, params: { 
            id: transfer.id, 
            inter_store_transfer: new_attributes 
          }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:notice]).to include("正常に更新されました")
        end
      end

      context "無効なパラメータの場合" do
        it "移動申請を更新しない" do
          original_quantity = transfer.quantity
          patch :update, params: { 
            id: transfer.id, 
            inter_store_transfer: invalid_attributes 
          }
          transfer.reload
          expect(transfer.quantity).to eq(original_quantity)
        end

        it "editテンプレートを再表示する" do
          patch :update, params: { 
            id: transfer.id, 
            inter_store_transfer: invalid_attributes 
          }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:edit)
        end
      end
    end

    describe "DELETE #destroy" do
      let!(:transfer) { create(:inter_store_transfer,
                              source_store: source_store,
                              destination_store: destination_store,
                              inventory: inventory,
                              requested_by: headquarters_admin,
                              status: :pending) }

      before { sign_in headquarters_admin }

      context "キャンセル可能な移動申請の場合" do
        it "移動申請を削除する" do
          expect {
            delete :destroy, params: { id: transfer.id }
          }.to change(InterStoreTransfer, :count).by(-1)
        end

        it "移動申請一覧にリダイレクトする" do
          delete :destroy, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfers_path)
          expect(flash[:notice]).to include("正常に削除されました")
        end
      end

      context "削除できない移動申請の場合" do
        before do
          transfer.update!(status: :completed)
        end

        it "移動申請を削除しない" do
          expect {
            delete :destroy, params: { id: transfer.id }
          }.not_to change(InterStoreTransfer, :count)
        end

        it "エラーメッセージと共にリダイレクトする" do
          delete :destroy, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:alert]).to include("削除できません")
        end
      end
    end
  end

  # ============================================
  # ワークフローアクションテスト
  # ============================================

  describe "workflow actions" do
    let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }
    let(:store_admin) { create(:admin, role: :store_admin, store: destination_store) }
    let(:transfer) { create(:inter_store_transfer,
                           source_store: source_store,
                           destination_store: destination_store,
                           inventory: inventory,
                           requested_by: headquarters_admin,
                           status: :pending) }

    before do
      # 十分な在庫を確保
      create(:store_inventory, 
             store: source_store, 
             inventory: inventory, 
             quantity: 100, 
             safety_stock_level: 20)
    end

    describe "PATCH #approve" do
      before { sign_in headquarters_admin }

      context "承認可能な移動申請の場合" do
        it "移動申請を承認する" do
          patch :approve, params: { id: transfer.id }
          transfer.reload
          expect(transfer.approved?).to be true
          expect(transfer.approved_by).to eq(headquarters_admin)
          expect(transfer.approved_at).to be_present
        end

        it "成功メッセージと共にリダイレクトする" do
          patch :approve, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:notice]).to include("承認しました")
        end
      end

      context "承認できない移動申請の場合" do
        before do
          # 在庫を不足させる
          source_store.store_inventories.first.update!(quantity: 1)
        end

        it "承認に失敗する" do
          patch :approve, params: { id: transfer.id }
          transfer.reload
          expect(transfer.pending?).to be true
        end

        it "エラーメッセージと共にリダイレクトする" do
          patch :approve, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:alert]).to include("承認に失敗しました")
        end
      end
    end

    describe "PATCH #reject" do
      before { sign_in headquarters_admin }

      context "却下理由がある場合" do
        it "移動申請を却下する" do
          patch :reject, params: { 
            id: transfer.id, 
            rejection_reason: "在庫過多のため不要" 
          }
          transfer.reload
          expect(transfer.rejected?).to be true
          expect(transfer.approved_by).to eq(headquarters_admin)
          expect(transfer.reason).to include("却下理由")
        end

        it "成功メッセージと共にリダイレクトする" do
          patch :reject, params: { 
            id: transfer.id, 
            rejection_reason: "在庫過多のため不要" 
          }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:notice]).to include("却下しました")
        end
      end

      context "却下理由がない場合" do
        it "却下せずエラーメッセージを表示する" do
          patch :reject, params: { id: transfer.id }
          transfer.reload
          expect(transfer.pending?).to be true
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:alert]).to include("却下理由を入力してください")
        end
      end
    end

    describe "PATCH #complete" do
      before do
        sign_in headquarters_admin
        transfer.update!(status: :approved, approved_by: headquarters_admin)
      end

      context "実行可能な移動申請の場合" do
        it "移動を実行する" do
          patch :complete, params: { id: transfer.id }
          transfer.reload
          expect(transfer.completed?).to be true
          expect(transfer.completed_at).to be_present
        end

        it "在庫を移動する" do
          source_inventory = source_store.store_inventories.first
          initial_source_qty = source_inventory.quantity
          initial_reserved_qty = source_inventory.reserved_quantity

          patch :complete, params: { id: transfer.id }

          source_inventory.reload
          expect(source_inventory.quantity).to eq(initial_source_qty - transfer.quantity)
          expect(source_inventory.reserved_quantity).to eq(initial_reserved_qty - transfer.quantity)

          # 移動先在庫の確認
          dest_inventory = destination_store.store_inventories.find_by(inventory: inventory)
          expect(dest_inventory).to be_present
          expect(dest_inventory.quantity).to eq(transfer.quantity)
        end

        it "成功メッセージと共にリダイレクトする" do
          patch :complete, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:notice]).to include("正常に完了しました")
        end
      end
    end

    describe "PATCH #cancel" do
      before { sign_in headquarters_admin }

      context "キャンセル可能な移動申請の場合" do
        it "移動申請をキャンセルする" do
          patch :cancel, params: { 
            id: transfer.id, 
            cancellation_reason: "緊急事態のため" 
          }
          transfer.reload
          expect(transfer.cancelled?).to be true
        end

        it "成功メッセージと共にリダイレクトする" do
          patch :cancel, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:notice]).to include("キャンセルしました")
        end
      end

      context "キャンセルできない移動申請の場合" do
        before do
          transfer.update!(status: :completed)
        end

        it "キャンセルに失敗する" do
          patch :cancel, params: { id: transfer.id }
          transfer.reload
          expect(transfer.completed?).to be true
        end

        it "エラーメッセージと共にリダイレクトする" do
          patch :cancel, params: { id: transfer.id }
          expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
          expect(flash[:alert]).to include("キャンセルに失敗しました")
        end
      end
    end
  end

  # ============================================
  # 特別なアクションテスト
  # ============================================

  describe "special actions" do
    let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }

    before { sign_in headquarters_admin }

    describe "GET #pending" do
      before do
        create_list(:inter_store_transfer, 3,
                   source_store: source_store,
                   destination_store: destination_store,
                   inventory: inventory,
                   status: :pending)
        create_list(:inter_store_transfer, 2,
                   source_store: source_store,
                   destination_store: destination_store,
                   inventory: inventory,
                   status: :completed)
      end

      it "成功レスポンスを返す" do
        get :pending
        expect(response).to be_successful
      end

      it "保留中の移動申請のみを取得する" do
        get :pending
        pending_transfers = assigns(:pending_transfers)
        expect(pending_transfers.count).to eq(3)
        expect(pending_transfers.all?(&:pending?)).to be true
      end

      it "保留統計を計算する" do
        get :pending
        stats = assigns(:pending_stats)
        expect(stats).to include(:total_pending, :urgent_count, :emergency_count, :avg_waiting_time)
        expect(stats[:total_pending]).to be > 0
      end
    end
  end

  # ============================================
  # 権限テスト
  # ============================================

  describe "authorization" do
    let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }
    let(:store_admin) { create(:admin, role: :store_admin, store: source_store) }
    let(:other_store_admin) { create(:admin, role: :store_admin, store: destination_store) }
    let(:transfer) { create(:inter_store_transfer,
                           source_store: source_store,
                           destination_store: destination_store,
                           inventory: inventory,
                           requested_by: store_admin) }

    context "本部管理者" do
      before { sign_in headquarters_admin }

      it "全てのアクションにアクセスできる" do
        get :index
        expect(response).to be_successful

        get :show, params: { id: transfer.id }
        expect(response).to be_successful

        get :analytics
        expect(response).to be_successful
      end

      it "全ての移動申請を承認・却下できる" do
        patch :approve, params: { id: transfer.id }
        expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
      end
    end

    context "店舗管理者" do
      before { sign_in store_admin }

      it "自店舗関連の移動申請にアクセスできる" do
        get :show, params: { id: transfer.id }
        expect(response).to be_successful
      end

      it "自分が申請した移動申請を編集できる" do
        get :edit, params: { id: transfer.id }
        expect(response).to be_successful
      end

      it "移動先店舗の管理者は承認できる" do
        sign_in other_store_admin
        patch :approve, params: { id: transfer.id }
        expect(response).to redirect_to(admin_inter_store_transfer_path(transfer))
      end
    end

    context "認証なしアクセス" do
      before { sign_out :admin }

      it "ログインページにリダイレクトされる" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)

        get :analytics
        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }

    before { sign_in headquarters_admin }

    describe "N+1 query prevention" do
      it "index画面でN+1クエリを防ぐ" do
        create_list(:inter_store_transfer, 10,
                   source_store: source_store,
                   destination_store: destination_store,
                   inventory: inventory)

        expect {
          get :index
        }.not_to exceed_query_limit(15)
      end

      it "analytics画面でN+1クエリを防ぐ" do
        create_list(:store, 5)
        create_list(:inter_store_transfer, 20,
                   source_store: source_store,
                   destination_store: destination_store,
                   inventory: inventory)

        expect {
          get :analytics
        }.not_to exceed_query_limit(25)
      end
    end

    describe "large data handling" do
      it "大量データでのパフォーマンス" do
        create_list(:inter_store_transfer, 100,
                   source_store: source_store,
                   destination_store: destination_store,
                   inventory: inventory)

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
    let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }

    before { sign_in headquarters_admin }

    context "XSS防止" do
      let(:xss_attributes) do
        {
          source_store_id: source_store.id,
          destination_store_id: destination_store.id,
          inventory_id: inventory.id,
          quantity: 10,
          reason: "<script>alert('XSS')</script>悪意のある理由",
          notes: "<img src=x onerror=alert('XSS')>メモ"
        }
      end

      it "理由フィールドのXSSスクリプトはエスケープされる" do
        post :create, params: { inter_store_transfer: xss_attributes }
        transfer = InterStoreTransfer.last
        expect(transfer.reason).not_to include("<script>")
        expect(transfer.reason).to include("悪意のある理由")
      end
    end

    context "Mass Assignment防止" do
      it "許可されていないパラメータは無視される" do
        malicious_params = {
          source_store_id: source_store.id,
          destination_store_id: destination_store.id,
          inventory_id: inventory.id,
          quantity: 10,
          reason: "正当な理由",
          status: "completed", # 不正なパラメータ
          approved_by_id: 999, # 不正なパラメータ
          created_at: 1.year.ago # 不正なパラメータ
        }

        post :create, params: { inter_store_transfer: malicious_params }
        transfer = InterStoreTransfer.last

        expect(transfer.reason).to eq("正当な理由")
        expect(transfer.pending?).to be true # statusは変更されない
        expect(transfer.created_at).to be > 1.hour.ago
      end
    end

    context "SQL Injection防止" do
      it "検索パラメータでのSQL Injection防止" do
        malicious_search = "'; DROP TABLE inter_store_transfers; --"
        create(:inter_store_transfer,
               source_store: source_store,
               destination_store: destination_store,
               inventory: inventory)

        expect {
          get :index, params: { search: malicious_search }
        }.not_to raise_error

        expect(InterStoreTransfer.count).to be > 0
      end
    end
  end
end
