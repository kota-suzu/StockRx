# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InterStoreTransfersController, type: :controller do
  # CLAUDE.md準拠: 店舗間移動管理機能のテスト品質向上
  # メタ認知: analytics機能のTypeError修正とデータ構造整合性確保
  # 横展開: 他の統計表示機能でも同様のテスト構造を適用

  let(:admin) { create(:admin) }
  let(:source_store) { create(:store, name: "本店") }
  let(:destination_store) { create(:store, name: "支店") }
  let(:inventory) { create(:inventory) }

  before do
    sign_in admin, scope: :admin
  end

  describe "GET #analytics" do
    context "with valid admin authentication" do
      it "returns a success response" do
        get :analytics
        expect(response).to be_successful
      end

      it "assigns analytics data with correct structure" do
        get :analytics
        
        expect(assigns(:analytics)).to be_present
        expect(assigns(:store_analytics)).to be_an(Array)
        expect(assigns(:trend_data)).to be_present
        expect(assigns(:period)).to be_present
      end

      it "handles store_analytics as array structure for view compatibility" do
        # 店舗とサンプルデータを作成
        create_list(:store, 3)
        
        get :analytics
        
        store_analytics = assigns(:store_analytics)
        expect(store_analytics).to be_an(Array)
        
        if store_analytics.any?
          store_data = store_analytics.first
          expect(store_data).to have_key(:store)
          expect(store_data).to have_key(:stats)
          expect(store_data[:stats]).to be_a(Hash)
        end
      end

      context "with period parameter" do
        it "accepts valid period parameter" do
          get :analytics, params: { period: 7 }
          expect(assigns(:period)).to eq(7.days.ago.to_date)
        end

        it "uses default period for invalid parameters" do
          get :analytics, params: { period: -1 }
          expect(assigns(:period)).to eq(30.days.ago.to_date)
        end

        it "uses default period for excessive parameters" do
          get :analytics, params: { period: 400 }
          expect(assigns(:period)).to eq(30.days.ago.to_date)
        end
      end

      context "with transfer data" do
        before do
          # テスト用の移動データを作成
          @transfer1 = create(:inter_store_transfer, 
                             source_store: source_store,
                             destination_store: destination_store,
                             inventory: inventory,
                             status: :completed,
                             requested_at: 15.days.ago,
                             completed_at: 14.days.ago)
          
          @transfer2 = create(:inter_store_transfer,
                             source_store: destination_store,
                             destination_store: source_store,
                             inventory: inventory,
                             status: :pending,
                             requested_at: 5.days.ago)
        end

        it "calculates store analytics correctly" do
          get :analytics
          
          store_analytics = assigns(:store_analytics)
          expect(store_analytics).not_to be_empty
          
          # 各店舗のデータが正しい構造を持つことを確認
          store_analytics.each do |store_data|
            expect(store_data[:store]).to be_a(Store)
            stats = store_data[:stats]
            
            expect(stats).to include(:outgoing_count, :incoming_count, 
                                   :outgoing_completed, :incoming_completed,
                                   :net_flow, :approval_rate, :efficiency_score)
            expect(stats[:outgoing_count]).to be_a(Integer)
            expect(stats[:incoming_count]).to be_a(Integer)
            expect(stats[:approval_rate]).to be_a(Numeric)
            expect(stats[:efficiency_score]).to be_a(Numeric)
          end
        end
      end
    end

    context "without authentication" do
      before { sign_out admin }

      it "redirects to sign in page" do
        get :analytics
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "when errors occur during calculation" do
      before do
        # エラーを発生させるためのモック
        allow(InterStoreTransfer).to receive(:transfer_analytics).and_raise(StandardError, "Test error")
      end

      it "handles errors gracefully and provides fallback data" do
        get :analytics
        
        expect(response).to be_successful
        expect(assigns(:analytics)).to eq({})
        expect(assigns(:store_analytics)).to eq([])
        expect(assigns(:trend_data)).to eq({})
        expect(flash.now[:alert]).to include("分析データの取得中にエラーが発生しました")
      end
    end
  end

  describe "private methods" do
    describe "#calculate_store_transfer_analytics" do
      let(:period) { 30.days.ago }

      context "with stores and transfers" do
        before do
          @stores = create_list(:store, 2)
          @transfers = create_list(:inter_store_transfer, 3, 
                                  source_store: @stores.first,
                                  destination_store: @stores.last,
                                  requested_at: 15.days.ago)
        end

        it "returns array structure suitable for view" do
          analytics = controller.send(:calculate_store_transfer_analytics, period)
          
          expect(analytics).to be_an(Array)
          expect(analytics.length).to eq(Store.active.count)
          
          analytics.each do |store_data|
            expect(store_data).to have_key(:store)
            expect(store_data).to have_key(:stats)
            expect(store_data[:store]).to be_a(Store)
            expect(store_data[:stats]).to be_a(Hash)
          end
        end
      end
    end

    describe "#calculate_store_efficiency" do
      it "calculates efficiency score correctly" do
        # モックデータでのテスト
        outgoing = double("outgoing_transfers", 
                         count: 10, 
                         where: double(count: 8))
        incoming = double("incoming_transfers", 
                         count: 5, 
                         where: double(count: 4))

        efficiency = controller.send(:calculate_store_efficiency, outgoing, incoming)
        
        expect(efficiency).to be_a(Numeric)
        expect(efficiency).to be_between(0, 100)
      end

      it "handles zero transfers gracefully" do
        outgoing = double("outgoing_transfers", count: 0)
        incoming = double("incoming_transfers", count: 0)

        efficiency = controller.send(:calculate_store_efficiency, outgoing, incoming)
        expect(efficiency).to eq(0)
      end
    end

    # CLAUDE.md準拠: パフォーマンス最適化メソッドのテスト
    # メタ認知: システムリマインダーで確認された新機能のテスト実装
    # 横展開: 他のパフォーマンス最適化実装でも同様のテスト構造適用
    describe "performance optimization methods" do
      let(:sample_transfers) do
        [
          double("transfer", status: "completed", completed_at: 2.hours.ago, requested_at: 1.day.ago, inventory: double("inventory")),
          double("transfer", status: "approved", completed_at: nil, requested_at: 2.days.ago, inventory: double("inventory")),
          double("transfer", status: "pending", completed_at: nil, requested_at: 3.days.ago, inventory: double("inventory"))
        ]
      end

      describe "#calculate_store_efficiency_from_arrays" do
        it "calculates efficiency from transfer arrays" do
          outgoing = [sample_transfers[0], sample_transfers[1]]
          incoming = [sample_transfers[2]]

          efficiency = controller.send(:calculate_store_efficiency_from_arrays, outgoing, incoming)
          
          expect(efficiency).to be_a(Numeric)
          expect(efficiency).to be_between(0, 100)
        end

        it "handles empty arrays" do
          efficiency = controller.send(:calculate_store_efficiency_from_arrays, [], [])
          expect(efficiency).to eq(0)
        end
      end

      describe "#calculate_approval_rate_from_array" do
        it "calculates approval rate from transfer array" do
          rate = controller.send(:calculate_approval_rate_from_array, sample_transfers)
          
          expect(rate).to be_a(Numeric)
          expect(rate).to be_between(0, 100)
          # 3件中2件がapproved/completed
          expect(rate).to eq(66.7)
        end

        it "handles empty array" do
          rate = controller.send(:calculate_approval_rate_from_array, [])
          expect(rate).to eq(0)
        end
      end

      describe "#calculate_average_completion_time_from_array" do
        let(:completed_transfers) do
          [
            double("transfer", completed_at: 2.hours.ago, requested_at: 1.day.ago),
            double("transfer", completed_at: 1.hour.ago, requested_at: 12.hours.ago)
          ]
        end

        it "calculates average completion time from transfer array" do
          avg_time = controller.send(:calculate_average_completion_time_from_array, completed_transfers)
          
          expect(avg_time).to be_a(Numeric)
          expect(avg_time).to be > 0
        end

        it "handles transfers without completion time" do
          invalid_transfers = [double("transfer", completed_at: nil, requested_at: 1.day.ago)]
          avg_time = controller.send(:calculate_average_completion_time_from_array, invalid_transfers)
          
          expect(avg_time).to eq(0)
        end

        it "handles empty array" do
          avg_time = controller.send(:calculate_average_completion_time_from_array, [])
          expect(avg_time).to eq(0)
        end
      end

      describe "#calculate_most_transferred_items_from_array" do
        let(:inventory1) { double("inventory1", name: "商品A") }
        let(:inventory2) { double("inventory2", name: "商品B") }
        let(:transfers_with_items) do
          [
            double("transfer", inventory: inventory1),
            double("transfer", inventory: inventory1),
            double("transfer", inventory: inventory2),
            double("transfer", inventory: inventory1)
          ]
        end

        it "returns most transferred items from transfer array" do
          result = controller.send(:calculate_most_transferred_items_from_array, transfers_with_items)
          
          expect(result).to be_an(Array)
          expect(result.length).to be <= 3
          
          if result.any?
            top_item = result.first
            expect(top_item).to have_key(:inventory)
            expect(top_item).to have_key(:count)
            expect(top_item[:count]).to eq(3) # inventory1が3回
          end
        end

        it "handles empty array" do
          result = controller.send(:calculate_most_transferred_items_from_array, [])
          expect(result).to eq([])
        end
      end
    end
  end

  # TODO: 🟡 Phase 3（中）- 統合テスト強化
  # 優先度: 中（基本機能は動作確認済み）
  # 実装内容: 
  #   - 大量データでのパフォーマンステスト
  #   - エッジケース（空データ、異常値）のテスト
  #   - セキュリティテスト（権限チェック）
  # 期待効果: 本番環境での安定性保証
  # 工数見積: 2-3日
  # 依存関係: テストデータ充実化、権限機能実装

  describe "performance considerations" do
    # TODO: 🟢 Phase 4（推奨）- N+1クエリ防止テスト
    # 優先度: 低（includes使用済み）
    # 実装内容: Bulletと連携したクエリ数監視
    # 理由: パフォーマンス回帰防止
    # 期待効果: レスポンス時間維持
    # 工数見積: 1日
    # 依存関係: Bullet gem設定

    it "loads analytics efficiently without excessive queries" do
      create_list(:store, 5)
      create_list(:inter_store_transfer, 10)

      expect { get :analytics }.not_to exceed_query_limit(20)
    end
  end

  # CLAUDE.md準拠: 原因となったNoMethodErrorの回帰防止テスト
  # メタ認知: edit_admin_inter_store_transfer_pathエラーの特化テスト
  # 横展開: 他のルーティングヘルパーでも同様のテスト実装
  describe "routing helpers validation" do
    it "edit_admin_inter_store_transfer_path exists and generates correct path" do
      transfer = create(:inter_store_transfer, source_store: source_store, destination_store: destination_store, inventory: inventory)
      
      # ルーティングヘルパーの存在確認
      expect(controller.helpers).to respond_to(:edit_admin_inter_store_transfer_path)
      
      # 正しいパス生成確認
      path = controller.helpers.edit_admin_inter_store_transfer_path(transfer)
      expect(path).to eq("/admin/transfers/#{transfer.id}/edit")
    end

    it "all inter_store_transfer routing helpers are available" do
      transfer = create(:inter_store_transfer, source_store: source_store, destination_store: destination_store, inventory: inventory)
      
      helpers = controller.helpers
      expect(helpers).to respond_to(:admin_inter_store_transfers_path)
      expect(helpers).to respond_to(:admin_inter_store_transfer_path)
      expect(helpers).to respond_to(:new_admin_inter_store_transfer_path)
      expect(helpers).to respond_to(:edit_admin_inter_store_transfer_path)
      
      # パス生成テスト
      expect(helpers.admin_inter_store_transfers_path).to eq("/admin/transfers")
      expect(helpers.admin_inter_store_transfer_path(transfer)).to eq("/admin/transfers/#{transfer.id}")
      expect(helpers.new_admin_inter_store_transfer_path).to eq("/admin/transfers/new")
      expect(helpers.edit_admin_inter_store_transfer_path(transfer)).to eq("/admin/transfers/#{transfer.id}/edit")
    end
  end
end