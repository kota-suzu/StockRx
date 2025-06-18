# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::DashboardController, type: :controller do
  # CLAUDE.md準拠: テスト品質向上とカバレッジ改善
  # メタ認知: 管理者ダッシュボードの基本機能とセキュリティ設定を確認
  # 横展開: 他のAdminControllersでも同様のテスト構造を適用

  let(:admin) { create(:admin) }

  before do
    sign_in admin, scope: :admin
  end

  describe "GET #index" do
    # TODO: 🟡 Phase 3（中）- 統計データ詳細テスト
    # 優先度: 中（基本動作は確認済み）
    # 実装内容: 統計計算の正確性、パフォーマンス、エラーハンドリング
    # 理由: データの整合性とパフォーマンス保証
    # 期待効果: 品質向上、回帰テスト強化
    # 工数見積: 2-3日
    # 依存関係: テストデータ充実化

    context "with valid admin authentication" do
      it "returns a success response" do
        get :index
        expect(response).to be_successful
      end

      it "assigns dashboard statistics" do
        get :index
        expect(assigns(:stats)).to be_present
        expect(assigns(:stats)).to include(
          :total_inventories,
          :low_stock_count,
          :total_inventory_value
        )
      end

      it "assigns recent activities" do
        get :index
        expect(assigns(:recent_logs)).to be_present
      end
    end

    context "without authentication" do
      before { sign_out admin }

      it "redirects to sign in page" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  describe "security compliance" do
    it "skips audit_sensitive_data_access callback" do
      # メタ認知: ダッシュボードは統計表示のみで機密データ操作なし
      # コールバックがスキップされていることを確認
      callbacks = controller.class._process_action_callbacks
      audit_callbacks = callbacks.select { |cb| cb.filter == :audit_sensitive_data_access }
      
      # DashboardControllerではskip_around_actionが適用されているため
      # audit_sensitive_data_accessコールバックは実行されない
      expect(audit_callbacks).to be_empty
    end
  end

  describe "performance optimization" do
    # TODO: 🟢 Phase 4（推奨）- N+1クエリ防止テスト
    # 優先度: 低（Counter Cache実装済み）
    # 実装内容: Bulletと連携したクエリ数監視
    # 理由: パフォーマンス回帰防止
    # 期待効果: レスポンス時間維持
    # 工数見積: 1日
    # 依存関係: Bullet gem設定

    it "loads dashboard efficiently without N+1 queries" do
      # 基本的なクエリ効率性テスト
      expect { get :index }.not_to exceed_query_limit(10)
    end
  end
end