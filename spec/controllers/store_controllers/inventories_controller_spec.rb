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

  # ============================================
  # GET #index の詳細テスト
  # ============================================

  describe "GET #index" do
    context "認証なしアクセス（公開アクセス）" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)
      end

      it "公開アクセスが許可される" do
        get :index
        expect(response).to be_successful
      end

      it "基本情報のみ表示される" do
        get :index
        expect(assigns(:authenticated_access)).to be false
        expect(assigns(:store_inventories)).to be_present
      end

      it "全店舗のアクティブ在庫が表示される" do
        other_store_inventory = create(:store_inventory, store: other_store, inventory: inventory1, quantity: 50)

        get :index
        store_inventories = assigns(:store_inventories)

        store_ids = store_inventories.map(&:store_id).uniq
        expect(store_ids).to include(store.id, other_store.id)
      end

      it "非アクティブ店舗の在庫は表示されない" do
        inactive_store = create(:store, active: false)
        create(:store_inventory, store: inactive_store, inventory: inventory1, quantity: 50)

        get :index
        store_inventories = assigns(:store_inventories)

        store_ids = store_inventories.map(&:store_id)
        expect(store_ids).not_to include(inactive_store.id)
      end

      it "統計情報は読み込まれない" do
        get :index
        expect(assigns(:statistics)).to be_nil
      end

      it "フィルタリング用データが読み込まれる" do
        get :index
        expect(assigns(:categories)).to be_present
        expect(assigns(:manufacturers)).to be_present
        expect(assigns(:stock_levels)).to be_present
      end

      it "適切な関連データが事前読み込みされる" do
        get :index
        store_inventories = assigns(:store_inventories)

        if store_inventories.any?
          expect(store_inventories.first.association(:inventory)).to be_loaded
          expect(store_inventories.first.association(:store)).to be_loaded
        end
      end
    end

    context "認証済みアクセス（店舗ユーザー）" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "認証済みアクセスが成功する" do
        get :index
        expect(response).to be_successful
      end

      it "店舗スコープでの詳細情報が表示される" do
        get :index
        expect(assigns(:authenticated_access)).to be true
        expect(assigns(:store_inventories)).to be_present
      end

      it "現在の店舗の在庫のみが表示される" do
        other_store_inventory = create(:store_inventory, store: other_store, inventory: inventory1, quantity: 50)

        get :index
        store_inventories = assigns(:store_inventories)

        expect(store_inventories.all? { |si| si.store_id == store.id }).to be true
        expect(store_inventories.map(&:store_id)).not_to include(other_store.id)
      end

      it "統計情報が読み込まれる" do
        get :index
        statistics = assigns(:statistics)

        expect(statistics).to be_present
        expect(statistics).to have_key(:total_items)
        expect(statistics).to have_key(:total_quantity)
        expect(statistics).to have_key(:total_value)
        expect(statistics).to have_key(:low_stock_percentage)
      end

      it "正確な統計値を計算する" do
        get :index
        statistics = assigns(:statistics)

        expect(statistics[:total_items]).to eq(3)
        expect(statistics[:total_quantity]).to eq(105) # 100 + 5 + 0
        expect(statistics[:total_value]).to eq(125000) # (100*500) + (5*15000) + (0*200)
        expect(statistics[:low_stock_percentage]).to eq(66.7) # 2/3 * 100
      end

      it "適切な関連データが事前読み込みされる" do
        get :index
        store_inventories = assigns(:store_inventories)

        if store_inventories.any?
          expect(store_inventories.first.association(:inventory)).to be_loaded
        end
      end
    end

    context "CSV出力機能" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "CSV形式でレスポンスを返す" do
        get :index, format: :csv

        expect(response).to be_successful
        expect(response.content_type).to include("text/csv")
      end

      it "適切なContent-Dispositionヘッダーが設定される" do
        get :index, format: :csv

        content_disposition = response.headers["Content-Disposition"]
        expect(content_disposition).to include("attachment")
        expect(content_disposition).to include("在庫一覧")
      end

      it "BOM付きUTF-8でCSV内容を出力する" do
        get :index, format: :csv

        expect(response.body).to start_with("\uFEFF")
      end

      it "CSV内容に期待されるヘッダーが含まれる" do
        get :index, format: :csv

        csv_lines = response.body.split("\n")
        headers = csv_lines[0]
        expect(headers).to include("商品名", "商品コード", "カテゴリ", "現在在庫数", "安全在庫レベル")
      end

      it "CSV内容に在庫データが含まれる" do
        get :index, format: :csv

        expect(response.body).to include(inventory1.name)
        expect(response.body).to include(inventory2.name)
        expect(response.body).to include(inventory3.name)
      end

      it "認証なしアクセスでCSV出力が拒否される" do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)

        get :index, format: :csv

        expect(response).to redirect_to(stores_path)
        expect(flash[:alert]).to include("アクセス権限がありません")
      end
    end

    context "検索・フィルタリング機能" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "商品名による検索フィルター" do
        get :index, params: { q: { name_cont: "アスピリン" } }

        store_inventories = assigns(:store_inventories)
        names = store_inventories.map { |si| si.inventory.name }
        expect(names).to include("アスピリン錠100mg")
        expect(names).not_to include("デジタル血圧計")
      end

      it "カテゴリによる検索フィルター" do
        get :index, params: { q: { category_eq: "医薬品" } }

        store_inventories = assigns(:store_inventories)
        names = store_inventories.map { |si| si.inventory.name }
        expect(names).to include("アスピリン錠100mg")
      end

      it "在庫レベルによる検索フィルター（在庫切れ）" do
        get :index, params: { q: { stock_level_eq: "out_of_stock" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity == 0 }).to be true
      end

      it "在庫レベルによる検索フィルター（低在庫）" do
        get :index, params: { q: { stock_level_eq: "low_stock" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity > 0 && si.quantity <= si.safety_stock_level }).to be true
      end

      it "在庫レベルによる検索フィルター（適正在庫）" do
        get :index, params: { q: { stock_level_eq: "normal_stock" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity > si.safety_stock_level && si.quantity <= si.safety_stock_level * 2 }).to be true
      end

      it "在庫レベルによる検索フィルター（過剰在庫）" do
        create(:store_inventory, store: store, inventory: create(:inventory), quantity: 200, safety_stock_level: 50)

        get :index, params: { q: { stock_level_eq: "excess_stock" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity > si.safety_stock_level * 2 }).to be true
      end

      it "メーカーによる検索フィルター" do
        get :index, params: { q: { manufacturer_eq: "薬品メーカーA" } }

        store_inventories = assigns(:store_inventories)
        manufacturers = store_inventories.map { |si| si.inventory.manufacturer }
        expect(manufacturers).to all(eq("薬品メーカーA"))
      end

      it "在庫数範囲による検索フィルター（最小値）" do
        get :index, params: { q: { quantity_gteq: "50" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity >= 50 }).to be true
      end

      it "在庫数範囲による検索フィルター（最大値）" do
        get :index, params: { q: { quantity_lteq: "10" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity <= 10 }).to be true
      end

      it "在庫数範囲による検索フィルター（範囲指定）" do
        get :index, params: { q: { quantity_gteq: "5", quantity_lteq: "100" } }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.all? { |si| si.quantity.between?(5, 100) }).to be true
      end

      it "複数フィルターの組み合わせ" do
        get :index, params: {
          q: {
            name_cont: "アスピリン",
            stock_level_eq: "normal_stock",
            manufacturer_eq: "薬品メーカーA"
          }
        }

        expect(response).to be_successful
        expect(assigns(:store_inventories)).to be_present
      end
    end

    context "ソート機能" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "商品名で昇順ソート" do
        get :index, params: { sort: "inventories.name", direction: "asc" }

        store_inventories = assigns(:store_inventories)
        names = store_inventories.map { |si| si.inventory.name }
        expect(names).to eq(names.sort)
      end

      it "商品名で降順ソート" do
        get :index, params: { sort: "inventories.name", direction: "desc" }

        store_inventories = assigns(:store_inventories)
        names = store_inventories.map { |si| si.inventory.name }
        expect(names).to eq(names.sort.reverse)
      end

      it "在庫数で昇順ソート" do
        get :index, params: { sort: "store_inventories.quantity", direction: "asc" }

        store_inventories = assigns(:store_inventories)
        quantities = store_inventories.map(&:quantity)
        expect(quantities).to eq(quantities.sort)
      end

      it "デフォルトソートが適用される" do
        get :index

        expect(controller.send(:sort_column)).to eq("inventories.name")
        expect(controller.send(:sort_direction)).to eq("asc")
      end

      it "無効なソートカラムでデフォルトが使用される" do
        get :index, params: { sort: "invalid_column" }

        expect(controller.send(:sort_column)).to eq("inventories.name")
      end

      it "無効なソート方向でデフォルトが使用される" do
        get :index, params: { direction: "invalid_direction" }

        expect(controller.send(:sort_direction)).to eq("asc")
      end
    end

    context "ページネーション機能" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user

        # 大量データ作成
        create_list(:store_inventory, 25, store: store)
      end

      it "ページネーションが適用される" do
        get :index, params: { page: 1 }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.size).to be <= StoreControllers::InventoriesController::PER_PAGE
        expect(store_inventories).to respond_to(:current_page)
      end

      it "2ページ目が正しく表示される" do
        get :index, params: { page: 2 }

        store_inventories = assigns(:store_inventories)
        expect(store_inventories.current_page).to eq(2)
      end
    end
  end

  # ============================================
  # GET #show の詳細テスト
  # ============================================

  describe "GET #show" do
    before do
      allow(controller).to receive(:store_user_signed_in?).and_return(true)
      allow(controller).to receive(:current_store).and_return(store)
      sign_in store_user, scope: :store_user
    end

    context "基本機能" do
      it "成功レスポンスを返す" do
        get :show, params: { id: inventory1.id }

        expect(response).to be_successful
      end

      it "在庫詳細情報が正しく取得される" do
        get :show, params: { id: inventory1.id }

        expect(assigns(:inventory)).to eq(inventory1)
        expect(assigns(:store_inventory)).to eq(store_inventory1)
      end

      it "在庫詳細に関連データが事前読み込みされる" do
        get :show, params: { id: inventory1.id }

        store_inventory = assigns(:store_inventory)
        expect(store_inventory.association(:inventory)).to be_loaded
      end
    end

    context "バッチ情報表示" do
      before do
        @batch1 = create(:batch, inventory: inventory1, expires_on: 30.days.from_now, lot_code: "LOT001")
        @batch2 = create(:batch, inventory: inventory1, expires_on: 60.days.from_now, lot_code: "LOT002")
      end

      it "バッチ情報が有効期限順で取得される" do
        get :show, params: { id: inventory1.id }

        batches = assigns(:batches)
        expect(batches.count).to eq(2)
        expect(batches.first.expires_on).to be <= batches.second.expires_on
      end

      it "バッチ情報がページネーション付きで取得される" do
        get :show, params: { id: inventory1.id, batch_page: 1 }

        batches = assigns(:batches)
        expect(batches).to respond_to(:current_page)
      end
    end

    context "在庫履歴表示" do
      before do
        @log1 = create(:inventory_log, inventory: inventory1, admin: admin, created_at: 1.hour.ago)
        @log2 = create(:inventory_log, inventory: inventory1, admin: admin, created_at: 2.hours.ago)
      end

      it "在庫履歴が時系列順で取得される" do
        get :show, params: { id: inventory1.id }

        inventory_logs = assigns(:inventory_logs)
        expect(inventory_logs.count).to eq(2)
        if inventory_logs.count >= 2
          expect(inventory_logs.first.created_at).to be >= inventory_logs.second.created_at
        end
      end

      it "在庫履歴に関連データが事前読み込みされる" do
        get :show, params: { id: inventory1.id }

        inventory_logs = assigns(:inventory_logs)
        if inventory_logs.any?
          expect(inventory_logs.first.association(:admin)).to be_loaded
        end
      end

      it "在庫履歴が20件制限で取得される" do
        create_list(:inventory_log, 25, inventory: inventory1, admin: admin)

        get :show, params: { id: inventory1.id }

        inventory_logs = assigns(:inventory_logs)
        expect(inventory_logs.count).to eq(20)
      end
    end

    context "移動履歴表示" do
      before do
        @transfer1 = create(:inter_store_transfer, inventory: inventory1, source_store: store,
                           destination_store: other_store, created_at: 1.day.ago)
        @transfer2 = create(:inter_store_transfer, inventory: inventory1, source_store: other_store,
                           destination_store: store, created_at: 2.days.ago)
      end

      it "移動履歴が時系列順で取得される" do
        get :show, params: { id: inventory1.id }

        transfer_history = assigns(:transfer_history)
        expect(transfer_history.count).to eq(2)
        if transfer_history.count >= 2
          expect(transfer_history.first.created_at).to be >= transfer_history.second.created_at
        end
      end

      it "移動履歴に関連データが事前読み込みされる" do
        get :show, params: { id: inventory1.id }

        transfer_history = assigns(:transfer_history)
        if transfer_history.any?
          expect(transfer_history.first.association(:source_store)).to be_loaded
          expect(transfer_history.first.association(:destination_store)).to be_loaded
        end
      end

      it "移動履歴が10件制限で取得される" do
        create_list(:inter_store_transfer, 15, inventory: inventory1, source_store: store)

        get :show, params: { id: inventory1.id }

        transfer_history = assigns(:transfer_history)
        expect(transfer_history.count).to eq(10)
      end
    end

    context "存在しない在庫へのアクセス" do
      it "RecordNotFoundエラーが発生する" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # GET #adjust_form の詳細テスト
  # ============================================

  describe "GET #adjust_form" do
    context "認証済みユーザー" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "成功レスポンスを返す" do
        get :adjust_form, params: { id: inventory1.id }

        expect(response).to be_successful
      end

      it "在庫調整フォーム用データが取得される" do
        get :adjust_form, params: { id: inventory1.id }

        expect(assigns(:inventory)).to eq(inventory1)
        expect(assigns(:store_inventory)).to eq(store_inventory1)
      end

      it "調整履歴が取得される" do
        create_list(:inventory_log, 5, inventory: inventory1, operation_type: "adjustment", admin: admin)
        create(:inventory_log, inventory: inventory1, operation_type: "receipt", admin: admin) # 調整以外

        get :adjust_form, params: { id: inventory1.id }

        adjustment_history = assigns(:adjustment_history)
        expect(adjustment_history.count).to eq(5)
        expect(adjustment_history.all? { |log| log.operation_type == "adjustment" }).to be true
      end

      it "調整履歴に関連データが事前読み込みされる" do
        create(:inventory_log, inventory: inventory1, operation_type: "adjustment", admin: admin)

        get :adjust_form, params: { id: inventory1.id }

        adjustment_history = assigns(:adjustment_history)
        if adjustment_history.any?
          expect(adjustment_history.first.association(:admin)).to be_loaded
        end
      end

      it "調整履歴が10件制限で取得される" do
        create_list(:inventory_log, 15, inventory: inventory1, operation_type: "adjustment", admin: admin)

        get :adjust_form, params: { id: inventory1.id }

        adjustment_history = assigns(:adjustment_history)
        expect(adjustment_history.count).to eq(10)
      end
    end

    context "認証なしアクセス" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)
      end

      it "認証が必要でリダイレクトされる" do
        get :adjust_form, params: { id: inventory1.id }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("ログインが必要です")
      end
    end
  end

  # ============================================
  # POST #adjust の詳細テスト
  # ============================================

  describe "POST #adjust" do
    context "認証済みユーザー" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      context "有効なパラメータ" do
        it "在庫調整が成功する" do
          expect {
            post :adjust, params: {
              id: inventory1.id,
              adjustment: {
                new_quantity: 120,
                reason: "棚卸し調整",
                notes: "実地棚卸しの結果"
              }
            }
          }.to change { store_inventory1.reload.quantity }.from(100).to(120)
        end

        it "在庫ログが作成される" do
          expect {
            post :adjust, params: {
              id: inventory1.id,
              adjustment: {
                new_quantity: 120,
                reason: "棚卸し調整",
                notes: "実地棚卸しの結果"
              }
            }
          }.to change { InventoryLog.count }.by(1)

          log = InventoryLog.last
          expect(log.inventory).to eq(inventory1)
          expect(log.operation_type).to eq("adjustment")
          expect(log.quantity_change).to eq(20)
          expect(log.reason).to eq("棚卸し調整")
          expect(log.notes).to include("店舗調整: 実地棚卸しの結果")
        end

        it "成功メッセージとリダイレクト" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 120,
              reason: "棚卸し調整",
              notes: "実地棚卸しの結果"
            }
          }

          expect(response).to redirect_to(store_inventory_path(inventory1))
          expect(flash[:success]).to include("在庫調整が完了しました")
          expect(flash[:success]).to include("100 → 120個")
        end

        it "数量減少の調整も正常に処理される" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 80,
              reason: "損傷品除去",
              notes: "破損した商品を除去"
            }
          }

          expect(store_inventory1.reload.quantity).to eq(80)

          log = InventoryLog.last
          expect(log.quantity_change).to eq(-20)
        end

        it "ゼロへの調整も正常に処理される" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 0,
              reason: "全量廃棄",
              notes: "期限切れによる全量廃棄"
            }
          }

          expect(store_inventory1.reload.quantity).to eq(0)
        end
      end

      context "無効なパラメータ" do
        it "新数量が未指定の場合エラー" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              reason: "棚卸し調整",
              notes: "実地棚卸しの結果"
            }
          }

          expect(response).to redirect_to(adjust_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("有効な在庫数を入力してください")
          expect(store_inventory1.reload.quantity).to eq(100) # 変更されない
        end

        it "新数量が負の値の場合エラー" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: -10,
              reason: "棚卸し調整",
              notes: "実地棚卸しの結果"
            }
          }

          expect(response).to redirect_to(adjust_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("有効な在庫数を入力してください")
        end

        it "調整理由が未入力の場合エラー" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 120,
              reason: "",
              notes: "実地棚卸しの結果"
            }
          }

          expect(response).to redirect_to(adjust_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("調整理由を入力してください")
        end

        it "調整理由が空白のみの場合エラー" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 120,
              reason: "   ",
              notes: "実地棚卸しの結果"
            }
          }

          expect(response).to redirect_to(adjust_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("調整理由を入力してください")
        end
      end

      context "データベースエラー" do
        before do
          allow_any_instance_of(StoreInventory).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(store_inventory1))
        end

        it "レコード無効エラーを適切に処理する" do
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 120,
              reason: "棚卸し調整",
              notes: "実地棚卸しの結果"
            }
          }

          expect(response).to redirect_to(adjust_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("在庫調整に失敗しました")
        end
      end
    end

    context "認証なしアクセス" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)
      end

      it "認証が必要でリダイレクトされる" do
        post :adjust, params: {
          id: inventory1.id,
          adjustment: {
            new_quantity: 120,
            reason: "不正調整",
            notes: "認証なし"
          }
        }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("ログインが必要です")
        expect(store_inventory1.reload.quantity).to eq(100) # 変更されない
      end
    end
  end

  # ============================================
  # GET #request_transfer_form の詳細テスト
  # ============================================

  describe "GET #request_transfer_form" do
    context "認証済みユーザー" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "成功レスポンスを返す" do
        get :request_transfer_form, params: { id: inventory1.id }

        expect(response).to be_successful
      end

      it "移動申請フォーム用データが取得される" do
        get :request_transfer_form, params: { id: inventory1.id }

        expect(assigns(:inventory)).to eq(inventory1)
        expect(assigns(:store_inventory)).to eq(store_inventory1)
      end

      it "移動先候補店舗が取得される" do
        active_store1 = create(:store, active: true, name: "アクティブ店舗1")
        active_store2 = create(:store, active: true, name: "アクティブ店舗2")
        inactive_store = create(:store, active: false, name: "非アクティブ店舗")

        get :request_transfer_form, params: { id: inventory1.id }

        other_stores = assigns(:other_stores)
        store_ids = other_stores.pluck(:id)

        expect(store_ids).to include(active_store1.id, active_store2.id)
        expect(store_ids).not_to include(store.id) # 現在店舗は除外
        expect(store_ids).not_to include(inactive_store.id) # 非アクティブは除外
      end

      it "移動先候補店舗が名前順でソートされる" do
        create(:store, active: true, name: "Z店舗")
        create(:store, active: true, name: "A店舗")

        get :request_transfer_form, params: { id: inventory1.id }

        other_stores = assigns(:other_stores)
        store_names = other_stores.pluck(:name)
        expect(store_names).to eq(store_names.sort)
      end

      it "移動履歴が取得される" do
        transfer1 = create(:inter_store_transfer, inventory: inventory1, source_store: store,
                          destination_store: other_store, created_at: 1.day.ago)
        transfer2 = create(:inter_store_transfer, inventory: inventory1, source_store: other_store,
                          destination_store: store, created_at: 2.days.ago)
        other_inventory_transfer = create(:inter_store_transfer, source_store: store) # 他の商品

        get :request_transfer_form, params: { id: inventory1.id }

        transfer_history = assigns(:transfer_history)
        expect(transfer_history.count).to eq(2)
        transfer_ids = transfer_history.pluck(:id)
        expect(transfer_ids).to include(transfer1.id, transfer2.id)
        expect(transfer_ids).not_to include(other_inventory_transfer.id)
      end

      it "移動履歴が5件制限で取得される" do
        create_list(:inter_store_transfer, 7, inventory: inventory1, source_store: store)

        get :request_transfer_form, params: { id: inventory1.id }

        transfer_history = assigns(:transfer_history)
        expect(transfer_history.count).to eq(5)
      end

      it "移動履歴に関連データが事前読み込みされる" do
        create(:inter_store_transfer, inventory: inventory1, source_store: store, destination_store: other_store)

        get :request_transfer_form, params: { id: inventory1.id }

        transfer_history = assigns(:transfer_history)
        if transfer_history.any?
          expect(transfer_history.first.association(:source_store)).to be_loaded
          expect(transfer_history.first.association(:destination_store)).to be_loaded
        end
      end
    end

    context "認証なしアクセス" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)
      end

      it "認証が必要でリダイレクトされる" do
        get :request_transfer_form, params: { id: inventory1.id }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("ログインが必要です")
      end
    end
  end

  # ============================================
  # POST #request_transfer の詳細テスト
  # ============================================

  describe "POST #request_transfer" do
    context "認証済みユーザー" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        allow(controller).to receive(:current_store_user).and_return(store_user)
        sign_in store_user, scope: :store_user
      end

      context "有効なパラメータ" do
        it "移動申請が成功する" do
          expect {
            post :request_transfer, params: {
              id: inventory1.id,
              transfer: {
                destination_store_id: other_store.id,
                quantity: 20,
                reason: "他店舗の在庫不足",
                notes: "緊急補充"
              }
            }
          }.to change { InterStoreTransfer.count }.by(1)

          transfer = InterStoreTransfer.last
          expect(transfer.inventory).to eq(inventory1)
          expect(transfer.source_store).to eq(store)
          expect(transfer.destination_store).to eq(other_store)
          expect(transfer.quantity).to eq(20)
          expect(transfer.status).to eq("pending")
          expect(transfer.reason).to eq("他店舗の在庫不足")
          expect(transfer.notes).to eq("緊急補充")
          expect(transfer.requested_by).to eq(store_user)
        end

        it "成功メッセージとリダイレクト" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: other_store.id,
              quantity: 20,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(store_inventory_path(inventory1))
          expect(flash[:success]).to include("移動申請を送信しました")
          expect(flash[:success]).to include(other_store.name)
          expect(flash[:success]).to include("20個")
        end
      end

      context "無効なパラメータ" do
        it "移動先店舗未選択の場合エラー" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              quantity: 20,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("移動先店舗を選択してください")
          expect(InterStoreTransfer.count).to eq(0)
        end

        it "移動数量未入力の場合エラー" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: other_store.id,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("有効な移動数量を入力してください")
        end

        it "移動数量がゼロ以下の場合エラー" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: other_store.id,
              quantity: 0,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("有効な移動数量を入力してください")
        end

        it "移動数量が現在在庫数を超える場合エラー" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: other_store.id,
              quantity: 150, # 現在在庫100を超える
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("移動数量が現在在庫数を超えています")
        end

        it "移動理由未入力の場合エラー" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: other_store.id,
              quantity: 20,
              reason: "",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("移動理由を入力してください")
        end

        it "存在しない移動先店舗の場合エラー" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: 999999,
              quantity: 20,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("指定された移動先店舗が見つかりません")
        end

        it "非アクティブな移動先店舗の場合エラー" do
          inactive_store = create(:store, active: false)

          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: inactive_store.id,
              quantity: 20,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("指定された移動先店舗が見つかりません")
        end
      end

      context "データベースエラー" do
        before do
          allow(InterStoreTransfer).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(InterStoreTransfer.new))
        end

        it "レコード無効エラーを適切に処理する" do
          post :request_transfer, params: {
            id: inventory1.id,
            transfer: {
              destination_store_id: other_store.id,
              quantity: 20,
              reason: "他店舗の在庫不足",
              notes: "緊急補充"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory1))
          expect(flash[:alert]).to include("移動申請に失敗しました")
        end
      end
    end

    context "認証なしアクセス" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)
      end

      it "認証が必要でリダイレクトされる" do
        post :request_transfer, params: {
          id: inventory1.id,
          transfer: {
            destination_store_id: other_store.id,
            quantity: 20,
            reason: "不正申請",
            notes: "認証なし"
          }
        }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("ログインが必要です")
        expect(InterStoreTransfer.count).to eq(0)
      end
    end
  end

  # ============================================
  # ヘルパーメソッドのテスト
  # ============================================

  describe "helper methods" do
    before do
      allow(controller).to receive(:store_user_signed_in?).and_return(true)
      allow(controller).to receive(:current_store).and_return(store)
      sign_in store_user, scope: :store_user
    end

    describe "#stock_level_badge" do
      it "在庫切れの場合は危険バッジを返す" do
        result = controller.send(:stock_level_badge, store_inventory3) # quantity: 0
        expect(result[:text]).to eq("在庫切れ")
        expect(result[:class]).to eq("badge bg-danger")
      end

      it "低在庫の場合は警告バッジを返す" do
        result = controller.send(:stock_level_badge, store_inventory2) # quantity: 5, safety: 10
        expect(result[:text]).to eq("低在庫")
        expect(result[:class]).to eq("badge bg-warning text-dark")
      end

      it "過剰在庫の場合は情報バッジを返す" do
        excessive_inventory = create(:store_inventory, store: store, quantity: 200, safety_stock_level: 50)
        result = controller.send(:stock_level_badge, excessive_inventory)
        expect(result[:text]).to eq("過剰在庫")
        expect(result[:class]).to eq("badge bg-info")
      end

      it "適正在庫の場合は成功バッジを返す" do
        result = controller.send(:stock_level_badge, store_inventory1) # quantity: 100, safety: 20
        expect(result[:text]).to eq("適正")
        expect(result[:class]).to eq("badge bg-success")
      end
    end

    describe "#turnover_days" do
      it "在庫数がゼロの場合は「---」を返す" do
        result = controller.send(:turnover_days, store_inventory3) # quantity: 0
        expect(result).to eq("---")
      end

      it "在庫数がある場合は日数を計算する" do
        result = controller.send(:turnover_days, store_inventory1) # quantity: 100
        expect(result).to eq(20) # 100 / 5 = 20日
      end
    end

    describe "#batch_status_badge" do
      it "期限切れの場合は危険バッジを返す" do
        expired_batch = build(:batch, expires_on: 1.day.ago)
        result = controller.send(:batch_status_badge, expired_batch)
        expect(result[:text]).to eq("期限切れ")
        expect(result[:class]).to eq("badge bg-danger")
      end

      it "30日以内期限切れの場合は警告バッジを返す" do
        soon_expired_batch = build(:batch, expires_on: 15.days.from_now)
        result = controller.send(:batch_status_badge, soon_expired_batch)
        expect(result[:text]).to eq("15日")
        expect(result[:class]).to eq("badge bg-warning text-dark")
      end

      it "90日以内期限切れの場合は情報バッジを返す" do
        warning_batch = build(:batch, expires_on: 60.days.from_now)
        result = controller.send(:batch_status_badge, warning_batch)
        expect(result[:text]).to eq("60日")
        expect(result[:class]).to eq("badge bg-info")
      end

      it "90日以上期限がある場合は良好バッジを返す" do
        good_batch = build(:batch, expires_on: 180.days.from_now)
        result = controller.send(:batch_status_badge, good_batch)
        expect(result[:text]).to eq("良好")
        expect(result[:class]).to eq("badge bg-success")
      end
    end

    describe "#categorize_by_name" do
      it "医薬品キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "アスピリン錠100mg")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "パラセタモールカプセル")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "ヒルドイド軟膏")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "インスリン注射液")).to eq("医薬品")
      end

      it "医療機器キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "デジタル血圧計")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "体温計セット")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "パルスオキシメーター")).to eq("医療機器")
      end

      it "消耗品キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "マスク50枚入り")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "医療用手袋")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "アルコール消毒液")).to eq("消耗品")
      end

      it "サプリメントキーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "ビタミンCサプリ")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "オメガ3脂肪酸")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "プロバイオティクス")).to eq("サプリメント")
      end

      it "分類不能な商品は「その他」に分類する" do
        expect(controller.send(:categorize_by_name, "未知の商品XYZ")).to eq("その他")
        expect(controller.send(:categorize_by_name, "")).to eq("その他")
      end
    end

    describe "filter data loading" do
      it "フィルタリング用データが正しく読み込まれる" do
        get :index

        expect(assigns(:categories)).to include("医薬品", "医療機器", "消耗品")
        expect(assigns(:manufacturers)).to include("薬品メーカーA", "医療機器メーカーB", "消耗品メーカーC")
        expect(assigns(:stock_levels)).to be_an(Array)
        expect(assigns(:stock_levels).map(&:last)).to include("out_of_stock", "low_stock", "normal_stock", "excess_stock")
      end
    end
  end

  # ============================================
  # パフォーマンス・N+1クエリテスト
  # ============================================

  describe "performance tests" do
    before do
      allow(controller).to receive(:store_user_signed_in?).and_return(true)
      allow(controller).to receive(:current_store).and_return(store)
      sign_in store_user, scope: :store_user
    end

    describe "N+1 query prevention" do
      it "index アクションでのN+1クエリ防止" do
        create_list(:store_inventory, 10, store: store)

        expect {
          get :index
        }.not_to exceed_query_limit(15) # includes使用で制限
      end

      it "show アクションでのN+1クエリ防止" do
        create_list(:batch, 5, inventory: inventory1)
        create_list(:inventory_log, 5, inventory: inventory1, admin: admin)
        create_list(:inter_store_transfer, 5, inventory: inventory1, source_store: store)

        expect {
          get :show, params: { id: inventory1.id }
        }.not_to exceed_query_limit(10) # includes使用で制限
      end

      it "CSV出力でのN+1クエリ防止" do
        create_list(:store_inventory, 20, store: store)

        expect {
          get :index, format: :csv
        }.not_to exceed_query_limit(15) # includes使用で制限
      end
    end

    describe "bulk operations performance" do
      it "大量データでのindex表示パフォーマンス" do
        create_list(:store_inventory, 50, store: store)

        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 1000 # 1秒以内
      end

      it "CSV出力のパフォーマンス" do
        create_list(:store_inventory, 100, store: store)

        start_time = Time.current
        get :index, format: :csv
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 3000 # 3秒以内
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "SQL Injection 防止" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "検索パラメータでのSQL Injection防止" do
        malicious_search = "'; DROP TABLE inventories; --"

        expect {
          get :index, params: { q: { name_cont: malicious_search } }
        }.not_to raise_error

        expect(Inventory.count).to be > 0 # テーブルが削除されていない
      end

      it "ソートパラメータでのSQL Injection防止" do
        malicious_sort = "inventories.name; DROP TABLE stores; --"

        get :index, params: { sort: malicious_sort }

        expect(controller.send(:sort_column)).to eq("inventories.name") # デフォルト値
        expect(Store.count).to be > 0 # テーブルが削除されていない
      end
    end

    context "認証・認可" do
      it "認証なしでの操作系アクションはリダイレクトされる" do
        allow(controller).to receive(:store_user_signed_in?).and_return(false)
        allow(controller).to receive(:current_store).and_return(nil)

        [ :adjust_form, :adjust, :request_transfer_form, :request_transfer ].each do |action|
          case action
          when :adjust, :request_transfer
            post action, params: { id: inventory1.id }
          else
            get action, params: { id: inventory1.id }
          end

          expect(response).to redirect_to(store_selection_path)
          expect(flash[:alert]).to include("ログインが必要です")
        end
      end
    end

    context "Mass Assignment 防止" do
      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(store)
        sign_in store_user, scope: :store_user
      end

      it "在庫調整でのMass Assignment防止" do
        post :adjust, params: {
          id: inventory1.id,
          adjustment: {
            new_quantity: 120,
            reason: "調整",
            notes: "メモ",
            malicious_param: "悪意のあるデータ"
          }
        }

        expect {
          post :adjust, params: {
            id: inventory1.id,
            adjustment: {
              new_quantity: 120,
              reason: "調整",
              notes: "メモ",
              malicious_param: "悪意のあるデータ"
            }
          }
        }.not_to raise_error(ActiveModel::ForbiddenAttributesError)
      end
    end
  end

  # ============================================
  # エラーハンドリングテスト
  # ============================================

  describe "error handling" do
    before do
      allow(controller).to receive(:store_user_signed_in?).and_return(true)
      allow(controller).to receive(:current_store).and_return(store)
      sign_in store_user, scope: :store_user
    end

    context "存在しない在庫ID" do
      it "RecordNotFoundエラーが発生する" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "データベース接続エラー" do
      before do
        allow(StoreInventory).to receive(:joins).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "データベースエラーは適切に伝播される" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "CSVファイル名の文字エンコーディング" do
      it "日本語文字を含むファイル名が適切にエンコードされる" do
        allow(Time).to receive(:current).and_return(Time.parse("2023-01-01 12:00:00"))

        get :index, format: :csv

        content_disposition = response.headers["Content-Disposition"]
        expect(content_disposition).to include("UTF-8")
      end
    end
  end

  # ============================================
  # レスポンス形式テスト
  # ============================================

  describe "response formats" do
    before do
      allow(controller).to receive(:store_user_signed_in?).and_return(true)
      allow(controller).to receive(:current_store).and_return(store)
      sign_in store_user, scope: :store_user
    end

    context "HTML レスポンス" do
      it "HTMLテンプレートが正しくレンダリングされる" do
        get :index

        expect(response).to render_template(:index)
        expect(response.content_type).to include("text/html")
      end
    end

    context "CSV レスポンス" do
      it "CSV形式で正しい内容が返される" do
        get :index, format: :csv

        expect(response.content_type).to include("text/csv")
        csv_lines = response.body.split("\n")
        expect(csv_lines.count).to be >= 2 # ヘッダー + データ行
      end
    end
  end
end
