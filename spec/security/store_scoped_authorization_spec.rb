# frozen_string_literal: true

require 'rails_helper'

# QAレビュー対応: 店舗スコープ認可テスト
# Critical Issue #1: 店舗間アクセス制御の完全実装
RSpec.describe "StoreScopedAuthorization", type: :request do
  let(:store1) { create(:store, name: "Store 1") }
  let(:store2) { create(:store, name: "Store 2") }
  let(:manager1) { create(:store_user, store: store1, role: 'manager') }
  let(:manager2) { create(:store_user, store: store2, role: 'manager') }
  let(:supervisor) { create(:store_user, store: store1, role: 'supervisor') }

  let(:inventory1) { create(:inventory, name: "Inventory 1") }
  let(:inventory2) { create(:inventory, name: "Inventory 2") }

  let!(:store_inventory1) { create(:store_inventory, store: store1, inventory: inventory1) }
  let!(:store_inventory2) { create(:store_inventory, store: store2, inventory: inventory2) }

  describe "店舗間アクセス制御" do
    context "通常の店舗ユーザー" do
      before { sign_in manager1 }

      it "自店舗の在庫にのみアクセス可能" do
        get store_inventory_path(inventory1)
        expect(response).to have_http_status(:success)
      end

      it "他店舗の在庫へのアクセスを拒否" do
        get store_inventory_path(inventory2)
        expect(response).to have_http_status(:not_found)
      end

      it "在庫調整で自店舗のみ許可" do
        post adjust_store_inventory_path(inventory1), params: {
          adjustment: { new_quantity: 100, reason: "Test adjustment" }
        }
        expect(response).to redirect_to(store_inventory_path(inventory1))
      end

      it "他店舗在庫の調整を拒否" do
        post adjust_store_inventory_path(inventory2), params: {
          adjustment: { new_quantity: 100, reason: "Test adjustment" }
        }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "スーパーバイザー権限" do
      before { sign_in supervisor }

      it "全店舗の在庫にアクセス可能" do
        get store_inventory_path(inventory1)
        expect(response).to have_http_status(:success)

        get store_inventory_path(inventory2)
        expect(response).to have_http_status(:success)
      end

      it "全店舗の在庫を調整可能" do
        post adjust_store_inventory_path(inventory1), params: {
          adjustment: { new_quantity: 100, reason: "Supervisor adjustment" }
        }
        expect(response).to redirect_to(store_inventory_path(inventory1))

        post adjust_store_inventory_path(inventory2), params: {
          adjustment: { new_quantity: 50, reason: "Supervisor adjustment" }
        }
        expect(response).to redirect_to(store_inventory_path(inventory2))
      end
    end

    context "権限昇格攻撃対策" do
      before { sign_in manager1 }

      it "URLパラメータでstore_idを改ざんしても無効" do
        post adjust_store_inventory_path(inventory1), params: {
          adjustment: { new_quantity: 100, reason: "Test" },
          store_id: store2.id  # 他店舗IDを注入
        }

        # 自店舗の在庫が更新される
        store_inventory1.reload
        expect(store_inventory1.quantity).to eq(100)

        # 他店舗の在庫は変更されない
        store_inventory2.reload
        expect(store_inventory2.quantity).not_to eq(100)
      end

      it "不正な権限パラメータを無視" do
        post adjust_store_inventory_path(inventory1), params: {
          adjustment: { new_quantity: 100, reason: "Test" },
          is_supervisor: true,
          admin_override: true
        }

        # ユーザーの権限は変更されない
        expect(manager1.reload.role).to eq('manager')
      end
    end
  end

  describe "認可ログ記録" do
    before { sign_in manager1 }

    it "正常なアクセスを記録" do
      expect {
        get store_inventory_path(inventory1)
      }.to change(AuthorizationLog, :count).by(1)

      log = AuthorizationLog.last
      expect(log.user_type).to eq('StoreUser')
      expect(log.user_id).to eq(manager1.id)
      expect(log.store_id).to eq(store1.id)
      expect(log.authorized).to be true
    end

    it "不正アクセス試行を記録" do
      expect {
        get store_inventory_path(inventory2)
      }.to change(SecurityEventLog, :count).by(1)

      log = SecurityEventLog.last
      expect(log.event_type).to eq('unauthorized_access')
      expect(log.reason).to eq(:inventory_not_in_store)
    end
  end

  describe "機密情報マスキング" do
    let(:test_params) do
      {
        adjustment: {
          new_quantity: 100,
          reason: "Test with email user@example.com and phone 090-1234-5678"
        },
        secret_token: "abc123def456"
      }
    end

    before { sign_in manager1 }

    it "ログで機密情報をマスキング" do
      expect(Rails.logger).to receive(:info) do |message|
        expect(message).to include('use***@example.com')
        expect(message).not_to include('user@example.com')
        expect(message).to include('[FILTERED]')
        expect(message).not_to include('abc123def456')
      end

      post adjust_store_inventory_path(inventory1), params: test_params
    end
  end

  describe "エラーレスポンスの安全化" do
    before { sign_in manager1 }

    it "詳細なエラー情報を隠す" do
      get store_inventory_path(inventory2)

      expect(response.body).not_to include(store2.name)
      expect(response.body).not_to include('StoreInventory')
      expect(response.body).not_to include(inventory2.name)
    end

    it "セキュリティエラーで最小限の情報のみ返す" do
      allow_any_instance_of(StoreScopedAuthorization).to receive(:verify_store_access!)
        .and_raise(SecurityError, "Detailed security error with sensitive info")

      get store_inventory_path(inventory1)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to eq("Security Error")
    end
  end

  describe "セッション攻撃対策" do
    it "CSRF攻撃を防ぐ" do
      sign_in manager1

      # CSRFトークンなしのリクエスト
      expect {
        post adjust_store_inventory_path(inventory1), params: {
          adjustment: { new_quantity: 100, reason: "CSRF test" }
        }, headers: { 'HTTP_X_CSRF_TOKEN' => 'invalid_token' }
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "セッション固定攻撃を防ぐ" do
      initial_session_id = nil

      # 初期セッションID記録
      post new_store_user_session_path
      initial_session_id = session.id

      # ログイン
      post store_user_session_path, params: {
        store_user: { email: manager1.email, password: 'password' }
      }

      # セッションIDが変更されている
      expect(session.id).not_to eq(initial_session_id)
    end
  end

  describe "セキュリティヘッダー" do
    before { sign_in manager1 }

    it "必要なセキュリティヘッダーが設定される" do
      get store_inventory_path(inventory1)

      expect(response.headers['X-Frame-Options']).to eq('DENY')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['X-XSS-Protection']).to eq('1; mode=block')
      expect(response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
      expect(response.headers['Content-Security-Policy']).to be_present
    end

    it "CSPが適切に設定される" do
      get store_inventory_path(inventory1)

      csp = response.headers['Content-Security-Policy']
      expect(csp).to include("default-src 'self'")
      expect(csp).to include("frame-src 'none'")
      expect(csp).to include("object-src 'none'")
    end
  end

  describe "レート制限" do
    before { sign_in manager1 }

    it "通常のリクエストを許可" do
      5.times do
        get store_inventory_path(inventory1)
        expect(response).to have_http_status(:success)
      end
    end

    it "大量のリクエストを制限" do
      # Note: 実際のレート制限実装に依存
      # 100回のリクエストで制限されることを確認
      expect {
        100.times { get store_inventory_path(inventory1) }
      }.to eventually_raise(an_instance_of(ActionController::TooManyRequests))
    end
  end

  # ヘルパーメソッドのテスト
  describe "セキュリティヘルパーメソッド" do
    let(:controller) { StoreControllers::InventoriesController.new }

    before do
      allow(controller).to receive(:current_store_user).and_return(manager1)
      allow(controller).to receive(:current_store).and_return(store1)
    end

    describe "#authorized_for_store?" do
      it "所属店舗へのアクセスを許可" do
        expect(controller.send(:authorized_for_store?, store1.id)).to be true
      end

      it "他店舗へのアクセスを拒否" do
        expect(controller.send(:authorized_for_store?, store2.id)).to be false
      end
    end

    describe "#belongs_to_current_store?" do
      it "店舗に属するリソースを判定" do
        expect(controller.send(:belongs_to_current_store?, store_inventory1)).to be true
        expect(controller.send(:belongs_to_current_store?, store_inventory2)).to be false
      end
    end

    describe "#store_manager?" do
      it "管理者権限を正しく判定" do
        expect(controller.send(:store_manager?)).to be true
      end

      it "一般ユーザーを正しく判定" do
        staff = create(:store_user, store: store1, role: 'staff')
        allow(controller).to receive(:current_store_user).and_return(staff)
        expect(controller.send(:store_manager?)).to be false
      end
    end
  end
end

# カスタムマッチャー
RSpec::Matchers.define :eventually_raise do |expected_exception|
  match do |block|
    attempts = 0
    max_attempts = 10

    begin
      block.call
      attempts += 1
    rescue expected_exception
      return true
    rescue => e
      if attempts < max_attempts
        attempts += 1
        retry
      else
        return false
      end
    end

    false
  end
end
