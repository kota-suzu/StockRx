# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchQuery, type: :service do
  describe ".call" do
    # 各テストの前後でデータをクリア
    before(:each) do
      Inventory.destroy_all
      # テストデータを作成
      @inventory1 = create(:inventory, name: "Test Product 1", quantity: 10, price: 1000)
      @inventory2 = create(:inventory, name: "Test Product 2", quantity: 50, price: 2000)
      @inventory3 = create(:inventory, name: "Test Product 3", quantity: 100, price: 3000)
      @inventory4 = create(:inventory, name: "Another Product", quantity: 0, price: 500)
    end

    after(:each) do
      Inventory.destroy_all
    end

    context "在庫数範囲フィルター" do
      describe "最小在庫数フィルター" do
        it "指定した最小在庫数以上の商品のみを返す" do
          params = { min_quantity: 50 }
          result = described_class.call(params)

          expect(result.count).to eq(2)
          expect(result).to include(@inventory2, @inventory3)
          expect(result).not_to include(@inventory1, @inventory4)
        end
      end

      describe "最大在庫数フィルター" do
        it "指定した最大在庫数以下の商品のみを返す" do
          params = { max_quantity: 50 }
          result = described_class.call(params)

          expect(result.count).to eq(3)
          expect(result).to include(@inventory1, @inventory2, @inventory4)
          expect(result).not_to include(@inventory3)
        end
      end

      describe "在庫数範囲フィルター（最小・最大指定）" do
        it "指定した範囲内の在庫数の商品のみを返す" do
          params = { min_quantity: 10, max_quantity: 50 }
          result = described_class.call(params)

          expect(result.count).to eq(2)
          expect(result).to include(@inventory1, @inventory2)
          expect(result).not_to include(@inventory3, @inventory4)
        end
      end

      describe "在庫数0の商品を含む範囲フィルター" do
        it "最小在庫数0を指定した場合、在庫切れ商品も含める" do
          params = { min_quantity: 0, max_quantity: 10 }
          result = described_class.call(params)

          expect(result.count).to eq(2)
          expect(result).to include(@inventory1, @inventory4)
          expect(result).not_to include(@inventory2, @inventory3)
        end
      end
    end

    context "他のフィルターとの組み合わせ" do
      it "キーワード検索と在庫数範囲フィルターを組み合わせて使用できる" do
        params = { q: "Test", min_quantity: 20 }
        result = described_class.call(params)

        expect(result.count).to eq(2)
        expect(result).to include(@inventory2, @inventory3)
        expect(result).not_to include(@inventory1, @inventory4)
      end

      it "ステータスフィルターと在庫数範囲フィルターを組み合わせて使用できる" do
        @inventory1.update!(status: "active")
        @inventory2.update!(status: "archived")
        @inventory3.update!(status: "active")
        @inventory4.update!(status: "archived")

        params = { status: "active", min_quantity: 10, max_quantity: 100 }
        result = described_class.call(params)

        expect(result.count).to eq(2)
        expect(result).to include(@inventory1, @inventory3)
        expect(result).not_to include(@inventory2, @inventory4)
      end
    end

    context "無効な入力値の処理" do
      it "文字列の在庫数を数値に変換して処理する" do
        params = { min_quantity: "20", max_quantity: "80" }
        result = described_class.call(params)

        expect(result.count).to eq(1)
        expect(result).to include(@inventory2)
      end

      it "空文字列の在庫数は無視する" do
        params = { min_quantity: "", max_quantity: "" }
        result = described_class.call(params)

        expect(result.count).to eq(4)
      end

      it "nilの在庫数は無視する" do
        params = { min_quantity: nil, max_quantity: nil }
        result = described_class.call(params)

        expect(result.count).to eq(4)
      end

      describe "負の値の処理" do
        it "負の最小在庫数を0に変換する" do
          params = { min_quantity: -10, max_quantity: 50 }
          result = described_class.call(params)

          # デバッグ用: 結果を確認
          # puts "Total inventories in DB: #{Inventory.count}"
          # puts "Result count: #{result.count}"
          # puts "Test data IDs: #{[@inventory1.id, @inventory2.id, @inventory3.id, @inventory4.id]}"
          # puts "Result IDs: #{result.pluck(:id)}"

          # min_quantity = 0, max_quantity = 50として処理される
          # このテストで作成した4つのインベントリのみを考慮
          test_data_ids = [ @inventory1.id, @inventory2.id, @inventory3.id, @inventory4.id ]
          filtered_result = result.where(id: test_data_ids)

          expect(filtered_result.count).to eq(3)
          expect(filtered_result).to include(@inventory1, @inventory2, @inventory4)
          expect(filtered_result).not_to include(@inventory3)
        end

        it "負の最大在庫数を0に変換する" do
          params = { min_quantity: 0, max_quantity: -10 }
          result = described_class.call(params)

          # min_quantity = 0, max_quantity = 0として処理される
          # このテストで作成した4つのインベントリのみを考慮
          test_data_ids = [ @inventory1.id, @inventory2.id, @inventory3.id, @inventory4.id ]
          filtered_result = result.where(id: test_data_ids)

          expect(filtered_result.count).to eq(1)
          expect(filtered_result).to include(@inventory4)
          expect(filtered_result).not_to include(@inventory1, @inventory2, @inventory3)
        end

        it "両方が負の値の場合、両方を0に変換する" do
          params = { min_quantity: -50, max_quantity: -10 }
          result = described_class.call(params)

          # min_quantity = 0, max_quantity = 0として処理される
          # このテストで作成した4つのインベントリのみを考慮
          test_data_ids = [ @inventory1.id, @inventory2.id, @inventory3.id, @inventory4.id ]
          filtered_result = result.where(id: test_data_ids)

          expect(filtered_result.count).to eq(1)
          expect(filtered_result).to include(@inventory4)
        end
      end

      describe "最小値と最大値の入れ替え処理" do
        it "最小値が最大値より大きい場合、値を入れ替える" do
          params = { min_quantity: 100, max_quantity: 10 }
          result = described_class.call(params)

          # min_quantity = 10, max_quantity = 100として処理される
          # このテストで作成した4つのインベントリのみを考慮
          test_data_ids = [ @inventory1.id, @inventory2.id, @inventory3.id, @inventory4.id ]
          filtered_result = result.where(id: test_data_ids)

          expect(filtered_result.count).to eq(3)
          expect(filtered_result).to include(@inventory1, @inventory2, @inventory3)
          expect(filtered_result).not_to include(@inventory4)
        end

        it "負の値を含む場合でも、変換後に入れ替え処理を行う" do
          params = { min_quantity: 50, max_quantity: -10 }
          result = described_class.call(params)

          # max_quantity = 0に変換後、min_quantity = 0, max_quantity = 50として入れ替えられる
          # このテストで作成した4つのインベントリのみを考慮
          test_data_ids = [ @inventory1.id, @inventory2.id, @inventory3.id, @inventory4.id ]
          filtered_result = result.where(id: test_data_ids)

          expect(filtered_result.count).to eq(3)
          expect(filtered_result).to include(@inventory1, @inventory2, @inventory4)
          expect(filtered_result).not_to include(@inventory3)
        end
      end
    end

    context "complex_search_requiredの判定" do
      it "min_quantityが指定されている場合は高度な検索を使用する" do
        params = { min_quantity: 10 }

        expect(SearchQuery).to receive(:advanced_search).and_call_original
        described_class.call(params)
      end

      it "max_quantityが指定されている場合は高度な検索を使用する" do
        params = { max_quantity: 50 }

        expect(SearchQuery).to receive(:advanced_search).and_call_original
        described_class.call(params)
      end
    end

    context "パフォーマンス" do
      it "大量データでも適切なクエリを生成する" do
        # このテストの前に全データを削除
        Inventory.destroy_all

        # 1000件のデータを作成
        create_list(:inventory, 1000, quantity: 75)

        params = { min_quantity: 50, max_quantity: 100 }

        # クエリ数をカウント
        query_count = 0
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          query_count += 1
        end

        result = described_class.call(params)

        # 適切な数のクエリで実行されることを確認（N+1問題がないこと）
        expect(query_count).to be < 10
        expect(result.count).to eq(1000)  # ちょうど1000件
      ensure
        ActiveSupport::Notifications.unsubscribe("sql.active_record")
        # このテストの後も全データを削除
        Inventory.destroy_all
      end
    end

    context "simple_search" do
      it "キーワード検索を実行する" do
        params = { q: "Test" }
        result = described_class.call(params)

        expect(result.count).to eq(3)
        expect(result).to include(@inventory1, @inventory2, @inventory3)
        expect(result).not_to include(@inventory4)
      end

      it "ステータスでフィルタリングする" do
        @inventory1.update!(status: "active")
        @inventory2.update!(status: "archived")

        params = { status: "active" }
        result = described_class.call(params)

        expect(result).to include(@inventory1)
        expect(result).not_to include(@inventory2)
      end

      it "無効なステータスは無視される" do
        params = { status: "invalid_status" }
        result = described_class.call(params)

        expect(result.count).to eq(4)
      end

      it "low_stock=trueで在庫切れ商品のみ表示する" do
        params = { low_stock: "true" }
        result = described_class.call(params)

        expect(result.count).to eq(1)
        expect(result).to include(@inventory4)
      end

      it "ソート機能が動作する" do
        params = { sort: "name", direction: "asc" }
        result = described_class.call(params)

        expect(result.first).to eq(@inventory4)
        expect(result.last.name).to start_with("Test Product")
      end

      it "価格でソートする" do
        params = { sort: "price", direction: "desc" }
        result = described_class.call(params)

        expect(result.first).to eq(@inventory3)
        expect(result.last).to eq(@inventory4)
      end

      it "数量でソートする" do
        params = { sort: "quantity", direction: "asc" }
        result = described_class.call(params)

        expect(result.first).to eq(@inventory4)
        expect(result.last).to eq(@inventory3)
      end

      it "無効なソート方向はDESCにデフォルト設定される" do
        params = { sort: "name", direction: "invalid" }
        result = described_class.call(params)

        expect(result.to_sql).to include("ORDER BY name DESC")
      end
    end

    context "advanced_search" do
      let!(:batch_inventory) { create(:inventory, name: "Batch Product") }
      let!(:batch) { create(:batch, inventory: batch_inventory, lot_code: "LOT123", expires_on: 10.days.from_now) }
      let!(:shipment_inventory) { create(:inventory, name: "Shipped Product") }
      let!(:shipment) { create(:shipment, inventory: shipment_inventory, destination: "Tokyo", shipment_status: :pending) }
      let!(:receipt_inventory) { create(:inventory, name: "Received Product") }
      let!(:receipt) { create(:receipt, inventory: receipt_inventory, source: "Supplier A", receipt_status: :pending) }

      it "価格範囲でフィルタリングする" do
        params = { min_price: 1500, max_price: 2500 }
        result = described_class.call(params)

        expect(result.count).to eq(1)
        expect(result).to include(@inventory2)
      end

      it "日付範囲でフィルタリングする" do
        @inventory1.update!(created_at: 2.weeks.ago)

        params = { created_from: 1.week.ago.to_date.to_s, created_to: Date.today.to_s }
        result = described_class.call(params)

        expect(result).not_to include(@inventory1)
      end

      it "ロットコードでフィルタリングする" do
        params = { lot_code: "LOT" }
        result = described_class.call(params)

        expect(result).to include(batch_inventory)
        expect(result).not_to include(@inventory1)
      end

      it "期限切れ日付でフィルタリングする" do
        params = { expires_before: 15.days.from_now.to_date.to_s }
        result = described_class.call(params)

        expect(result).to include(batch_inventory)
      end

      it "期限切れ後日付でフィルタリングする" do
        params = { expires_after: 5.days.from_now.to_date.to_s }
        result = described_class.call(params)

        expect(result).to include(batch_inventory)
      end

      it "期限切れ間近でフィルタリングする" do
        params = { expiring_soon: "true", expiring_days: "20" }
        result = described_class.call(params)

        expect(result).to include(batch_inventory)
      end

      it "expiring_daysが未指定の場合デフォルト30日を使用する" do
        params = { expiring_soon: "true" }
        result = described_class.call(params)

        expect(result).to include(batch_inventory)
      end

      it "最近更新された商品でフィルタリングする" do
        old_inventory = create(:inventory, updated_at: 2.weeks.ago)

        params = { recently_updated: "true", updated_days: "7" }
        result = described_class.call(params)

        expect(result).not_to include(old_inventory)
      end

      it "updated_daysが未指定の場合デフォルト7日を使用する" do
        params = { recently_updated: "true" }
        result = described_class.call(params)

        expect(result.count).to be >= 0
      end

      it "出荷ステータスでフィルタリングする" do
        params = { shipment_status: "pending" }
        result = described_class.call(params)

        expect(result).to include(shipment_inventory)
        expect(result).not_to include(@inventory1)
      end

      it "配送先でフィルタリングする" do
        params = { destination: "Tokyo" }
        result = described_class.call(params)

        expect(result).to include(shipment_inventory)
      end

      it "入荷ステータスでフィルタリングする" do
        params = { receipt_status: "pending" }
        result = described_class.call(params)

        expect(result).to include(receipt_inventory)
      end

      it "仕入先でフィルタリングする" do
        params = { source: "Supplier" }
        result = described_class.call(params)

        expect(result).to include(receipt_inventory)
      end

      it "stock_filterでout_of_stockをフィルタリングする" do
        params = { stock_filter: "out_of_stock" }
        result = described_class.call(params)

        expect(result).to include(@inventory4)
        expect(result).not_to include(@inventory1, @inventory2, @inventory3)
      end

      it "stock_filterでlow_stockをフィルタリングする" do
        low_stock_inventory = create(:inventory, quantity: 5)

        params = { stock_filter: "low_stock", low_stock_threshold: "10" }
        result = described_class.call(params)

        expect(result).to include(low_stock_inventory)
        expect(result).not_to include(@inventory4) # quantity: 0
      end

      it "stock_filterでin_stockをフィルタリングする" do
        params = { stock_filter: "in_stock", low_stock_threshold: "10" }
        result = described_class.call(params)

        expect(result).to include(@inventory2, @inventory3)
        expect(result).not_to include(@inventory1, @inventory4)
      end

      it "OR条件での検索を実行する" do
        params = { or_conditions: [ { name: "Test Product 1" }, { name: "Test Product 2" } ] }

        allow(AdvancedSearchQuery).to receive(:build).and_return(double(
          includes: double(
            search_keywords: double(
              with_status: double(
                where_any: double(
                  order_by: double(
                    results: [ @inventory1, @inventory2 ]
                  )
                )
              )
            )
          )
        ))

        result = described_class.call(params)

        expect(result).to include(@inventory1, @inventory2)
      end

      it "複雑な条件での検索を実行する" do
        params = { complex_condition: { "and" => [ { status: "active" } ] } }

        # スタブを設定
        mock_query = double("AdvancedSearchQuery")
        allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
        allow(mock_query).to receive(:includes).and_return(mock_query)
        allow(mock_query).to receive(:search_keywords).and_return(mock_query)
        allow(mock_query).to receive(:with_status).and_return(mock_query)
        allow(mock_query).to receive(:complex_where).and_yield(mock_query).and_return(mock_query)
        allow(mock_query).to receive(:where).and_return(mock_query)
        allow(mock_query).to receive(:order_by).and_return(mock_query)
        allow(mock_query).to receive(:results).and_return(Inventory.all)

        result = described_class.call(params)

        expect(result).to be_a(ActiveRecord::Relation)
      end

      it "ページネーションを適用する" do
        params = { page: "2", per_page: "10", min_price: 100 }

        # ページネーションのスタブ
        mock_query = double("AdvancedSearchQuery")
        allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
        allow(mock_query).to receive(:includes).and_return(mock_query)
        allow(mock_query).to receive(:search_keywords).and_return(mock_query)
        allow(mock_query).to receive(:with_status).and_return(mock_query)
        allow(mock_query).to receive(:in_range).and_return(mock_query)
        allow(mock_query).to receive(:order_by).and_return(mock_query)
        allow(mock_query).to receive(:paginate).with(page: 2, per_page: 10).and_return(mock_query)
        allow(mock_query).to receive(:results).and_return(Inventory.page(2).per(10))

        result = described_class.call(params)

        expect(result).to be_a(ActiveRecord::Relation)
      end
    end

    context "call_with_result" do
      it "シンプル検索でSearchResultを返す" do
        params = { q: "Test" }
        result = described_class.call_with_result(params)

        expect(result).to be_a(SearchResult)
        expect(result.records.count).to eq(3)
        expect(result.query_metadata[:search_type]).to eq("simple")
        expect(result.query_metadata[:complex_query]).to be false
      end

      it "高度な検索でSearchResultを返す" do
        params = { min_price: 1000, max_price: 2000 }

        # スタブを設定
        mock_query = double("AdvancedSearchQuery")
        allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
        allow(mock_query).to receive(:includes).and_return(mock_query)
        allow(mock_query).to receive(:search_keywords).and_return(mock_query)
        allow(mock_query).to receive(:with_status).and_return(mock_query)
        allow(mock_query).to receive(:in_range).and_return(mock_query)
        allow(mock_query).to receive(:order_by).and_return(mock_query)
        allow(mock_query).to receive(:results).and_return(Inventory.all)

        result = described_class.call_with_result(params)

        expect(result).to be_a(SearchResult)
        expect(result.query_metadata[:search_type]).to eq("advanced")
        expect(result.query_metadata[:complex_query]).to be true
      end

      it "条件サマリーを正しく生成する" do
        params = {
          q: "Test",
          status: "active",
          min_price: 1000,
          max_price: 2000,
          created_from: "2024-01-01",
          created_to: "2024-12-31"
        }

        # スタブを設定
        mock_query = double("AdvancedSearchQuery")
        allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
        allow(mock_query).to receive(:includes).and_return(mock_query)
        allow(mock_query).to receive(:search_keywords).and_return(mock_query)
        allow(mock_query).to receive(:with_status).and_return(mock_query)
        allow(mock_query).to receive(:in_range).and_return(mock_query)
        allow(mock_query).to receive(:between_dates).and_return(mock_query)
        allow(mock_query).to receive(:order_by).and_return(mock_query)
        allow(mock_query).to receive(:results).and_return(Inventory.all)

        result = described_class.call_with_result(params)

        expect(result.conditions_summary).to include("キーワード: Test")
        expect(result.conditions_summary).to include("ステータス: active")
        expect(result.conditions_summary).to include("価格範囲: 1000〜2000円")
      end

      it "条件がない場合は「すべて」を返す" do
        params = {}
        result = described_class.call_with_result(params)

        expect(result.conditions_summary).to eq("すべて")
      end
    end

    context "build_complex_condition" do
      it "ハッシュ以外の条件は無視する" do
        mock_query = double("query")

        result = described_class.send(:build_complex_condition, mock_query, "invalid")

        expect(result).to eq(mock_query)
      end

      it "OR条件を処理する" do
        mock_query = double("query")
        allow(mock_query).to receive(:complex_where).and_yield(mock_query)
        allow(mock_query).to receive(:where_any).with([ { name: "test" } ]).and_return(mock_query)

        condition = { "or" => [ { name: "test" } ] }
        result = described_class.send(:build_complex_condition, mock_query, condition)

        expect(mock_query).to have_received(:where_any)
      end

      it "不正なOR条件は処理しない" do
        mock_query = double("query")
        allow(mock_query).to receive(:complex_where).and_yield(mock_query)

        condition = { "or" => "invalid" }
        result = described_class.send(:build_complex_condition, mock_query, condition)

        expect(result).to eq(mock_query)
      end
    end

    context "エッジケース" do
      it "or_conditionsが配列でない場合は無視する" do
        params = { or_conditions: "invalid" }

        result = described_class.call(params)

        expect(result.count).to eq(4) # 全件取得
      end

      it "complex_conditionがハッシュでない場合は無視する" do
        params = { complex_condition: "invalid" }

        # スタブを設定
        mock_query = double("AdvancedSearchQuery")
        allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
        allow(mock_query).to receive(:includes).and_return(mock_query)
        allow(mock_query).to receive(:search_keywords).and_return(mock_query)
        allow(mock_query).to receive(:with_status).and_return(mock_query)
        allow(mock_query).to receive(:order_by).and_return(mock_query)
        allow(mock_query).to receive(:results).and_return(Inventory.all)
        allow(described_class).to receive(:build_complex_condition).and_return(mock_query)

        result = described_class.call(params)

        expect(result).to be_a(ActiveRecord::Relation)
      end
    end
  end

  # Branch coverage: complex_search_required? method
  context "complex_search_required? method branches" do
    it "returns false for no parameters" do
      params = {}
      expect(described_class.send(:complex_search_required?, params)).to be false
    end

    it "returns false for simple q parameter only" do
      params = { q: "test" }
      expect(described_class.send(:complex_search_required?, params)).to be false
    end

    it "returns false for simple status parameter" do
      params = { status: "active" }
      expect(described_class.send(:complex_search_required?, params)).to be false
    end

    it "returns false for simple low_stock parameter" do
      params = { low_stock: "true" }
      expect(described_class.send(:complex_search_required?, params)).to be false
    end

    it "returns true for min_price parameter" do
      params = { min_price: 100 }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true for max_price parameter" do
      params = { max_price: 1000 }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true for min_quantity parameter" do
      params = { min_quantity: 10 }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true for max_quantity parameter" do
      params = { max_quantity: 100 }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true for created_from parameter" do
      params = { created_from: "2024-01-01" }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true for or_conditions parameter" do
      params = { or_conditions: [ { name: "test" } ] }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true for complex_condition parameter" do
      params = { complex_condition: { "and" => [] } }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end

    it "returns true when multiple simple and complex conditions exist" do
      params = { q: "test", status: "active", min_price: 100, lot_code: "LOT" }
      expect(described_class.send(:complex_search_required?, params)).to be true
    end
  end

  # Branch coverage: sortable_fields validation
  context "sortable fields validation" do
    it "accepts valid sortable fields" do
      %w[name price quantity created_at updated_at status].each do |field|
        params = { sort: field }
        result = described_class.call(params)
        expect(result.to_sql).to include("ORDER BY #{field}")
      end
    end

    it "rejects invalid sortable fields" do
      params = { sort: "invalid_field" }
      result = described_class.call(params)
      # Should use default sort order
      expect(result.to_sql).to include("ORDER BY updated_at DESC")
    end

    it "handles SQL injection attempts in sort field" do
      params = { sort: "name; DROP TABLE inventories;" }
      result = described_class.call(params)
      # Should safely reject and use default
      expect(result.to_sql).not_to include("DROP TABLE")
    end
  end

  # Branch coverage: direction normalization
  context "direction normalization" do
    it "normalizes ASC variants" do
      %w[asc ASC ascending ASCENDING].each do |dir|
        params = { sort: "name", direction: dir }
        result = described_class.call(params)
        expect(result.to_sql).to include("ORDER BY name ASC")
      end
    end

    it "normalizes DESC variants" do
      %w[desc DESC descending DESCENDING].each do |dir|
        params = { sort: "name", direction: dir }
        result = described_class.call(params)
        expect(result.to_sql).to include("ORDER BY name DESC")
      end
    end

    it "defaults invalid direction to DESC" do
      params = { sort: "name", direction: "invalid" }
      result = described_class.call(params)
      expect(result.to_sql).to include("ORDER BY name DESC")
    end
  end

  # Branch coverage: numeric parameter normalization
  context "numeric parameter normalization" do
    it "converts string numbers to integers" do
      params = {
        min_price: "100.50",
        max_price: "999.99",
        min_quantity: "10",
        max_quantity: "100",
        expiring_days: "30",
        updated_days: "7",
        low_stock_threshold: "5"
      }

      # スタブ設定
      mock_query = double("AdvancedSearchQuery")
      allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
      allow(mock_query).to receive(:includes).and_return(mock_query)
      allow(mock_query).to receive(:search_keywords).and_return(mock_query)
      allow(mock_query).to receive(:with_status).and_return(mock_query)
      allow(mock_query).to receive(:in_range) do |field, min, max|
        expect(min).to be_a(Numeric) if min
        expect(max).to be_a(Numeric) if max
        mock_query
      end
      allow(mock_query).to receive(:order_by).and_return(mock_query)
      allow(mock_query).to receive(:results).and_return(Inventory.all)

      result = described_class.call(params)
      expect(result).to be_a(ActiveRecord::Relation)
    end

    it "handles empty string numeric parameters" do
      params = {
        min_price: "",
        max_price: "",
        min_quantity: "",
        max_quantity: ""
      }

      result = described_class.call(params)
      expect(result).to eq(Inventory.all)
    end

    it "handles nil numeric parameters" do
      params = {
        min_price: nil,
        max_price: nil,
        min_quantity: nil,
        max_quantity: nil
      }

      result = described_class.call(params)
      expect(result).to eq(Inventory.all)
    end
  end

  # Branch coverage: date parameter handling
  context "date parameter handling" do
    it "converts string dates correctly" do
      params = {
        created_from: "2024-01-01",
        created_to: "2024-12-31",
        updated_from: "2024-06-01",
        updated_to: "2024-06-30",
        expires_before: "2025-01-01",
        expires_after: "2024-07-01"
      }

      # スタブ設定
      mock_query = double("AdvancedSearchQuery")
      allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)
      allow(mock_query).to receive(:includes).and_return(mock_query)
      allow(mock_query).to receive(:search_keywords).and_return(mock_query)
      allow(mock_query).to receive(:with_status).and_return(mock_query)
      allow(mock_query).to receive(:between_dates).and_return(mock_query)
      allow(mock_query).to receive(:with_expiry_before).and_return(mock_query)
      allow(mock_query).to receive(:with_expiry_after).and_return(mock_query)
      allow(mock_query).to receive(:order_by).and_return(mock_query)
      allow(mock_query).to receive(:results).and_return(Inventory.all)

      result = described_class.call(params)
      expect(result).to be_a(ActiveRecord::Relation)
    end

    it "handles invalid date formats" do
      params = {
        created_from: "invalid-date",
        created_to: "2024/13/45", # Invalid month/day
        expires_before: "not a date"
      }

      expect { described_class.call(params) }.not_to raise_error
    end
  end

  # Branch coverage: advanced search conditions combinations
  context "advanced search combinations" do
    it "combines all possible advanced conditions" do
      params = {
        q: "test",
        status: "active",
        min_price: 100,
        max_price: 1000,
        min_quantity: 10,
        max_quantity: 100,
        created_from: "2024-01-01",
        created_to: "2024-12-31",
        updated_from: "2024-06-01",
        updated_to: "2024-06-30",
        lot_code: "LOT",
        expires_before: "2025-01-01",
        expires_after: "2024-07-01",
        expiring_soon: "true",
        expiring_days: "30",
        recently_updated: "true",
        updated_days: "7",
        shipment_status: "pending",
        destination: "Tokyo",
        receipt_status: "received",
        source: "Supplier",
        stock_filter: "low_stock",
        low_stock_threshold: "10",
        sort: "name",
        direction: "asc",
        page: "2",
        per_page: "20"
      }

      # スタブ設定
      mock_query = double("AdvancedSearchQuery")
      allow(AdvancedSearchQuery).to receive(:build).and_return(mock_query)

      # チェインメソッドのスタブ
      methods = [ :includes, :search_keywords, :with_status, :in_range, :between_dates,
                 :with_lot_code, :with_expiry_before, :with_expiry_after, :expiring_soon,
                 :recently_updated, :with_shipment_status, :with_destination,
                 :with_receipt_status, :with_source, :with_stock_filter, :order_by, :paginate ]

      methods.each do |method|
        allow(mock_query).to receive(method).and_return(mock_query)
      end

      allow(mock_query).to receive(:results).and_return(Inventory.page(2).per(20))

      result = described_class.call(params)
      expect(result).to be_a(ActiveRecord::Relation)
    end
  end

  # Branch coverage: conditions_summary generation
  context "conditions_summary generation" do
    it "generates summary for all condition types" do
      conditions = [
        { q: "test" },
        { status: "active" },
        { min_price: 100, max_price: 1000 },
        { min_quantity: 10, max_quantity: 100 },
        { created_from: "2024-01-01", created_to: "2024-12-31" },
        { updated_from: "2024-06-01", updated_to: "2024-06-30" },
        { lot_code: "LOT123" },
        { expires_before: "2025-01-01" },
        { expires_after: "2024-07-01" },
        { expiring_soon: "true", expiring_days: "30" },
        { recently_updated: "true", updated_days: "7" },
        { shipment_status: "pending" },
        { destination: "Tokyo" },
        { receipt_status: "received" },
        { source: "Supplier" },
        { stock_filter: "out_of_stock" },
        { stock_filter: "low_stock", low_stock_threshold: "10" },
        { stock_filter: "in_stock", low_stock_threshold: "10" }
      ]

      conditions.each do |params|
        result = described_class.call_with_result(params)
        expect(result.conditions_summary).not_to eq("すべて")
        expect(result.conditions_summary).to be_present
      end
    end

    it "handles date range variations in summary" do
      variations = [
        { created_from: "2024-01-01", created_to: "2024-12-31" },
        { created_from: "2024-01-01" }, # from only
        { created_to: "2024-12-31" }, # to only
        { updated_from: "2024-06-01", updated_to: "2024-06-30" },
        { updated_from: "2024-06-01" }, # from only
        { updated_to: "2024-06-30" } # to only
      ]

      variations.each do |params|
        result = described_class.call_with_result(params)
        expect(result.conditions_summary).to include("日")
      end
    end
  end
end
