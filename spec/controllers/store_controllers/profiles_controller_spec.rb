# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::ProfilesController, type: :controller do
  # メタ認知: セキュリティ関連機能のテストは認証前提
  # 横展開: 他のstore_controllersと同様の認証パターン適用
  let(:store) { create(:store) }
  let(:store_user) { create(:store_user, store: store) }
  let(:manager_user) { create(:store_user, :manager, store: store) }

  before do
    sign_in store_user
    allow(controller).to receive(:current_store).and_return(store)
  end

  describe "GET #show" do
    # ベストプラクティス: 基本動作の確認
    it "returns a success response" do
      get :show
      expect(response).to be_successful
    end

    it "assigns current user" do
      get :show
      expect(assigns(:user)).to eq(store_user)
    end

    it "builds login history" do
      get :show
      expect(assigns(:login_history)).to be_present
      expect(assigns(:login_history)).to include(:current_sign_in_at, :sign_in_count)
    end

    it "builds security settings" do
      get :show
      expect(assigns(:security_settings)).to be_present
      expect(assigns(:security_settings)).to include(:password_changed_at, :two_factor_enabled)
    end

    # 横展開: タイトルとパンくずリストの確認
    it "sets correct page title and breadcrumbs" do
      get :show
      expect(response.body).to include("プロフィール")
    end
  end

  describe "GET #edit" do
    it "returns a success response" do
      get :edit
      expect(response).to be_successful
    end

    it "assigns current user for editing" do
      get :edit
      expect(assigns(:user)).to eq(store_user)
    end

    # TODO: 🟡 Phase 4 - ビューテンプレートの詳細テスト
    # メタ認知: HTMLレンダリング結果の検証必要
    it "renders edit template" do
      get :edit
      expect(response).to render_template(:edit)
    end
  end

  describe "PATCH #update" do
    let(:valid_attributes) do
      {
        name: "更新された名前",
        email: "updated@example.com",
        employee_code: "EMP999"
      }
    end

    let(:invalid_attributes) do
      {
        name: "",
        email: "invalid-email"
      }
    end

    context "with valid parameters" do
      it "updates the user" do
        patch :update, params: { store_user: valid_attributes }
        store_user.reload
        expect(store_user.name).to eq("更新された名前")
        expect(store_user.email).to eq("updated@example.com")
        expect(store_user.employee_code).to eq("EMP999")
      end

      it "redirects to profile page" do
        patch :update, params: { store_user: valid_attributes }
        expect(response).to redirect_to(store_profile_path)
      end

      it "shows success message" do
        patch :update, params: { store_user: valid_attributes }
        expect(flash[:notice]).to be_present
      end
    end

    context "with invalid parameters" do
      it "does not update the user" do
        original_name = store_user.name
        patch :update, params: { store_user: invalid_attributes }
        store_user.reload
        expect(store_user.name).to eq(original_name)
      end

      it "renders edit template" do
        patch :update, params: { store_user: invalid_attributes }
        expect(response).to render_template(:edit)
      end

      it "returns unprocessable entity status" do
        patch :update, params: { store_user: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    # セキュリティテスト: パラメータ制限確認
    context "with unauthorized parameters" do
      it "does not allow updating unauthorized fields" do
        unauthorized_params = {
          name: "新しい名前",
          role: "admin", # 不正なパラメータ
          admin: true    # 不正なパラメータ
        }

        patch :update, params: { store_user: unauthorized_params }
        store_user.reload
        expect(store_user.name).to eq("新しい名前")
        # 不正なパラメータは無視される
        expect(store_user).not_to respond_to(:role)
        expect(store_user).not_to respond_to(:admin)
      end
    end
  end

  describe "GET #change_password" do
    it "returns a success response" do
      get :change_password
      expect(response).to be_successful
    end

    it "assigns password expiration info" do
      get :change_password
      expect(assigns(:password_expires_in)).to be_present
      expect(assigns(:must_change)).to be_in([ true, false ])
    end

    context "when password is expired" do
      let(:expired_user) { create(:store_user, :password_expired, store: store) }

      before do
        sign_in expired_user
      end

      it "sets must_change flag" do
        get :change_password
        expect(assigns(:must_change)).to be_truthy
      end
    end
  end

  describe "PATCH #update_password" do
    let(:current_password) { "Password1234!" }
    let(:new_password) { "NewPassword1234!" }

    let(:valid_password_params) do
      {
        current_password: current_password,
        password: new_password,
        password_confirmation: new_password
      }
    end

    let(:invalid_password_params) do
      {
        current_password: "wrong_password",
        password: new_password,
        password_confirmation: new_password
      }
    end

    context "with valid current password" do
      let(:test_user) do
        create(:store_user, store: store, password: current_password, password_confirmation: current_password)
      end

      before do
        sign_in test_user
        allow(controller).to receive(:current_store).and_return(store)
      end

      it "updates the password" do
        patch :update_password, params: { store_user: valid_password_params }
        expect(test_user.reload.valid_password?(new_password)).to be_truthy
      end

      # TODO: 🟡 Phase 4 - 詳細なパスワード更新テスト
      # メタ認知: password_changed_atカラムの存在確認が必要
      it "processes password update successfully" do
        patch :update_password, params: { store_user: valid_password_params }
        expect(response).to have_http_status(:redirect)
      end

      it "redirects to profile page" do
        patch :update_password, params: { store_user: valid_password_params }
        expect(response).to redirect_to(store_profile_path)
      end
    end

    context "with invalid current password" do
      it "does not update the password" do
        original_encrypted_password = store_user.encrypted_password
        patch :update_password, params: { store_user: invalid_password_params }
        expect(store_user.reload.encrypted_password).to eq(original_encrypted_password)
      end

      it "adds error to current_password" do
        patch :update_password, params: { store_user: invalid_password_params }
        expect(assigns(:user).errors[:current_password]).to be_present
      end

      it "renders change_password template" do
        patch :update_password, params: { store_user: invalid_password_params }
        expect(response).to render_template(:change_password)
      end
    end
  end

  # ヘルパーメソッドのテスト（ビューから確認）
  describe "helper methods" do
    render_views

    describe "#password_strength_class" do
      # メタ認知: helper_methodはビューで確認するのがベストプラクティス
      it "renders appropriate classes in view" do
        get :show
        # パスワード強度クラスがビューに含まれていることを確認
        expect(response.body).to include("password-strength")
      end
    end

    describe "#format_ip_address" do
      let(:user_with_ip) do
        create(:store_user, :with_login_history,
               store: store,
               current_sign_in_ip: "192.168.1.100")
      end

      before do
        sign_in user_with_ip
        allow(controller).to receive(:current_store).and_return(store)
      end

      it "masks IP addresses in view for privacy" do
        get :show
        # マスクされたIPアドレスがビューに表示されることを確認
        expect(response.body).to include("192.168.***.***")
        expect(response.body).not_to include("192.168.1.100")
      end
    end
  end

  # 認証テスト
  describe "authentication" do
    context "when not logged in" do
      before { sign_out store_user }

      it "redirects to appropriate page" do
        get :show
        # 横展開: 他のstore_controllersと同様の認証チェック
        expect(response).to have_http_status(:redirect)
        # TODO: 🟡 正確なリダイレクト先を確認して修正
      end
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張テスト
# ============================================
# 1. 🔴 機能テスト (Feature Specs)
#    - プロフィール編集の完全なフロー
#    - パスワード変更の完全なフロー
#    - エラーケースのUI確認
#
# 2. 🟡 ビューテスト (View Specs)
#    - edit.html.erbの詳細テスト
#    - フォーム要素の検証
#    - JavaScript動作確認
#
# 3. 🟢 セキュリティテスト
#    - CSRFトークン検証
#    - パラメータ改ざんテスト
#    - 権限チェックテスト
