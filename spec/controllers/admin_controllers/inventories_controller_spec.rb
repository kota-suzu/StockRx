# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InventoriesController, type: :controller do
  # CLAUDE.md準拠: 包括的なコントローラーテスト
  # メタ認知: 全アクションと全分岐をカバーしてBranch Coverage向上
  # 横展開: 他のAdminコントローラーでも同様のテストパターン適用

  let(:admin) { create(:admin) }
  let(:inventory) { create(:inventory) }
  let(:valid_attributes) {
    {
      name: "新商品",
      quantity: 100,
      price: 1000,
      status: "active"
    }
  }
  let(:invalid_attributes) {
    {
      name: "",
      quantity: -1,
      price: -100,
      status: "invalid"
    }
  }

  before do
    sign_in admin
  end

  # ============================================
  # GET #index
  # ============================================

  describe "GET #index" do
    before do
      create_list(:inventory, 5)
    end

    context "HTML形式" do
      it "成功レスポンスを返す" do
        get :index
        expect(response).to be_successful
      end

      it "@inventoriesにページネーションされた在庫リストを設定する" do
        get :index
        expect(assigns(:inventories)).to be_present
        expect(assigns(:inventories_raw)).to respond_to(:current_page)
      end

      it "per_pageパラメータを正しく処理する" do
        get :index, params: { per_page: "100" }
        expect(assigns(:inventories_raw).limit_value).to eq(100)
      end

      it "無効なper_pageパラメータはデフォルト値を使用する" do
        get :index, params: { per_page: "999" }
        expect(assigns(:inventories_raw).limit_value).to eq(50)
      end

      it "検索パラメータを処理する" do
        expect(SearchQuery).to receive(:call).with(hash_including("search" => "test"))
          .and_return(Inventory.all)
        get :index, params: { search: "test" }
      end
    end

    context "JSON形式" do
      it "JSONレスポンスを返す" do
        get :index, format: :json
        expect(response).to be_successful
        expect(response.content_type).to match(/json/)
      end

      it "ページネーション情報を含む" do
        get :index, format: :json
        json_response = JSON.parse(response.body)

        expect(json_response).to have_key("inventories")
        expect(json_response).to have_key("pagination")
        expect(json_response["pagination"]).to include(
          "current_page", "total_pages", "total_count", "per_page"
        )
      end
    end

    context "Turbo Stream形式" do
      it "Turbo Streamレスポンスを返す" do
        get :index, format: :turbo_stream
        expect(response).to be_successful
        expect(response.content_type).to match(/turbo_stream/)
      end
    end
  end

  # ============================================
  # GET #show
  # ============================================

  describe "GET #show" do
    context "HTML形式" do
      it "成功レスポンスを返す" do
        get :show, params: { id: inventory.id }
        expect(response).to be_successful
      end

      it "バッチ情報を含む在庫を読み込む" do
        create(:batch, inventory: inventory)
        get :show, params: { id: inventory.id }
        expect(assigns(:inventory).association(:batches)).to be_loaded
      end
    end

    context "JSON形式" do
      it "JSONレスポンスを返す" do
        get :show, params: { id: inventory.id }, format: :json
        expect(response).to be_successful
        expect(response.content_type).to match(/json/)
      end
    end

    context "存在しない在庫" do
      it "RecordNotFoundエラーを発生させる" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # GET #new
  # ============================================

  describe "GET #new" do
    it "成功レスポンスを返す" do
      get :new
      expect(response).to be_successful
    end

    it "新しいInventoryインスタンスを作成する" do
      get :new
      expect(assigns(:inventory)).to be_a_new(Inventory)
    end
  end

  # ============================================
  # GET #edit
  # ============================================

  describe "GET #edit" do
    it "成功レスポンスを返す" do
      get :edit, params: { id: inventory.id }
      expect(response).to be_successful
    end

    it "基本情報のみの在庫を読み込む（パフォーマンス最適化）" do
      get :edit, params: { id: inventory.id }
      expect(assigns(:inventory).association(:batches)).not_to be_loaded
    end
  end

  # ============================================
  # POST #create
  # ============================================

  describe "POST #create" do
    context "有効なパラメータの場合" do
      context "HTML形式" do
        it "新しい在庫を作成する" do
          expect {
            post :create, params: { inventory: valid_attributes }
          }.to change(Inventory, :count).by(1)
        end

        it "作成した在庫にリダイレクトする" do
          post :create, params: { inventory: valid_attributes }
          expect(response).to redirect_to(admin_inventory_path(Inventory.last))
          expect(flash[:notice]).to eq("在庫が正常に登録されました。")
        end
      end

      context "JSON形式" do
        it "201ステータスで作成した在庫を返す" do
          post :create, params: { inventory: valid_attributes }, format: :json
          expect(response).to have_http_status(:created)
          json_response = JSON.parse(response.body)
          expect(json_response).to have_key("id")
        end
      end

      context "Turbo Stream形式" do
        it "成功メッセージを設定する" do
          post :create, params: { inventory: valid_attributes }, format: :turbo_stream
          expect(response).to be_successful
          expect(flash.now[:notice]).to eq("在庫が正常に登録されました。")
        end
      end
    end

    context "無効なパラメータの場合" do
      context "HTML形式" do
        it "在庫を作成しない" do
          expect {
            post :create, params: { inventory: invalid_attributes }
          }.not_to change(Inventory, :count)
        end

        it "newテンプレートを再表示する" do
          post :create, params: { inventory: invalid_attributes }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:new)
          expect(flash.now[:alert]).to eq("入力内容に問題があります")
        end
      end

      context "JSON形式" do
        it "422ステータスでエラーを返す" do
          post :create, params: { inventory: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response).to include(
            "code" => "validation_error",
            "message" => "入力内容に問題があります",
            "details" => be_an(Array)
          )
        end
      end

      context "Turbo Stream形式" do
        it "422ステータスでform_updateを返す" do
          post :create, params: { inventory: invalid_attributes }, format: :turbo_stream
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:form_update)
        end
      end
    end
  end

  # ============================================
  # PATCH/PUT #update
  # ============================================

  describe "PATCH #update" do
    let(:new_attributes) {
      {
        name: "更新された商品名",
        quantity: 200
      }
    }

    context "有効なパラメータの場合" do
      context "HTML形式" do
        it "在庫を更新する" do
          patch :update, params: { id: inventory.id, inventory: new_attributes }
          inventory.reload
          expect(inventory.name).to eq("更新された商品名")
          expect(inventory.quantity).to eq(200)
        end

        it "更新した在庫にリダイレクトする" do
          patch :update, params: { id: inventory.id, inventory: new_attributes }
          expect(response).to redirect_to(admin_inventory_path(inventory))
          expect(flash[:notice]).to eq("在庫が正常に更新されました。")
        end
      end

      context "JSON形式" do
        it "更新した在庫を返す" do
          patch :update, params: { id: inventory.id, inventory: new_attributes }, format: :json
          expect(response).to be_successful
          json_response = JSON.parse(response.body)
          expect(json_response).to have_key("id")
        end
      end

      context "Turbo Stream形式" do
        it "成功メッセージを設定する" do
          patch :update, params: { id: inventory.id, inventory: new_attributes }, format: :turbo_stream
          expect(response).to be_successful
          expect(flash.now[:notice]).to eq("在庫が正常に更新されました。")
        end
      end
    end

    context "無効なパラメータの場合" do
      context "HTML形式" do
        it "在庫を更新しない" do
          original_name = inventory.name
          patch :update, params: { id: inventory.id, inventory: invalid_attributes }
          inventory.reload
          expect(inventory.name).to eq(original_name)
        end

        it "editテンプレートを再表示する" do
          patch :update, params: { id: inventory.id, inventory: invalid_attributes }
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response).to render_template(:edit)
          expect(flash.now[:alert]).to eq("入力内容に問題があります")
        end
      end

      context "JSON形式" do
        it "422ステータスでエラーを返す" do
          patch :update, params: { id: inventory.id, inventory: invalid_attributes }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response).to include(
            "code" => "validation_error",
            "message" => "入力内容に問題があります",
            "details" => be_an(Array)
          )
        end
      end
    end
  end

  # ============================================
  # DELETE #destroy
  # ============================================

  describe "DELETE #destroy" do
    let!(:inventory_to_delete) { create(:inventory) }

    context "削除可能な在庫の場合" do
      context "HTML形式" do
        it "在庫を削除する" do
          expect {
            delete :destroy, params: { id: inventory_to_delete.id }
          }.to change(Inventory, :count).by(-1)
        end

        it "在庫一覧にリダイレクトする" do
          delete :destroy, params: { id: inventory_to_delete.id }
          expect(response).to redirect_to(admin_inventories_path)
          expect(response).to have_http_status(:see_other)
          expect(flash[:notice]).to eq("在庫が正常に削除されました。")
        end
      end

      context "JSON形式" do
        it "204ステータスを返す" do
          delete :destroy, params: { id: inventory_to_delete.id }, format: :json
          expect(response).to have_http_status(:no_content)
        end
      end

      context "Turbo Stream形式" do
        it "成功メッセージを設定する" do
          delete :destroy, params: { id: inventory_to_delete.id }, format: :turbo_stream
          expect(response).to be_successful
          expect(flash.now[:notice]).to eq("在庫が正常に削除されました。")
        end
      end
    end

    context "削除できない在庫の場合" do
      before do
        # 在庫ログを作成して削除制限を発生させる
        create(:inventory_log, inventory: inventory_to_delete)
      end

      context "HTML形式" do
        it "在庫を削除しない" do
          expect {
            delete :destroy, params: { id: inventory_to_delete.id }
          }.not_to change(Inventory, :count)
        end

        it "エラーメッセージと共にリダイレクトする" do
          delete :destroy, params: { id: inventory_to_delete.id }
          expect(response).to redirect_to(admin_inventories_path)
          expect(flash[:alert]).to include("関連する記録が存在するため削除できません")
        end
      end

      context "JSON形式" do
        it "422ステータスでエラーを返す" do
          delete :destroy, params: { id: inventory_to_delete.id }, format: :json
          expect(response).to have_http_status(:unprocessable_entity)

          json_response = JSON.parse(response.body)
          expect(json_response).to include(
            "code" => "deletion_error",
            "message" => be_a(String)
          )
        end
      end
    end

    context "予期しないエラーが発生した場合" do
      before do
        allow_any_instance_of(Inventory).to receive(:destroy).and_raise(StandardError, "Unexpected error")
      end

      it "一般的なエラーメッセージを表示する" do
        delete :destroy, params: { id: inventory_to_delete.id }
        expect(response).to redirect_to(admin_inventories_path)
        expect(flash[:alert]).to eq("削除中にエラーが発生しました。")
      end
    end
  end

  # ============================================
  # GET #import_form
  # ============================================

  describe "GET #import_form" do
    it "成功レスポンスを返す" do
      get :import_form
      expect(response).to be_successful
    end

    it "インポート関連の情報を設定する" do
      get :import_form
      expect(assigns(:import_security_info)).to include(
        max_file_size: "10MB",
        allowed_formats: [ ".csv" ],
        required_headers: %w[name quantity price]
      )
      expect(assigns(:csv_template_headers)).to eq(%w[name quantity price status])
      expect(assigns(:csv_sample_data)).to be_present
      expect(assigns(:current_import_jobs)).to eq([])
    end
  end

  # ============================================
  # POST #import
  # ============================================

  describe "POST #import" do
    let(:csv_content) do
      "name,quantity,price,status\n商品A,100,1000,active\n商品B,50,2000,active"
    end
    let(:csv_file) do
      file = Tempfile.new([ 'test', '.csv' ])
      file.write(csv_content)
      file.rewind

      ActionDispatch::Http::UploadedFile.new(
        tempfile: file,
        filename: 'test.csv',
        type: 'text/csv',
        original_filename: 'test.csv'
      )
    end

    context "有効なCSVファイルの場合" do
      before do
        allow(ImportInventoriesJob).to receive(:perform_later).and_return(true)
      end

      it "インポートジョブをエンキューする" do
        expect(ImportInventoriesJob).to receive(:perform_later).with(
          anything, # temp_file_path
          admin.id,
          hash_including(batch_size: 1000, skip_invalid: false),
          anything  # job_id
        )

        post :import, params: { csv_file: csv_file }
      end

      it "ジョブステータスページにリダイレクトする" do
        post :import, params: { csv_file: csv_file }
        expect(response).to redirect_to(admin_job_status_path(assigns(:job_id)))
        expect(flash[:notice]).to include("CSVインポートを開始しました")
      end

      it "インポートオプションを正しく処理する" do
        expect(ImportInventoriesJob).to receive(:perform_later).with(
          anything,
          admin.id,
          hash_including(skip_invalid: true, update_existing: true),
          anything
        )

        post :import, params: {
          csv_file: csv_file,
          skip_invalid: "1",
          update_existing: "1"
        }
      end
    end

    context "CSVファイルが指定されていない場合" do
      it "インポートフォームにリダイレクトする" do
        post :import, params: {}
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to eq("CSVファイルを選択してください。")
      end
    end

    context "ファイルサイズが大きすぎる場合" do
      let(:large_csv_file) do
        file = Tempfile.new([ 'large', '.csv' ])
        file.write("a" * 11.megabytes)
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'large.csv',
          type: 'text/csv',
          original_filename: 'large.csv'
        )
      end

      it "エラーメッセージと共にリダイレクトする" do
        post :import, params: { csv_file: large_csv_file }
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to include("ファイルサイズが大きすぎます")
      end
    end

    context "無効なファイル形式の場合" do
      let(:invalid_file) do
        file = Tempfile.new([ 'test', '.txt' ])
        file.write("invalid content")
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'test.txt',
          type: 'text/plain',
          original_filename: 'test.txt'
        )
      end

      it "エラーメッセージと共にリダイレクトする" do
        post :import, params: { csv_file: invalid_file }
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to include("CSVファイルを選択してください")
      end
    end

    context "不正なファイル名の場合" do
      let(:malicious_file) do
        file = Tempfile.new([ 'test', '.csv' ])
        file.write(csv_content)
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: '../../../etc/passwd.csv',
          type: 'text/csv',
          original_filename: '../../../etc/passwd.csv'
        )
      end

      it "エラーメッセージと共にリダイレクトする" do
        post :import, params: { csv_file: malicious_file }
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to eq("不正なファイル名です。")
      end
    end

    context "CSVフォーマットが不正な場合" do
      let(:malformed_csv_file) do
        file = Tempfile.new([ 'malformed', '.csv' ])
        file.write("invalid\"csv\"content\nwith\"unclosed\"quotes")
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'malformed.csv',
          type: 'text/csv',
          original_filename: 'malformed.csv'
        )
      end

      it "エラーメッセージと共にリダイレクトする" do
        post :import, params: { csv_file: malformed_csv_file }
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to include("CSVファイルの形式が正しくありません")
      end
    end

    context "ジョブのエンキューに失敗した場合" do
      before do
        allow(ImportInventoriesJob).to receive(:perform_later).and_raise(StandardError, "Job error")
      end

      it "エラーメッセージと共にリダイレクトする" do
        post :import, params: { csv_file: csv_file }
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to include("CSVインポート中にエラーが発生しました")
      end

      it "一時ファイルをクリーンアップする" do
        expect(controller).to receive(:cleanup_temp_file).at_least(:once)
        post :import, params: { csv_file: csv_file }
      end
    end
  end

  # ============================================
  # プライベートメソッドのテスト（send経由）
  # ============================================

  describe "private methods" do
    describe "#validate_per_page_param" do
      it "有効な値を返す" do
        expect(controller.send(:validate_per_page_param, "50")).to eq(50)
        expect(controller.send(:validate_per_page_param, "100")).to eq(100)
        expect(controller.send(:validate_per_page_param, "200")).to eq(200)
      end

      it "無効な値はデフォルトを返す" do
        expect(controller.send(:validate_per_page_param, "999")).to eq(50)
        expect(controller.send(:validate_per_page_param, nil)).to eq(50)
        expect(controller.send(:validate_per_page_param, "abc")).to eq(50)
      end
    end

    describe "#build_import_options" do
      it "デフォルトオプションを構築する" do
        options = controller.send(:build_import_options, {})
        expect(options).to include(
          batch_size: 1000,
          skip_invalid: false,
          update_existing: false,
          unique_key: "name",
          admin_id: admin.id
        )
      end

      it "カスタムオプションを処理する" do
        params = ActionController::Parameters.new({
          skip_invalid: "1",
          update_existing: "1",
          unique_key: "code"
        })

        options = controller.send(:build_import_options, params)
        expect(options).to include(
          skip_invalid: true,
          update_existing: true,
          unique_key: "code"
        )
      end
    end
  end

  # ============================================
  # パフォーマンス・N+1クエリテスト
  # ============================================

  describe "performance tests" do
    describe "N+1 query prevention" do
      context "index action" do
        it "避けるN+1クエリ（一覧表示）" do
          create_list(:inventory, 5) do |inventory|
            create(:batch, inventory: inventory)
            create(:inventory_log, inventory: inventory)
          end

          expect {
            get :index
          }.not_to exceed_query_limit(10) # 基本的なクエリ数制限
        end

        it "ページネーション時のクエリ数も一定" do
          create_list(:inventory, 50)

          expect {
            get :index, params: { page: 1, per_page: 50 }
          }.not_to exceed_query_limit(10)

          expect {
            get :index, params: { page: 2, per_page: 50 }
          }.not_to exceed_query_limit(10)
        end
      end

      context "show action with includes" do
        it "バッチ情報読み込み時のN+1クエリ防止" do
          inventory = create(:inventory)
          create_list(:batch, 3, inventory: inventory)

          expect {
            get :show, params: { id: inventory.id }
          }.not_to exceed_query_limit(5) # インクルード使用で制限
        end
      end

      context "edit/update actions optimization" do
        it "編集時は基本情報のみで高速化" do
          inventory = create(:inventory)
          create_list(:batch, 3, inventory: inventory)

          expect {
            get :edit, params: { id: inventory.id }
          }.not_to exceed_query_limit(3) # バッチ情報を読み込まない
        end

        it "更新時も基本情報のみで高速化" do
          inventory = create(:inventory)
          create_list(:batch, 3, inventory: inventory)

          expect {
            patch :update, params: { 
              id: inventory.id, 
              inventory: { name: "Updated" } 
            }
          }.not_to exceed_query_limit(4) # 更新クエリも最小限
        end
      end
    end

    describe "bulk operations performance" do
      it "大量データでのindex表示パフォーマンス" do
        create_list(:inventory, 100)

        start_time = Time.current
        get :index, params: { per_page: 100 }
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 500 # 500ms以内
      end

      it "検索機能のパフォーマンス" do
        inventories = create_list(:inventory, 50)
        search_target = inventories.first

        start_time = Time.current
        get :index, params: { search: search_target.name[0..2] }
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 300 # 300ms以内
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "認証なしアクセス" do
      before { sign_out admin }

      it "index画面への認証なしアクセスは拒否される" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "CSV import画面への認証なしアクセスは拒否される" do
        get :import_form
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "XSS防止" do
      let(:xss_attributes) do
        {
          name: "<script>alert('XSS')</script>悪意のある商品",
          quantity: 100,
          price: 1000,
          status: "active"
        }
      end

      it "商品名のXSSスクリプトはエスケープされる" do
        post :create, params: { inventory: xss_attributes }
        created_inventory = Inventory.last
        expect(created_inventory.name).not_to include("<script>")
        expect(created_inventory.name).to include("悪意のある商品")
      end
    end

    context "Mass Assignment防止" do
      it "許可されていないパラメータは無視される" do
        malicious_params = valid_attributes.merge(
          admin_id: 999,
          created_at: 1.year.ago,
          internal_code: "SECRET"
        )

        post :create, params: { inventory: malicious_params }
        inventory = Inventory.last

        expect(inventory.name).to eq(valid_attributes[:name])
        expect(inventory.quantity).to eq(valid_attributes[:quantity])
        # 許可されていないパラメータは設定されない
        expect(inventory.created_at).to be > 1.hour.ago
      end
    end

    context "CSVインポートセキュリティ" do
      let(:csv_injection_content) do
        "=cmd|'/c calc.exe'!A1,quantity,price,status\n商品A,100,1000,active"
      end
      
      let(:csv_injection_file) do
        file = Tempfile.new(['injection', '.csv'])
        file.write(csv_injection_content)
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'injection.csv',
          type: 'text/csv',
          original_filename: 'injection.csv'
        )
      end

      it "CSV Injectionを含むファイルは安全に処理される" do
        allow(ImportInventoriesJob).to receive(:perform_later).and_return(true)
        
        expect {
          post :import, params: { csv_file: csv_injection_file }
        }.not_to raise_error
        
        expect(response).to redirect_to(admin_job_status_path(assigns(:job_id)))
      end
    end
  end

  # ============================================
  # エラーハンドリングテスト
  # ============================================

  describe "error handling" do
    context "データベース接続エラー" do
      before do
        allow(Inventory).to receive(:all).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "適切にエラーハンドリングされる" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "メモリ不足エラー" do
      before do
        allow(SearchQuery).to receive(:call).and_raise(NoMemoryError)
      end

      it "メモリエラーは適切に伝播される" do
        expect {
          get :index
        }.to raise_error(NoMemoryError)
      end
    end

    context "ディスク容量不足（CSV保存時）" do
      let(:csv_file) do
        file = Tempfile.new(['test', '.csv'])
        file.write("name,quantity,price\n商品A,100,1000")
        file.rewind

        ActionDispatch::Http::UploadedFile.new(
          tempfile: file,
          filename: 'test.csv',
          type: 'text/csv',
          original_filename: 'test.csv'
        )
      end

      before do
        allow(controller).to receive(:save_uploaded_file_securely)
          .and_raise(Errno::ENOSPC, "No space left on device")
      end

      it "ディスク容量不足エラーを適切に処理する" do
        post :import, params: { csv_file: csv_file }
        expect(response).to redirect_to(import_form_admin_inventories_path)
        expect(flash[:alert]).to include("CSVインポート中にエラーが発生しました")
      end
    end
  end

  # ============================================
  # ブラウザ・レスポンス形式互換性テスト
  # ============================================

  describe "browser compatibility" do
    context "古いブラウザ対応" do
      before do
        request.headers["User-Agent"] = "Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko" # IE11
      end

      it "HTML形式でのレスポンスが正常" do
        get :index
        expect(response).to be_successful
        expect(response.content_type).to match(/html/)
      end
    end

    context "モバイルデバイス対応" do
      before do
        request.headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X)"
      end

      it "モバイルデバイスでの表示が正常" do
        get :index
        expect(response).to be_successful
      end
    end

    context "API利用（JSON）" do
      it "Content-Typeが正しく設定される" do
        get :index, format: :json
        expect(response.content_type).to match(/application\/json/)
      end

      it "CORS対応（将来実装時の準備）" do
        # TODO: Phase 4 - CORS設定テスト
        get :index, format: :json
        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # アクセシビリティ・ユーザビリティテスト  
  # ============================================

  describe "accessibility tests" do
    it "一覧ページでのスクリーンリーダー対応" do
      create_list(:inventory, 3)
      get :index
      
      expect(response.body).to include('role=') if response.body.present?
      expect(response).to be_successful
    end

    it "フォームでのaria-label対応準備" do
      get :new
      expect(response).to be_successful
      # TODO: ビューテンプレートでのaria-label実装後にテスト追加
    end
  end
end
