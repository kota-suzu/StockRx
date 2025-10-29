# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventorySearchForm, type: :model do
  let(:form) { described_class.new }

  describe "attributes" do
    it "has expected attributes" do
      expect(form).to respond_to(:name, :status, :min_price, :max_price)
      expect(form).to respond_to(:min_quantity, :max_quantity)
      expect(form).to respond_to(:created_from, :created_to, :updated_from, :updated_to)
      expect(form).to respond_to(:lot_code, :expires_before, :expires_after)
      expect(form).to respond_to(:search_type, :include_archived, :stock_filter)
      expect(form).to respond_to(:q, :low_stock, :advanced_search)
    end
  end

  describe "initialization" do
    it "sets default values" do
      expect(form.search_type).to eq("basic")
      expect(form.include_archived).to be false
      expect(form.low_stock_threshold).to eq(10)
      expect(form.low_stock).to be false
      expect(form.advanced_search).to be false
      expect(form.updated_days).to eq(7)
    end

    it "handles custom_conditions initialization" do
      expect(form.custom_conditions).to eq([])
      expect(form.or_conditions).to eq([])
      expect(form.complex_condition).to eq({})
    end

    it "maps sort and direction to sort_field and sort_direction" do
      form = described_class.new(sort: "name", direction: "asc")

      expect(form.sort_field).to eq("name")
      expect(form.sort_direction).to eq("asc")
    end
  end

  describe "validations" do
    describe "name length" do
      it "accepts names up to 255 characters" do
        form.name = "a" * 255
        expect(form).to be_valid
      end

      it "rejects names over 255 characters" do
        form.name = "a" * 256
        expect(form).not_to be_valid
        expect(form.errors[:name]).to include("は255文字以内で入力してください")
      end
    end

    describe "price validations" do
      it "accepts valid prices" do
        form.min_price = 100
        form.max_price = 500
        expect(form).to be_valid
      end

      it "rejects negative prices" do
        form.min_price = -10
        expect(form).not_to be_valid
        expect(form.errors[:min_price]).to include("は0以上の値にしてください")
      end

      it "accepts zero price" do
        form.min_price = 0
        expect(form).to be_valid
      end
    end

    describe "quantity validations" do
      it "accepts valid quantities" do
        form.min_quantity = 0
        form.max_quantity = 100
        expect(form).to be_valid
      end

      it "rejects negative quantities" do
        form.min_quantity = -5
        expect(form).not_to be_valid
        expect(form.errors[:min_quantity]).to include("は0以上の値にしてください")
      end
    end

    describe "search_type validation" do
      it "accepts valid search types" do
        %w[basic advanced custom].each do |type|
          form.search_type = type
          expect(form).to be_valid
        end
      end

      it "rejects invalid search types" do
        form.search_type = "invalid"
        expect(form).not_to be_valid
        expect(form.errors[:search_type]).to include("は一覧にありません")
      end
    end

    describe "stock_filter validation" do
      it "accepts valid stock filters" do
        %w[out_of_stock low_stock in_stock].each do |filter|
          form.stock_filter = filter
          expect(form).to be_valid
        end
      end

      it "accepts blank stock filter" do
        form.stock_filter = ""
        expect(form).to be_valid
      end

      it "rejects invalid stock filters" do
        form.stock_filter = "invalid"
        expect(form).not_to be_valid
        expect(form.errors[:stock_filter]).to include("は一覧にありません")
      end
    end

    describe "range consistency validations" do
      context "price range" do
        it "is valid when min_price <= max_price" do
          form.min_price = 100
          form.max_price = 200
          expect(form).to be_valid
        end

        it "is invalid when min_price > max_price" do
          form.min_price = 200
          form.max_price = 100
          form.valid?
          expect(form.errors[:max_price]).to be_present
        end
      end

      context "quantity range" do
        it "is valid when min_quantity <= max_quantity" do
          form.min_quantity = 10
          form.max_quantity = 20
          expect(form).to be_valid
        end

        it "is invalid when min_quantity > max_quantity" do
          form.min_quantity = 20
          form.max_quantity = 10
          form.valid?
          expect(form.errors[:max_quantity]).to be_present
        end
      end

      context "date range" do
        it "is valid when from_date <= to_date" do
          form.created_from = Date.today - 1.week
          form.created_to = Date.today
          expect(form).to be_valid
        end

        it "is invalid when from_date > to_date" do
          form.created_from = Date.today
          form.created_to = Date.today - 1.week
          form.valid?
          expect(form.errors[:created_to]).to be_present
        end
      end
    end
  end

  describe "#effective_name" do
    it "returns name when present" do
      form.name = "test_name"
      form.q = "test_q"
      expect(form.effective_name).to eq("test_name")
    end

    it "returns q when name is blank" do
      form.name = ""
      form.q = "test_q"
      expect(form.effective_name).to eq("test_q")
    end

    it "returns nil when both are blank" do
      form.name = ""
      form.q = ""
      expect(form.effective_name).to be_nil
    end
  end

  describe "condition checking methods" do
    describe "#has_search_conditions?" do
      it "returns true when basic conditions exist" do
        form.name = "test"
        expect(form.has_search_conditions?).to be true
      end

      it "returns true when advanced conditions exist" do
        form.lot_code = "LOT123"
        expect(form.has_search_conditions?).to be true
      end

      it "returns false when no conditions exist" do
        expect(form.has_search_conditions?).to be false
      end
    end

    describe "#basic_conditions?" do
      it "returns true for name condition" do
        form.name = "test"
        expect(form.basic_conditions?).to be true
      end

      it "returns true for status condition" do
        form.status = "active"
        expect(form.basic_conditions?).to be true
      end

      it "returns true for price range" do
        form.min_price = 100
        expect(form.basic_conditions?).to be true
      end

      it "returns true for low_stock flag" do
        form.low_stock = true
        expect(form.basic_conditions?).to be true
      end

      it "returns false when no basic conditions" do
        expect(form.basic_conditions?).to be false
      end
    end

    describe "#advanced_conditions?" do
      it "returns true for date range conditions" do
        form.created_from = Date.today - 1.week
        expect(form.advanced_conditions?).to be true
      end

      it "returns true for lot code" do
        form.lot_code = "LOT123"
        expect(form.advanced_conditions?).to be true
      end

      it "returns true for expiring_soon flag" do
        form.expiring_soon = true
        expect(form.advanced_conditions?).to be true
      end

      it "returns false when no advanced conditions" do
        expect(form.advanced_conditions?).to be false
      end
    end

    describe "#complex_search_required?" do
      it "returns true for complex conditions" do
        form.created_from = Date.today - 1.week
        expect(form.complex_search_required?).to be true
      end

      it "returns true for advanced_search flag" do
        form.advanced_search = true
        expect(form.complex_search_required?).to be true
      end

      it "returns false for basic conditions only" do
        form.name = "test"
        expect(form.complex_search_required?).to be false
      end
    end
  end

  describe "display methods" do
    describe "#price_range_display" do
      it "displays range when both values present" do
        form.min_price = 100
        form.max_price = 500
        result = form.price_range_display
        expect(result).not_to be_empty
      end

      it "displays from only when max_price missing" do
        form.min_price = 100
        result = form.price_range_display
        expect(result).not_to be_empty
      end

      it "returns empty string when no prices" do
        expect(form.price_range_display).to eq("")
      end
    end

    describe "#stock_filter_display" do
      it "returns translated out_of_stock" do
        form.stock_filter = "out_of_stock"
        allow(I18n).to receive(:t).with("inventories.search.stock_filter.out_of_stock").and_return("在庫切れ")
        expect(form.stock_filter_display).to eq("在庫切れ")
      end

      it "returns translated low_stock with threshold" do
        form.stock_filter = "low_stock"
        form.low_stock_threshold = 5
        allow(I18n).to receive(:t).with("inventories.search.stock_filter.low_stock", threshold: 5).and_return("在庫少")
        expect(form.stock_filter_display).to eq("在庫少")
      end

      it "returns empty string when no filter" do
        expect(form.stock_filter_display).to eq("")
      end
    end
  end

  describe "#to_params" do
    it "excludes blank values" do
      form.name = "test"
      form.status = ""
      form.min_price = nil

      params = form.to_params
      expect(params).to include("name" => "test")
      expect(params).not_to have_key("status")
      expect(params).not_to have_key("min_price")
    end
  end

  describe "#to_search_params" do
    it "converts to legacy format" do
      form.name = "test"
      form.low_stock = true
      form.min_price = 100

      params = form.to_search_params
      expect(params[:q]).to eq("test")
      expect(params[:low_stock]).to eq("true")
      expect(params[:min_price]).to eq(100)
    end

    it "sets advanced_search flag when advanced conditions exist" do
      form.lot_code = "LOT123"

      params = form.to_search_params
      expect(params[:advanced_search]).to eq("true")
    end
  end

  describe "search methods" do
    let!(:inventory1) { create(:inventory, name: "Test Product", status: "active", price: 100, quantity: 10) }
    let!(:inventory2) { create(:inventory, name: "Another Product", status: "archived", price: 200, quantity: 0) }
    let!(:inventory3) { create(:inventory, name: "Third Product", status: "active", price: 200, quantity: 0) }

    describe "#search" do
      it "returns empty relation when invalid" do
        form.min_price = -100  # Invalid
        expect(form.search).to eq(Inventory.none)
      end

      it "performs basic search for simple conditions" do
        form.search_type = "basic"
        form.name = "Test"

        results = form.search
        expect(results).to include(inventory1)
        expect(results).not_to include(inventory2)
      end

      it "determines search type automatically" do
        form.search_type = nil
        form.name = "Test"  # Basic condition

        results = form.search
        expect(results).to include(inventory1)
      end

      # Branch coverage: determine_search_type_and_execute method
      it "auto-detects basic search type" do
        form.search_type = nil
        form.status = "active"  # Only basic condition

        results = form.search
        expect(results).to include(inventory1, inventory3)
      end

      it "auto-detects advanced search type" do
        form.search_type = nil
        form.lot_code = "LOT123"  # Advanced condition

        allow(form).to receive(:perform_advanced_search).and_return(Inventory.none)
        form.search
        expect(form).to have_received(:perform_advanced_search)
      end

      it "auto-detects custom search type with custom_conditions" do
        form.search_type = nil
        form.custom_conditions = [ { field: "name", operator: "contains", value: "Test" } ]

        # カスタム検索はAdvancedSearchQueryを使用
        allow(AdvancedSearchQuery).to receive(:build).and_return(double(results: Inventory.none))
        results = form.search
        expect(results).to eq([])
      end

      it "auto-detects custom search type with complex_condition" do
        form.search_type = nil
        form.complex_condition = { type: "and", conditions: [] }

        # カスタム検索はAdvancedSearchQueryを使用
        allow(AdvancedSearchQuery).to receive(:build).and_return(double(results: Inventory.none))
        results = form.search
        expect(results).to eq([])
      end
    end

    describe "basic search functionality" do
      it "filters by name" do
        form.search_type = "basic"
        form.name = "Test"

        results = form.search
        expect(results).to include(inventory1)
        expect(results).not_to include(inventory2)
      end

      it "filters by status" do
        form.search_type = "basic"
        form.status = "active"

        results = form.search
        expect(results).to include(inventory1)
        expect(results).to include(inventory3)
        expect(results).not_to include(inventory2) # archived status should be excluded
      end

      it "filters by stock level" do
        form.search_type = "basic"
        form.low_stock = true

        results = form.search
        expect(results).to include(inventory3)  # quantity: 0, status: active
        expect(results).not_to include(inventory1)  # quantity: 10
        expect(results).not_to include(inventory2)  # archived, excluded by default
      end

      it "filters by price range" do
        form.search_type = "basic"
        form.min_price = 150
        form.max_price = 250

        results = form.search
        expect(results).to include(inventory3)  # price: 200, status: active
        expect(results).not_to include(inventory1)  # price: 100
        expect(results).not_to include(inventory2)  # archived, excluded by default
      end
    end
  end

  describe "edge cases" do
    it "handles nil attributes gracefully" do
      form = described_class.new(nil)
      expect(form.search_type).to eq("basic")
    end

    it "handles empty hash attributes" do
      form = described_class.new({})
      expect(form.search_type).to eq("basic")
    end

    it "handles string boolean values" do
      form = described_class.new(low_stock: "true", advanced_search: "false")
      expect(form.low_stock).to be true
      expect(form.advanced_search).to be false
    end
  end

  describe "private helper methods" do
    describe "#range_display_helper" do
      it "handles both values present", :fast do
        result = form.send(:range_display_helper, 10, 20, :default)
        expect(result).to be_present
      end

      it "handles only from value", :fast do
        result = form.send(:range_display_helper, 10, nil, :default)
        expect(result).to be_present
      end

      it "handles only to value", :fast do
        result = form.send(:range_display_helper, nil, 20, :default)
        expect(result).to be_present
      end

      it "returns empty string for no values", :ultra_fast do
        result = form.send(:range_display_helper, nil, nil, :default)
        expect(result).to eq("")
      end

      it "handles yen type formatting" do
        result = form.send(:range_display_helper, 100, 200, :yen)
        expect(result).to be_present
      end

      it "handles date type formatting" do
        date1 = Date.today
        date2 = Date.today + 7.days
        result = form.send(:range_display_helper, date1, date2, :date)
        expect(result).to be_present
      end
    end

    describe "#sortable_fields" do
      it "returns expected sortable fields" do
        expect(form.send(:sortable_fields)).to eq(%w[name price quantity created_at updated_at status])
      end
    end

    describe "#determine_template_key" do
      it "returns :both_present when both values exist" do
        result = form.send(:determine_template_key, 10, 20, :default)
        expect(result).to eq(:both_present)
      end

      it "returns :from_only when only from value exists" do
        result = form.send(:determine_template_key, 10, nil, :default)
        expect(result).to eq(:from_only)
      end

      it "returns :to_only when only to value exists" do
        result = form.send(:determine_template_key, nil, 20, :default)
        expect(result).to eq(:to_only)
      end

      it "returns :empty when both values are nil" do
        result = form.send(:determine_template_key, nil, nil, :default)
        expect(result).to eq(:empty)
      end
    end
  end

  describe "advanced search methods" do
    let!(:inventory_with_batch) { create(:inventory, name: "Batch Product") }
    let!(:batch) { create(:batch, inventory: inventory_with_batch, lot_code: "LOT123", expires_on: 10.days.from_now) }
    let!(:inventory_with_shipment) { create(:inventory, name: "Shipped Product") }
    let!(:shipment) { create(:shipment, inventory: inventory_with_shipment, destination: "Tokyo", shipment_status: :pending) }
    let!(:inventory_with_receipt) { create(:inventory, name: "Received Product") }
    let!(:receipt) { create(:receipt, inventory: inventory_with_receipt, source: "Supplier A") }

    describe "#perform_advanced_search" do
      it "filters by lot code" do
        form.search_type = "advanced"
        form.lot_code = "LOT"

        results = form.search
        expect(results).to include(inventory_with_batch)
        expect(results).not_to include(inventory_with_shipment)
      end

      it "filters by expiry date before" do
        form.search_type = "advanced"
        form.expires_before = 15.days.from_now

        results = form.search
        expect(results).to include(inventory_with_batch)
      end

      it "filters by expiry date after" do
        form.search_type = "advanced"
        form.expires_after = 5.days.from_now

        results = form.search
        expect(results).to include(inventory_with_batch)
      end

      it "filters by expiring soon" do
        form.search_type = "advanced"
        form.expiring_soon = true
        form.expiring_days = 20

        results = form.search
        expect(results).to include(inventory_with_batch)
      end

      it "filters by recently updated" do
        inventory_with_batch.update!(updated_at: 1.day.ago)

        form.search_type = "advanced"
        form.recently_updated = true
        form.updated_days = 3

        results = form.search
        expect(results).to include(inventory_with_batch)
      end

      it "filters by shipment status" do
        form.search_type = "advanced"
        form.shipment_status = "pending"

        results = form.search
        expect(results).to include(inventory_with_shipment)
        expect(results).not_to include(inventory_with_batch)
      end

      it "filters by destination" do
        form.search_type = "advanced"
        form.destination = "Tokyo"

        results = form.search
        expect(results).to include(inventory_with_shipment)
      end

      it "filters by receipt status" do
        form.search_type = "advanced"
        form.receipt_status = "received"

        results = form.search
        expect(results).to include(inventory_with_receipt)
      end

      it "filters by source" do
        form.search_type = "advanced"
        form.source = "Supplier"

        results = form.search
        expect(results).to include(inventory_with_receipt)
      end
    end

    describe "#custom_search" do
      it "handles custom search type" do
        form.search_type = "custom"
        form.custom_conditions = []

        # カスタム検索実装前のスタブ
        allow(AdvancedSearchQuery).to receive(:build).and_return(double(results: Inventory.none))

        results = form.search
        expect(results).to eq([])
      end
    end
  end

  describe "conditions_summary" do
    before do
      allow(I18n).to receive(:t).and_call_original
    end

    it "shows all conditions when no filters applied" do
      allow(I18n).to receive(:t).with("inventories.search.conditions.all").and_return("すべて")

      expect(form.conditions_summary).to eq("すべて")
    end

    it "includes name condition" do
      form.name = "Test Product"
      allow(I18n).to receive(:t).with("inventories.search.conditions.name", value: "Test Product").and_return("名前: Test Product")

      expect(form.conditions_summary).to include("名前: Test Product")
    end

    it "includes status condition" do
      form.status = "active"
      allow(I18n).to receive(:t).with("inventories.search.conditions.status", value: "active").and_return("ステータス: active")

      expect(form.conditions_summary).to include("ステータス: active")
    end

    it "includes price range condition" do
      form.min_price = 100
      form.max_price = 500
      allow(I18n).to receive(:t).with("inventories.search.conditions.price", value: anything).and_return("価格: 100-500円")

      expect(form.conditions_summary).to include("価格: 100-500円")
    end

    it "includes quantity range condition" do
      form.min_quantity = 10
      form.max_quantity = 50
      allow(I18n).to receive(:t).with("inventories.search.conditions.quantity", value: anything).and_return("数量: 10-50")

      expect(form.conditions_summary).to include("数量: 10-50")
    end

    it "includes expiring soon condition" do
      form.expiring_soon = true
      form.expiring_days = 30
      allow(I18n).to receive(:t).with("inventories.search.conditions.expiring_soon_days", days: 30).and_return("30日以内に期限切れ")

      expect(form.conditions_summary).to include("30日以内に期限切れ")
    end

    it "includes recently updated condition" do
      form.recently_updated = true
      form.updated_days = 7
      allow(I18n).to receive(:t).with("inventories.search.conditions.recently_updated_days", days: 7).and_return("7日以内に更新")

      expect(form.conditions_summary).to include("7日以内に更新")
    end
  end

  describe "stock_filter conditions" do
    let!(:out_of_stock) { create(:inventory, quantity: 0, name: "Out of Stock") }
    let!(:low_stock) { create(:inventory, quantity: 5, name: "Low Stock") }
    let!(:in_stock) { create(:inventory, quantity: 20, name: "In Stock") }

    it "filters out of stock items" do
      form.stock_filter = "out_of_stock"

      results = form.search
      expect(results).to include(out_of_stock)
      expect(results).not_to include(low_stock)
      expect(results).not_to include(in_stock)
    end

    it "filters low stock items" do
      form.stock_filter = "low_stock"
      form.low_stock_threshold = 10

      results = form.search
      expect(results).to include(low_stock)
      expect(results).not_to include(out_of_stock)
      expect(results).not_to include(in_stock)
    end

    it "filters in stock items" do
      form.stock_filter = "in_stock"
      form.low_stock_threshold = 10

      results = form.search
      expect(results).to include(in_stock)
      expect(results).not_to include(out_of_stock)
      expect(results).not_to include(low_stock)
    end
  end

  describe "date range filtering" do
    let!(:old_inventory) { create(:inventory, created_at: 2.months.ago, updated_at: 2.months.ago) }
    let!(:recent_inventory) { create(:inventory, created_at: 1.week.ago, updated_at: 1.day.ago) }

    it "filters by created date range" do
      form.search_type = "advanced"
      form.created_from = 2.weeks.ago.to_date
      form.created_to = Date.today

      results = form.search
      expect(results).to include(recent_inventory)
      expect(results).not_to include(old_inventory)
    end

    it "filters by created_from only" do
      form.search_type = "advanced"
      form.created_from = 2.weeks.ago.to_date

      results = form.search
      expect(results).to include(recent_inventory)
      expect(results).not_to include(old_inventory)
    end

    it "filters by created_to only" do
      form.search_type = "advanced"
      form.created_to = 3.weeks.ago.to_date

      results = form.search
      expect(results).to include(old_inventory)
      expect(results).not_to include(recent_inventory)
    end

    it "filters by updated date range" do
      form.search_type = "advanced"
      form.updated_from = 3.days.ago.to_date
      form.updated_to = Date.today

      results = form.search
      expect(results).to include(recent_inventory)
      expect(results).not_to include(old_inventory)
    end
  end

  describe "complex conditions" do
    it "handles multiple conditions combined" do
      form.search_type = "advanced"
      form.name = "Stock"
      form.status = "active"
      form.min_price = 0
      form.max_price = 100
      form.stock_filter = "low_stock"

      # 複数の条件を組み合わせてテスト
      results = form.search
      expect(results).to be_a(ActiveRecord::Relation)
    end
  end

  describe "sorting and pagination" do
    it "applies sorting to results" do
      form.sort_field = "name"
      form.sort_direction = "asc"

      results = form.search
      expect(results.to_sql).to include("ORDER BY name ASC")
    end

    it "applies default sorting when invalid field" do
      form.sort_field = "invalid_field"

      results = form.search
      expect(results.to_sql).to include("ORDER BY updated_at DESC")
    end

    it "applies pagination when page is set" do
      form.page = 2
      form.per_page = 10

      # Kaminariがインストールされている前提
      allow_any_instance_of(ActiveRecord::Relation).to receive(:page).and_return(Inventory.all)
      allow_any_instance_of(ActiveRecord::Relation).to receive(:per).and_return(Inventory.all)

      results = form.search
      expect(results).to be_a(ActiveRecord::Relation)
    end
  end

  describe "include_archived option" do
    let!(:active_inventory) { create(:inventory, status: "active") }
    let!(:archived_inventory) { create(:inventory, status: "archived") }

    it "excludes archived by default" do
      results = form.search
      expect(results).to include(active_inventory)
      expect(results).not_to include(archived_inventory)
    end

    it "includes archived when flag is true" do
      form.include_archived = true

      results = form.search
      expect(results).to include(active_inventory)
      expect(results).to include(archived_inventory)
    end
  end

  describe "expiry_display" do
    it "displays lot code when present" do
      form.lot_code = "LOT123"
      result = form.send(:expiry_display)
      expect(result).to include("ロット: LOT123")
    end

    it "displays expires_before when present" do
      form.expires_before = Date.today + 30.days
      result = form.send(:expiry_display)
      expect(result).to include("期限前:")
    end

    it "displays expires_after when present" do
      form.expires_after = Date.today
      result = form.send(:expiry_display)
      expect(result).to include("期限後:")
    end

    it "combines multiple expiry conditions" do
      form.lot_code = "LOT123"
      form.expires_before = Date.today + 30.days
      result = form.send(:expiry_display)
      expect(result).to include("ロット: LOT123")
      expect(result).to include("期限前:")
    end
  end

  # Branch coverage: apply_basic_conditions_to_standard method
  describe "apply_basic_conditions_to_standard" do
    let(:relation) { Inventory.all }

    it "applies name condition with q parameter" do
      form.q = "Product"
      form.name = nil
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("LIKE")
    end

    it "applies name condition with name parameter" do
      form.name = "Product"
      form.q = nil
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("LIKE")
    end

    it "applies status condition" do
      form.status = "active"
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("status")
    end

    it "applies price range with both min and max" do
      form.min_price = 100
      form.max_price = 500
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("price")
    end

    it "applies only min_price when max_price is blank" do
      form.min_price = 100
      form.max_price = nil
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include(">=")
    end

    it "applies only max_price when min_price is blank" do
      form.min_price = nil
      form.max_price = 500
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("<=")
    end

    it "applies quantity range with both values" do
      form.min_quantity = 10
      form.max_quantity = 100
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("quantity")
    end

    it "applies low_stock condition" do
      form.low_stock = true
      form.low_stock_threshold = 5
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("quantity")
    end

    it "applies stock_filter for out_of_stock" do
      form.stock_filter = "out_of_stock"
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("quantity = 0")
    end

    it "applies stock_filter for low_stock" do
      form.stock_filter = "low_stock"
      form.low_stock_threshold = 10
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("quantity > 0")
    end

    it "applies stock_filter for in_stock" do
      form.stock_filter = "in_stock"
      form.low_stock_threshold = 10
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("quantity >")
    end

    it "excludes archived by default" do
      form.include_archived = false
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).to include("status != 1")
    end

    it "includes archived when flag is true" do
      form.include_archived = true
      result = form.send(:apply_basic_conditions_to_standard, relation)
      expect(result.to_sql).not_to include("status != 1")
    end
  end

  # Branch coverage: apply_advanced_conditions_to_standard method
  describe "apply_advanced_conditions_to_standard" do
    let(:relation) { Inventory.all }

    it "applies created date range" do
      form.created_from = Date.today - 7.days
      form.created_to = Date.today
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.to_sql).to include("created_at")
    end

    it "applies updated date range" do
      form.updated_from = Date.today - 7.days
      form.updated_to = Date.today
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.to_sql).to include("updated_at")
    end

    it "applies recently_updated condition" do
      form.recently_updated = true
      form.updated_days = 3
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.to_sql).to include("updated_at")
    end

    it "applies expiring_soon condition" do
      form.expiring_soon = true
      form.expiring_days = 30
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:batches)
    end

    it "applies lot_code condition" do
      form.lot_code = "LOT123"
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:batches)
    end

    it "applies expires_before condition" do
      form.expires_before = Date.today + 30.days
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:batches)
    end

    it "applies expires_after condition" do
      form.expires_after = Date.today
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:batches)
    end

    it "applies shipment_status condition" do
      form.shipment_status = "pending"
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:shipments)
    end

    it "applies destination condition" do
      form.destination = "Tokyo"
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:shipments)
    end

    it "applies receipt_status condition" do
      form.receipt_status = "pending"
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:receipts)
    end

    it "applies source condition" do
      form.source = "Supplier A"
      result = form.send(:apply_advanced_conditions_to_standard, relation)
      expect(result.joins_values).to include(:receipts)
    end
  end

  # Branch coverage: sorting and direction
  describe "apply_sorting" do
    let(:relation) { Inventory.all }

    it "applies valid sort field with direction" do
      form.sort_field = "name"
      form.sort_direction = "asc"
      result = form.send(:apply_sorting, relation)
      expect(result.to_sql).to include("ORDER BY name ASC")
    end

    it "applies default sort when field is invalid" do
      form.sort_field = "invalid_field"
      form.sort_direction = "asc"
      result = form.send(:apply_sorting, relation)
      expect(result.to_sql).to include("ORDER BY updated_at DESC")
    end

    it "applies default sort when field is blank" do
      form.sort_field = ""
      result = form.send(:apply_sorting, relation)
      expect(result.to_sql).to include("ORDER BY updated_at DESC")
    end

    it "normalizes desc direction" do
      form.sort_field = "price"
      form.sort_direction = "DESC"
      result = form.send(:apply_sorting, relation)
      expect(result.to_sql).to include("ORDER BY price DESC")
    end

    it "defaults to desc for invalid direction" do
      form.sort_field = "quantity"
      form.sort_direction = "invalid"
      result = form.send(:apply_sorting, relation)
      expect(result.to_sql).to include("ORDER BY quantity DESC")
    end
  end

  # Branch coverage: Edge cases and error handling
  describe "error handling and edge cases" do
    it "handles nil effective_name gracefully" do
      form.name = nil
      form.q = nil
      relation = form.send(:apply_basic_conditions_to_standard, Inventory.all)
      expect(relation).to be_a(ActiveRecord::Relation)
    end

    it "handles extremely long search strings" do
      form.name = "a" * 1000
      expect { form.search }.not_to raise_error
    end

    it "handles special characters in search" do
      form.name = "Test%_[Product]"
      expect { form.search }.not_to raise_error
    end

    it "handles date edge cases" do
      form.created_from = Date.new(1900, 1, 1)
      form.created_to = Date.new(2100, 12, 31)
      expect { form.search }.not_to raise_error
    end

    it "handles negative thresholds" do
      form.low_stock_threshold = -10
      form.low_stock = true
      expect { form.search }.not_to raise_error
    end
  end

  # Branch coverage: Combined conditions
  describe "combined search conditions" do
    it "combines basic and advanced conditions" do
      form.search_type = "advanced"
      form.name = "Product"
      form.status = "active"
      form.lot_code = "LOT"
      form.min_price = 100
      form.expiring_soon = true

      result = form.search
      expect(result).to be_a(ActiveRecord::Relation)
    end

    it "handles all stock filters with other conditions" do
      %w[out_of_stock low_stock in_stock].each do |filter|
        form.stock_filter = filter
        form.name = "Test"
        form.status = "active"

        expect { form.search }.not_to raise_error
      end
    end

    it "handles all date range combinations" do
      form.created_from = Date.today - 30.days
      form.created_to = Date.today
      form.updated_from = Date.today - 7.days
      form.updated_to = Date.today
      form.expires_before = Date.today + 30.days
      form.expires_after = Date.today

      expect { form.search }.not_to raise_error
    end
  end
end
