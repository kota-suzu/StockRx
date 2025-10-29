# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Controllers Performance", type: :request do
  describe "N+1 Query Detection" do
    let(:admin) { create(:admin) }
    let(:store) { create(:store) }
    let!(:inventories) { create_list(:inventory, 5) }
    let!(:store_inventories) do
      inventories.map do |inventory|
        create(:store_inventory, store: store, inventory: inventory)
      end
    end

    before do
      sign_in admin
      # Counter Cache更新
      Store.reset_counters(store.id, :store_inventories)
      inventories.each do |inventory|
        Inventory.reset_counters(inventory.id, :batches)
      end
    end

    context "AdminControllers::InventoriesController" do
      describe "GET /admin/inventories" do
        it "does not have N+1 queries" do
          # ウォームアップクエリ
          get admin_inventories_path

          expect {
            get admin_inventories_path
          }.not_to exceed_query_limit(10)  # 基準値は調整が必要
        end

        it "efficiently loads inventory data" do
          control_query_count = 0

          # 1件での計測
          expect {
            get admin_inventories_path
            control_query_count = ActiveRecord::Base.connection.query_cache.size
          }.to perform_constant_number_of_queries

          # 10件追加
          create_list(:inventory, 10)

          # クエリ数が大幅に増えないことを確認
          expect {
            get admin_inventories_path
          }.not_to exceed_query_limit(control_query_count + 3)
        end
      end

      describe "GET /admin/inventories/:id" do
        let(:inventory) { inventories.first }
        let!(:batches) { create_list(:batch, 3, inventory: inventory) }

        it "efficiently loads inventory with associations" do
          expect {
            get admin_inventory_path(inventory)
          }.not_to exceed_query_limit(5)
        end
      end
    end

    context "AdminControllers::DashboardController" do
      describe "GET /admin/dashboard" do
        let!(:inventory_logs) { create_list(:inventory_log, 5, inventory: inventories.first) }

        it "does not have N+1 queries for dashboard statistics" do
          # ウォームアップ
          get admin_dashboard_path

          expect {
            get admin_dashboard_path
          }.not_to exceed_query_limit(15)  # ダッシュボードは複雑なので少し多め
        end

        it "efficiently calculates statistics" do
          # 統計計算が重くないことを確認
          expect {
            get admin_dashboard_path
          }.to perform_under(200).ms
        end
      end
    end

    context "StoreControllers::DashboardController" do
      let(:store_user) { create(:store_user, store: store) }

      before do
        sign_in store_user
      end

      describe "GET /stores/dashboard" do
        let!(:transfers) do
          create_list(:inter_store_transfer, 3,
                     source_store: store,
                     destination_store: create(:store))
        end

        it "does not have N+1 queries for alerts and transfers" do
          # ウォームアップ
          get store_dashboard_path

          expect {
            get store_dashboard_path
          }.not_to exceed_query_limit(20)
        end

        it "efficiently loads inventory alerts" do
          # 低在庫アイテムを追加
          store_inventories.each do |si|
            si.update!(quantity: 5, safety_stock_level: 10)
          end

          expect {
            get store_dashboard_path
          }.to perform_under(300).ms
        end
      end
    end

    context "AdminControllers::StoresController" do
      describe "GET /admin/stores" do
        let!(:stores) { create_list(:store, 5) }

        it "uses counter cache effectively" do
          stores.each do |s|
            create_list(:store_inventory, 3, store: s)
            Store.reset_counters(s.id, :store_inventories)
          end

          expect {
            get admin_stores_path
          }.not_to exceed_query_limit(5)  # Counter Cache使用で少ないクエリ数
        end
      end

      describe "GET /admin/stores/:id" do
        it "efficiently loads store details" do
          create_list(:store_inventory, 10, store: store)

          expect {
            get admin_store_path(store)
          }.not_to exceed_query_limit(10)
        end
      end
    end

    context "Api::V1::InventoriesController" do
      describe "GET /api/v1/inventories" do
        it "efficiently loads inventory list with search" do
          # APIトークン設定（必要に応じて）
          headers = { "Accept" => "application/json" }

          expect {
            get api_v1_inventories_path, headers: headers
          }.not_to exceed_query_limit(8)
        end

        it "handles pagination efficiently" do
          create_list(:inventory, 50)

          headers = { "Accept" => "application/json" }

          expect {
            get api_v1_inventories_path(page: 2, per_page: 20), headers: headers
          }.not_to exceed_query_limit(8)
        end
      end
    end
  end

  describe "Response Time Measurement" do
    let(:admin) { create(:admin) }

    before do
      sign_in admin
      # テストデータの準備
      create_list(:inventory, 100)
      create_list(:store, 10)
    end

    it "measures controller response times" do
      response_times = {}

      # AdminControllers
      response_times[:admin_inventories_index] = measure_response_time { get admin_inventories_path }
      response_times[:admin_dashboard] = measure_response_time { get admin_dashboard_path }
      response_times[:admin_stores_index] = measure_response_time { get admin_stores_path }

      # API
      headers = { "Accept" => "application/json" }
      response_times[:api_inventories] = measure_response_time { get api_v1_inventories_path, headers: headers }

      # レポート出力
      puts "\n=== Response Time Report ==="
      response_times.each do |endpoint, time|
        puts "#{endpoint}: #{time.round(2)}ms"
      end
      puts "==========================="

      # 基準値チェック
      expect(response_times[:admin_inventories_index]).to be < 200
      expect(response_times[:admin_dashboard]).to be < 300
      expect(response_times[:api_inventories]).to be < 150
    end
  end

  private

  def measure_response_time(&block)
    start_time = Time.current
    yield
    (Time.current - start_time) * 1000  # ミリ秒に変換
  end
end
