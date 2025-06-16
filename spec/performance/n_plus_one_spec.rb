# frozen_string_literal: true

require "rails_helper"

# TODO: 🔴 Phase 1（緊急）- N+1クエリ検出テストの完全実装
# 優先度: 高（パフォーマンス監視基盤）
# 実装内容:
#   - 各コントローラーアクションでのクエリカウント確認
#   - 新規機能追加時の自動N+1検出
#   - CI/CDパイプラインでの自動実行

RSpec.describe "N+1 Query Detection", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # カスタムマッチャー: クエリ数が増加しないことを確認
  RSpec::Matchers.define :not_exceed_query_count do |expected|
    match do |actual|
      @query_count = count_queries(&actual)
      @query_count <= expected
    end

    failure_message do
      "expected query count to not exceed #{expected}, but was #{@query_count}"
    end

    def count_queries(&block)
      count = 0
      counter = ->(name, started, finished, unique_id, payload) {
        count += 1 unless payload[:sql]&.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)
      }

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      count
    end
  end

  describe "StoresController" do
    let!(:admin) { create(:admin, headquarters_admin: true) }
    let!(:stores) { create_list(:store, 3) }
    let!(:inventories) { create_list(:inventory, 5) }

    before do
      sign_in admin

      # 各店舗に在庫を設定
      stores.each do |store|
        inventories.each do |inventory|
          create(:store_inventory, store: store, inventory: inventory)
        end

        # 店舗間移動申請を作成
        create_list(:inter_store_transfer, 2,
                   source_store: store,
                   destination_store: stores.sample,
                   inventory: inventories.sample,
                   requested_by: admin,
                   status: :pending)
      end
    end

    it "店舗一覧でN+1クエリが発生しないこと" do
      # ウォームアップ（キャッシュを考慮）
      get admin_stores_path

      # Counter Cacheを使用しているため、店舗数が増えてもクエリ数は一定
      expect {
        get admin_stores_path
      }.to not_exceed_query_count(10)
    end

    it "店舗詳細でN+1クエリが発生しないこと" do
      store = stores.first

      expect {
        get admin_store_path(store)
      }.to not_exceed_query_count(15)
    end
  end

  describe "InterStoreTransfersController" do
    let!(:admin) { create(:admin, headquarters_admin: true) }
    let!(:stores) { create_list(:store, 4) }
    let!(:inventories) { create_list(:inventory, 3) }
    let!(:transfers) { [] }

    before do
      sign_in admin

      # 移動申請を作成
      10.times do
        transfers << create(:inter_store_transfer,
                           source_store: stores.sample,
                           destination_store: stores.sample,
                           inventory: inventories.sample,
                           requested_by: admin,
                           status: [ :pending, :approved, :completed ].sample)
      end
    end

    it "移動申請一覧でN+1クエリが発生しないこと" do
      # includesが適切に設定されているため、転送数が増えてもクエリ数は一定
      expect {
        get admin_inter_store_transfers_path
      }.to not_exceed_query_count(8)
    end

    it "承認待ち一覧でN+1クエリが発生しないこと" do
      expect {
        get pending_admin_inter_store_transfers_path
      }.to not_exceed_query_count(8)
    end
  end

  describe "InventoriesController (API)" do
    let!(:admin) { create(:admin, headquarters_admin: true) }
    let!(:inventories) { create_list(:inventory, 10) }

    before do
      sign_in admin

      # 各在庫にバッチを追加
      inventories.each do |inventory|
        create_list(:batch, 3, inventory: inventory)
      end
    end

    it "API在庫一覧でN+1クエリが発生しないこと" do
      # includes(:batches)が使用されているため、クエリ数は一定
      expect {
        get api_v1_inventories_path, headers: { "Accept" => "application/json" }
      }.to not_exceed_query_count(10)
    end
  end

  # TODO: 🟡 Phase 2（重要）- パフォーマンスベンチマーク機能
  # 優先度: 中（継続的な品質向上）
  # 実装内容:
  #   - レスポンスタイム測定
  #   - メモリ使用量追跡
  #   - 大量データでのストレステスト
  describe "Performance Benchmarks" do
    it "大量データでのパフォーマンス検証" do
      skip "TODO: Phase 2 - 大量データ（10万件以上）でのパフォーマンステスト実装"
      # - 10万件の在庫データ生成
      # - 各画面の表示速度測定
      # - メモリ使用量の監視
      # - SQLクエリの実行計画分析
    end

    it "同時アクセス時のパフォーマンス検証" do
      skip "TODO: Phase 2 - 並行処理でのパフォーマンステスト実装"
      # - 複数スレッドでの同時アクセスシミュレーション
      # - データベースロックの検証
      # - Counter Cacheの競合状態確認
    end
  end

  # TODO: 🟢 Phase 3（推奨）- 継続的パフォーマンス監視
  # 優先度: 低（長期的な品質保証）
  # 実装内容:
  #   - NewRelic/DatadogなどのAPM統合
  #   - パフォーマンス劣化の自動検出
  #   - 週次パフォーマンスレポート生成
end
