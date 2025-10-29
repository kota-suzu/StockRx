# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InventoryLogsController, type: :controller do
  # CLAUDE.md準拠: 在庫変動履歴管理機能の包括的テスト
  # メタ認知: 権限ベースのデータアクセス制御と監査証跡の検証
  # 横展開: 他の履歴管理コントローラーでも同様のテストパターン適用

  # MySQLトランザクションエラー対策（2025年6月25日実装）
  # 問題: "Table definition has changed, please retry transaction"
  # 解決策: テスト実行前のスキーマキャッシュクリアと最適化設定
  before(:all) do
    if ActiveRecord::Base.connection.adapter_name == 'Mysql2'
      # スキーマキャッシュの完全クリア
      ActiveRecord::Base.connection.schema_cache.clear!

      # トランザクション最適化設定
      ActiveRecord::Base.connection.execute('SET SESSION innodb_lock_wait_timeout = 2')
      ActiveRecord::Base.connection.execute('SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED')
    end
  rescue => e
    Rails.logger.warn "MySQL最適化設定警告: #{e.message}"
  end

  let(:headquarters_admin) { create(:admin, role: :headquarters_admin, store: nil) }
  let(:store_admin) { create(:admin, role: :store_admin, store: store) }
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }
  let(:inventory) { create(:inventory) }
  let(:other_inventory) { create(:inventory) }

  # 店舗在庫とログの関連設定
  let!(:store_inventory) { create(:store_inventory, store: store, inventory: inventory) }
  let!(:other_store_inventory) { create(:store_inventory, store: other_store, inventory: other_inventory) }
  let!(:inventory_log) { create(:inventory_log, inventory: inventory, admin: headquarters_admin) }
  let!(:other_store_log) { create(:inventory_log, inventory: other_inventory, admin: headquarters_admin) }

  # ============================================
  # 権限チェック機能のテスト
  # ============================================

  describe "authorization requirements" do
    context "本部管理者（headquarters_admin）" do
      before { sign_in headquarters_admin, scope: :admin }

      it "全ての在庫ログアクションにアクセス可能" do
        get :index
        expect(response).to be_successful
      end

      it "システム全体のログ表示（all アクション）が可能" do
        get :all
        expect(response).to be_successful
      end

      it "全店舗のログが表示される" do
        get :all
        logs = assigns(:logs)
        log_inventory_ids = logs.map(&:inventory_id)

        expect(log_inventory_ids).to include(inventory.id, other_inventory.id)
      end

      it "操作種別別ログ表示が可能" do
        get :by_operation, params: { operation_type: "adjustment" }
        expect(response).to be_successful
      end
    end

    context "店舗管理者（store_admin）" do
      before { sign_in store_admin, scope: :admin }

      it "index アクションにアクセス可能" do
        get :index
        expect(response).to be_successful
      end

      it "自店舗のログのみ表示される" do
        get :index
        logs = assigns(:logs)

        # 店舗管理者は自店舗の在庫ログのみ表示
        expect(logs.map(&:inventory_id)).to include(inventory.id)
        expect(logs.map(&:inventory_id)).not_to include(other_inventory.id)
      end

      it "システム全体のログ表示（all アクション）は拒否される" do
        get :all
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ実行可能")
      end

      it "他店舗のログ詳細表示は拒否される" do
        expect {
          get :show, params: { id: other_store_log.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "自店舗のログ詳細表示は可能" do
        get :show, params: { id: inventory_log.id }
        expect(response).to be_successful
        expect(assigns(:log)).to eq(inventory_log)
      end
    end

    context "認証なしアクセス" do
      before { sign_out :admin }

      it "認証を要求される" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "all アクションも認証を要求される" do
        get :all
        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  # ============================================
  # 在庫ログ一覧機能のテスト
  # ============================================

  describe "GET #index" do
    before { sign_in headquarters_admin, scope: :admin }

    context "基本機能" do
      before do
        create_list(:inventory_log, 25, inventory: inventory, admin: headquarters_admin)
      end

      it "成功レスポンスを返す" do
        get :index
        expect(response).to be_successful
      end

      it "在庫ログがページネーション付きで表示される" do
        get :index
        logs = assigns(:logs)

        expect(logs).to be_present
        expect(logs.count).to eq(20) # PER_PAGE = 20
        expect(logs).to respond_to(:current_page)
      end

      it "適切な関連データがeager loadingされる" do
        get :index
        logs = assigns(:logs)

        if logs.any?
          expect(logs.first.association(:inventory)).to be_loaded
          expect(logs.first.association(:admin)).to be_loaded
        end
      end
    end

    context "特定在庫のログ表示" do
      it "inventory_id パラメータがある場合、特定在庫のログのみ表示される" do
        get :index, params: { inventory_id: inventory.id }

        expect(assigns(:inventory)).to eq(inventory)
        logs = assigns(:logs)
        expect(logs.all? { |log| log.inventory_id == inventory.id }).to be true
      end

      it "存在しない inventory_id の場合はRecordNotFoundエラー" do
        expect {
          get :index, params: { inventory_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "日付フィルタリング" do
      before do
        create(:inventory_log, inventory: inventory, admin: headquarters_admin,
               created_at: 3.days.ago)
        create(:inventory_log, inventory: inventory, admin: headquarters_admin,
               created_at: 1.day.ago)
      end

      it "開始日フィルターが適用される" do
        get :index, params: { start_date: 2.days.ago.to_date.to_s }
        logs = assigns(:logs)

        expect(logs.count).to eq(1) # 1日前のログのみ
      end

      it "終了日フィルターが適用される" do
        get :index, params: { end_date: 2.days.ago.to_date.to_s }
        logs = assigns(:logs)

        expect(logs.count).to eq(1) # 3日前のログのみ
      end

      it "日付範囲フィルターが適用される" do
        get :index, params: {
          start_date: 4.days.ago.to_date.to_s,
          end_date: 2.days.ago.to_date.to_s
        }
        logs = assigns(:logs)

        expect(logs.count).to eq(1) # 3日前のログのみ
      end

      it "不正な日付形式はスキップされる" do
        get :index, params: { start_date: "invalid_date" }

        expect(response).to be_successful
        expect(flash.now[:alert]).to include("日付の形式が正しくありません")
      end
    end

    context "レスポンス形式" do
      it "HTMLレスポンスが正常" do
        get :index
        expect(response.content_type).to include("text/html")
      end

      it "JSONレスポンスが正常" do
        get :index, format: :json
        expect(response.content_type).to include("application/json")

        json_data = JSON.parse(response.body)
        expect(json_data).to be_an(Array)

        if json_data.any?
          log_data = json_data.first
          expect(log_data).to have_key("id")
          expect(log_data).to have_key("inventory")
          expect(log_data).to have_key("operation_type")
          expect(log_data).to have_key("delta")
          expect(log_data).to have_key("admin")
        end
      end

      it "CSVエクスポートが正常" do
        get :index, format: :csv
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("inventory_logs-all-#{Date.today}.csv")
      end

      it "特定在庫のCSVエクスポートファイル名が正しい" do
        get :index, params: { inventory_id: inventory.id }, format: :csv
        expected_filename = "inventory_logs-#{inventory.name.gsub(/[^\w\-]/, '_')}-#{Date.today}.csv"
        expect(response.headers["Content-Disposition"]).to include(expected_filename)
      end
    end
  end

  # ============================================
  # 在庫ログ詳細機能のテスト
  # ============================================

  describe "GET #show" do
    before { sign_in headquarters_admin, scope: :admin }

    context "有効なログID" do
      it "成功レスポンスを返す" do
        get :show, params: { id: inventory_log.id }
        expect(response).to be_successful
      end

      it "ログを正しく取得する" do
        get :show, params: { id: inventory_log.id }
        expect(assigns(:log)).to eq(inventory_log)
      end
    end

    context "存在しないログID" do
      it "RecordNotFoundエラーが発生する" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "権限チェック" do
      before { sign_in store_admin, scope: :admin }

      it "自店舗のログは表示可能" do
        get :show, params: { id: inventory_log.id }
        expect(response).to be_successful
      end

      it "他店舗のログは表示不可" do
        expect {
          get :show, params: { id: other_store_log.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # システム全体ログ機能のテスト
  # ============================================

  describe "GET #all" do
    context "本部管理者" do
      before { sign_in headquarters_admin, scope: :admin }

      it "成功レスポンスを返す" do
        get :all
        expect(response).to be_successful
      end

      it "システム全体のログが表示される" do
        get :all
        logs = assigns(:logs)

        expect(logs).to be_present
        expect(logs).to respond_to(:current_page)
      end

      it "適切な関連データがeager loadingされる" do
        get :all
        logs = assigns(:logs)

        if logs.any?
          expect(logs.first.association(:inventory)).to be_loaded
          expect(logs.first.association(:admin)).to be_loaded
        end
      end

      it "index テンプレートを使用する" do
        get :all
        expect(response).to render_template(:index)
      end
    end

    context "店舗管理者" do
      before { sign_in store_admin, scope: :admin }

      it "アクセスが拒否される" do
        get :all
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ実行可能")
      end
    end
  end

  # ============================================
  # 操作種別別ログ機能のテスト
  # ============================================

  describe "GET #by_operation" do
    before do
      sign_in headquarters_admin, scope: :admin

      create(:inventory_log, inventory: inventory, admin: headquarters_admin,
             operation_type: "adjustment")
      create(:inventory_log, inventory: inventory, admin: headquarters_admin,
             operation_type: "stock_in")
      create(:inventory_log, inventory: inventory, admin: headquarters_admin,
             operation_type: "stock_out")
    end

    it "成功レスポンスを返す" do
      get :by_operation, params: { operation_type: "adjustment" }
      expect(response).to be_successful
    end

    it "指定された操作種別が設定される" do
      get :by_operation, params: { operation_type: "adjustment" }
      expect(assigns(:operation_type)).to eq("adjustment")
    end

    it "指定された操作種別のログのみ表示される" do
      get :by_operation, params: { operation_type: "adjustment" }
      logs = assigns(:logs)

      expect(logs.all? { |log| log.operation_type == "adjustment" }).to be true
    end

    it "権限フィルターが適用される" do
      sign_in store_admin, scope: :admin

      get :by_operation, params: { operation_type: "adjustment" }
      logs = assigns(:logs)

      # 店舗管理者は自店舗のログのみ表示
      log_inventory_ids = logs.map(&:inventory_id)
      expect(log_inventory_ids).to include(inventory.id)
      expect(log_inventory_ids).not_to include(other_inventory.id)
    end

    it "index テンプレートを使用する" do
      get :by_operation, params: { operation_type: "adjustment" }
      expect(response).to render_template(:index)
    end
  end

  # ============================================
  # 権限フィルタリング機能のテスト
  # ============================================

  describe "permission filtering" do
    before do
      create_list(:inventory_log, 3, inventory: inventory, admin: headquarters_admin)
      create_list(:inventory_log, 2, inventory: other_inventory, admin: headquarters_admin)
    end

    context "本部管理者" do
      before { sign_in headquarters_admin, scope: :admin }

      it "全店舗のログが表示される" do
        get :index
        logs = assigns(:logs)

        log_inventory_ids = logs.map(&:inventory_id).uniq
        expect(log_inventory_ids).to include(inventory.id, other_inventory.id)
      end
    end

    context "店舗管理者" do
      before { sign_in store_admin, scope: :admin }

      it "自店舗のログのみ表示される" do
        get :index
        logs = assigns(:logs)

        log_inventory_ids = logs.map(&:inventory_id)
        expect(log_inventory_ids).to include(inventory.id)
        expect(log_inventory_ids).not_to include(other_inventory.id)
      end

      it "操作種別別表示でも権限フィルターが適用される" do
        get :by_operation, params: { operation_type: "adjustment" }
        logs = assigns(:logs)

        log_inventory_ids = logs.map(&:inventory_id)
        expect(log_inventory_ids).to include(inventory.id)
        expect(log_inventory_ids).not_to include(other_inventory.id)
      end
    end
  end

  # ============================================
  # CSVエクスポート機能のテスト
  # ============================================

  describe "CSV export functionality" do
    before do
      sign_in headquarters_admin, scope: :admin

      @log1 = create(:inventory_log,
                     inventory: inventory,
                     admin: headquarters_admin,
                     operation_type: "adjustment",
                     delta: 10,
                     previous_quantity: 100,
                     current_quantity: 110,
                     note: "定期調整")
    end

    it "CSVヘッダーが正しく設定される" do
      get :index, format: :csv
      csv_data = response.body
      lines = csv_data.split("\n")

      expect(lines.first).to include("日時,商品名,操作種別,変動数,変動前在庫,変動後在庫,実行者,備考")
    end

    it "CSVデータが正しく生成される" do
      get :index, format: :csv
      csv_data = response.body
      lines = csv_data.split("\n")

      # データ行をチェック（ヘッダー行をスキップ）
      data_line = lines[1]
      expect(data_line).to include(inventory.name)
      expect(data_line).to include("10") # delta
      expect(data_line).to include("100") # previous_quantity
      expect(data_line).to include("110") # current_quantity
      expect(data_line).to include("定期調整") # note
    end

    it "特定在庫のCSVエクスポートが正常" do
      get :index, params: { inventory_id: inventory.id }, format: :csv

      expect(response).to be_successful
      expect(response.content_type).to include("text/csv")
    end

    it "日付フィルター適用後のCSVエクスポートが正常" do
      get :index, params: {
        start_date: 1.day.ago.to_date.to_s,
        end_date: Date.current.to_s
      }, format: :csv

      expect(response).to be_successful
      expect(response.content_type).to include("text/csv")
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    before { sign_in headquarters_admin, scope: :admin }

    context "N+1クエリ防止" do
      before do
        create_list(:inventory_log, 50, inventory: inventory, admin: headquarters_admin)
      end

      it "index アクションでのN+1クエリ防止" do
        expect {
          get :index
        }.not_to exceed_query_limit(10) # includes(:inventory, :admin)による最適化
      end

      it "all アクションでのN+1クエリ防止" do
        expect {
          get :all
        }.not_to exceed_query_limit(10) # includes(:inventory, :admin)による最適化
      end

      it "by_operation アクションでのN+1クエリ防止" do
        expect {
          get :by_operation, params: { operation_type: "adjustment" }
        }.not_to exceed_query_limit(12) # 操作種別フィルターとincludes
      end

      it "JSONレスポンスでのN+1クエリ防止" do
        expect {
          get :index, format: :json
        }.not_to exceed_query_limit(10) # eager loadingによる最適化
      end
    end

    context "レスポンス時間" do
      before do
        create_list(:inventory_log, 100, inventory: inventory, admin: headquarters_admin)
      end

      it "index アクションは200ms以内" do
        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 200
      end

      it "CSVエクスポートは500ms以内" do
        start_time = Time.current
        get :index, format: :csv
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 500
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "権限エスカレーション防止" do
      before { sign_in store_admin, scope: :admin }

      it "店舗管理者は他店舗のログにアクセス不可" do
        expect {
          get :show, params: { id: other_store_log.id }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "店舗管理者はシステム全体ログにアクセス不可" do
        get :all
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者のみ")
      end
    end

    context "入力検証" do
      before { sign_in headquarters_admin, scope: :admin }

      it "不正な日付パラメータは適切に処理される" do
        expect {
          get :index, params: {
            start_date: "invalid_date",
            end_date: "also_invalid"
          }
        }.not_to raise_error

        expect(flash.now[:alert]).to include("日付の形式が正しくありません")
      end

      it "存在しないinventory_idは404エラー" do
        expect {
          get :index, params: { inventory_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "存在しないログIDは404エラー" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "データアクセス制限" do
      before { sign_in store_admin, scope: :admin }

      it "権限フィルターによりデータが適切に制限される" do
        get :index
        logs = assigns(:logs)

        # 店舗管理者は自店舗の在庫ログのみ表示
        logs.each do |log|
          expect(log.inventory.store_inventories.exists?(store_id: store_admin.store_id)).to be true
        end
      end
    end
  end

  # ============================================
  # 設定値の検証
  # ============================================

  describe "configuration validation" do
    before { sign_in headquarters_admin, scope: :admin }

    it "適切なページネーション設定" do
      create_list(:inventory_log, 25, inventory: inventory, admin: headquarters_admin)

      get :index
      logs = assigns(:logs)

      expect(logs.count).to eq(20) # PER_PAGE = 20
      expect(logs).to respond_to(:current_page)
    end

    it "監査スキップが正しく設定" do
      # skip_around_action :audit_sensitive_data_access の確認
      callbacks = AdminControllers::InventoryLogsController._process_action_callbacks
      audit_callback = callbacks.find { |c| c.filter == :audit_sensitive_data_access }

      # スキップされているため、コールバックが見つからないか無効化されている
      expect(audit_callback).to be_nil
    end

    it "継承とモジュール構成の確認" do
      expect(AdminControllers::InventoryLogsController.ancestors).to include(
        AdminControllers::BaseController
      )
    end
  end

  # ============================================
  # エラーハンドリングのテスト
  # ============================================

  describe "error handling" do
    before { sign_in headquarters_admin, scope: :admin }

    context "データベースエラー" do
      before do
        allow(InventoryLog).to receive(:recent).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "適切にエラーハンドリングされる" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "日付解析エラー" do
      it "不正な日付形式でもアプリケーションが停止しない" do
        get :index, params: { start_date: "2023-99-99" }

        expect(response).to be_successful
        expect(flash.now[:alert]).to include("日付の形式が正しくありません")
      end

      it "エラーログが記録される" do
        expect(Rails.logger).to receive(:info).with(/Invalid date format/)

        get :index, params: { start_date: "invalid" }
      end
    end
  end

  # ============================================
  # JSON APIレスポンスの詳細テスト
  # ============================================

  describe "JSON API response details" do
    before do
      sign_in headquarters_admin, scope: :admin

      @test_log = create(:inventory_log,
                         inventory: inventory,
                         admin: headquarters_admin,
                         operation_type: "adjustment",
                         delta: 5,
                         previous_quantity: 95,
                         current_quantity: 100,
                         note: "テスト調整")
    end

    it "JSONレスポンスの構造が正しい" do
      get :index, format: :json
      json_data = JSON.parse(response.body)

      expect(json_data).to be_an(Array)

      if json_data.any?
        log_data = json_data.first

        expect(log_data).to have_key("id")
        expect(log_data).to have_key("inventory")
        expect(log_data).to have_key("operation_type")
        expect(log_data).to have_key("operation_type_text")
        expect(log_data).to have_key("delta")
        expect(log_data).to have_key("previous_quantity")
        expect(log_data).to have_key("current_quantity")
        expect(log_data).to have_key("admin")
        expect(log_data).to have_key("note")
        expect(log_data).to have_key("created_at")

        # ネストされたオブジェクトの構造確認
        expect(log_data["inventory"]).to have_key("id")
        expect(log_data["inventory"]).to have_key("name")
        expect(log_data["admin"]).to have_key("id")
        expect(log_data["admin"]).to have_key("name")
      end
    end
  end
end
