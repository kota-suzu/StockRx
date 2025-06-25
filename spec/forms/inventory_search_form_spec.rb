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
        expect(result).to include("100").and include("500")
      end

      it "displays from only when max_price missing" do
        form.min_price = 100
        result = form.price_range_display
        expect(result).to include("100")
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
    end

    describe "#sortable_fields" do
      it "returns expected sortable fields" do
        expect(form.send(:sortable_fields)).to eq(%w[name price quantity created_at updated_at status])
      end
    end
  end
end
