# frozen_string_literal: true

require 'rails_helper'

# CLAUDE.md準拠: Mass Assignment脆弱性テスト
# OWASP Top 10 - A03:2021 Injection対策の検証
RSpec.describe "Mass Assignment Security", type: :request do
  describe "AdminControllers::InventoriesController" do
    let(:admin) { create(:admin) }
    let(:inventory) { create(:inventory) }

    before do
      sign_in admin
    end

    describe "POST /admin/inventories" do
      context "正常なパラメータ" do
        let(:valid_params) do
          {
            inventory: {
              name: "Test Product",
              quantity: 100,
              price: 1000,
              status: "active"
            }
          }
        end

        it "許可されたパラメータのみを受け入れる" do
          expect {
            post admin_inventories_path, params: valid_params
          }.to change(Inventory, :count).by(1)

          inventory = Inventory.last
          expect(inventory.name).to eq("Test Product")
          expect(inventory.quantity).to eq(100)
          expect(inventory.price).to eq(1000)
          expect(inventory.status).to eq("active")
        end
      end

      context "Mass Assignment攻撃の試行" do
        let(:malicious_params) do
          {
            inventory: {
              name: "Test Product",
              quantity: 100,
              price: 1000,
              status: "active",
              # 許可されていないパラメータ
              id: 9999,
              created_at: 1.year.ago,
              updated_at: 1.year.ago,
              admin_id: 999,
              internal_notes: "Should not be saved"
            }
          }
        end

        it "許可されていないパラメータを無視する" do
          post admin_inventories_path, params: malicious_params

          inventory = Inventory.last
          expect(inventory.id).not_to eq(9999)
          expect(inventory.created_at).to be > 1.minute.ago
          expect(inventory.updated_at).to be > 1.minute.ago

          # internal_notesなどの保護されたフィールドは変更されない
          expect(inventory).not_to respond_to(:internal_notes)
        end

        it "セキュリティログを記録する" do
          expect(Rails.logger).to receive(:warn).with(/Unpermitted parameters/)

          # ActionController::Parameters.action_on_unpermitted_parametersを一時的に設定
          original_setting = ActionController::Parameters.action_on_unpermitted_parameters
          ActionController::Parameters.action_on_unpermitted_parameters = :log

          post admin_inventories_path, params: malicious_params

          ActionController::Parameters.action_on_unpermitted_parameters = original_setting
        end
      end

      context "SQLインジェクション対策" do
        let(:sql_injection_params) do
          {
            inventory: {
              name: "'; DROP TABLE inventories; --",
              quantity: "100 OR 1=1",
              price: "1000; DELETE FROM inventories",
              status: "active"
            }
          }
        end

        it "SQLインジェクションを防ぐ" do
          expect {
            post admin_inventories_path, params: sql_injection_params
          }.to change(Inventory, :count).by(1)

          inventory = Inventory.last
          # 文字列がそのまま保存される（SQLとして実行されない）
          expect(inventory.name).to eq("'; DROP TABLE inventories; --")
          # 数値フィールドは適切に変換される
          expect(inventory.quantity).to eq(100)
          expect(inventory.price).to eq(1000)
        end
      end

      context "XSS対策" do
        let(:xss_params) do
          {
            inventory: {
              name: "<script>alert('XSS')</script>",
              quantity: 100,
              price: 1000,
              status: "active"
            }
          }
        end

        it "XSSペイロードをエスケープする" do
          post admin_inventories_path, params: xss_params

          inventory = Inventory.last
          # HTMLエスケープされて保存される
          expect(inventory.name).to include("&lt;script&gt;")
          expect(inventory.name).not_to include("<script>")
        end
      end

      context "ファイルアップロード時のセキュリティ" do
        let(:csv_file) { fixture_file_upload('test_inventory.csv', 'text/csv') }
        let(:malicious_file) { fixture_file_upload('malicious.exe', 'application/x-executable') }

        it "許可されたファイル形式のみを受け入れる" do
          post import_admin_inventories_path, params: { csv_file: csv_file }
          expect(response).to redirect_to(admin_job_status_path(assigns(:job_id)))
        end

        it "危険なファイル形式を拒否する" do
          post import_admin_inventories_path, params: { csv_file: malicious_file }
          expect(response).to redirect_to(import_form_admin_inventories_path)
          expect(flash[:alert]).to include("CSVファイルを選択してください")
        end

        it "大きすぎるファイルを拒否する" do
          # 11MBのファイルをシミュレート
          allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(11.megabytes)

          post import_admin_inventories_path, params: { csv_file: csv_file }
          expect(response).to redirect_to(import_form_admin_inventories_path)
          expect(flash[:alert]).to include("ファイルサイズが大きすぎます")
        end
      end
    end

    describe "PATCH /admin/inventories/:id" do
      context "パラメータ改ざん攻撃" do
        let(:update_params) do
          {
            inventory: {
              name: "Updated Product",
              # 以下は許可されていないパラメータ
              id: 999,
              created_at: 1.year.ago
            }
          }
        end

        it "IDの改ざんを防ぐ" do
          patch admin_inventory_path(inventory), params: update_params

          inventory.reload
          expect(inventory.name).to eq("Updated Product")
          expect(inventory.id).not_to eq(999)
          expect(inventory.created_at).not_to eq(1.year.ago)
        end
      end

      context "データ長制限" do
        let(:long_string_params) do
          {
            inventory: {
              name: "A" * 1000,  # 極端に長い文字列
              quantity: 100
            }
          }
        end

        it "文字列長を適切に制限する" do
          patch admin_inventory_path(inventory), params: long_string_params

          inventory.reload
          # 255文字で切り詰められる
          expect(inventory.name.length).to be <= 255
        end
      end
    end
  end

  describe "StoreControllers::InventoriesController" do
    let(:store) { create(:store) }
    let(:store_user) { create(:store_user, store: store) }
    let(:inventory) { create(:inventory) }
    let(:store_inventory) { create(:store_inventory, store: store, inventory: inventory) }

    before do
      sign_in store_user
      allow_any_instance_of(StoreControllers::BaseController).to receive(:current_store).and_return(store)
    end

    describe "POST /store/inventories/:id/adjust" do
      context "在庫調整パラメータの検証" do
        it "正の数値のみを受け入れる" do
          post adjust_store_inventory_path(inventory), params: {
            adjustment: {
              new_quantity: -100,
              reason: "Test adjustment"
            }
          }

          expect(response).to redirect_to(adjust_form_store_inventory_path(inventory))
          expect(flash[:alert]).to include("負の数は入力できません")
        end

        it "文字列を数値に適切に変換する" do
          post adjust_store_inventory_path(inventory), params: {
            adjustment: {
              new_quantity: "50abc",  # 不正な数値
              reason: "Test adjustment"
            }
          }

          # 50として処理される
          expect(response).to redirect_to(store_inventory_path(inventory))
          store_inventory.reload
          expect(store_inventory.quantity).to eq(50)
        end
      end

      context "理由フィールドのサニタイゼーション" do
        it "HTMLタグを除去する" do
          post adjust_store_inventory_path(inventory), params: {
            adjustment: {
              new_quantity: 100,
              reason: "<script>alert('XSS')</script>Adjustment",
              notes: "<img src=x onerror=alert('XSS')>"
            }
          }

          log = InventoryLog.last
          expect(log.reason).to include("&lt;script&gt;")
          expect(log.notes).to include("&lt;img")
        end
      end
    end

    describe "POST /store/inventories/:id/request_transfer" do
      let(:destination_store) { create(:store, active: true) }

      context "移動申請パラメータの検証" do
        it "正の数量のみを受け入れる" do
          post request_transfer_store_inventory_path(inventory), params: {
            transfer: {
              destination_store_id: destination_store.id,
              quantity: 0,
              reason: "Transfer request"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory))
          expect(flash[:alert]).to include("正の数を入力してください")
        end

        it "存在しない店舗IDを拒否する" do
          post request_transfer_store_inventory_path(inventory), params: {
            transfer: {
              destination_store_id: 99999,
              quantity: 10,
              reason: "Transfer request"
            }
          }

          expect(response).to redirect_to(request_transfer_form_store_inventory_path(inventory))
          expect(flash[:alert]).to include("指定された移動先店舗が見つかりません")
        end
      end
    end

    describe "検索機能のセキュリティ" do
      before do
        create(:store_inventory, store: store, inventory: create(:inventory, name: "Test Product"))
      end

      context "検索クエリのサニタイゼーション" do
        it "SQLワイルドカードをエスケープする" do
          get store_inventories_path, params: {
            q: { name_cont: "Test%Product" }
          }

          expect(response).to be_successful
          # %がエスケープされて検索される
          expect(assigns(:store_inventories)).to be_empty
        end

        it "SQLインジェクションを防ぐ" do
          get store_inventories_path, params: {
            q: { name_cont: "'; DROP TABLE inventories; --" }
          }

          expect(response).to be_successful
          # SQLエラーが発生しない
          expect { Inventory.count }.not_to raise_error
        end
      end

      context "ソートパラメータの検証" do
        it "許可されたカラムのみでソートする" do
          get store_inventories_path, params: {
            sort: "inventories.secret_column",
            direction: "asc"
          }

          expect(response).to be_successful
          # デフォルトカラムでソートされる
          expect(assigns(:store_inventories).to_sql).to include("ORDER BY inventories.name asc")
        end

        it "不正なソート順を拒否する" do
          get store_inventories_path, params: {
            sort: "inventories.name",
            direction: "random"
          }

          expect(response).to be_successful
          # デフォルトのascでソートされる
          expect(assigns(:store_inventories).to_sql).to include("ORDER BY inventories.name asc")
        end
      end
    end
  end

  describe "共通セキュリティ機能" do
    context "CSRFトークン検証" do
      let(:admin) { create(:admin) }
      let(:inventory) { create(:inventory) }

      it "CSRFトークンなしのリクエストを拒否する" do
        # CSRFトークンを無効化
        allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)
        allow_any_instance_of(ActionController::Base).to receive(:verified_request?).and_return(false)

        sign_in admin

        expect {
          post admin_inventories_path, params: {
            inventory: { name: "Test", quantity: 100, price: 1000 }
          }
        }.to raise_error(ActionController::InvalidAuthenticityToken)
      end
    end

    context "セッション固定攻撃対策" do
      let(:admin) { create(:admin) }

      it "ログイン後にセッションIDを変更する" do
        # 初期セッションID
        get new_admin_session_path
        initial_session_id = session.id

        # ログイン
        post admin_session_path, params: {
          admin: { email: admin.email, password: admin.password }
        }

        # セッションIDが変更されている
        expect(session.id).not_to eq(initial_session_id)
      end
    end
  end
end
