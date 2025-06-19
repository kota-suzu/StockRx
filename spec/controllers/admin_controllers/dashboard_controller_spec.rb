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

      # カバレッジ向上: 詳細な統計データテスト
      context 'with test data' do
        let!(:store1) { create(:store) }
        let!(:store2) { create(:store) }
        let!(:inventory1) { create(:inventory, name: 'アスピリン錠', price: 100) }
        let!(:inventory2) { create(:inventory, name: '血圧計', price: 5000) }
        let!(:inventory3) { create(:inventory, name: 'ガーゼ', price: 50) }

        before do
          # 店舗在庫設定（低在庫商品を含む）
          create(:store_inventory, store: store1, inventory: inventory1, quantity: 100, safety_stock_level: 20)
          create(:store_inventory, store: store1, inventory: inventory2, quantity: 5, safety_stock_level: 10) # 低在庫
          create(:store_inventory, store: store2, inventory: inventory3, quantity: 200, safety_stock_level: 50)
        end

        it '正確な統計データを計算すること' do
          get :index
          stats = assigns(:stats)

          expect(stats[:total_inventories]).to eq(3)
          expect(stats[:low_stock_count]).to eq(1) # inventory2のみ低在庫
          expect(stats[:total_inventory_value]).to eq(inventory1.price + inventory2.price + inventory3.price)
        end

        it '在庫アラートを適切に識別すること' do
          get :index
          stats = assigns(:stats)

          # 低在庫商品が正しくカウントされていることを確認
          expect(stats[:low_stock_items]).to be_present
          low_stock_names = stats[:low_stock_items].map { |item| item[:name] }
          expect(low_stock_names).to include('血圧計')
          expect(low_stock_names).not_to include('アスピリン錠', 'ガーゼ')
        end
      end

      # カバレッジ向上: パフォーマンステスト
      context 'performance considerations' do
        before do
          # 大量データ作成（テスト環境を考慮して数を制限）
          stores = create_list(:store, 5)
          inventories = create_list(:inventory, 20)

          stores.each do |store|
            inventories.each do |inventory|
              create(:store_inventory, store: store, inventory: inventory, quantity: rand(0..100))
            end
          end
        end

        it 'ダッシュボード読み込みが効率的に動作すること' do
          expect {
            get :index
          }.to perform_under(500).ms
        end

        it 'N+1クエリが発生しないこと' do
          expect {
            get :index
          }.not_to exceed_query_limit(10)
        end
      end

      # カバレッジ向上: エラーハンドリング
      context 'error handling' do
        it 'データベースエラー時でも適切に処理すること' do
          # ActiveRecord::StatementInvalidをシミュレート
          allow(Inventory).to receive(:count).and_raise(ActiveRecord::StatementInvalid.new('Database error'))

          expect {
            get :index
          }.not_to raise_error

          expect(response).to be_successful
          stats = assigns(:stats)
          expect(stats[:total_inventories]).to eq(0) # フォールバック値
        end
      end

      # カバレッジ向上: レスポンス形式テスト
      context 'response formats' do
        it 'JSON形式で統計データを返すこと' do
          get :index, format: :json

          expect(response).to be_successful
          expect(response.content_type).to include('application/json')

          json_response = JSON.parse(response.body)
          expect(json_response).to include('stats')
          expect(json_response['stats']).to include(
            'total_inventories',
            'low_stock_count',
            'total_inventory_value'
          )
        end
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
