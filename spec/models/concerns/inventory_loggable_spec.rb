# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLoggable, type: :model do
  let(:test_model_class) do
    Class.new(ApplicationRecord) do
      include InventoryLoggable
      
      self.table_name = 'inventories'
      
      validates :name, presence: true
      validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
      
      def self.name
        'Inventory'
      end
    end
  end

  let(:inventory1) { create(:inventory, name: 'テスト1', quantity: 10) }
  let(:inventory2) { create(:inventory, name: 'テスト2', quantity: 20) }

  describe '.create_bulk_inventory_logs' do
    it 'record_timestamps: trueオプションでタイムスタンプが自動設定される' do
      records = [inventory1, inventory2]
      inserted_ids = [[inventory1.id], [inventory2.id]]

      initial_count = InventoryLog.count

      test_model_class.create_bulk_inventory_logs(records, inserted_ids)

      # ログが2件作成されることを確認
      expect(InventoryLog.count).to eq(initial_count + 2)

      # 作成されたログの確認
      created_logs = InventoryLog.last(2)
      created_logs.each_with_index do |log, index|
        expect(log.inventory_id).to eq(records[index].id)
        expect(log.delta).to eq(records[index].quantity)
        expect(log.operation_type).to eq('add')
        expect(log.previous_quantity).to eq(0)
        expect(log.current_quantity).to eq(records[index].quantity)
        expect(log.note).to eq('CSVインポートによる登録')
        
        # タイムスタンプが正しく設定されていることを確認
        expect(log.created_at).to be_present
        expect(log.updated_at).to be_present
        expect(log.created_at).to be_within(1.second).of(Time.current)
        expect(log.updated_at).to be_within(1.second).of(Time.current)
      end
    end

    it '空のレコード配列の場合は何もしない' do
      expect {
        test_model_class.create_bulk_inventory_logs([], [])
      }.not_to change(InventoryLog, :count)
    end

    it 'recordsがnilの場合は何もしない' do
      expect {
        test_model_class.create_bulk_inventory_logs(nil, [])
      }.not_to change(InventoryLog, :count)
    end

    it 'inserted_idsがnilの場合は何もしない' do
      expect {
        test_model_class.create_bulk_inventory_logs([inventory1], nil)
      }.not_to change(InventoryLog, :count)
    end
  end

  describe 'Rails 7互換性' do
    it 'InventoryLog.insert_allがrecord_timestamps: trueオプションを使用している' do
      records = [inventory1]
      inserted_ids = [[inventory1.id]]

      # insert_allメソッドをモック
      expect(InventoryLog).to receive(:insert_all)
        .with(anything, record_timestamps: true)
        .and_call_original

      test_model_class.create_bulk_inventory_logs(records, inserted_ids)
    end
  end

  describe '#log_operation' do
    it '在庫操作ログが正常に作成される' do
      inventory = create(:inventory, quantity: 100)
      
      expect {
        inventory.log_operation('add', 10, 'テスト入庫')
      }.to change(InventoryLog, :count).by(1)

      log = InventoryLog.last
      expect(log.inventory_id).to eq(inventory.id)
      expect(log.delta).to eq(10)
      expect(log.operation_type).to eq('add')
      expect(log.previous_quantity).to eq(90) # 100 - 10
      expect(log.current_quantity).to eq(100)
      expect(log.note).to eq('テスト入庫')
    end
  end

  describe '#add_stock' do
    it '在庫を正常に追加できる' do
      inventory = create(:inventory, quantity: 50)
      
      result = inventory.add_stock(25, 'テスト入庫')
      
      expect(result).to be true
      expect(inventory.reload.quantity).to eq(75)
      
      log = InventoryLog.last
      expect(log.operation_type).to eq('add')
      expect(log.delta).to eq(25)
    end

    it '0以下の数量では追加できない' do
      inventory = create(:inventory, quantity: 50)
      
      result = inventory.add_stock(-10)
      
      expect(result).to be false
      expect(inventory.reload.quantity).to eq(50)
    end
  end

  describe '#remove_stock' do
    it '在庫を正常に減らせる' do
      inventory = create(:inventory, quantity: 50)
      
      result = inventory.remove_stock(20, 'テスト出庫')
      
      expect(result).to be true
      expect(inventory.reload.quantity).to eq(30)
      
      log = InventoryLog.last
      expect(log.operation_type).to eq('remove')
      expect(log.delta).to eq(-20)
    end

    it '在庫数量を超える場合は減らせない' do
      inventory = create(:inventory, quantity: 10)
      
      result = inventory.remove_stock(20)
      
      expect(result).to be false
      expect(inventory.reload.quantity).to eq(10)
    end
  end
end