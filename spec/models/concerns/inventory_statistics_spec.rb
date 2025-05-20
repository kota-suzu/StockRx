require 'rails_helper'

RSpec.describe InventoryStatistics do
  let(:inventory_class) do
    Class.new(ApplicationRecord) do
      self.table_name = 'inventories'
      include InventoryStatistics
    end
  end

  describe 'scopes' do
    before do
      Inventory.delete_all
      create(:inventory, quantity: 0)
      create(:inventory, quantity: 3)
      create(:inventory, quantity: 10)
    end

    it 'low_stockは閾値以下の在庫を返す' do
      expect(inventory_class.low_stock.count).to eq(1)
    end

    it 'out_of_stockは在庫切れの商品を返す' do
      expect(inventory_class.out_of_stock.count).to eq(1)
    end

    it 'normal_stockは閾値より多い在庫を返す' do
      expect(inventory_class.normal_stock.count).to eq(1)
    end
  end

  describe 'instance methods' do
    let(:out_of_stock) { build(:inventory, quantity: 0) }
    let(:low_stock) { build(:inventory, quantity: 3) }
    let(:normal_stock) { build(:inventory, quantity: 10) }

    it 'low_stock?は閾値以下かを判定する' do
      expect(out_of_stock.low_stock?).to be false
      expect(low_stock.low_stock?).to be true
      expect(normal_stock.low_stock?).to be false
    end

    it 'out_of_stock?は在庫切れかを判定する' do
      expect(out_of_stock.out_of_stock?).to be true
      expect(low_stock.out_of_stock?).to be false
    end

    it 'stock_statusは適切なステータスを返す' do
      expect(out_of_stock.stock_status).to eq(:out_of_stock)
      expect(low_stock.stock_status).to eq(:low_stock)
      expect(normal_stock.stock_status).to eq(:normal)
    end
  end

  describe 'class methods' do
    before do
      Inventory.delete_all
      create(:inventory, quantity: 0, price: 100)
      create(:inventory, quantity: 3, price: 200)
      create(:inventory, quantity: 10, price: 300)
    end

    it 'stock_summaryは在庫の統計情報を返す' do
      summary = inventory_class.stock_summary

      expect(summary[:total_count]).to eq(3)
      expect(summary[:total_value]).to eq(3*200 + 10*300)
      expect(summary[:low_stock_count]).to eq(1)
      expect(summary[:out_of_stock_count]).to eq(1)
      expect(summary[:normal_stock_count]).to eq(1)
    end
  end
end
