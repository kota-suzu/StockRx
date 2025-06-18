# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchQuery, type: :service do
  describe ".call" do
    # 各テストの前後でデータをクリア
    before(:each) do
      Inventory.destroy_all
      # テストデータを作成
      @@inventory1 = create(:inventory, name: "Test Product 1", quantity: 10, price: 1000)
      @@inventory2 = create(:inventory, name: "Test Product 2", quantity: 50, price: 2000)
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
          expect(result).to include(@inventory2, inventory3)
          expect(result).not_to include(@inventory1, inventory4)
        end
      end

      describe "最大在庫数フィルター" do
        it "指定した最大在庫数以下の商品のみを返す" do
          params = { max_quantity: 50 }
          result = described_class.call(params)
          
          expect(result.count).to eq(3)
          expect(result).to include(@inventory1, @inventory2, inventory4)
          expect(result).not_to include(inventory3)
        end
      end

      describe "在庫数範囲フィルター（最小・最大指定）" do
        it "指定した範囲内の在庫数の商品のみを返す" do
          params = { min_quantity: 10, max_quantity: 50 }
          result = described_class.call(params)
          
          expect(result.count).to eq(2)
          expect(result).to include(@inventory1, @inventory2)
          expect(result).not_to include(inventory3, inventory4)
        end
      end

      describe "在庫数0の商品を含む範囲フィルター" do
        it "最小在庫数0を指定した場合、在庫切れ商品も含める" do
          params = { min_quantity: 0, max_quantity: 10 }
          result = described_class.call(params)
          
          expect(result.count).to eq(2)
          expect(result).to include(@inventory1, inventory4)
          expect(result).not_to include(@inventory2, inventory3)
        end
      end
    end

    context "他のフィルターとの組み合わせ" do
      it "キーワード検索と在庫数範囲フィルターを組み合わせて使用できる" do
        params = { q: "Test", min_quantity: 20 }
        result = described_class.call(params)
        
        expect(result.count).to eq(2)
        expect(result).to include(@inventory2, inventory3)
        expect(result).not_to include(@inventory1, inventory4)
      end

      it "ステータスフィルターと在庫数範囲フィルターを組み合わせて使用できる" do
        @inventory1.update!(status: "active")
        @inventory2.update!(status: "archived")
        inventory3.update!(status: "active")
        inventory4.update!(status: "archived")
        
        params = { status: "active", min_quantity: 10, max_quantity: 100 }
        result = described_class.call(params)
        
        expect(result.count).to eq(2)
        expect(result).to include(@inventory1, inventory3)
        expect(result).not_to include(@inventory2, inventory4)
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
          
          # min_quantity = 0, max_quantity = 50として処理される
          expect(result.count).to eq(3)
          expect(result).to include(@inventory1, @inventory2, inventory4)
          expect(result).not_to include(inventory3)
        end

        it "負の最大在庫数を0に変換する" do
          params = { min_quantity: 0, max_quantity: -10 }
          result = described_class.call(params)
          
          # min_quantity = 0, max_quantity = 0として処理される
          expect(result.count).to eq(1)
          expect(result).to include(inventory4)
          expect(result).not_to include(@inventory1, @inventory2, inventory3)
        end

        it "両方が負の値の場合、両方を0に変換する" do
          params = { min_quantity: -50, max_quantity: -10 }
          result = described_class.call(params)
          
          # min_quantity = 0, max_quantity = 0として処理される
          expect(result.count).to eq(1)
          expect(result).to include(inventory4)
        end
      end

      describe "最小値と最大値の入れ替え処理" do
        it "最小値が最大値より大きい場合、値を入れ替える" do
          params = { min_quantity: 100, max_quantity: 10 }
          result = described_class.call(params)
          
          # min_quantity = 10, max_quantity = 100として処理される
          expect(result.count).to eq(3)
          expect(result).to include(@inventory1, @inventory2, inventory3)
          expect(result).not_to include(inventory4)
        end

        it "負の値を含む場合でも、変換後に入れ替え処理を行う" do
          params = { min_quantity: 50, max_quantity: -10 }
          result = described_class.call(params)
          
          # max_quantity = 0に変換後、min_quantity = 0, max_quantity = 50として入れ替えられる
          expect(result.count).to eq(3)
          expect(result).to include(@inventory1, @inventory2, inventory4)
          expect(result).not_to include(inventory3)
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
        expect(result.count).to be > 1000
      ensure
        ActiveSupport::Notifications.unsubscribe("sql.active_record")
      end
    end
  end
end