# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShipmentManagement do
  # CLAUDE.md準拠: 出荷管理機能の包括的テスト
  # メタ認知: 複雑な在庫移動ロジックと複数の分岐パスの品質保証
  # 横展開: 他の在庫移動系concernでも同様のテストパターン適用

  # テスト用のダミークラス作成
  let(:dummy_class) do
    Class.new(ApplicationRecord) do
      self.table_name = 'inventories'
      include ShipmentManagement

      # 必要な属性定義
      attr_accessor :quantity, :name, :code

      # 基本的なバリデーション
      validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }

      # テスト用のメソッド
      def add_stock(quantity, reason)
        self.quantity += quantity
        true
      end

      def remove_stock(quantity, reason)
        self.quantity -= quantity
        true
      end

      def add_batch(quantity, expiry_date, batch_number)
        true
      end
    end
  end

  let(:test_class) { dummy_class }
  let(:test_instance) do
    instance = test_class.new
    instance.quantity = 100
    instance.name = "Test Item"
    instance.code = "TEST001"
    allow(instance).to receive(:id).and_return(1)
    allow(instance).to receive(:shipments).and_return(shipments_relation)
    allow(instance).to receive(:receipts).and_return(receipts_relation)
    instance
  end

  let(:shipments_relation) { double('shipments_relation') }
  let(:receipts_relation) { double('receipts_relation') }

  # ============================================
  # インスタンスメソッドのテスト
  # ============================================

  describe '#create_shipment' do
    let(:mock_shipment) { double('shipment', id: 1, quantity: 10) }

    before do
      allow(shipments_relation).to receive(:new).and_return(mock_shipment)
    end

    context 'with valid parameters' do
      it 'creates shipment successfully' do
        allow(mock_shipment).to receive(:save).and_return(true)
        expect(test_instance).to receive(:remove_stock).with(10, "出荷: Tokyo向け TRK123")

        result = test_instance.create_shipment(10, "Tokyo", tracking_number: "TRK123")

        expect(result).to be true
      end

      it 'creates shipment with default values' do
        expect(shipments_relation).to receive(:new).with(hash_including(
          quantity: 20,
          destination: "Osaka",
          scheduled_date: Date.current,
          shipment_status: :pending,
          tracking_number: nil,
          carrier: nil,
          notes: nil
        ))
        allow(mock_shipment).to receive(:save).and_return(true)

        test_instance.create_shipment(20, "Osaka")
      end

      it 'creates shipment with custom options' do
        custom_date = Date.tomorrow
        expect(shipments_relation).to receive(:new).with(hash_including(
          quantity: 15,
          destination: "Kyoto",
          scheduled_date: custom_date,
          shipment_status: :processing,
          tracking_number: "TRK456",
          carrier: "Yamato",
          notes: "Fragile items"
        ))
        allow(mock_shipment).to receive(:save).and_return(true)

        test_instance.create_shipment(15, "Kyoto", {
          scheduled_date: custom_date,
          status: :processing,
          tracking_number: "TRK456",
          carrier: "Yamato",
          notes: "Fragile items"
        })
      end
    end

    context 'with invalid parameters' do
      it 'returns false for zero quantity' do
        result = test_instance.create_shipment(0, "Tokyo")
        expect(result).to be false
      end

      it 'returns false for negative quantity' do
        result = test_instance.create_shipment(-5, "Tokyo")
        expect(result).to be false
      end

      it 'returns false when quantity exceeds stock' do
        result = test_instance.create_shipment(150, "Tokyo")
        expect(result).to be false
      end

      it 'returns false when shipment save fails' do
        allow(mock_shipment).to receive(:save).and_return(false)

        result = test_instance.create_shipment(10, "Tokyo")
        expect(result).to be false
      end
    end
  end

  describe '#create_receipt' do
    let(:mock_receipt) { double('receipt', id: 1, quantity: 50) }

    before do
      allow(receipts_relation).to receive(:new).and_return(mock_receipt)
    end

    context 'with valid parameters' do
      it 'creates receipt successfully' do
        allow(mock_receipt).to receive(:save).and_return(true)
        expect(test_instance).to receive(:add_stock).with(50, "入荷: Supplier Aから PO123")

        result = test_instance.create_receipt(50, "Supplier A", purchase_order: "PO123")

        expect(result).to be true
      end

      it 'creates receipt with batch when expiry_date provided' do
        allow(mock_receipt).to receive(:save).and_return(true)
        allow(test_instance).to receive(:respond_to?).with(:add_batch).and_return(true)
        expect(test_instance).to receive(:add_batch).with(30, Date.tomorrow, "BATCH123")

        test_instance.create_receipt(30, "Supplier B", {
          expiry_date: Date.tomorrow,
          batch_number: "BATCH123"
        })
      end

      it 'generates batch number from receipt ID when not provided' do
        allow(mock_receipt).to receive(:save).and_return(true)
        allow(test_instance).to receive(:respond_to?).with(:add_batch).and_return(true)
        expect(test_instance).to receive(:add_batch).with(25, Date.tomorrow, "RN-1")

        test_instance.create_receipt(25, "Supplier C", expiry_date: Date.tomorrow)
      end

      it 'creates receipt with all custom options' do
        receipt_date = Date.yesterday
        expect(receipts_relation).to receive(:new).with(hash_including(
          quantity: 40,
          source: "Supplier D",
          receipt_date: receipt_date,
          receipt_status: :pending,
          batch_number: "BATCH456",
          purchase_order: "PO456",
          cost_per_unit: 50.5,
          notes: "Urgent delivery"
        ))
        allow(mock_receipt).to receive(:save).and_return(true)

        test_instance.create_receipt(40, "Supplier D", {
          receipt_date: receipt_date,
          status: :pending,
          batch_number: "BATCH456",
          purchase_order: "PO456",
          cost_per_unit: 50.5,
          notes: "Urgent delivery"
        })
      end
    end

    context 'with invalid parameters' do
      it 'returns false for zero quantity' do
        result = test_instance.create_receipt(0, "Supplier A")
        expect(result).to be false
      end

      it 'returns false for negative quantity' do
        result = test_instance.create_receipt(-10, "Supplier A")
        expect(result).to be false
      end

      it 'returns false when receipt save fails' do
        allow(mock_receipt).to receive(:save).and_return(false)

        result = test_instance.create_receipt(50, "Supplier A")
        expect(result).to be false
      end

      it 'does not add batch when add_batch method not available' do
        allow(mock_receipt).to receive(:save).and_return(true)
        allow(test_instance).to receive(:respond_to?).with(:add_batch).and_return(false)
        expect(test_instance).not_to receive(:add_batch)

        test_instance.create_receipt(30, "Supplier E", expiry_date: Date.tomorrow)
      end
    end
  end

  describe '#cancel_shipment' do
    let(:pending_shipment) { double('shipment', quantity: 20, pending?: true, processing?: false) }
    let(:processing_shipment) { double('shipment', quantity: 30, pending?: false, processing?: true) }
    let(:shipped_shipment) { double('shipment', quantity: 25, pending?: false, processing?: false) }

    context 'with pending shipment' do
      it 'cancels successfully and restores stock' do
        allow(shipments_relation).to receive(:find_by).with(id: 1).and_return(pending_shipment)
        expect(pending_shipment).to receive(:cancelled!)
        expect(test_instance).to receive(:add_stock).with(20, "出荷取消: 在庫不足")

        result = test_instance.cancel_shipment(1, "在庫不足")
        expect(result).to be true
      end

      it 'uses default reason when not provided' do
        allow(shipments_relation).to receive(:find_by).with(id: 2).and_return(pending_shipment)
        expect(pending_shipment).to receive(:cancelled!)
        expect(test_instance).to receive(:add_stock).with(20, "出荷取消: 理由なし")

        result = test_instance.cancel_shipment(2)
        expect(result).to be true
      end
    end

    context 'with processing shipment' do
      it 'cancels successfully' do
        allow(shipments_relation).to receive(:find_by).with(id: 3).and_return(processing_shipment)
        expect(processing_shipment).to receive(:cancelled!)
        expect(test_instance).to receive(:add_stock).with(30, "出荷取消: 顧客キャンセル")

        result = test_instance.cancel_shipment(3, "顧客キャンセル")
        expect(result).to be true
      end
    end

    context 'with invalid conditions' do
      it 'returns false when shipment not found' do
        allow(shipments_relation).to receive(:find_by).with(id: 999).and_return(nil)

        result = test_instance.cancel_shipment(999)
        expect(result).to be false
      end

      it 'returns false when shipment already shipped' do
        allow(shipments_relation).to receive(:find_by).with(id: 4).and_return(shipped_shipment)

        result = test_instance.cancel_shipment(4)
        expect(result).to be false
      end
    end
  end

  describe '#process_return' do
    let(:shipped_shipment) do
      double('shipment',
        quantity: 50,
        shipped?: true,
        delivered?: false,
        update: true
      )
    end

    let(:delivered_shipment) do
      double('shipment',
        quantity: 60,
        shipped?: false,
        delivered?: true,
        update: true
      )
    end

    let(:pending_shipment) do
      double('shipment',
        quantity: 40,
        shipped?: false,
        delivered?: false
      )
    end

    context 'with valid return' do
      it 'processes return for shipped item with quality check' do
        allow(shipments_relation).to receive(:find_by).with(id: 1).and_return(shipped_shipment)
        expect(shipped_shipment).to receive(:update).with(hash_including(
          shipment_status: :returned,
          return_quantity: 20,
          return_reason: "Damaged",
          return_date: Date.current
        ))
        expect(test_instance).to receive(:add_stock).with(20, "返品受入: Damaged")

        result = test_instance.process_return(1, 20, "Damaged", true)
        expect(result).to be true
      end

      it 'processes return for delivered item' do
        allow(shipments_relation).to receive(:find_by).with(id: 2).and_return(delivered_shipment)
        expect(test_instance).to receive(:add_stock).with(30, "返品受入: Wrong item")

        result = test_instance.process_return(2, 30, "Wrong item")
        expect(result).to be true
      end

      it 'processes return without restocking when quality check fails' do
        allow(shipments_relation).to receive(:find_by).with(id: 3).and_return(shipped_shipment)
        expect(shipped_shipment).to receive(:update)
        expect(test_instance).not_to receive(:add_stock)

        result = test_instance.process_return(3, 15, "Defective", false)
        expect(result).to be true
      end

      it 'uses default reason when not provided' do
        allow(shipments_relation).to receive(:find_by).with(id: 4).and_return(shipped_shipment)
        expect(test_instance).to receive(:add_stock).with(10, "返品受入: 理由なし")

        result = test_instance.process_return(4, 10)
        expect(result).to be true
      end
    end

    context 'with invalid return' do
      it 'returns false when shipment not found' do
        allow(shipments_relation).to receive(:find_by).with(id: 999).and_return(nil)

        result = test_instance.process_return(999, 10)
        expect(result).to be false
      end

      it 'returns false for zero return quantity' do
        allow(shipments_relation).to receive(:find_by).with(id: 5).and_return(shipped_shipment)

        result = test_instance.process_return(5, 0)
        expect(result).to be false
      end

      it 'returns false for negative return quantity' do
        allow(shipments_relation).to receive(:find_by).with(id: 6).and_return(shipped_shipment)

        result = test_instance.process_return(6, -5)
        expect(result).to be false
      end

      it 'returns false when return quantity exceeds shipment quantity' do
        allow(shipments_relation).to receive(:find_by).with(id: 7).and_return(shipped_shipment)

        result = test_instance.process_return(7, 60) # shipment quantity is 50
        expect(result).to be false
      end

      it 'returns false when shipment not shipped or delivered' do
        allow(shipments_relation).to receive(:find_by).with(id: 8).and_return(pending_shipment)

        result = test_instance.process_return(8, 20)
        expect(result).to be false
      end
    end
  end

  # ============================================
  # クラスメソッドのテスト
  # ============================================

  describe '.ship' do
    let(:inventory) { test_instance }

    before do
      allow(test_class).to receive(:find).with(1).and_return(inventory)
      allow(InventoryLog).to receive(:create!)
    end

    context 'with valid shipment' do
      it 'reduces inventory quantity' do
        expect {
          test_class.ship(1, 20, {})
        }.to change { inventory.quantity }.from(100).to(80)
      end

      it 'creates inventory log with correct data' do
        expect(InventoryLog).to receive(:create!).with(hash_including(
          inventory_id: 1,
          delta: -30,
          operation_type: "ship",
          previous_quantity: 100,
          current_quantity: 70,
          user_id: nil,
          note: "出荷処理",
          reference_number: nil,
          destination: nil
        ))

        test_class.ship(1, 30, {})
      end

      it 'uses custom options' do
        expect(InventoryLog).to receive(:create!).with(hash_including(
          user_id: 123,
          note: "Urgent shipment",
          reference_number: "REF001",
          destination: "Tokyo"
        ))

        test_class.ship(1, 25, {
          user_id: 123,
          note: "Urgent shipment",
          reference_number: "REF001",
          destination: "Tokyo"
        })
      end
    end

    context 'with invalid shipment' do
      it 'raises error when quantity exceeds stock' do
        expect {
          test_class.ship(1, 150, {})
        }.to raise_error("出荷数量が在庫数量を超えています（在庫: 100, 出荷: 150）")
      end

      it 'rolls back transaction on save failure' do
        allow(inventory).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          test_class.ship(1, 20, {})
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(inventory.quantity).to eq(100) # Should remain unchanged
      end
    end
  end

  describe '.receive' do
    let(:inventory) { test_instance }

    before do
      allow(test_class).to receive(:find).with(1).and_return(inventory)
      allow(InventoryLog).to receive(:create!)
    end

    context 'with valid receipt' do
      it 'increases inventory quantity' do
        expect {
          test_class.receive(1, 50, {})
        }.to change { inventory.quantity }.from(100).to(150)
      end

      it 'creates inventory log with correct data' do
        expect(InventoryLog).to receive(:create!).with(hash_including(
          inventory_id: 1,
          delta: 40,
          operation_type: "receive",
          previous_quantity: 100,
          current_quantity: 140,
          user_id: nil,
          note: "入荷処理",
          reference_number: nil,
          source: nil
        ))

        test_class.receive(1, 40, {})
      end

      it 'uses custom options' do
        expect(InventoryLog).to receive(:create!).with(hash_including(
          user_id: 456,
          note: "Regular delivery",
          reference_number: "PO123",
          source: "Supplier XYZ"
        ))

        test_class.receive(1, 60, {
          user_id: 456,
          note: "Regular delivery",
          reference_number: "PO123",
          source: "Supplier XYZ"
        })
      end
    end

    context 'with transaction failure' do
      it 'rolls back on save failure' do
        allow(inventory).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          test_class.receive(1, 30, {})
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(inventory.quantity).to eq(100) # Should remain unchanged
      end
    end
  end

  describe '.transfer' do
    let(:from_inventory) { test_instance }
    let(:to_inventory) do
      to = test_class.new
      to.quantity = 50
      to.name = "Destination Item"
      allow(to).to receive(:id).and_return(2)
      to
    end

    before do
      allow(test_class).to receive(:find).with(1).and_return(from_inventory)
      allow(test_class).to receive(:find).with(2).and_return(to_inventory)
      allow(test_class).to receive(:ship)
      allow(test_class).to receive(:receive)
    end

    context 'with valid transfer' do
      it 'calls ship and receive with correct parameters' do
        expect(test_class).to receive(:ship).with(1, 30, hash_including(
          note: "在庫移動（出庫）: Test Item → Destination Item"
        ))
        expect(test_class).to receive(:receive).with(2, 30, hash_including(
          note: "在庫移動（入庫）: Test Item → Destination Item"
        ))

        test_class.transfer(1, 2, 30, {})
      end

      it 'passes custom options to both operations' do
        custom_options = { user_id: 789, reference_number: "TRF001" }

        expect(test_class).to receive(:ship).with(1, 25, hash_including(custom_options))
        expect(test_class).to receive(:receive).with(2, 25, hash_including(custom_options))

        test_class.transfer(1, 2, 25, custom_options)
      end

      it 'returns logs array' do
        allow(test_class).to receive(:ship).and_return("ship_log")
        allow(test_class).to receive(:receive).and_return("receive_log")

        result = test_class.transfer(1, 2, 20, {})
        expect(result).to eq([ "ship_log", "receive_log" ])
      end
    end

    context 'with invalid transfer' do
      it 'raises error when quantity exceeds source stock' do
        expect {
          test_class.transfer(1, 2, 150, {})
        }.to raise_error("移動数量が在庫数量を超えています（在庫: 100, 移動: 150）")
      end

      it 'rolls back entire transaction on failure' do
        allow(test_class).to receive(:ship).and_raise(ActiveRecord::RecordInvalid)

        expect {
          test_class.transfer(1, 2, 30, {})
        }.to raise_error(ActiveRecord::RecordInvalid)

        expect(test_class).not_to receive(:receive)
      end
    end
  end

  describe '.shipments_by_period' do
    it 'queries shipments within date range' do
      start_date = Date.new(2024, 1, 1)
      end_date = Date.new(2024, 1, 31)

      relation = double('relation')
      expect(test_class).to receive(:joins).with(:shipments).and_return(relation)
      expect(relation).to receive(:where).with(
        "shipments.scheduled_date BETWEEN ? AND ?", start_date, end_date
      ).and_return(relation)
      expect(relation).to receive(:group).with("inventories.id").and_return(relation)
      expect(relation).to receive(:select).with(
        "inventories.*, COUNT(shipments.id) as shipment_count, SUM(shipments.quantity) as total_shipped"
      )

      test_class.shipments_by_period(start_date, end_date)
    end
  end

  describe '.receipts_by_period' do
    it 'queries receipts within date range' do
      start_date = Date.new(2024, 2, 1)
      end_date = Date.new(2024, 2, 29)

      relation = double('relation')
      expect(test_class).to receive(:joins).with(:receipts).and_return(relation)
      expect(relation).to receive(:where).with(
        "receipts.receipt_date BETWEEN ? AND ?", start_date, end_date
      ).and_return(relation)
      expect(relation).to receive(:group).with("inventories.id").and_return(relation)
      expect(relation).to receive(:select).with(
        "inventories.*, COUNT(receipts.id) as receipt_count, SUM(receipts.quantity) as total_received"
      )

      test_class.receipts_by_period(start_date, end_date)
    end
  end

  describe '.movement_report' do
    let(:start_date) { Date.new(2024, 1, 1) }
    let(:end_date) { Date.new(2024, 1, 31) }

    before do
      # Mock for shipped items query
      shipped_relation = double('shipped_relation')
      allow(test_class).to receive(:joins).with(:inventory_logs).and_return(shipped_relation)
      allow(shipped_relation).to receive(:where).and_return(shipped_relation)
      allow(shipped_relation).to receive(:distinct).and_return(shipped_relation)
      allow(shipped_relation).to receive(:pluck).with(:id).and_return([ 1, 2 ])

      # Mock for received items query
      received_relation = double('received_relation')
      allow(received_relation).to receive(:where).and_return(received_relation)
      allow(received_relation).to receive(:distinct).and_return(received_relation)
      allow(received_relation).to receive(:pluck).with(:id).and_return([ 2, 3 ])

      # Mock inventory data
      inv1 = double(id: 1, name: "Item 1", code: "CODE1")
      inv2 = double(id: 2, name: "Item 2", code: "CODE2")
      inv3 = double(id: 3, name: "Item 3", code: "CODE3")

      allow(Inventory).to receive(:where).with(id: [ 1, 2, 3 ]).and_return([ inv1, inv2, inv3 ])
      allow([ inv1, inv2, inv3 ]).to receive(:index_by).and_return({
        1 => inv1, 2 => inv2, 3 => inv3
      })

      # Mock inventory logs
      allow(InventoryLog).to receive(:where).and_return(double(sum: 0, count: 0))
    end

    it 'generates movement report with correct structure' do
      ship_logs = double(sum: -50, count: 2)
      receive_logs = double(sum: 30, count: 1)

      allow(InventoryLog).to receive(:where).with(hash_including(
        inventory_id: anything,
        operation_type: "ship"
      )).and_return(ship_logs)

      allow(InventoryLog).to receive(:where).with(hash_including(
        inventory_id: anything,
        operation_type: "receive"
      )).and_return(receive_logs)

      report = test_class.movement_report(start_date, end_date)

      expect(report).to include(
        start_date: start_date,
        end_date: end_date,
        total_shipped: be >= 0,
        total_received: be >= 0,
        net_change: be_a(Numeric),
        items: be_an(Array)
      )
    end

    it 'calculates item-level movements correctly' do
      # Mock specific inventory logs
      ship_logs1 = double(sum: -30, count: 2)
      receive_logs1 = double(sum: 20, count: 1)

      allow(InventoryLog).to receive(:where).with(hash_including(
        inventory_id: 1,
        operation_type: "ship"
      )).and_return(ship_logs1)

      allow(InventoryLog).to receive(:where).with(hash_including(
        inventory_id: 1,
        operation_type: "receive"
      )).and_return(receive_logs1)

      report = test_class.movement_report(start_date, end_date)

      item1 = report[:items].find { |item| item[:id] == 1 }
      expect(item1).to include(
        id: 1,
        name: "Item 1",
        code: "CODE1",
        shipped_quantity: 30,
        received_quantity: 20,
        net_change: -10,
        ship_count: 2,
        receive_count: 1
      )
    end

    it 'sorts results by specified field' do
      report = test_class.movement_report(start_date, end_date, {
        sort_by: :net_change,
        sort_direction: :desc
      })

      # Items should be sorted by net_change in descending order
      if report[:items].size > 1
        report[:items].each_cons(2) do |a, b|
          expect(a[:net_change]).to be >= b[:net_change]
        end
      end
    end

    it 'handles ascending sort direction' do
      report = test_class.movement_report(start_date, end_date, {
        sort_by: :shipped_quantity,
        sort_direction: :asc
      })

      # Items should be sorted by shipped_quantity in ascending order
      if report[:items].size > 1
        report[:items].each_cons(2) do |a, b|
          expect(a[:shipped_quantity]).to be <= b[:shipped_quantity]
        end
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe 'edge cases' do
    describe 'nil handling' do
      it 'handles nil destination in create_shipment' do
        allow(shipments_relation).to receive(:new).and_return(double(save: true))
        expect(test_instance).to receive(:remove_stock)

        result = test_instance.create_shipment(10, nil)
        expect(result).to be true
      end

      it 'handles nil source in create_receipt' do
        allow(receipts_relation).to receive(:new).and_return(double(save: true))
        expect(test_instance).to receive(:add_stock)

        result = test_instance.create_receipt(20, nil)
        expect(result).to be true
      end
    end

    describe 'boundary values' do
      it 'allows shipment of entire stock' do
        mock_shipment = double(save: true)
        allow(shipments_relation).to receive(:new).and_return(mock_shipment)
        expect(test_instance).to receive(:remove_stock).with(100, anything)

        result = test_instance.create_shipment(100, "Tokyo")
        expect(result).to be true
      end

      it 'allows return of entire shipment quantity' do
        shipment = double(quantity: 50, shipped?: true, update: true)
        allow(shipments_relation).to receive(:find_by).and_return(shipment)
        expect(test_instance).to receive(:add_stock).with(50, anything)

        result = test_instance.process_return(1, 50)
        expect(result).to be true
      end
    end

    describe 'concurrent operations' do
      it 'handles multiple shipments' do
        mock_shipment1 = double(save: true)
        mock_shipment2 = double(save: true)

        allow(shipments_relation).to receive(:new).and_return(mock_shipment1, mock_shipment2)
        allow(test_instance).to receive(:remove_stock)

        result1 = test_instance.create_shipment(30, "Tokyo")
        result2 = test_instance.create_shipment(40, "Osaka")

        expect(result1).to be true
        expect(result2).to be true
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it 'generates movement report efficiently' do
      # Mock large dataset
      allow(test_class).to receive_message_chain(:joins, :where, :distinct, :pluck)
        .and_return((1..100).to_a)

      inventories = (1..100).map do |i|
        double(id: i, name: "Item #{i}", code: "CODE#{i}")
      end

      allow(Inventory).to receive(:where).and_return(inventories)
      allow(inventories).to receive(:index_by).and_return(
        inventories.each_with_object({}) { |inv, hash| hash[inv.id] = inv }
      )

      allow(InventoryLog).to receive(:where).and_return(double(sum: 0, count: 0))

      start_time = Time.now
      test_class.movement_report(Date.new(2024, 1, 1), Date.new(2024, 12, 31))
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 200 # Should complete in under 200ms
    end
  end
end
