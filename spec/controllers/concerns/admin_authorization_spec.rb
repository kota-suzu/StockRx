# frozen_string_literal: true

require 'rails_helper'

# AdminAuthorization 完全ブランチカバレッジテスト
# CLAUDE.md準拠: 認証・認可システムの包括的テスト実装
# メタ認知: 全権限チェック分岐を完全カバーしてセキュリティ保証
# 横展開: 他のAuthorizationコンサーンでも同様のテストパターン適用
RSpec.describe AdminAuthorization, type: :controller do
  # テスト用ダミーコントローラ
  controller(ApplicationController) do
    include AdminAuthorization
    before_action :authenticate_admin!

    def test_headquarters_admin_required
      authorize_headquarters_admin!
      render plain: "success"
    end

    def test_store_management_required
      store = Store.find(params[:store_id])
      authorize_store_management!(store)
      render plain: "success"
    end

    def test_store_view_required
      store = Store.find(params[:store_id])
      authorize_store_view!(store)
      render plain: "success"
    end

    def test_transfer_approval_required
      transfer = InterStoreTransfer.find(params[:transfer_id])
      authorize_transfer_approval!(transfer)
      render plain: "success"
    end

    def test_transfer_modification_required
      transfer = InterStoreTransfer.find(params[:transfer_id])
      authorize_transfer_modification!(transfer)
      render plain: "success"
    end

    def test_transfer_cancellation_required
      transfer = InterStoreTransfer.find(params[:transfer_id])
      authorize_transfer_cancellation!(transfer)
      render plain: "success"
    end

    def test_audit_log_access_required
      authorize_audit_log_access!
      render plain: "success"
    end

    def test_multi_store_permissions_required
      ensure_multi_store_permissions
      render plain: "success"
    end

    def test_can_manage_store
      store = Store.find(params[:store_id])
      render json: { can_manage: can_manage_store?(store) }
    end

    def test_can_view_store
      store = Store.find(params[:store_id])
      render json: { can_view: can_view_store?(store) }
    end

    def test_can_modify_transfer
      transfer = InterStoreTransfer.find(params[:transfer_id])
      render json: { can_modify: can_modify_transfer?(transfer) }
    end

    def test_can_cancel_transfer
      transfer = InterStoreTransfer.find(params[:transfer_id])
      render json: { can_cancel: can_cancel_transfer?(transfer) }
    end

    def test_can_access_inventory_logs
      inventory = params[:inventory_id] ? Inventory.find(params[:inventory_id]) : nil
      render json: { can_access: can_access_inventory_logs?(inventory) }
    end

    private

    def admin_root_path
      "/admin"
    end
  end

  # テスト用ルート追加
  before do
    routes.draw do
      get "test_headquarters_admin_required" => "anonymous#test_headquarters_admin_required"
      get "test_store_management_required" => "anonymous#test_store_management_required"
      get "test_store_view_required" => "anonymous#test_store_view_required"
      get "test_transfer_approval_required" => "anonymous#test_transfer_approval_required"
      get "test_transfer_modification_required" => "anonymous#test_transfer_modification_required"
      get "test_transfer_cancellation_required" => "anonymous#test_transfer_cancellation_required"
      get "test_audit_log_access_required" => "anonymous#test_audit_log_access_required"
      get "test_multi_store_permissions_required" => "anonymous#test_multi_store_permissions_required"
      get "test_can_manage_store" => "anonymous#test_can_manage_store"
      get "test_can_view_store" => "anonymous#test_can_view_store"
      get "test_can_modify_transfer" => "anonymous#test_can_modify_transfer"
      get "test_can_cancel_transfer" => "anonymous#test_can_cancel_transfer"
      get "test_can_access_inventory_logs" => "anonymous#test_can_access_inventory_logs"
    end
  end

  # ============================================
  # テストデータセットアップ
  # ============================================

  let(:headquarters_admin) { create(:admin, :headquarters_admin) }
  let(:store_manager) { create(:admin, :store_manager, store: store) }
  let(:store_admin) { create(:admin, :store_admin, store: store) }
  let(:pharmacist) { create(:admin, :pharmacist, store: store) }
  let(:other_store_manager) { create(:admin, :store_manager, store: other_store) }

  let(:store) { create(:store) }
  let(:other_store) { create(:store) }
  let(:inventory) { create(:inventory) }

  let(:pending_transfer) do
    create(:inter_store_transfer,
           requested_by: store_manager,
           source_store: store,
           destination_store: other_store,
           status: :pending)
  end

  let(:approved_transfer) do
    create(:inter_store_transfer,
           requested_by: store_manager,
           source_store: store,
           destination_store: other_store,
           status: :approved)
  end

  let(:completed_transfer) do
    create(:inter_store_transfer,
           requested_by: store_manager,
           source_store: store,
           destination_store: other_store,
           status: :completed)
  end

  # ============================================
  # 本部管理者権限テスト
  # ============================================

  describe "#authorize_headquarters_admin!" do
    context "when user is headquarters admin" do
      before { sign_in headquarters_admin }

      it "allows access" do
        get :test_headquarters_admin_required
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user is not headquarters admin" do
      before { sign_in store_manager }

      it "redirects with alert for store manager" do
        get :test_headquarters_admin_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この操作は本部管理者のみ実行可能です。")
      end
    end

    context "when user is store admin" do
      before { sign_in store_admin }

      it "redirects with alert for store admin" do
        get :test_headquarters_admin_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この操作は本部管理者のみ実行可能です。")
      end
    end

    context "when user is pharmacist" do
      before { sign_in pharmacist }

      it "redirects with alert for pharmacist" do
        get :test_headquarters_admin_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この操作は本部管理者のみ実行可能です。")
      end
    end
  end

  # ============================================
  # 店舗管理権限テスト
  # ============================================

  describe "#authorize_store_management!" do
    context "when user can manage the store" do
      before do
        sign_in store_manager
        allow(store_manager).to receive(:can_manage_store?).with(store).and_return(true)
      end

      it "allows access" do
        get :test_store_management_required, params: { store_id: store.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user cannot manage the store" do
      before do
        sign_in other_store_manager
        allow(other_store_manager).to receive(:can_manage_store?).with(store).and_return(false)
      end

      it "redirects with alert" do
        get :test_store_management_required, params: { store_id: store.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この店舗を管理する権限がありません。")
      end
    end

    context "when headquarters admin accesses any store" do
      before do
        sign_in headquarters_admin
        allow(headquarters_admin).to receive(:can_manage_store?).with(store).and_return(true)
      end

      it "allows access" do
        get :test_store_management_required, params: { store_id: store.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end
  end

  # ============================================
  # 店舗閲覧権限テスト
  # ============================================

  describe "#authorize_store_view!" do
    context "when user can view the store" do
      before do
        sign_in store_admin
        allow(store_admin).to receive(:can_view_store?).with(store).and_return(true)
      end

      it "allows access" do
        get :test_store_view_required, params: { store_id: store.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user cannot view the store" do
      before do
        sign_in pharmacist
        allow(pharmacist).to receive(:can_view_store?).with(other_store).and_return(false)
      end

      it "redirects with alert" do
        get :test_store_view_required, params: { store_id: other_store.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この店舗を閲覧する権限がありません。")
      end
    end

    context "when pharmacist accesses own store" do
      before do
        sign_in pharmacist
        allow(pharmacist).to receive(:can_view_store?).with(store).and_return(true)
      end

      it "allows access" do
        get :test_store_view_required, params: { store_id: store.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end
  end

  # ============================================
  # 移動申請承認権限テスト
  # ============================================

  describe "#authorize_transfer_approval!" do
    context "when user can approve transfers" do
      before do
        sign_in headquarters_admin
        allow(headquarters_admin).to receive(:can_approve_transfers?).and_return(true)
      end

      it "allows access" do
        get :test_transfer_approval_required, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user cannot approve transfers" do
      before do
        sign_in store_manager
        allow(store_manager).to receive(:can_approve_transfers?).and_return(false)
      end

      it "redirects with alert" do
        get :test_transfer_approval_required, params: { transfer_id: pending_transfer.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("移動申請の承認権限がありません。")
      end
    end

    context "when store admin tries to approve" do
      before do
        sign_in store_admin
        allow(store_admin).to receive(:can_approve_transfers?).and_return(false)
      end

      it "redirects with alert" do
        get :test_transfer_approval_required, params: { transfer_id: pending_transfer.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("移動申請の承認権限がありません。")
      end
    end
  end

  # ============================================
  # 移動申請修正権限テスト
  # ============================================

  describe "#authorize_transfer_modification!" do
    context "when user can modify transfer" do
      before { sign_in store_manager }

      it "allows access when user is the requester" do
        get :test_transfer_modification_required, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user cannot modify transfer" do
      before { sign_in other_store_manager }

      it "redirects with alert" do
        get :test_transfer_modification_required, params: { transfer_id: pending_transfer.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この移動申請を修正する権限がありません。")
      end
    end

    context "when headquarters admin modifies any transfer" do
      before { sign_in headquarters_admin }

      it "allows access" do
        get :test_transfer_modification_required, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end
  end

  # ============================================
  # 移動申請取消権限テスト
  # ============================================

  describe "#authorize_transfer_cancellation!" do
    context "when user can cancel transfer" do
      before { sign_in store_manager }

      it "allows access when user is the requester" do
        get :test_transfer_cancellation_required, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user cannot cancel transfer" do
      before { sign_in other_store_manager }

      it "redirects with alert" do
        get :test_transfer_cancellation_required, params: { transfer_id: pending_transfer.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("この移動申請をキャンセルする権限がありません。")
      end
    end

    context "when headquarters admin cancels any transfer" do
      before { sign_in headquarters_admin }

      it "allows access" do
        get :test_transfer_cancellation_required, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end
  end

  # ============================================
  # 監査ログアクセス権限テスト
  # ============================================

  describe "#authorize_audit_log_access!" do
    context "when user is headquarters admin" do
      before { sign_in headquarters_admin }

      it "allows access" do
        get :test_audit_log_access_required
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user is not headquarters admin" do
      before { sign_in store_manager }

      it "redirects with alert for store manager" do
        get :test_audit_log_access_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("監査ログへのアクセス権限がありません。本部管理者権限が必要です。")
      end
    end

    context "when user is store admin" do
      before { sign_in store_admin }

      it "redirects with alert for store admin" do
        get :test_audit_log_access_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("監査ログへのアクセス権限がありません。本部管理者権限が必要です。")
      end
    end

    context "when user is pharmacist" do
      before { sign_in pharmacist }

      it "redirects with alert for pharmacist" do
        get :test_audit_log_access_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("監査ログへのアクセス権限がありません。本部管理者権限が必要です。")
      end
    end
  end

  # ============================================
  # マルチストア権限テスト
  # ============================================

  describe "#ensure_multi_store_permissions" do
    context "when user can access all stores" do
      before do
        sign_in headquarters_admin
        allow(headquarters_admin).to receive(:can_access_all_stores?).and_return(true)
      end

      it "allows access" do
        get :test_multi_store_permissions_required
        expect(response).to have_http_status(:success)
        expect(response.body).to eq("success")
      end
    end

    context "when user cannot access all stores" do
      before do
        sign_in store_manager
        allow(store_manager).to receive(:can_access_all_stores?).and_return(false)
      end

      it "redirects with alert" do
        get :test_multi_store_permissions_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("マルチストア機能へのアクセス権限がありません。")
      end
    end

    context "when store admin tries to access multi store" do
      before do
        sign_in store_admin
        allow(store_admin).to receive(:can_access_all_stores?).and_return(false)
      end

      it "redirects with alert" do
        get :test_multi_store_permissions_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to eq("マルチストア機能へのアクセス権限がありません。")
      end
    end
  end

  # ============================================
  # 権限判定ヘルパーメソッドテスト
  # ============================================

  describe "#can_manage_store?" do
    context "when user can manage store" do
      before do
        sign_in store_manager
        allow(store_manager).to receive(:can_manage_store?).with(store).and_return(true)
      end

      it "returns true" do
        get :test_can_manage_store, params: { store_id: store.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_manage"]).to be true
      end
    end

    context "when user cannot manage store" do
      before do
        sign_in pharmacist
        allow(pharmacist).to receive(:can_manage_store?).with(other_store).and_return(false)
      end

      it "returns false" do
        get :test_can_manage_store, params: { store_id: other_store.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_manage"]).to be false
      end
    end
  end

  describe "#can_view_store?" do
    context "when user can view store" do
      before do
        sign_in store_admin
        allow(store_admin).to receive(:can_view_store?).with(store).and_return(true)
      end

      it "returns true" do
        get :test_can_view_store, params: { store_id: store.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_view"]).to be true
      end
    end

    context "when user cannot view store" do
      before do
        sign_in pharmacist
        allow(pharmacist).to receive(:can_view_store?).with(other_store).and_return(false)
      end

      it "returns false" do
        get :test_can_view_store, params: { store_id: other_store.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_view"]).to be false
      end
    end
  end

  # ============================================
  # 移動申請権限判定詳細テスト
  # ============================================

  describe "#can_modify_transfer?" do
    context "when user is headquarters admin" do
      before { sign_in headquarters_admin }

      it "returns true for any transfer" do
        get :test_can_modify_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be true
      end

      it "returns true for completed transfer" do
        get :test_can_modify_transfer, params: { transfer_id: completed_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be true
      end
    end

    context "when user is the requester" do
      before { sign_in store_manager }

      it "returns true for pending transfer" do
        get :test_can_modify_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be true
      end

      it "returns true for approved transfer" do
        get :test_can_modify_transfer, params: { transfer_id: approved_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be true
      end

      it "returns false for completed transfer" do
        get :test_can_modify_transfer, params: { transfer_id: completed_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be false
      end
    end

    context "when user is source store manager but not requester" do
      let(:different_requester) { create(:admin, :store_admin, store: store) }
      let(:transfer_by_different_user) do
        create(:inter_store_transfer,
               requested_by: different_requester,
               source_store: store,
               destination_store: other_store,
               status: :pending)
      end

      before { sign_in store_manager }

      it "returns true for transfer from their store" do
        get :test_can_modify_transfer, params: { transfer_id: transfer_by_different_user.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be true
      end
    end

    context "when user is unrelated to transfer" do
      before { sign_in other_store_manager }

      it "returns false" do
        get :test_can_modify_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_modify"]).to be false
      end
    end
  end

  describe "#can_cancel_transfer?" do
    context "when user is headquarters admin" do
      before { sign_in headquarters_admin }

      it "returns true for cancellable transfer" do
        allow(pending_transfer).to receive(:can_be_cancelled?).and_return(true)
        get :test_can_cancel_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_cancel"]).to be true
      end
    end

    context "when user is the requester" do
      before { sign_in store_manager }

      it "returns true for cancellable transfer" do
        allow(pending_transfer).to receive(:can_be_cancelled?).and_return(true)
        get :test_can_cancel_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_cancel"]).to be true
      end

      it "returns false for non-cancellable transfer" do
        allow(pending_transfer).to receive(:can_be_cancelled?).and_return(false)
        get :test_can_cancel_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_cancel"]).to be false
      end
    end

    context "when user is not the requester" do
      before { sign_in other_store_manager }

      it "returns false even for cancellable transfer" do
        allow(pending_transfer).to receive(:can_be_cancelled?).and_return(true)
        get :test_can_cancel_transfer, params: { transfer_id: pending_transfer.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_cancel"]).to be false
      end
    end
  end

  # ============================================
  # 在庫ログアクセス権限判定詳細テスト
  # ============================================

  describe "#can_access_inventory_logs?" do
    context "when user is headquarters admin" do
      before { sign_in headquarters_admin }

      it "returns true for any inventory" do
        get :test_can_access_inventory_logs, params: { inventory_id: inventory.id }
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_access"]).to be true
      end

      it "returns true without specific inventory" do
        get :test_can_access_inventory_logs
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_access"]).to be true
      end
    end

    context "when user has store_id" do
      before do
        sign_in store_manager
        allow(store_manager).to receive(:store_id).and_return(store.id)
      end

      it "returns true without specific inventory" do
        get :test_can_access_inventory_logs
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_access"]).to be true
      end

      context "when inventory is in user's store" do
        before do
          allow(inventory.store_inventories).to receive(:exists?).with(store_id: store.id).and_return(true)
        end

        it "returns true" do
          get :test_can_access_inventory_logs, params: { inventory_id: inventory.id }
          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response["can_access"]).to be true
        end
      end

      context "when inventory is not in user's store" do
        before do
          allow(inventory.store_inventories).to receive(:exists?).with(store_id: store.id).and_return(false)
        end

        it "returns false" do
          get :test_can_access_inventory_logs, params: { inventory_id: inventory.id }
          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response["can_access"]).to be false
        end
      end
    end

    context "when user has no store_id" do
      before do
        sign_in store_manager
        allow(store_manager).to receive(:store_id).and_return(nil)
      end

      it "returns false" do
        get :test_can_access_inventory_logs
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response["can_access"]).to be false
      end
    end
  end

  # ============================================
  # エッジケースとエラーハンドリングテスト
  # ============================================

  describe "edge cases and error handling" do
    context "when store does not exist" do
      before { sign_in headquarters_admin }

      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :test_store_management_required, params: { store_id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when transfer does not exist" do
      before { sign_in headquarters_admin }

      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :test_transfer_modification_required, params: { transfer_id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when inventory does not exist" do
      before { sign_in headquarters_admin }

      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :test_can_access_inventory_logs, params: { inventory_id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when current_admin is nil" do
      it "raises NoMethodError" do
        expect {
          get :test_headquarters_admin_required
        }.to raise_error(NoMethodError)
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "privilege escalation attempts" do
      before { sign_in pharmacist }

      it "cannot access headquarters admin functions" do
        get :test_headquarters_admin_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to include("本部管理者のみ")
      end

      it "cannot access other store management" do
        allow(pharmacist).to receive(:can_manage_store?).with(other_store).and_return(false)
        get :test_store_management_required, params: { store_id: other_store.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to include("権限がありません")
      end

      it "cannot access audit logs" do
        get :test_audit_log_access_required
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to include("監査ログへのアクセス権限がありません")
      end
    end

    context "cross-store access attempts" do
      before { sign_in store_manager }

      it "cannot modify transfers from other stores" do
        other_transfer = create(:inter_store_transfer,
                               requested_by: other_store_manager,
                               source_store: other_store,
                               destination_store: store)

        get :test_transfer_modification_required, params: { transfer_id: other_transfer.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to include("修正する権限がありません")
      end

      it "cannot cancel transfers from other users" do
        other_transfer = create(:inter_store_transfer,
                               requested_by: other_store_manager,
                               source_store: store,
                               destination_store: other_store)

        get :test_transfer_cancellation_required, params: { transfer_id: other_transfer.id }
        expect(response).to redirect_to("/admin")
        expect(flash[:alert]).to include("キャンセルする権限がありません")
      end
    end
  end
end
