# frozen_string_literal: true

require "rails_helper"

RSpec.describe SearchQuery do
  let!(:inventory1) { create(:inventory, name: "Product A", quantity: 100, price: 50.0, status: "active") }
  let!(:inventory2) { create(:inventory, name: "Product B", quantity: 0, price: 100.0, status: "active") }
  let!(:inventory3) { create(:inventory, name: "Item C", quantity: 5, price: 25.0, status: "archived") }
  let!(:inventory4) { create(:inventory, name: "Item D", quantity: 50, price: 75.0, status: "active") }

  describe ".call" do
    context "with basic parameters" do
      it "returns all inventories with no parameters" do
        results = described_class.call({})
        expect(results.count).to eq(4)
      end

      it "returns empty result with invalid parameters" do
        results = described_class.call(nil)
        expect(results.count).to eq(0)
      end
    end

    context "simple search scenarios" do
      it "searches by keyword" do
        results = described_class.call(q: "Product")
        expect(results.count).to eq(2)
        expect(results.pluck(:name)).to include("Product A", "Product B")
      end

      it "filters by status" do
        results = described_class.call(status: "active")
        expect(results.count).to eq(3)
        expect(results.pluck(:status)).to all(eq("active"))
      end

      it "filters by low stock" do
        results = described_class.call(low_stock: "true")
        expect(results.count).to eq(1)
        expect(results.first.name).to eq("Product B")
      end

      it "sorts by name ascending" do
        results = described_class.call(sort: "name", direction: "asc")
        expect(results.pluck(:name)).to eq([ "Item C", "Item D", "Product A", "Product B" ])
      end

      it "sorts by price descending" do
        results = described_class.call(sort: "price", direction: "desc")
        expect(results.pluck(:price)).to eq([ 100.0, 75.0, 50.0, 25.0 ])
      end

      it "combines multiple simple filters" do
        results = described_class.call(
          status: "active",
          sort: "price",
          direction: "asc"
        )
        expect(results.count).to eq(3)
        expect(results.pluck(:price)).to eq([ 50.0, 75.0, 100.0 ])
      end
    end

    context "complex search scenarios (uses AdvancedSearchQuery)" do
      it "uses advanced search for price range" do
        results = described_class.call(min_price: 30, max_price: 80)
        expect(results.count).to eq(2)
        expect(results.pluck(:name)).to include("Product A", "Item D")
      end

      it "uses advanced search for stock filter" do
        results = described_class.call(stock_filter: "out_of_stock")
        expect(results.count).to eq(1)
        expect(results.first.name).to eq("Product B")
      end

      it "uses advanced search for low stock with threshold" do
        results = described_class.call(
          stock_filter: "low_stock",
          low_stock_threshold: 10
        )
        expect(results.count).to eq(1)
        expect(results.first.name).to eq("Item C")
      end

      it "uses advanced search for in stock filter" do
        results = described_class.call(
          stock_filter: "in_stock",
          low_stock_threshold: 10
        )
        expect(results.count).to eq(2)
        expect(results.pluck(:name)).to include("Product A", "Item D")
      end
    end

    context "parameter validation" do
      it "raises error for invalid sort column" do
        expect {
          described_class.call(sort: "invalid_column")
        }.to raise_error(ArgumentError, /Invalid sort column/)
      end

      it "raises error for invalid sort direction" do
        expect {
          described_class.call(direction: "invalid_direction")
        }.to raise_error(ArgumentError, /Invalid sort direction/)
      end

      it "raises error for invalid status" do
        expect {
          described_class.call(status: "invalid_status")
        }.to raise_error(ArgumentError, /Invalid status/)
      end

      it "handles valid edge case parameters" do
        # ASC should be converted to lowercase and work fine
        expect {
          described_class.call(sort: "name", direction: "ASC")
        }.not_to raise_error
      end
    end

    context "SQL injection protection" do
      it "safely handles malicious input in keyword search" do
        malicious_input = "'; DROP TABLE inventories; --"
        expect {
          results = described_class.call(q: malicious_input)
          expect(results.count).to eq(0) # Should find nothing but not cause SQL error
        }.not_to raise_error
      end

      it "safely handles malicious input in sort parameter" do
        expect {
          described_class.call(sort: "name; DROP TABLE inventories; --")
        }.to raise_error(ArgumentError) # Should be caught by validation
      end
    end

    context "error handling" do
      it "returns empty result when AdvancedSearchQuery fails" do
        allow(AdvancedSearchQuery).to receive(:build).and_raise(StandardError, "Database error")

        results = described_class.call(min_price: 50)
        expect(results.count).to eq(0)
      end

      it "logs errors appropriately" do
        allow(AdvancedSearchQuery).to receive(:build).and_raise(StandardError, "Test error")
        expect(Rails.logger).to receive(:error).with(/SearchQuery error: Test error/)

        described_class.call(min_price: 50)
      end
    end
  end

  describe ".complex_search_required?" do
    it "returns false for simple parameters" do
      params = { q: "test", status: "active", sort: "name" }
      expect(described_class.send(:complex_search_required?, params)).to be_falsey
    end

    it "returns true for advanced parameters" do
      params = { min_price: 50, max_price: 100 }
      expect(described_class.send(:complex_search_required?, params)).to be_truthy
    end

    it "returns false for nil parameters" do
      expect(described_class.send(:complex_search_required?, nil)).to be_falsey
    end

    it "returns false for non-hash parameters" do
      expect(described_class.send(:complex_search_required?, "string")).to be_falsey
    end
  end

  describe "private methods" do
    describe ".apply_keyword_filter" do
      it "applies keyword filter correctly" do
        base_query = Inventory.all
        result = described_class.send(:apply_keyword_filter, base_query, "Product")
        expect(result.count).to eq(2)
      end

      it "returns original query for blank keyword" do
        base_query = Inventory.all
        result = described_class.send(:apply_keyword_filter, base_query, "")
        expect(result.count).to eq(4)
      end
    end

    describe ".apply_status_filter" do
      it "applies status filter correctly" do
        base_query = Inventory.all
        result = described_class.send(:apply_status_filter, base_query, "active")
        expect(result.count).to eq(3)
      end

      it "ignores invalid status" do
        base_query = Inventory.all
        result = described_class.send(:apply_status_filter, base_query, "invalid")
        expect(result.count).to eq(4)
      end
    end

    describe ".apply_stock_filter" do
      it "applies low stock filter correctly" do
        base_query = Inventory.all
        result = described_class.send(:apply_stock_filter, base_query, "true")
        expect(result.count).to eq(1)
        expect(result.first.quantity).to eq(0)
      end

      it "returns original query for non-true value" do
        base_query = Inventory.all
        result = described_class.send(:apply_stock_filter, base_query, "false")
        expect(result.count).to eq(4)
      end
    end

    describe ".apply_safe_ordering" do
      it "applies safe ordering with valid parameters" do
        base_query = Inventory.all
        result = described_class.send(:apply_safe_ordering, base_query, "name", "asc")
        expect(result.pluck(:name)).to eq([ "Item C", "Item D", "Product A", "Product B" ])
      end

      it "uses default ordering for invalid parameters" do
        base_query = Inventory.all
        result = described_class.send(:apply_safe_ordering, base_query, "invalid", "invalid")
        # Should default to updated_at desc
        expect(result.first.updated_at).to be >= result.last.updated_at
      end
    end
  end
end
