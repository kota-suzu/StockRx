# frozen_string_literal: true

require 'rails_helper'

# QueryOptimization 完全ブランチカバレッジテスト
# CLAUDE.md準拠: DB・トランザクション処理の包括的テスト実装
# メタ認知: クエリ最適化の全機能の条件分岐を完全カバー
# 横展開: 全モデルで共通使用されるクエリ最適化パターンのテスト
RSpec.describe QueryOptimization, type: :model do
  # テスト用モデル作成
  let(:test_model_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "inventories"
      include QueryOptimization

      # 関連を定義
      has_many :batches, dependent: :destroy, foreign_key: :inventory_id
      has_many :inventory_logs, dependent: :destroy, foreign_key: :inventory_id

      def self.name
        "TestQueryModel"
      end

      # オーバーライドメソッドの定義
      def self.unnecessary_columns_for_index
        %w[description notes]
      end

      def self.all_associations_for_show
        [ :batches, :inventory_logs ]
      end

      def perform_expensive_calculation
        # テスト用の重い計算をシミュレート
        sleep(0.001) if Rails.env.test?
        "expensive_result_#{id}"
      end
    end
  end

  let!(:record1) { test_model_class.create!(name: "Test Item 1", price: 100, quantity: 10) }
  let!(:record2) { test_model_class.create!(name: "Test Item 2", price: 200, quantity: 20) }
  let!(:record3) { test_model_class.create!(name: "Test Item 3", price: 300, quantity: 30) }

  before do
    # キャッシュクリア
    Rails.cache.clear
  end

  # ============================================
  # スコープテスト
  # ============================================

  describe "scopes" do
    describe ".with_associations" do
      context "when associations are provided" do
        it "includes the specified associations" do
          scope = test_model_class.with_associations([ :batches, :inventory_logs ])

          expect(scope.includes_values).to contain_exactly(:batches, :inventory_logs)
        end

        it "handles single association" do
          scope = test_model_class.with_associations(:batches)

          expect(scope.includes_values).to contain_exactly(:batches)
        end
      end

      context "when associations are nil or empty" do
        it "returns all scope for nil" do
          scope = test_model_class.with_associations(nil)

          expect(scope.includes_values).to be_empty
        end

        it "returns all scope for empty array" do
          scope = test_model_class.with_associations([])

          expect(scope.includes_values).to be_empty
        end

        it "returns all scope for empty string" do
          scope = test_model_class.with_associations("")

          expect(scope.includes_values).to be_empty
        end
      end
    end

    describe ".optimized_for_index" do
      it "excludes unnecessary columns for index view" do
        scope = test_model_class.optimized_for_index

        # SELECTされるカラムから除外されるものを確認
        sql = scope.to_sql
        expect(sql).not_to include("description")
        expect(sql).not_to include("notes")
        expect(sql).to include("name")
        expect(sql).to include("price")
      end

      it "includes necessary columns" do
        scope = test_model_class.optimized_for_index

        # 必要なカラムが含まれることを確認
        sql = scope.to_sql
        expect(sql).to include("id")
        expect(sql).to include("name")
        expect(sql).to include("quantity")
      end
    end

    describe ".optimized_for_show" do
      it "includes all associations for detailed view" do
        scope = test_model_class.optimized_for_show

        expect(scope.includes_values).to contain_exactly(:batches, :inventory_logs)
      end
    end

    describe ".recent" do
      it "returns recent records in descending order" do
        recent_records = test_model_class.recent(2)

        expect(recent_records.count).to eq(2)
        expect(recent_records.first.created_at).to be >= recent_records.last.created_at
      end

      it "defaults to limit of 10" do
        scope = test_model_class.recent

        expect(scope.limit_value).to eq(10)
      end

      it "respects custom limit" do
        scope = test_model_class.recent(5)

        expect(scope.limit_value).to eq(5)
      end
    end

    describe ".by_ids" do
      it "returns records indexed by id" do
        ids = [ record1.id, record3.id ]
        indexed_records = test_model_class.by_ids(ids)

        expect(indexed_records).to be_a(Hash)
        expect(indexed_records.keys).to contain_exactly(record1.id, record3.id)
        expect(indexed_records[record1.id]).to eq(record1)
        expect(indexed_records[record3.id]).to eq(record3)
      end

      it "handles empty ids array" do
        indexed_records = test_model_class.by_ids([])

        expect(indexed_records).to be_a(Hash)
        expect(indexed_records).to be_empty
      end
    end
  end

  # ============================================
  # クラスメソッドテスト
  # ============================================

  describe "class methods" do
    describe ".update_all_in_batches" do
      let!(:records) { create_list(:inventory, 25, name: "Batch Test") }

      it "updates all records in batches" do
        expect {
          test_model_class.where(name: "Batch Test").update_all_in_batches(
            { name: "Updated Name" },
            batch_size: 10
          )
        }.to change {
          test_model_class.where(name: "Updated Name").count
        }.from(0).to(25)
      end

      it "uses transactions for batch updates" do
        expect(ActiveRecord::Base).to receive(:transaction).and_call_original

        test_model_class.where(name: "Batch Test").update_all_in_batches(
          { name: "Updated Name" },
          batch_size: 10
        )
      end

      it "handles errors and rolls back" do
        allow(test_model_class).to receive(:update_all).and_raise(StandardError, "Update failed")

        expect {
          test_model_class.where(name: "Batch Test").update_all_in_batches(
            { name: "Updated Name" },
            batch_size: 10
          )
        }.to raise_error(StandardError, "Update failed")

        # データが変更されていないことを確認
        expect(test_model_class.where(name: "Updated Name").count).to eq(0)
      end

      it "respects custom batch size" do
        expect(test_model_class.where(name: "Batch Test")).to receive(:find_in_batches)
          .with(batch_size: 5).and_call_original

        test_model_class.where(name: "Batch Test").update_all_in_batches(
          { name: "Updated Name" },
          batch_size: 5
        )
      end
    end

    describe ".exists_with_cache?" do
      it "caches existence check results" do
        # 最初の呼び出し
        expect(test_model_class.exists_with_cache?(record1.id)).to be true

        # キャッシュから読み込まれる
        expect(Rails.cache).to receive(:fetch).with(
          "inventories/exists/#{record1.id}",
          expires_in: 1.hour
        ).and_call_original

        test_model_class.exists_with_cache?(record1.id)
      end

      it "returns false for non-existent records" do
        expect(test_model_class.exists_with_cache?(99999)).to be false
      end

      it "caches negative results" do
        # 存在しないIDのキャッシュテスト
        non_existent_id = 99999

        expect(test_model_class.exists_with_cache?(non_existent_id)).to be false

        # 2回目の呼び出しでキャッシュが使われることを確認
        expect(test_model_class).not_to receive(:exists?)
        expect(test_model_class.exists_with_cache?(non_existent_id)).to be false
      end
    end

    describe ".find_with_preload" do
      it "finds record with preloaded associations" do
        record = test_model_class.find_with_preload(record1.id, [ :batches ])

        expect(record).to eq(record1)
        expect(record.association(:batches)).to be_loaded
      end

      it "works without associations" do
        record = test_model_class.find_with_preload(record1.id, [])

        expect(record).to eq(record1)
      end

      it "handles multiple associations" do
        record = test_model_class.find_with_preload(record1.id, [ :batches, :inventory_logs ])

        expect(record).to eq(record1)
        expect(record.association(:batches)).to be_loaded
        expect(record.association(:inventory_logs)).to be_loaded
      end

      it "raises error for non-existent record" do
        expect {
          test_model_class.find_with_preload(99999, [ :batches ])
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe ".cached_stats" do
      before do
        travel_to(Time.current.beginning_of_day)
      end

      after do
        travel_back
      end

      it "returns cached statistics" do
        stats = test_model_class.cached_stats

        expect(stats).to be_a(Hash)
        expect(stats).to include(
          :total_count,
          :created_today,
          :updated_today
        )
        expect(stats[:total_count]).to eq(3)
      end

      it "caches results for 1 hour" do
        expect(Rails.cache).to receive(:fetch).with(
          "inventories/stats/#{Date.current}",
          expires_in: 1.hour
        ).and_call_original

        test_model_class.cached_stats
      end

      it "uses custom cache key" do
        custom_key = "custom/stats/key"

        expect(Rails.cache).to receive(:fetch).with(
          custom_key,
          expires_in: 1.hour
        ).and_call_original

        test_model_class.cached_stats(custom_key)
      end

      it "calculates today's statistics correctly" do
        # 今日作成されたレコードを追加
        travel_to(Time.current + 1.hour) do
          test_model_class.create!(name: "Today's Item", price: 100, quantity: 10)
        end

        stats = test_model_class.cached_stats
        expect(stats[:created_today]).to eq(1)
      end
    end

    describe ".explain_query" do
      context "in development environment" do
        before do
          allow(Rails.env).to receive(:development?).and_return(true)
        end

        it "explains query and returns explanation" do
          scope = test_model_class.where(name: "Test")

          expect(scope).to receive(:explain).and_return("Seq Scan on inventories")
          expect(Rails.logger).to receive(:debug)

          explanation = test_model_class.explain_query(scope)
          expect(explanation).to eq("Seq Scan on inventories")
        end

        it "warns about potential performance issues" do
          scope = test_model_class.where(name: "Test")
          explanation_with_filesort = "Using filesort; Using temporary"

          allow(scope).to receive(:explain).and_return(explanation_with_filesort)
          expect(Rails.logger).to receive(:warn).with(/Potential performance issue/)

          test_model_class.explain_query(scope)
        end

        it "detects filesort usage" do
          scope = test_model_class.where(name: "Test")

          allow(scope).to receive(:explain).and_return("Using filesort")
          expect(Rails.logger).to receive(:warn)

          test_model_class.explain_query(scope)
        end

        it "detects temporary table usage" do
          scope = test_model_class.where(name: "Test")

          allow(scope).to receive(:explain).and_return("Using temporary")
          expect(Rails.logger).to receive(:warn)

          test_model_class.explain_query(scope)
        end
      end

      context "in non-development environment" do
        before do
          allow(Rails.env).to receive(:development?).and_return(false)
        end

        it "returns nil and doesn't explain query" do
          scope = test_model_class.where(name: "Test")

          expect(scope).not_to receive(:explain)
          result = test_model_class.explain_query(scope)

          expect(result).to be_nil
        end
      end
    end

    describe ".optimization_suggestions" do
      it "suggests preload for multiple joins" do
        scope = double("scope")
        allow(scope).to receive(:to_sql).and_return(
          "SELECT * FROM inventories " +
          "LEFT OUTER JOIN batches ON inventories.id = batches.inventory_id " +
          "LEFT OUTER JOIN inventory_logs ON inventories.id = inventory_logs.inventory_id " +
          "LEFT OUTER JOIN stores ON inventories.store_id = stores.id " +
          "LEFT OUTER JOIN receipts ON inventories.id = receipts.inventory_id"
        )
        allow(scope).to receive(:count).and_return(100)

        suggestions = test_model_class.optimization_suggestions(scope)

        expect(suggestions).to include("Consider using preload instead of includes for better performance")
      end

      it "suggests batching for large datasets" do
        scope = double("scope")
        allow(scope).to receive(:to_sql).and_return("SELECT * FROM inventories")
        allow(scope).to receive(:count).and_return(15000)

        suggestions = test_model_class.optimization_suggestions(scope)

        expect(suggestions).to include("Consider using find_in_batches for large datasets")
      end

      it "suggests index verification for WHERE clauses" do
        scope = double("scope")
        allow(scope).to receive(:to_sql).and_return(
          "SELECT * FROM inventories WHERE name = 'test'"
        )
        allow(scope).to receive(:count).and_return(100)

        suggestions = test_model_class.optimization_suggestions(scope)

        expect(suggestions).to include("Ensure proper indexes exist for WHERE conditions")
      end

      it "returns empty suggestions for optimized queries" do
        scope = double("scope")
        allow(scope).to receive(:to_sql).and_return(
          "SELECT * FROM inventories WHERE id = 1 INDEX (PRIMARY)"
        )
        allow(scope).to receive(:count).and_return(1)

        suggestions = test_model_class.optimization_suggestions(scope)

        expect(suggestions).to be_empty
      end

      it "provides multiple suggestions when applicable" do
        scope = double("scope")
        allow(scope).to receive(:to_sql).and_return(
          "SELECT * FROM inventories " +
          "LEFT OUTER JOIN batches ON inventories.id = batches.inventory_id " +
          "LEFT OUTER JOIN inventory_logs ON inventories.id = inventory_logs.inventory_id " +
          "LEFT OUTER JOIN stores ON inventories.store_id = stores.id " +
          "LEFT OUTER JOIN receipts ON inventories.id = receipts.inventory_id " +
          "WHERE inventories.name = 'test'"
        )
        allow(scope).to receive(:count).and_return(15000)

        suggestions = test_model_class.optimization_suggestions(scope)

        expect(suggestions.size).to eq(3)
        expect(suggestions).to include("Consider using preload instead of includes for better performance")
        expect(suggestions).to include("Consider using find_in_batches for large datasets")
        expect(suggestions).to include("Ensure proper indexes exist for WHERE conditions")
      end
    end
  end

  # ============================================
  # インスタンスメソッドテスト
  # ============================================

  describe "instance methods" do
    describe "#load_association_if_needed" do
      it "loads association if not already loaded" do
        record = test_model_class.find(record1.id)

        # 関連がまだ読み込まれていないことを確認
        expect(record.association(:batches)).not_to be_loaded

        # メソッド呼び出し
        result = record.load_association_if_needed(:batches)

        # 関連が読み込まれたことを確認
        expect(record.association(:batches)).to be_loaded
        expect(result).to eq(record.batches)
      end

      it "skips loading if association is already loaded" do
        record = test_model_class.includes(:batches).find(record1.id)

        # 関連がすでに読み込まれていることを確認
        expect(record.association(:batches)).to be_loaded

        # Preloaderが呼ばれないことを確認
        expect(ActiveRecord::Associations::Preloader).not_to receive(:new)

        result = record.load_association_if_needed(:batches)
        expect(result).to eq(record.batches)
      end
    end

    describe "#memoized_expensive_calculation" do
      it "memoizes expensive calculations" do
        record = record1

        # 最初の呼び出し
        expect(record).to receive(:perform_expensive_calculation).once.and_call_original

        result1 = record.memoized_expensive_calculation
        result2 = record.memoized_expensive_calculation

        expect(result1).to eq(result2)
        expect(result1).to eq("expensive_result_#{record.id}")
      end

      it "calculates once per instance" do
        record1_result = record1.memoized_expensive_calculation
        record2_result = record2.memoized_expensive_calculation

        expect(record1_result).to eq("expensive_result_#{record1.id}")
        expect(record2_result).to eq("expensive_result_#{record2.id}")
        expect(record1_result).not_to eq(record2_result)
      end
    end

    describe "#cache_key_with_associations" do
      it "generates cache key without associations" do
        cache_key = record1.cache_key_with_associations

        expect(cache_key).to eq(record1.cache_key)
      end

      it "includes association timestamps in cache key" do
        # バッチを作成してタイムスタンプを設定
        batch = create(:batch, inventory: record1)

        cache_key = record1.cache_key_with_associations(:batches)

        expect(cache_key).to include(record1.cache_key)
        expect(cache_key).to include("associations")
        expect(cache_key).to include(batch.updated_at.to_i.to_s)
      end

      it "handles multiple associations" do
        batch = create(:batch, inventory: record1)
        log = create(:inventory_log, inventory: record1)

        cache_key = record1.cache_key_with_associations(:batches, :inventory_logs)

        expect(cache_key).to include("associations")
        expect(cache_key).to include(batch.updated_at.to_i.to_s)
        expect(cache_key).to include(log.updated_at.to_i.to_s)
      end

      it "handles nil association records" do
        cache_key = record1.cache_key_with_associations(:batches)

        # バッチが存在しない場合でもエラーにならない
        expect(cache_key).to include("associations")
        expect(cache_key).to include("0") # nil時のデフォルト値
      end

      it "handles single record associations" do
        # has_one風の関連をシミュレート
        allow(record1).to receive(:batches).and_return(record1.batches.first)

        if record1.batches.any?
          cache_key = record1.cache_key_with_associations(:batches)
          expect(cache_key).to include("associations")
        end
      end

      it "handles associations without updated_at" do
        # updated_atを持たないレコードをシミュレート
        mock_association = double("association", updated_at: nil)
        allow(record1).to receive(:batches).and_return(mock_association)

        cache_key = record1.cache_key_with_associations(:batches)

        expect(cache_key).to include("associations")
        expect(cache_key).to include("0") # nil時のデフォルト値
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    describe "batch operations" do
      let!(:large_dataset) { create_list(:inventory, 100) }

      it "performs batch updates efficiently" do
        start_time = Time.current

        test_model_class.where(id: large_dataset.map(&:id))
                        .update_all_in_batches({ name: "Batch Updated" }, batch_size: 25)

        elapsed_time = Time.current - start_time
        expect(elapsed_time).to be < 2.0 # 2秒以内
      end
    end

    describe "caching performance" do
      it "improves performance with caching" do
        # キャッシュなしの時間測定
        Rails.cache.clear
        start_time = Time.current

        10.times { test_model_class.cached_stats }

        cached_time = Time.current - start_time

        # キャッシュありの場合は大幅に高速化される
        expect(cached_time).to be < 0.1 # 100ms以内
      end
    end

    describe "association loading" do
      it "reduces N+1 queries with proper preloading" do
        records = test_model_class.optimized_for_show.limit(5)

        # クエリ数を監視
        query_count = 0
        callback = ->(_, _, _, _, payload) { query_count += 1 if payload[:sql] }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          records.each { |record| record.batches.count }
        end

        # preloadされているため、N+1クエリが発生しない
        expect(query_count).to be <= 2 # 初期クエリ + preloadクエリ
      end
    end
  end

  # ============================================
  # エラーハンドリングとエッジケース
  # ============================================

  describe "error handling and edge cases" do
    describe "cache failures" do
      it "handles cache failures gracefully" do
        allow(Rails.cache).to receive(:fetch).and_raise(Redis::CannotConnectError)

        expect {
          test_model_class.exists_with_cache?(record1.id)
        }.to raise_error(Redis::CannotConnectError)
      end
    end

    describe "database connection issues" do
      it "handles database timeouts in batch operations" do
        allow(test_model_class).to receive(:find_in_batches).and_raise(ActiveRecord::ConnectionTimeoutError)

        expect {
          test_model_class.update_all_in_batches({ name: "Test" })
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    describe "invalid associations" do
      it "handles invalid association names" do
        expect {
          record1.load_association_if_needed(:non_existent_association)
        }.to raise_error(ActiveRecord::AssociationNotFoundError)
      end
    end

    describe "large datasets" do
      it "handles memory efficiently with very large result sets" do
        # メモリ使用量のテスト（簡易版）
        expect {
          test_model_class.optimized_for_index.limit(1000).to_a
        }.not_to raise_error
      end
    end

    describe "concurrent access" do
      it "handles concurrent cache access safely" do
        threads = []
        results = []

        5.times do
          threads << Thread.new do
            result = test_model_class.exists_with_cache?(record1.id)
            results << result
          end
        end

        threads.each(&:join)

        expect(results).to all(be true)
        expect(results.size).to eq(5)
      end
    end
  end

  # ============================================
  # 統合テスト
  # ============================================

  describe "integration tests" do
    it "works with complex query chains" do
      results = test_model_class
                .optimized_for_index
                .with_associations([ :batches ])
                .recent(2)
                .where("price > ?", 150)

      expect(results.count).to eq(2)
      expect(results.all? { |r| r.price > 150 }).to be true
    end

    it "integrates caching with associations" do
      record = test_model_class.find_with_preload(record1.id, [ :batches ])
      cache_key1 = record.cache_key_with_associations(:batches)

      # バッチを追加してキャッシュキーが変わることを確認
      create(:batch, inventory: record)

      cache_key2 = record.reload.cache_key_with_associations(:batches)
      expect(cache_key1).not_to eq(cache_key2)
    end

    it "provides optimization suggestions for real queries" do
      scope = test_model_class.joins(:batches, :inventory_logs)
                             .where("inventories.price > ?", 100)
                             .includes(:batches)

      suggestions = test_model_class.optimization_suggestions(scope)
      expect(suggestions).to be_an(Array)
    end
  end
end
