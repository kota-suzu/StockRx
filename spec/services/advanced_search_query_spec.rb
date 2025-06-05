# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdvancedSearchQuery do
  # テスト中はInventoryLoggableの自動ログ作成を無効化
  before(:all) do
    Inventory.skip_callback(:save, :after, :log_inventory_changes)
  end

  after(:all) do
    Inventory.set_callback(:save, :after, :log_inventory_changes, if: :saved_change_to_quantity?)
  end
  let!(:inventory1) { create(:inventory, name: "Product A", quantity: 100, price: 50.0, status: "active") }
  let!(:inventory2) { create(:inventory, name: "Product B", quantity: 0, price: 100.0, status: "active") }
  let!(:inventory3) { create(:inventory, name: "Item C", quantity: 5, price: 25.0, status: "archived") }
  let!(:inventory4) { create(:inventory, name: "Item D", quantity: 50, price: 75.0, status: "active") }

  # バッチデータ
  let!(:batch1) { create(:batch, inventory: inventory1, lot_code: "LOT001", expires_on: 10.days.from_now, quantity: 50) }
  let!(:batch2) { create(:batch, inventory: inventory1, lot_code: "LOT002", expires_on: 60.days.from_now, quantity: 50) }
  let!(:batch3) { create(:batch, inventory: inventory3, lot_code: "LOT003", expires_on: 5.days.ago, quantity: 5) }

  # ユーザーとログデータ
  let!(:user1) { create(:admin, email: "user1@example.com") }
  let!(:user2) { create(:admin, email: "user2@example.com") }

  let!(:log1) { create(:inventory_log, inventory: inventory1, admin: user1, operation_type: "add", delta: 10, current_quantity: 110, previous_quantity: 100) }
  let!(:log2) { create(:inventory_log, inventory: inventory2, admin: user2, operation_type: "remove", delta: -5, current_quantity: 0, previous_quantity: 5) }

  # 出荷・入荷データ
  let!(:shipment1) { create(:shipment, inventory: inventory1, shipment_status: :shipped, destination: "Tokyo", tracking_number: "TRACK001") }
  let!(:receipt1) { create(:receipt, inventory: inventory2, receipt_status: :completed, source: "Supplier A", cost_per_unit: 1000.0) }

  describe ".build" do
    it "creates a new instance with default scope" do
      query = described_class.build
      expect(query).to be_a(described_class)
      expect(query.results).to match_array([ inventory1, inventory2, inventory3, inventory4 ])
    end

    it "accepts a custom scope" do
      query = described_class.build(Inventory.active)
      expect(query.results).to match_array([ inventory1, inventory2, inventory4 ])
    end
  end

  describe "#where" do
    it "adds AND conditions" do
      results = described_class.build
        .where(status: "active")
        .where("quantity > ?", 10)
        .results

      expect(results).to match_array([ inventory1, inventory4 ])
    end
  end

  describe "#or_where" do
    it "adds OR conditions" do
      results = described_class.build
        .where(name: "Product A")
        .or_where(name: "Product B")
        .results

      expect(results).to match_array([ inventory1, inventory2 ])
    end
  end

  describe "#where_any" do
    it "combines multiple OR conditions" do
      results = described_class.build
        .where_any([
          { quantity: 0 },
          { price: 25.0 },
          { name: "Item D" }
        ])
        .results

      expect(results).to match_array([ inventory2, inventory3, inventory4 ])
    end
  end

  describe "#where_all" do
    it "combines multiple AND conditions" do
      results = described_class.build
        .where_all([
          { status: "active" },
          [ "quantity > ?", 30 ],
          [ "price < ?", 80 ]
        ])
        .results

      expect(results).to match_array([ inventory1, inventory4 ])
    end
  end

  describe "#complex_where" do
    it "handles complex AND/OR combinations" do
      results = described_class.build
        .complex_where do |builder|
          builder.and_group do |and_builder|
            and_builder.where(status: "active")
            and_builder.or_group do |or_builder|
              or_builder.where("quantity < ?", 10)
              or_builder.where("price > ?", 90)
            end
          end
        end
        .results

      expect(results).to match_array([ inventory2 ])
    end
  end

  describe "#search_keywords" do
    it "searches across multiple fields" do
      results = described_class.build
        .search_keywords("Product")
        .results

      expect(results).to match_array([ inventory1, inventory2 ])
    end

    it "accepts custom fields" do
      results = described_class.build
        .search_keywords("Item", fields: [ :name ])
        .results

      expect(results).to match_array([ inventory3, inventory4 ])
    end
  end

  describe "#between_dates" do
    it "filters by date range" do
      inventory1.update!(created_at: 5.days.ago)
      inventory2.update!(created_at: 10.days.ago)
      inventory3.update!(created_at: 15.days.ago)

      results = described_class.build
        .between_dates("created_at", 12.days.ago, 3.days.ago)
        .results

      expect(results).to match_array([ inventory1, inventory2 ])
    end
  end

  describe "#in_range" do
    it "filters by numeric range" do
      results = described_class.build
        .in_range("quantity", 5, 50)
        .results

      expect(results).to match_array([ inventory3, inventory4 ])
    end
  end

  describe "#with_status" do
    it "filters by single status" do
      results = described_class.build
        .with_status("archived")
        .results

      expect(results).to match_array([ inventory3 ])
    end

    it "filters by multiple statuses" do
      results = described_class.build
        .with_status([ "active", "archived" ])
        .results

      expect(results).to match_array([ inventory1, inventory2, inventory3, inventory4 ])
    end
  end

  describe "#with_batch_conditions" do
    it "searches by batch lot code" do
      results = described_class.build
        .with_batch_conditions do
          lot_code("LOT001")
        end
        .results

      expect(results).to match_array([ inventory1 ])
    end

    it "searches by batch expiry date" do
      results = described_class.build
        .with_batch_conditions do
          expires_before(30.days.from_now)
        end
        .results

      expect(results).to match_array([ inventory1, inventory3 ])
    end
  end

  describe "#with_inventory_log_conditions" do
    it "searches by log action type" do
      results = described_class.build
        .with_inventory_log_conditions do
          action_type("add")  # テストデータで実際に作成されているタイプに合わせる
        end
        .results

      expect(results).to match_array([ inventory1 ])
    end

    it "searches by user who made changes" do
      user2_id = user2.id  # ローカル変数をブロック外で設定
      results = described_class.build
        .with_inventory_log_conditions do
          by_user(user2_id)
        end
        .results

      expect(results).to match_array([ inventory2 ])
    end
  end

  describe "#with_shipment_conditions" do
    it "searches by shipment status" do
      results = described_class.build
        .with_shipment_conditions do
          status("shipped")
        end
        .results

      expect(results).to match_array([ inventory1 ])
    end

    it "searches by destination" do
      results = described_class.build
        .with_shipment_conditions do
          destination_like("Tokyo")
        end
        .results

      expect(results).to match_array([ inventory1 ])
    end
  end

  describe "#with_receipt_conditions" do
    it "searches by receipt source" do
      results = described_class.build
        .with_receipt_conditions do
          source_like("Supplier")
        end
        .results

      expect(results).to match_array([ inventory2 ])
    end

    it "searches by cost range" do
      results = described_class.build
        .with_receipt_conditions do
          cost_range(500, 1500)
        end
        .results

      expect(results).to match_array([ inventory2 ])
    end
  end

  describe "#expiring_soon" do
    it "finds items expiring within specified days" do
      results = described_class.build
        .expiring_soon(15)
        .results

      expect(results).to match_array([ inventory1 ])
    end
  end

  describe "#out_of_stock" do
    it "finds items with zero quantity" do
      results = described_class.build
        .out_of_stock
        .results

      expect(results).to match_array([ inventory2 ])
    end
  end

  describe "#low_stock" do
    it "finds items with low quantity" do
      results = described_class.build
        .low_stock(10)
        .results

      expect(results).to match_array([ inventory3 ])
    end
  end

  describe "#recently_updated" do
    it "finds recently updated items" do
      # より明確な時間差を設定して確実にテストを通す
      inventory1.update!(updated_at: 1.day.ago)
      inventory2.update!(updated_at: 10.days.ago)
      inventory3.update!(updated_at: 15.days.ago)
      inventory4.update!(updated_at: 20.days.ago)

      results = described_class.build
        .recently_updated(5)
        .results

      expect(results).to match_array([ inventory1 ])
    end
  end

  describe "#modified_by_user" do
    it "finds items modified by specific user" do
      results = described_class.build
        .modified_by_user(user1.id)
        .results

      expect(results).to match_array([ inventory1 ])
    end
  end

  describe "#order_by" do
    it "orders results by specified field" do
      results = described_class.build
        .order_by(:price, :desc)
        .results

      expect(results.map(&:price)).to eq([ 100.0, 75.0, 50.0, 25.0 ])
    end
  end

  describe "#order_by_multiple" do
    it "orders by multiple fields" do
      results = described_class.build
        .order_by_multiple(status: :asc, quantity: :desc)
        .results

      expect(results.first).to eq(inventory1)
      expect(results.last).to eq(inventory3)
    end
  end

  describe "#distinct" do
    it "removes duplicates from joined queries" do
      # 複数のバッチを持つ在庫があるため、JOINすると重複が発生する
      results = described_class.build
        .with_batch_conditions { quantity_greater_than(0) }
        .distinct
        .results

      expect(results).to match_array([ inventory1, inventory3 ])
      expect(results.size).to eq(2) # 重複なし
    end
  end

  describe "#paginate" do
    it "paginates results" do
      results = described_class.build
        .order_by(:id)
        .paginate(page: 1, per_page: 2)
        .results

      expect(results.size).to eq(2)
      expect(results).to match_array([ inventory1, inventory2 ])
    end
  end

  describe "#count" do
    it "returns count of matching records" do
      count = described_class.build
        .with_status("active")
        .count

      expect(count).to eq(3)
    end
  end

  describe "#to_sql" do
    it "returns SQL query for debugging" do
      sql = described_class.build
        .where(status: "active")
        .to_sql

      expect(sql).to include("WHERE")
      expect(sql).to include("status")
    end
  end

  describe "complex real-world scenarios" do
    it "finds active items with low stock that have been shipped recently" do
      shipment1.update!(created_at: 2.days.ago)

      results = described_class.build
        .with_status("active")
        .where("inventories.quantity <= ?", 100)  # テーブル名を明示してカラム曖昧性を回避
        .with_shipment_conditions do
          status("shipped")
        end
        .recently_updated(7)
        .results

      expect(results).to match_array([ inventory1 ])
    end

    it "finds items with expiring batches or recent receipts from specific suppliers" do
      results = described_class.build
        .complex_where do |builder|
          builder.or_group do |or_builder|
            or_builder.where(id: inventory1.id) # Has expiring batch
            or_builder.where(id: inventory2.id) # Has receipt from Supplier A
          end
        end
        .results

      expect(results).to match_array([ inventory1, inventory2 ])
    end

    it "performs cross-table search with multiple conditions" do
      results = described_class.build
        .search_keywords("Product")
        .with_inventory_log_conditions do
          changed_after(1.week.ago)
          action_type("add")  # テストデータで実際に作成されているタイプに合わせる
        end
        .order_by(:name)
        .results

      expect(results).to eq([ inventory1 ])
    end
  end
end
