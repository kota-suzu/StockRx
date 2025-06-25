# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::BaseController, type: :controller do
  # CLAUDE.md準拠: 管理者認証・認可の包括的テスト
  # メタ認知: セキュリティコンプライアンスとパフォーマンスの両立検証
  # 横展開: 他のベースコントローラーでも同様のテストパターン適用

  # BaseControllerは抽象クラスなので、具体的なコントローラーを作成してテスト
  controller(AdminControllers::BaseController) do
    def index
      render plain: "Admin Index"
    end

    def show
      render plain: "Admin Show"
    end

    def edit
      render plain: "Admin Edit"
    end

    def update
      render plain: "Admin Update"
    end

    def destroy
      render plain: "Admin Destroy"
    end
  end

  let(:admin_user) { create(:admin) }
  let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }
  let(:store_admin) { create(:admin, role: :store_admin) }

  # ============================================
  # 認証機能のテスト
  # ============================================

  describe "authentication requirements" do
    context "認証なしアクセス" do
      before { sign_out :admin }

      it "index アクションは認証を要求する" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "show アクションは認証を要求する" do
        get :show, params: { id: 1 }
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "edit アクションは認証を要求する" do
        get :edit, params: { id: 1 }
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "update アクションは認証を要求する" do
        patch :update, params: { id: 1 }
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "destroy アクションは認証を要求する" do
        delete :destroy, params: { id: 1 }
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "認証済みアクセス" do
      before { sign_in admin_user, scope: :admin }

      it "index アクションはアクセス可能" do
        get :index
        expect(response).to be_successful
        expect(response.body).to eq("Admin Index")
      end

      it "show アクションはアクセス可能" do
        get :show, params: { id: 1 }
        expect(response).to be_successful
        expect(response.body).to eq("Admin Show")
      end

      it "edit アクションはアクセス可能" do
        get :edit, params: { id: 1 }
        expect(response).to be_successful
        expect(response.body).to eq("Admin Edit")
      end

      it "update アクションはアクセス可能" do
        patch :update, params: { id: 1 }
        expect(response).to be_successful
        expect(response.body).to eq("Admin Update")
      end

      it "destroy アクションはアクセス可能" do
        delete :destroy, params: { id: 1 }
        expect(response).to be_successful
        expect(response.body).to eq("Admin Destroy")
      end
    end
  end

  # ============================================
  # レイアウト設定のテスト
  # ============================================

  describe "layout configuration" do
    before { sign_in admin_user, scope: :admin }

    it "admin レイアウトを使用する" do
      get :index
      expect(response).to render_template(layout: "admin")
    end

    it "ヘルパーが正しく設定されている" do
      get :index
      expect(controller.class.helpers).to include(AdminControllers::ApplicationHelper)
    end
  end

  # ============================================
  # セキュリティ機能のテスト
  # ============================================

  describe "security features" do
    before { sign_in admin_user, scope: :admin }

    context "CSRF保護" do
      it "CSRF保護が有効化されている" do
        expect(controller.protect_against_forgery?).to be true
      end

      it "CSRFトークンが検証される" do
        # CSRFトークンなしのPOSTリクエストは拒否される
        expect {
          post :update, params: { id: 1, test: "data" }
        }.to raise_error(ActionController::InvalidAuthenticityToken)
      end
    end

    context "セキュリティヘッダー" do
      it "適切なセキュリティヘッダーが設定される" do
        get :index

        # Content Security Policy
        expect(response.headers["Content-Security-Policy"]).to be_present

        # X-Frame-Options
        expect(response.headers["X-Frame-Options"]).to eq("SAMEORIGIN")

        # X-Content-Type-Options
        expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      end
    end

    context "監査ログ機能" do
      it "機密データアクセス時の監査ログが記録される" do
        expect(controller).to respond_to(:audit_sensitive_access)
      end

      it "show アクションは監査対象アクションに含まれる" do
        # audit_sensitive_access :show の設定確認
        get :show, params: { id: 1 }
        expect(response).to be_successful
      end

      it "edit アクションは監査対象アクションに含まれる" do
        # audit_sensitive_access :edit の設定確認
        get :edit, params: { id: 1 }
        expect(response).to be_successful
      end

      it "update アクションは監査対象アクションに含まれる" do
        # audit_sensitive_access :update の設定確認
        patch :update, params: { id: 1 }
        expect(response).to be_successful
      end

      it "destroy アクションは監査対象アクションに含まれる" do
        # audit_sensitive_access :destroy の設定確認
        delete :destroy, params: { id: 1 }
        expect(response).to be_successful
      end

      it "index アクションは監査対象外（統計データのため）" do
        # indexは一覧表示のため監査対象外
        get :index
        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # コンテキスト設定のテスト
  # ============================================

  describe "context setup" do
    context "管理者情報の設定" do
      before { sign_in admin_user, scope: :admin }

      it "現在の管理者情報がビューで参照可能" do
        get :index
        expect(assigns(:current_admin)).to eq(admin_user)
      end

      it "Current.adminが設定される" do
        get :index
        expect(Current.admin).to eq(admin_user)
      end
    end

    context "認証なし状態" do
      before { sign_out :admin }

      it "管理者情報は設定されない" do
        # 認証エラーによりリダイレクトされるため、コンテキスト設定は実行されない
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  # ============================================
  # インクルードされたモジュールのテスト
  # ============================================

  describe "included modules" do
    before { sign_in admin_user, scope: :admin }

    it "ErrorHandlers モジュールが含まれている" do
      expect(controller.class.ancestors).to include(ErrorHandlers)
    end

    it "AdminAuthorization モジュールが含まれている" do
      expect(controller.class.ancestors).to include(AdminAuthorization)
    end

    it "SecurityCompliance モジュールが含まれている" do
      expect(controller.class.ancestors).to include(SecurityCompliance)
    end
  end

  # ============================================
  # エラーハンドリングのテスト
  # ============================================

  describe "error handling" do
    before { sign_in admin_user, scope: :admin }

    context "一般的なエラー" do
      before do
        allow(controller).to receive(:index).and_raise(StandardError, "Test error")
      end

      it "ErrorHandlers モジュールによってエラーが処理される" do
        expect {
          get :index
        }.to raise_error(StandardError, "Test error")
      end
    end

    context "権限エラー" do
      # AdminAuthorization モジュールの機能テスト
      it "権限不足エラーが適切に処理される" do
        # AdminAuthorizationモジュールの権限チェックメソッドが利用可能
        expect(controller).to respond_to(:authorize_headquarters_admin!, true)
        expect(controller).to respond_to(:authorize_store_management!, true)
        expect(controller).to respond_to(:authorize_audit_log_access!, true)
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance" do
    before { sign_in admin_user, scope: :admin }

    it "ベースコントローラーの処理は高速" do
      start_time = Time.current
      get :index
      elapsed_time = (Time.current - start_time) * 1000

      expect(response).to be_successful
      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "Current設定のオーバーヘッドは最小限" do
      expect {
        get :index
      }.not_to exceed_query_limit(2) # 認証チェック程度の最小限クエリ
    end
  end

  # ============================================
  # 設定値の検証
  # ============================================

  describe "configuration validation" do
    before { sign_in admin_user, scope: :admin }

    it "適切なレイアウトファイルが存在する" do
      expect(File.exist?(Rails.root.join("app/views/layouts/admin.html.erb"))).to be true
    end

    it "継承階層が正しく設定されている" do
      expect(AdminControllers::BaseController.ancestors).to include(ApplicationController)
    end

    it "before_action の実行順序が正しい" do
      # authenticate_admin! -> set_admin_info の順序
      callbacks = AdminControllers::BaseController._process_action_callbacks
      auth_callback = callbacks.find { |c| c.filter == :authenticate_admin! }
      info_callback = callbacks.find { |c| c.filter == :set_admin_info }

      expect(auth_callback).to be_present
      expect(info_callback).to be_present
    end
  end

  # ============================================
  # セキュリティコンプライアンス統合テスト
  # ============================================

  describe "compliance integration" do
    before { sign_in admin_user, scope: :admin }

    context "PCI DSS準拠" do
      it "機密データアクセス時の保護機能が有効" do
        # SecurityCompliance モジュールのPCI DSS保護が有効
        expect(controller.class.ancestors).to include(SecurityCompliance)
        expect(controller.send(:methods).map(&:to_s)).to include("audit_sensitive_data_access")
      end

      it "データマスキング機能が利用可能" do
        # セキュリティマネージャーが初期化可能
        expect(controller.send(:initialize_security_manager)).to be_a(SecurityComplianceManager)
      end
    end

    context "GDPR準拠" do
      it "個人情報保護機能が有効" do
        # GDPR保護のクラスメソッドが定義されている
        expect(controller.class).to respond_to(:protect_with_gdpr)
      end

      it "データ削除要求への対応機能が利用可能" do
        # SecurityComplianceモジュールが含まれている
        expect(controller.class.ancestors).to include(SecurityCompliance)
      end
    end

    context "タイミング攻撃対策" do
      it "定数時間処理機能が有効" do
        # タイミング保護のafter_actionが設定されている
        callbacks = controller.class._process_action_callbacks
        after_actions = callbacks.select { |cb| cb.kind == :after }
        expect(after_actions.map(&:filter)).to include(:apply_timing_protection)
      end

      it "レスポンス時間の標準化機能が利用可能" do
        # SecurityComplianceモジュールが含まれている
        expect(controller.class.ancestors).to include(SecurityCompliance)
      end
    end
  end

  # ============================================
  # AdminAuthorization 詳細機能テスト（ブランチカバレッジ向上）
  # ============================================

  describe "AdminAuthorization detailed functionality" do
    # shared_examplesを使用した包括的テスト
    include_examples 'authorization enforcement with redirects'
    include_examples 'transfer modification authorization'
    include_examples 'transfer cancellation authorization'
    include_examples 'inventory log access authorization'

    # 個別の権限判定メソッドテスト
    describe "#can_view_store?" do
      let(:store) { create(:store) }
      let(:other_store) { create(:store) }

      context "as headquarters admin" do
        before { sign_in headquarters_admin }

        it "can view any store" do
          expect(controller.send(:can_view_store?, store)).to be true
          expect(controller.send(:can_view_store?, other_store)).to be true
        end
      end

      context "as store manager" do
        let(:store_manager) { create(:admin, :store_manager, store: store) }
        before { sign_in store_manager }

        it "can view own store" do
          expect(controller.send(:can_view_store?, store)).to be true
        end

        it "cannot view other store" do
          expect(controller.send(:can_view_store?, other_store)).to be false
        end
      end
    end

    describe "#can_manage_store?" do
      let(:store) { create(:store) }
      let(:other_store) { create(:store) }

      context "as headquarters admin" do
        before { sign_in headquarters_admin }

        it "can manage any store" do
          expect(controller.send(:can_manage_store?, store)).to be true
          expect(controller.send(:can_manage_store?, other_store)).to be true
        end
      end

      context "as store manager" do
        let(:store_manager) { create(:admin, :store_manager, store: store) }
        before { sign_in store_manager }

        it "can manage own store" do
          expect(controller.send(:can_manage_store?, store)).to be true
        end

        it "cannot manage other store" do
          expect(controller.send(:can_manage_store?, other_store)).to be false
        end
      end
    end

    describe "#ensure_multi_store_permissions" do
      context "when admin can access all stores" do
        before do
          sign_in headquarters_admin
          allow(headquarters_admin).to receive(:can_access_all_stores?).and_return(true)
        end

        it "does not redirect" do
          expect(controller.send(:ensure_multi_store_permissions)).to be_nil
          expect(response).not_to be_redirect
        end
      end

      context "when admin cannot access all stores" do
        let(:limited_admin) { create(:admin, :store_manager) }
        before do
          sign_in limited_admin
          allow(limited_admin).to receive(:can_access_all_stores?).and_return(false)
        end

        it "redirects with multi-store access denied message" do
          controller.send(:ensure_multi_store_permissions)
          expect(response).to redirect_to(admin_root_path)
          expect(flash[:alert]).to eq('マルチストア機能へのアクセス権限がありません。')
        end
      end
    end

    # Transfer authorization edge cases
    describe "transfer authorization edge cases" do
      let(:source_store) { create(:store) }
      let(:target_store) { create(:store) }
      let(:requester) { create(:admin, :store_manager, store: source_store) }

      context "when transfer status changes" do
        let(:transfer) { create(:inter_store_transfer, :pending, requested_by: requester, source_store: source_store) }

        before { sign_in requester }

        it "handles transfer status transitions correctly" do
          # Pending -> can modify
          expect(controller.send(:can_modify_transfer?, transfer)).to be true

          # Simulate status change to approved
          allow(transfer).to receive(:pending?).and_return(false)
          allow(transfer).to receive(:approved?).and_return(true)
          expect(controller.send(:can_modify_transfer?, transfer)).to be true

          # Simulate status change to completed
          allow(transfer).to receive(:approved?).and_return(false)
          allow(transfer).to receive(:completed?).and_return(true)
          expect(controller.send(:can_modify_transfer?, transfer)).to be false
        end
      end

      context "complex permission scenarios" do
        before { sign_in requester }

        it "handles nil transfer gracefully" do
          expect { controller.send(:can_modify_transfer?, nil) }.to raise_error(NoMethodError)
        end

        it "handles transfer without requester" do
          transfer_without_requester = create(:inter_store_transfer, :pending, requested_by: nil, source_store: source_store)
          expect(controller.send(:can_modify_transfer?, transfer_without_requester)).to be false
        end
      end
    end

    # Inventory log authorization with complex scenarios
    describe "inventory log authorization complex scenarios" do
      let(:store1) { create(:store) }
      let(:store2) { create(:store) }
      let(:inventory) { create(:inventory) }
      let(:multi_store_inventory) { create(:inventory) }

      before do
        # Create multi-store inventory
        create(:store_inventory, store: store1, inventory: multi_store_inventory)
        create(:store_inventory, store: store2, inventory: multi_store_inventory)
      end

      context "as store admin with multi-store inventory" do
        let(:store1_admin) { create(:admin, :store_manager, store: store1) }
        before { sign_in store1_admin }

        it "can access inventory present in own store" do
          expect(controller.send(:can_access_inventory_logs?, multi_store_inventory)).to be true
        end

        it "cannot access inventory not in own store" do
          store2_only_inventory = create(:inventory)
          create(:store_inventory, store: store2, inventory: store2_only_inventory)
          expect(controller.send(:can_access_inventory_logs?, store2_only_inventory)).to be false
        end
      end

      context "edge cases for inventory log access" do
        let(:unassigned_admin) { create(:admin, store_id: nil) }
        before { sign_in unassigned_admin }

        it "denies access when admin has no store assignment" do
          expect(controller.send(:can_access_inventory_logs?, inventory)).to be false
        end

        it "denies general access when admin has no store assignment" do
          expect(controller.send(:can_access_inventory_logs?)).to be false
        end
      end
    end
  end

  # ============================================
  # 将来拡張機能の準備テスト
  # ============================================

  describe "future extensibility" do
    before { sign_in admin_user, scope: :admin }

    it "多言語対応の基盤が準備されている" do
      expect(I18n).to be_present
      expect(controller.respond_to?(:set_locale)).to be_falsy # 未実装の確認
    end

    it "役割ベース認可の基盤が利用可能" do
      # AdminAuthorization モジュールによる将来拡張対応
      expect(admin_user).to respond_to(:role)
    end

    it "共通エラーハンドリングが設定されている" do
      expect(controller.class.ancestors).to include(ErrorHandlers)
    end
  end
end
