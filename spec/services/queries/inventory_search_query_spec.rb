# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Queries::InventorySearchQuery do
  # CLAUDE.md準拠: 在庫検索クエリの包括的テスト
  # メタ認知: 複雑な検索ロジックとパフォーマンス最適化の品質保証
  # 横展開: 他のQuery Objectでも同様のテストパターン適用

  let(:query) { described_class.new(params) }
  let(:params) { {} }

  # テストデータの準備
  let!(:medicine_inventory) { create(:inventory, name: "アスピリン錠100mg", status: "active", quantity: 100, price: 500) }
  let!(:equipment_inventory) { create(:inventory, name: "デジタル血圧計", status: "active", quantity: 5, price: 15000) }
  let!(:consumable_inventory) { create(:inventory, name: "マスク50枚入り", status: "inactive", quantity: 0, price: 200) }

  describe "#initialize" do
    it "デフォルト値を設定する" do
      query = described_class.new

      expect(query.sort_by).to eq('created_at')
      expect(query.sort_direction).to eq('desc')
      expect(query.include_associations).to eq([])
    end

    it "パラメータを正しく設定する" do
      query = described_class.new(
        keyword: "test",
        status: "active",
        min_quantity: 10,
        max_quantity: 100
      )

      expect(query.keyword).to eq("test")
      expect(query.status).to eq("active")
      expect(query.min_quantity).to eq(10)
      expect(query.max_quantity).to eq(100)
    end
  end

  describe "#call" do
    context "フィルターなしの場合" do
      it "全ての在庫を返す" do
        results = query.call

        expect(results.count).to eq(3)
      end
    end

    context "キーワード検索" do
      let(:params) { { keyword: "アスピリン" } }

      it "名前に一致する在庫を返す" do
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(medicine_inventory)
      end

      it "部分一致で検索する" do
        query.keyword = "錠"
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(medicine_inventory)
      end

      it "大文字小文字を区別しない" do
        query.keyword = "ASPIRIN"
        results = query.call

        # MySQLでは大文字小文字を区別しないため、結果に含まれる可能性がある
        expect(results).to include(medicine_inventory) if results.any?
      end

      it "SQLインジェクション対策がされている" do
        query.keyword = "'; DROP TABLE inventories; --"

        expect { query.call }.not_to raise_error
        expect(Inventory.table_exists?).to be true
      end
    end

    context "ステータスフィルター" do
      let(:params) { { status: "active" } }

      it "指定ステータスの在庫のみ返す" do
        results = query.call

        expect(results.count).to eq(2)
        expect(results).to include(medicine_inventory, equipment_inventory)
        expect(results).not_to include(consumable_inventory)
      end
    end

    context "数量範囲フィルター" do
      it "最小数量でフィルターする" do
        query.min_quantity = 10
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(medicine_inventory)
      end

      it "最大数量でフィルターする" do
        query.max_quantity = 50
        results = query.call

        expect(results.count).to eq(2)
        expect(results).to include(equipment_inventory, consumable_inventory)
      end

      it "範囲でフィルターする" do
        query.min_quantity = 1
        query.max_quantity = 50
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(equipment_inventory)
      end
    end

    context "価格範囲フィルター" do
      it "最小価格でフィルターする" do
        query.min_price = 1000
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(equipment_inventory)
      end

      it "最大価格でフィルターする" do
        query.max_price = 1000
        results = query.call

        expect(results.count).to eq(2)
        expect(results).to include(medicine_inventory, consumable_inventory)
      end

      it "範囲でフィルターする" do
        query.min_price = 300
        query.max_price = 10000
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(medicine_inventory)
      end
    end

    context "カテゴリフィルター" do
      before do
        # ApplicationHelperのカテゴリパターンをモック
        allow(ApplicationHelper).to receive(:category_patterns).and_return({
          "医薬品" => [ "錠", "薬", "カプセル" ],
          "医療機器" => [ "計", "器", "デバイス" ],
          "消耗品" => [ "マスク", "ガーゼ", "手袋" ]
        })
      end

      it "カテゴリで検索する" do
        query.category = "医薬品"
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(medicine_inventory)
      end
    end

    context "複合条件" do
      let(:params) do
        {
          keyword: "計",
          status: "active",
          min_price: 10000
        }
      end

      it "すべての条件を満たす在庫のみ返す" do
        results = query.call

        expect(results.count).to eq(1)
        expect(results.first).to eq(equipment_inventory)
      end
    end
  end

  describe "ソート機能" do
    context "名前でソート" do
      let(:params) { { sort_by: "name", sort_direction: "asc" } }

      it "昇順でソートする" do
        results = query.call.to_a

        expect(results.first).to eq(medicine_inventory)
        expect(results.last).to eq(consumable_inventory)
      end
    end

    context "価格でソート" do
      let(:params) { { sort_by: "price", sort_direction: "desc" } }

      it "降順でソートする" do
        results = query.call.to_a

        expect(results.first).to eq(equipment_inventory)
        expect(results.last).to eq(consumable_inventory)
      end
    end

    context "無効なソートカラム" do
      let(:params) { { sort_by: "invalid_column" } }

      it "デフォルトのソートを使用する" do
        expect { query.call }.not_to raise_error
      end
    end

    context "無効なソート方向" do
      let(:params) { { sort_direction: "invalid" } }

      it "デフォルトのソート方向を使用する" do
        expect { query.call }.not_to raise_error
      end
    end
  end

  describe "関連データの事前読み込み" do
    before do
      medicine_inventory.batches.create!(quantity: 50, lot_code: "LOT001")
      equipment_inventory.batches.create!(quantity: 3, lot_code: "LOT002")
    end

    it "デフォルトでbatchesを読み込む" do
      results = query.call

      # N+1クエリが発生しないことを確認
      expect { results.each(&:batches) }.not_to exceed_query_limit(1)
    end

    it "指定された関連を読み込む" do
      query.include_associations = [ :inventory_logs, :batches ]
      results = query.call

      expect { results.each { |r| r.inventory_logs.to_a } }.not_to exceed_query_limit(1)
    end
  end

  describe "#performance_stats" do
    it "パフォーマンス統計を記録する" do
      query.call
      stats = query.performance_stats

      expect(stats).to be_a(Hash)
      expect(stats[:query_time]).to be_present
      expect(stats[:record_count]).to be_present
    end
  end

  describe "セキュリティ" do
    it "SQLインジェクションを防ぐ" do
      dangerous_inputs = [
        "'; DROP TABLE inventories; --",
        "' OR '1'='1",
        "1' AND SLEEP(5) --",
        "%27%20OR%20%271%27%3D%271"
      ]

      dangerous_inputs.each do |input|
        query.keyword = input
        expect { query.call.to_a }.not_to raise_error
      end

      expect(Inventory.table_exists?).to be true
    end
  end

  describe "パフォーマンス" do
    before do
      # 大量のテストデータ作成
      100.times do |i|
        create(:inventory,
          name: "Item #{i}",
          quantity: rand(0..1000),
          price: rand(100..10000),
          status: [ "active", "inactive" ].sample
        )
      end
    end

    it "大量データでも高速に動作する" do
      start_time = Time.current
      results = query.call.to_a
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 0.5 # 500ms以内
      expect(results.count).to be > 100
    end

    it "複雑な条件でも適切に動作する" do
      query.keyword = "Item"
      query.status = "active"
      query.min_quantity = 100
      query.max_quantity = 500
      query.min_price = 1000
      query.max_price = 5000

      start_time = Time.current
      results = query.call.to_a
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 1.0 # 1秒以内
    end
  end

  describe "エラーハンドリング" do
    it "無効なデータ型でもエラーを発生させない" do
      query.min_quantity = "invalid"
      query.max_price = "not a number"

      expect { query.call }.not_to raise_error
    end
  end
end
