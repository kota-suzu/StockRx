# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLogsController, type: :controller do
  # CLAUDE.md準拠: 在庫ログ管理機能の包括的テスト
  # メタ認知: 将来的な管理画面への統合を考慮したテスト設計
  # 横展開: AdminControllersへの移行時にテストの再利用が可能

  let(:admin) { create(:admin) }
  let(:inventory) { create(:inventory) }
  let(:other_inventory) { create(:inventory) }

  # テスト用のログデータ作成
  let!(:inventory_log) do
    create(:inventory_log,
           inventory: inventory,
           admin: admin,
           operation_type: "adjustment",
           delta: 10,
           previous_quantity: 100,
           current_quantity: 110,
           note: "在庫調整")
  end

  let!(:other_log) do
    create(:inventory_log,
           inventory: other_inventory,
           admin: admin,
           operation_type: "stock_in",
           delta: 20,
           previous_quantity: 50,
           current_quantity: 70,
           note: "入庫処理")
  end

  before do
    # 認証をシミュレート（現在の実装では認証なし）
    # TODO: AdminControllersへの移行時に認証を追加
  end

  # ============================================
  # 在庫ログ一覧機能のテスト
  # ============================================

  describe "GET #index" do
    context "基本機能" do
      it "成功レスポンスを返す" do
        get :index
        expect(response).to be_successful
      end

      it "ログ一覧を取得する" do
        get :index
        expect(assigns(:logs)).to be_present
      end

      it "ページネーションが適用される" do
        # 21件のログを作成（PER_PAGE = 20）
        create_list(:inventory_log, 21, inventory: inventory, admin: admin)

        get :index
        logs = assigns(:logs)
        expect(logs.count).to eq(20)
        expect(logs).to respond_to(:current_page)
      end

      it "新しい順にソートされる" do
        old_log = create(:inventory_log, inventory: inventory, admin: admin, created_at: 2.days.ago)
        new_log = create(:inventory_log, inventory: inventory, admin: admin, created_at: 1.hour.ago)

        get :index
        logs = assigns(:logs)
        expect(logs.first.created_at).to be > logs.last.created_at
      end

      it "関連データがeager loadingされる" do
        get :index
        logs = assigns(:logs)

        expect(logs.first.association(:inventory)).to be_loaded
        expect(logs.first.association(:user)).to be_loaded
      end
    end

    context "特定在庫のログ表示" do
      it "inventory_idパラメータで特定在庫のログのみ表示" do
        get :index, params: { inventory_id: inventory.id }

        expect(assigns(:inventory)).to eq(inventory)
        logs = assigns(:logs)
        expect(logs.all? { |log| log.inventory_id == inventory.id }).to be true
      end

      it "存在しないinventory_idはRecordNotFoundエラー" do
        expect {
          get :index, params: { inventory_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "日付フィルタリング" do
      before do
        @old_log = create(:inventory_log, inventory: inventory, admin: admin, created_at: 5.days.ago)
        @recent_log = create(:inventory_log, inventory: inventory, admin: admin, created_at: 1.day.ago)
      end

      it "開始日フィルターが適用される" do
        get :index, params: { start_date: 3.days.ago.to_date.to_s }
        logs = assigns(:logs)

        expect(logs.map(&:id)).to include(@recent_log.id)
        expect(logs.map(&:id)).not_to include(@old_log.id)
      end

      it "終了日フィルターが適用される" do
        get :index, params: { end_date: 3.days.ago.to_date.to_s }
        logs = assigns(:logs)

        expect(logs.map(&:id)).to include(@old_log.id)
        expect(logs.map(&:id)).not_to include(@recent_log.id)
      end

      it "日付範囲フィルターが適用される" do
        get :index, params: {
          start_date: 6.days.ago.to_date.to_s,
          end_date: 4.days.ago.to_date.to_s
        }
        logs = assigns(:logs)

        expect(logs.map(&:id)).to include(@old_log.id)
        expect(logs.map(&:id)).not_to include(@recent_log.id)
      end

      it "不正な日付形式はスキップされる" do
        get :index, params: { start_date: "invalid_date" }

        expect(response).to be_successful
        expect(flash.now[:alert]).to include("日付の形式が正しくありません")
      end

      it "不正な日付でもエラーにならない" do
        expect {
          get :index, params: { start_date: "2023-99-99" }
        }.not_to raise_error

        expect(flash.now[:alert]).to include("日付の形式が正しくありません")
      end
    end

    context "レスポンス形式" do
      it "HTMLレスポンスを返す" do
        get :index
        expect(response.content_type).to include("text/html")
      end

      it "JSONレスポンスを返す" do
        get :index, format: :json
        expect(response.content_type).to include("application/json")

        json_data = JSON.parse(response.body)
        expect(json_data).to be_an(Array)
        expect(json_data.length).to be > 0
      end

      it "CSV形式でエクスポートできる" do
        get :index, format: :csv

        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("inventory_logs-#{Date.today}.csv")
      end

      it "CSVデータが正しく生成される" do
        get :index, format: :csv

        csv_data = response.body
        expect(csv_data).to include(inventory.name)
        expect(csv_data).to include("adjustment")
        expect(csv_data).to include("10") # delta
      end
    end

    context "ページネーション" do
      before do
        create_list(:inventory_log, 25, inventory: inventory, admin: admin)
      end

      it "2ページ目を表示できる" do
        get :index, params: { page: 2 }

        logs = assigns(:logs)
        expect(logs.current_page).to eq(2)
        expect(logs.count).to be <= 20
      end
    end
  end

  # ============================================
  # ログ詳細表示機能のテスト
  # ============================================

  describe "GET #show" do
    context "基本機能" do
      it "成功レスポンスを返す" do
        get :show, params: { id: inventory_log.id }
        expect(response).to be_successful
      end

      it "指定されたログを取得する" do
        get :show, params: { id: inventory_log.id }
        expect(assigns(:log)).to eq(inventory_log)
      end
    end

    context "エラーハンドリング" do
      it "存在しないIDは404エラー" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # システム全体ログ表示機能のテスト
  # ============================================

  describe "GET #all" do
    context "基本機能" do
      it "成功レスポンスを返す" do
        get :all
        expect(response).to be_successful
      end

      it "全ての在庫ログを表示する" do
        get :all
        logs = assigns(:logs)

        inventory_ids = logs.map(&:inventory_id).uniq
        expect(inventory_ids).to include(inventory.id, other_inventory.id)
      end

      it "indexテンプレートを使用する" do
        get :all
        expect(response).to render_template(:index)
      end

      it "ページネーションが適用される" do
        get :all
        logs = assigns(:logs)
        expect(logs).to respond_to(:current_page)
      end

      it "関連データがeager loadingされる" do
        get :all
        logs = assigns(:logs)

        if logs.any?
          expect(logs.first.association(:inventory)).to be_loaded
        end
      end
    end
  end

  # ============================================
  # 操作種別フィルタリング機能のテスト
  # ============================================

  describe "GET #by_operation" do
    before do
      create(:inventory_log, inventory: inventory, admin: admin, operation_type: "adjustment")
      create(:inventory_log, inventory: inventory, admin: admin, operation_type: "stock_in")
      create(:inventory_log, inventory: inventory, admin: admin, operation_type: "stock_out")
    end

    context "基本機能" do
      it "成功レスポンスを返す" do
        get :by_operation, params: { operation_type: "adjustment" }
        expect(response).to be_successful
      end

      it "指定された操作種別のログのみ表示する" do
        get :by_operation, params: { operation_type: "adjustment" }

        logs = assigns(:logs)
        expect(logs.all? { |log| log.operation_type == "adjustment" }).to be true
      end

      it "操作種別が設定される" do
        get :by_operation, params: { operation_type: "stock_in" }
        expect(assigns(:operation_type)).to eq("stock_in")
      end

      it "indexテンプレートを使用する" do
        get :by_operation, params: { operation_type: "adjustment" }
        expect(response).to render_template(:index)
      end
    end

    context "ページネーション" do
      before do
        create_list(:inventory_log, 25, inventory: inventory, admin: admin, operation_type: "adjustment")
      end

      it "ページネーションが適用される" do
        get :by_operation, params: { operation_type: "adjustment" }

        logs = assigns(:logs)
        expect(logs.count).to eq(20) # PER_PAGE
        expect(logs).to respond_to(:current_page)
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance" do
    context "N+1クエリ防止" do
      before do
        create_list(:inventory_log, 30, inventory: inventory, admin: admin)
      end

      it "indexアクションでN+1クエリが発生しない" do
        expect {
          get :index
        }.not_to exceed_query_limit(10)
      end

      it "allアクションでN+1クエリが発生しない" do
        expect {
          get :all
        }.not_to exceed_query_limit(10)
      end

      it "by_operationアクションでN+1クエリが発生しない" do
        expect {
          get :by_operation, params: { operation_type: "adjustment" }
        }.not_to exceed_query_limit(12)
      end
    end

    context "レスポンス時間" do
      before do
        create_list(:inventory_log, 50, inventory: inventory, admin: admin)
      end

      it "indexアクションは高速にレスポンスする" do
        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 200 # 200ms以内
      end
    end
  end

  # ============================================
  # エラーハンドリングのテスト
  # ============================================

  describe "error handling" do
    context "日付解析エラー" do
      it "エラーメッセージを表示する" do
        get :index, params: { start_date: "invalid" }
        expect(flash.now[:alert]).to include("日付の形式が正しくありません")
      end

      it "エラーログが記録される" do
        expect(Rails.logger).to receive(:info).with(/Invalid date format/)
        get :index, params: { start_date: "invalid" }
      end
    end

    context "データベースエラー" do
      before do
        allow(InventoryLog).to receive(:recent).and_raise(ActiveRecord::StatementInvalid)
      end

      it "エラーが適切に処理される" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::StatementInvalid)
      end
    end
  end

  # ============================================
  # 設定値の検証
  # ============================================

  describe "configuration" do
    it "適切な定数が定義されている" do
      expect(InventoryLogsController::PER_PAGE).to eq(20)
    end

    it "ApplicationControllerを継承している" do
      expect(InventoryLogsController.ancestors).to include(ApplicationController)
    end
  end

  # ============================================
  # TODO: AdminControllersへの移行準備
  # ============================================

  describe "future migration to AdminControllers" do
    it "移行時の考慮事項をドキュメント化" do
      # 移行時に必要な変更点：
      # 1. 認証機能の追加（authenticate_admin!）
      # 2. 権限チェックの実装（本部管理者 vs 店舗管理者）
      # 3. URLパスの変更（/inventory_logs → /admin/inventory_logs）
      # 4. 301リダイレクトの設定
      expect(true).to be true # プレースホルダー
    end
  end
end
