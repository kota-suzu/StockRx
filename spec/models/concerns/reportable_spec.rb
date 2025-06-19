# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Reportable do
  # CLAUDE.md準拠: レポート生成機能の包括的テスト
  # メタ認知: 多数の条件分岐とデータ集計ロジックの品質保証
  # 横展開: 他のレポート系concernでも同様のテストパターン適用

  # テスト用のダミークラス作成
  let(:dummy_class) do
    Class.new do
      include Reportable

      # ActiveRecord::Base相当のメソッドをモック
      def self.count
        0
      end

      def self.sum(column)
        0
      end

      def self.where(conditions)
        self
      end

      def self.all
        []
      end

      def self.low_stock
        where(quantity: 0..5)
      end

      def self.out_of_stock
        where(quantity: 0)
      end

      def self.active
        where(status: :active)
      end

      def self.find_each(&block)
        all.each(&block)
      end

      def self.order(args)
        self
      end

      def self.select(fields)
        self
      end

      # インスタンスメソッド
      attr_accessor :id, :name, :quantity, :price, :status, :updated_at

      def initialize(attrs = {})
        @id = attrs[:id] || 1
        @name = attrs[:name] || "Test Item"
        @quantity = attrs[:quantity] || 10
        @price = attrs[:price] || 100
        @status = attrs[:status] || :active
        @updated_at = attrs[:updated_at] || Time.current
        @batches = attrs[:batches] || []
      end

      def batches
        @batches
      end

      def stock_status
        return :out_of_stock if @quantity == 0
        return :low_stock if @quantity <= 5
        :in_stock
      end

      def nearest_expiry_date
        return nil if @batches.empty?
        @batches.map(&:expiration_date).compact.min
      end
    end
  end

  let(:test_class) { dummy_class }
  let(:test_instance) { test_class.new(id: 1, name: "Test Item", quantity: 10, price: 100) }

  # ============================================
  # インスタンスメソッドのテスト
  # ============================================

  describe '#generate_stock_report' do
    context 'with basic attributes' do
      it 'generates report with all basic fields' do
        report = test_instance.generate_stock_report

        expect(report).to include(
          id: 1,
          name: "Test Item",
          current_quantity: 10,
          value: 1000,
          status: :in_stock,
          batches_count: 0,
          last_updated: test_instance.updated_at,
          nearest_expiry: nil
        )
      end
    end

    context 'with different stock statuses' do
      it 'reports out_of_stock status' do
        instance = test_class.new(quantity: 0)
        report = instance.generate_stock_report

        expect(report[:status]).to eq(:out_of_stock)
        expect(report[:value]).to eq(0)
      end

      it 'reports low_stock status' do
        instance = test_class.new(quantity: 5)
        report = instance.generate_stock_report

        expect(report[:status]).to eq(:low_stock)
        expect(report[:value]).to eq(500)
      end
    end

    context 'with batches' do
      it 'includes batch count' do
        batch1 = double(expiration_date: 1.month.from_now)
        batch2 = double(expiration_date: 2.months.from_now)
        test_instance.instance_variable_set(:@batches, [ batch1, batch2 ])

        report = test_instance.generate_stock_report

        expect(report[:batches_count]).to eq(2)
        expect(report[:nearest_expiry]).to eq(1.month.from_now.to_date)
      end
    end

    context 'without batches method' do
      it 'handles missing batches method gracefully' do
        instance = test_class.new
        allow(instance).to receive(:respond_to?).with(:batches).and_return(false)

        report = instance.generate_stock_report

        expect(report[:batches_count]).to eq(0)
      end
    end

    context 'without nearest_expiry_date method' do
      it 'handles missing nearest_expiry_date method gracefully' do
        instance = test_class.new
        allow(instance).to receive(:respond_to?).with(:nearest_expiry_date).and_return(false)

        report = instance.generate_stock_report

        expect(report[:nearest_expiry]).to be_nil
      end
    end
  end

  # ============================================
  # クラスメソッドのテスト
  # ============================================

  describe '.generate_inventory_report' do
    before do
      allow(test_class).to receive(:count).and_return(100)
      allow(test_class).to receive(:sum).with("quantity * price").and_return(50000)
      allow(test_class).to receive(:low_stock).and_return(double(count: 10))
      allow(test_class).to receive(:out_of_stock).and_return(double(count: 5))
      allow(test_class).to receive(:active).and_return(double(count: 90))
      allow(test_class).to receive(:where).with(status: :archived).and_return(double(count: 10))
      allow(test_class).to receive(:get_summary_data).and_return({})
      allow(test_class).to receive(:get_detailed_data).and_return([])
    end

    context 'with default options' do
      it 'generates basic report structure' do
        report = test_class.generate_inventory_report

        expect(report).to include(
          generated_at: be_a(Time),
          as_of_date: be_a(Time),
          total_items: 100,
          total_value: 50000,
          low_stock_items: 10,
          out_of_stock_items: 5
        )

        expect(report[:items_by_status]).to eq({
          active: 90,
          archived: 10
        })
      end
    end

    context 'with as_of_date option' do
      it 'uses specified date' do
        specific_date = 1.week.ago
        report = test_class.generate_inventory_report(as_of_date: specific_date)

        expect(report[:as_of_date]).to eq(specific_date)
      end
    end

    context 'with include_details option' do
      it 'includes detailed item reports' do
        item1 = test_class.new(id: 1, name: "Item 1")
        item2 = test_class.new(id: 2, name: "Item 2")
        allow(test_class).to receive(:all).and_return([ item1, item2 ])

        report = test_class.generate_inventory_report(include_details: true)

        expect(report[:items]).to be_an(Array)
        expect(report[:items].size).to eq(2)
        expect(report[:items].first).to include(id: 1, name: "Item 1")
      end
    end

    context 'with compare_with_previous option' do
      before do
        allow(test_class).to receive(:get_historical_data).and_return({
          total_items: 80,
          total_value: 40000
        })
      end

      it 'includes comparison data with default 30 days' do
        report = test_class.generate_inventory_report(compare_with_previous: true)

        expect(report[:comparison]).to include(
          previous_total_items: 80,
          previous_total_value: 40000,
          items_change: 20,
          value_change: 10000,
          change_percentage: 25.0
        )
      end

      it 'uses custom compare_days' do
        expect(test_class).to receive(:get_historical_data).with(60.days.ago)

        test_class.generate_inventory_report(
          compare_with_previous: true,
          compare_days: 60
        )
      end

      it 'handles zero previous value' do
        allow(test_class).to receive(:get_historical_data).and_return({
          total_items: 0,
          total_value: 0
        })

        report = test_class.generate_inventory_report(compare_with_previous: true)

        expect(report[:comparison][:change_percentage]).to eq(0)
      end
    end

    context 'with compare_with option' do
      let(:compare_date) { 1.month.ago }

      before do
        allow(test_class).to receive(:get_historical_data).with(compare_date).and_return({
          total_count: 90,
          total_value: 45000
        })
        allow(test_class).to receive(:get_historical_data).with(be_a(Time)).and_return({
          total_count: 100,
          total_value: 50000
        })
        allow(test_class).to receive(:calculate_comparison_diff)
      end

      it 'includes comparison with specific date' do
        report = test_class.generate_inventory_report(compare_with: compare_date)

        expect(report[:comparison]).to include(
          previous_date: compare_date,
          previous_data: { total_count: 90, total_value: 45000 },
          current_data: { total_count: 100, total_value: 50000 }
        )
      end
    end

    context 'with output_file option' do
      it 'calls output_report_to_file' do
        expect(test_class).to receive(:output_report_to_file)

        test_class.generate_inventory_report(output_file: true)
      end
    end
  end

  describe '.get_historical_data' do
    let(:test_date) { 1.week.ago }

    before do
      # InventoryLogのモック
      allow(InventoryLog).to receive(:where).and_return(double(
        distinct: double(pluck: [ 1, 2, 3 ])
      ))
      allow(test_class).to receive(:where).and_return(double(
        pluck: [ [ 1, 100 ], [ 2, 200 ], [ 3, 300 ] ]
      ))
    end

    it 'retrieves historical data from inventory logs' do
      # サブクエリとfind_by_sqlのモック
      log1 = double(inventory_id: 1, current_quantity: 10)
      log2 = double(inventory_id: 2, current_quantity: 20)
      log3 = double(inventory_id: 3, current_quantity: 30)

      allow(InventoryLog).to receive(:find_by_sql).and_return([ log1, log2, log3 ])

      result = test_class.get_historical_data(test_date)

      expect(result).to eq({
        total_count: 3,
        total_value: 14000 # (10*100) + (20*200) + (30*300)
      })
    end

    it 'handles missing price data' do
      allow(test_class).to receive(:where).and_return(double(
        pluck: [ [ 1, 100 ], [ 2, nil ] ]
      ))

      log1 = double(inventory_id: 1, current_quantity: 10)
      log2 = double(inventory_id: 3, current_quantity: 30) # ID 3 has no price

      allow(InventoryLog).to receive(:find_by_sql).and_return([ log1, log2 ])

      result = test_class.get_historical_data(test_date)

      expect(result[:total_value]).to eq(1000) # Only 10*100
    end
  end

  describe '.export_inventory_report_csv' do
    it 'generates CSV with headers' do
      allow(test_class).to receive(:all).and_return([])

      csv_content = test_class.export_inventory_report_csv
      parsed_csv = CSV.parse(csv_content)

      expect(parsed_csv[0]).to eq([
        "ID", "商品名", "現在数量", "価格", "合計金額",
        "状態", "バッチ数", "最終更新日", "最短期限日"
      ])
    end

    it 'includes item data in CSV' do
      item = test_class.new(
        id: 1,
        name: "Test Item",
        quantity: 10,
        price: 100,
        updated_at: Time.parse("2024-01-01 12:00:00")
      )
      allow(test_class).to receive(:all).and_return([ item ])

      csv_content = test_class.export_inventory_report_csv
      parsed_csv = CSV.parse(csv_content)

      expect(parsed_csv[1]).to eq([
        "1", "Test Item", "10", "100", "1000",
        "in_stock", "0", "2024-01-01 12:00:00", nil
      ])
    end

    it 'handles items with expiry dates' do
      item = test_class.new
      batch = double(expiration_date: Date.parse("2024-12-31"))
      item.instance_variable_set(:@batches, [ batch ])
      allow(test_class).to receive(:all).and_return([ item ])

      csv_content = test_class.export_inventory_report_csv
      parsed_csv = CSV.parse(csv_content)

      expect(parsed_csv[1][8]).to eq("2024-12-31")
    end
  end

  describe '.generate_analysis_json' do
    before do
      allow(test_class).to receive(:generate_inventory_report).and_return({
        total_items: 100,
        total_value: 50000,
        low_stock_items: 10,
        out_of_stock_items: 5,
        items_by_status: { active: 90, archived: 10 },
        items: [
          { id: 1, name: "Item 1", current_quantity: 10, value: 1000, status: :in_stock },
          { id: 2, name: "Item 2", current_quantity: 0, value: 0, status: :out_of_stock }
        ]
      })
    end

    it 'generates JSON with summary and items' do
      json_string = test_class.generate_analysis_json
      parsed_json = JSON.parse(json_string)

      expect(parsed_json["summary"]).to eq({
        "total_items" => 100,
        "total_value" => 50000,
        "low_stock_items" => 10,
        "out_of_stock_items" => 5
      })

      expect(parsed_json["status_distribution"]).to eq({
        "active" => 90,
        "archived" => 10
      })

      expect(parsed_json["items"]).to be_an(Array)
      expect(parsed_json["items"].first).to eq({
        "id" => 1,
        "name" => "Item 1",
        "quantity" => 10,
        "value" => 1000,
        "status" => "in_stock"
      })
    end
  end

  # ============================================
  # プライベートメソッドのテスト（send経由）
  # ============================================

  describe 'private methods' do
    describe '.get_summary_data' do
      before do
        allow(test_class).to receive(:count).and_return(100)
        allow(test_class).to receive(:where).with("quantity > 0").and_return(double(count: 95))
        allow(test_class).to receive(:where).with(quantity: 0).and_return(double(count: 5))
        allow(test_class).to receive(:where).with("quantity > 0 AND quantity <= 5").and_return(double(count: 10))
        allow(test_class).to receive(:sum).with(:quantity).and_return(1000)
        allow(test_class).to receive(:calculate_total_value).and_return(50000)
        allow(test_class).to receive(:where).with(status: :active).and_return(double(count: 90))
        allow(test_class).to receive(:where).with(status: :archived).and_return(double(count: 10))
      end

      it 'returns comprehensive summary data' do
        summary = test_class.send(:get_summary_data, Time.current)

        expect(summary).to eq({
          total_count: 100,
          in_stock_count: 95,
          out_of_stock_count: 5,
          low_stock_count: 10,
          total_quantity: 1000,
          total_value: 50000,
          active_count: 90,
          archived_count: 10
        })
      end
    end

    describe '.get_detailed_data' do
      let(:mock_relation) { double('ActiveRecord::Relation') }

      before do
        allow(test_class).to receive(:all).and_return(mock_relation)
        allow(mock_relation).to receive(:where).and_return(mock_relation)
        allow(mock_relation).to receive(:order).and_return(mock_relation)
        allow(mock_relation).to receive(:select).and_return(mock_relation)
      end

      it 'applies status filter' do
        expect(mock_relation).to receive(:where).with(status: :active)

        test_class.send(:get_detailed_data, { status: :active })
      end

      it 'applies low stock filter' do
        expect(mock_relation).to receive(:where).with("quantity <= ?", 5)

        test_class.send(:get_detailed_data, { low_stock_only: true, low_stock_threshold: 5 })
      end

      it 'applies out of stock filter' do
        expect(mock_relation).to receive(:where).with(quantity: 0)

        test_class.send(:get_detailed_data, { out_of_stock_only: true })
      end

      it 'applies sorting' do
        expect(mock_relation).to receive(:order).with(quantity: :desc)

        test_class.send(:get_detailed_data, { sort_by: :quantity, sort_direction: :desc })
      end

      it 'defaults to ascending sort' do
        expect(mock_relation).to receive(:order).with(name: :asc)

        test_class.send(:get_detailed_data, { sort_by: :name })
      end

      it 'selects specific fields' do
        expect(mock_relation).to receive(:select).with([ :id, :name, :quantity ])

        test_class.send(:get_detailed_data, { select_fields: [ :id, :name, :quantity ] })
      end
    end

    describe '.calculate_comparison_diff' do
      it 'calculates differences correctly' do
        comparison = {
          current_data: { total_count: 100, total_value: 50000 },
          previous_data: { total_count: 80, total_value: 40000 },
          diff: {}
        }

        test_class.send(:calculate_comparison_diff, comparison)

        expect(comparison[:diff]).to eq({
          total_count_diff: 20,
          total_count_percent: 25.0,
          total_value_diff: 10000,
          total_value_percent: 25.0
        })
      end
    end

    describe '.calculate_percent_change' do
      it 'calculates positive change' do
        result = test_class.send(:calculate_percent_change, 100, 150)
        expect(result).to eq(50.0)
      end

      it 'calculates negative change' do
        result = test_class.send(:calculate_percent_change, 100, 80)
        expect(result).to eq(-20.0)
      end

      it 'returns 0 for zero old value' do
        result = test_class.send(:calculate_percent_change, 0, 100)
        expect(result).to eq(0)
      end

      it 'handles float precision' do
        result = test_class.send(:calculate_percent_change, 3, 4)
        expect(result).to eq(33.33)
      end
    end

    describe '.output_report_to_file' do
      let(:report_data) { { test: "data" } }
      let(:temp_file) { Tempfile.new([ 'report', '.json' ]) }

      before do
        allow(Rails.root).to receive(:join).and_return(temp_file.path)
      end

      after do
        temp_file.close
        temp_file.unlink
      end

      it 'writes JSON file by default' do
        path = test_class.send(:output_report_to_file, report_data, {})

        content = File.read(path)
        expect(JSON.parse(content)).to eq({ "test" => "data" })
      end

      it 'writes to specified path' do
        custom_path = Tempfile.new([ 'custom', '.json' ]).path

        path = test_class.send(:output_report_to_file, report_data, { file_path: custom_path })

        expect(path).to eq(custom_path)
      end

      it 'calls CSV output for CSV format' do
        expect(test_class).to receive(:output_report_to_csv)

        test_class.send(:output_report_to_file, report_data, { file_format: :csv })
      end
    end

    describe '.output_report_to_csv' do
      let(:report_data) do
        {
          generated_at: Time.parse("2024-01-01 12:00:00"),
          as_of_date: Time.parse("2024-01-01 00:00:00"),
          summary: {
            total_items: 100,
            total_value: 50000
          },
          details: [
            double(attributes: { id: 1, name: "Item 1", quantity: 10 }),
            double(attributes: { id: 2, name: "Item 2", quantity: 20 })
          ]
        }
      end

      let(:temp_file) { Tempfile.new([ 'report', '.csv' ]) }

      after do
        temp_file.close
        temp_file.unlink
      end

      it 'writes CSV with headers and data' do
        test_class.send(:output_report_to_csv, report_data, temp_file.path)

        csv_content = CSV.read(temp_file.path)

        # Header section
        expect(csv_content[0]).to include("Inventory Report")
        expect(csv_content[0]).to include("Generated at: 2024-01-01 12:00:00")

        # Summary section
        expect(csv_content).to include([ "Summary" ])
        expect(csv_content).to include([ "Total items", 100 ])
        expect(csv_content).to include([ "Total value", 50000 ])

        # Details section
        expect(csv_content).to include([ "Details" ])
      end

      it 'handles empty details' do
        report_data[:details] = []

        expect {
          test_class.send(:output_report_to_csv, report_data, temp_file.path)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe 'edge cases' do
    describe 'nil handling' do
      it 'handles nil price in stock report' do
        instance = test_class.new(price: nil)

        expect {
          report = instance.generate_stock_report
          expect(report[:value]).to eq(0)
        }.not_to raise_error
      end

      it 'handles nil quantity in stock report' do
        instance = test_class.new(quantity: nil)

        expect {
          report = instance.generate_stock_report
          expect(report[:current_quantity]).to be_nil
        }.not_to raise_error
      end
    end

    describe 'empty data handling' do
      it 'generates empty CSV for no items' do
        allow(test_class).to receive(:all).and_return([])

        csv_content = test_class.export_inventory_report_csv
        parsed_csv = CSV.parse(csv_content)

        expect(parsed_csv.size).to eq(1) # Headers only
      end

      it 'handles empty analysis JSON' do
        allow(test_class).to receive(:generate_inventory_report).and_return({
          total_items: 0,
          total_value: 0,
          low_stock_items: 0,
          out_of_stock_items: 0,
          items_by_status: { active: 0, archived: 0 },
          items: []
        })

        json_string = test_class.generate_analysis_json
        parsed_json = JSON.parse(json_string)

        expect(parsed_json["items"]).to eq([])
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it 'generates reports efficiently for large datasets' do
      # 1000アイテムのシミュレーション
      items = 1000.times.map do |i|
        test_class.new(id: i, name: "Item #{i}", quantity: rand(0..100))
      end

      allow(test_class).to receive(:all).and_return(items)
      allow(test_class).to receive(:count).and_return(1000)

      start_time = Time.now
      test_class.generate_inventory_report(include_details: true)
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 100 # Should complete in under 100ms
    end

    it 'exports CSV efficiently' do
      items = 500.times.map do |i|
        test_class.new(id: i, name: "Item #{i}")
      end

      allow(test_class).to receive(:all).and_return(items)

      start_time = Time.now
      test_class.export_inventory_report_csv
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 50 # Should complete in under 50ms
    end
  end
end
