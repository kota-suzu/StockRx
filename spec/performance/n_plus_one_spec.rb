# frozen_string_literal: true

require 'rails_helper'

# N+1クエリ問題の検出テスト
# ============================================
# CLAUDE.md準拠: パフォーマンステスト - N+1検出
# メタ認知: 全コントローラーアクションでN+1を防ぐ
# ============================================
RSpec.describe 'N+1 Query Detection', type: :request do
  describe 'AdminControllers::InventoriesController' do
    let(:admin) { create(:admin) }

    before do
      sign_in admin
    end

    describe 'GET /admin/inventories' do
      it 'avoids N+1 queries when loading inventories with associations' do
        # 最初のデータセットでクエリ数を計測
        create_list(:inventory, 2) do |inventory|
          create_list(:batch, 2, inventory: inventory)
          create_list(:inventory_log, 2, inventory: inventory)
        end

        control_count = ActiveRecord::QueryRecorder.new do
          get admin_inventories_path
        end.count

        # より多くのデータでクエリ数を再計測
        create_list(:inventory, 3) do |inventory|
          create_list(:batch, 3, inventory: inventory)
          create_list(:inventory_log, 3, inventory: inventory)
        end

        expect do
          get admin_inventories_path
        end.not_to exceed_query_limit(control_count)
      end

      it 'uses counter cache for associations count' do
        inventories = create_list(:inventory, 5)

        # Counter Cacheが正しく動作することを確認
        expect do
          get admin_inventories_path
          expect(response).to have_http_status(:success)

          # ビューでcountメソッドが呼ばれてもクエリが発行されないことを確認
          body = response.body
          inventories.each do |inventory|
            expect(body).to include(inventory.batches_count.to_s)
            expect(body).to include(inventory.inventory_logs_count.to_s)
          end
        end.not_to make_database_queries.matching(/SELECT COUNT/)
      end
    end

    describe 'GET /admin/inventories/:id' do
      let(:inventory) { create(:inventory) }

      it 'preloads all necessary associations' do
        # 関連データを作成
        create_list(:batch, 3, inventory: inventory)
        create_list(:inventory_log, 5, inventory: inventory)

        queries = ActiveRecord::QueryRecorder.new do
          get admin_inventory_path(inventory)
        end

        # 期待されるクエリ数（基本的に3つ以下であるべき）
        # 1. Inventory本体
        # 2. Batches
        # 3. InventoryLogs
        expect(queries.count).to be <= 3

        # 特定のN+1パターンが発生していないことを確認
        expect(queries.log).not_to include_query_matching(/SELECT.*FROM.*batches.*WHERE.*inventory_id/).more_than(1)
        expect(queries.log).not_to include_query_matching(/SELECT.*FROM.*inventory_logs.*WHERE.*inventory_id/).more_than(1)
      end
    end
  end

  describe 'StoreControllers::InventoriesController' do
    let(:store) { create(:store) }
    let(:store_user) { create(:store_user, store: store) }

    before do
      sign_in store_user
    end

    describe 'GET /store/inventories' do
      it 'efficiently loads store inventories without N+1' do
        # 店舗在庫データの作成
        inventories = create_list(:inventory, 3)
        inventories.each do |inventory|
          create(:store_inventory, store: store, inventory: inventory)
        end

        control_count = ActiveRecord::QueryRecorder.new do
          get store_inventories_path
        end.count

        # 追加データで再テスト
        more_inventories = create_list(:inventory, 5)
        more_inventories.each do |inventory|
          create(:store_inventory, store: store, inventory: inventory)
        end

        expect do
          get store_inventories_path
        end.not_to exceed_query_limit(control_count)
      end
    end
  end

  describe 'Repository Layer Performance' do
    let(:admin) { create(:admin) }

    it 'InventoryRepository.search performs efficiently' do
      # 大量のテストデータ作成
      create_list(:inventory, 20) do |inventory|
        create_list(:batch, 3, inventory: inventory)
      end

      # Repository経由の検索でN+1が発生しないことを確認
      expect do
        result = InventoryRepository.search(
          keyword: 'test',
          status: 'active',
          include_associations: [ :batches ]
        )

        # 結果を強制的に評価してクエリを実行
        result.each do |inventory|
          inventory.batches.to_a
        end
      end.not_to exceed_query_limit(5) # 基本クエリ + バッチ読み込みのみ
    end
  end
end

# カスタムマッチャーとヘルパー
module ActiveRecord
  class QueryRecorder
    attr_reader :log, :cached_log

    def initialize(&block)
      @log = []
      @cached_log = []

      ActiveSupport::Notifications.subscribed(method(:callback), 'sql.active_record', &block)
    end

    def callback(event)
      query = event.payload[:sql]

      # SCHEMA関連とCACHEクエリを除外
      unless query&.match?(/\A(?:PRAGMA|SCHEMA|CACHE)/)
        if event.payload[:cached]
          @cached_log << query
        else
          @log << query
        end
      end
    end

    def count
      @log.size
    end

    def cached_count
      @cached_log.size
    end
  end
end

# RSpecマッチャー拡張
RSpec::Matchers.define :include_query_matching do |pattern|
  match do |queries|
    queries.any? { |query| query.match?(pattern) }
  end

  chain :more_than do |count|
    @count = count
  end

  failure_message do |queries|
    if @count
      "expected to find more than #{@count} queries matching #{pattern}, but found #{queries.count { |q| q.match?(pattern) }}"
    else
      "expected to find a query matching #{pattern}"
    end
  end
end

RSpec::Matchers.define :make_database_queries do
  match do |block|
    queries = ActiveRecord::QueryRecorder.new(&block).log

    if @pattern
      queries.any? { |query| query.match?(@pattern) }
    else
      queries.any?
    end
  end

  chain :matching do |pattern|
    @pattern = pattern
  end

  failure_message do
    if @pattern
      "expected to make database queries matching #{@pattern}"
    else
      "expected to make database queries"
    end
  end

  failure_message_when_negated do
    if @pattern
      "expected not to make database queries matching #{@pattern}"
    else
      "expected not to make any database queries"
    end
  end
end
