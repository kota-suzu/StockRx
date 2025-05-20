# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryDecorator do
  # Inventory::LOW_STOCK_THRESHOLD defaults to 5, as per Inventory model
  let(:low_stock_threshold) { Inventory::LOW_STOCK_THRESHOLD }

  describe '#alert_badge' do
    context 'when inventory is completely out of stock (quantity is 0)' do
      let(:inventory) { build_stubbed(:inventory, quantity: 0) }
      subject(:decorated_inventory) { inventory.decorate }

      it 'returns the "在庫切れ" (out of stock) badge' do
        expect(decorated_inventory.alert_badge).to include('在庫切れ')
        expect(decorated_inventory.alert_badge).not_to include('要補充')
        expect(decorated_inventory.alert_badge).not_to include('OK')
      end
    end

    # Corresponds to original failure:
    # rspec ./spec/decorators/inventory_decorator_spec.rb:12 # InventoryDecorator#alert_badge 在庫がない場合 要補充の警告バッジを返すこと
    # "在庫がない場合" was likely a misnomer for "low stock".
    context 'when inventory is low stock (quantity > 0 and <= threshold)' do
      # Example: quantity = 3, threshold = 5. (3 > 0 && 3 <= 5) -> true
      let(:inventory_quantity) { low_stock_threshold > 1 ? low_stock_threshold - 1 : 1 } # Ensure positive quantity
      let(:inventory) { build_stubbed(:inventory, quantity: inventory_quantity) }
      subject(:decorated_inventory) { inventory.decorate }

      it 'returns the "要補充" (low stock) badge' do # Test from original line ~12
        expect(decorated_inventory.alert_badge).to include('要補充')
        expect(decorated_inventory.alert_badge).not_to include('在庫切れ')
        expect(decorated_inventory.alert_badge).not_to include('OK')
      end
    end

    # Corresponds to original failure:
    # rspec ./spec/decorators/inventory_decorator_spec.rb:21 # InventoryDecorator#alert_badge 在庫がある場合 OKのバッジを返すこと
    context 'when inventory has normal stock (quantity > threshold)' do
      # Example: quantity = 6, threshold = 5. (6 > 5) -> true
      let(:inventory) { build_stubbed(:inventory, quantity: low_stock_threshold + 1) }
      subject(:decorated_inventory) { inventory.decorate }

      it 'returns the "OK" (normal stock) badge' do # Test from original line ~21
        expect(decorated_inventory.alert_badge).to include('OK')
        expect(decorated_inventory.alert_badge).not_to include('在庫切れ')
        expect(decorated_inventory.alert_badge).not_to include('要補充')
      end
    end
  end

  describe '#formatted_price' do
    let(:inventory) { build_stubbed(:inventory, price: 1234) }
    subject(:decorated_inventory) { inventory.decorate }

    it 'formats the price as JPY currency' do
      expect(decorated_inventory.formatted_price).to eq('¥1,234')
    end

    context 'with decimal price' do
      let(:inventory) { build_stubbed(:inventory, price: 567.89) }
      it 'formats and rounds the price' do
        expect(decorated_inventory.formatted_price).to eq('¥568') # precision: 0 rounds
      end
    end
  end

  # Corresponds to original failure:
  # rspec ./spec/decorators/inventory_decorator_spec.rb:56 # InventoryDecorator#as_json_with_decorated 装飾済みの属性を含めたJSONハッシュを返すこと
  describe '#as_json_with_decorated' do
    # The original test expected quantity: 5.
    let(:inventory) do
      build_stubbed(:inventory, id: 1, name: 'Test Item', quantity: 5, price: 1234.56, status: 'active', created_at: Time.current, updated_at: Time.current)
    end
    subject(:decorated_inventory) { inventory.decorate }

    it 'returns a JSON hash including decorated attributes' do # Test from original line ~56
      json = decorated_inventory.as_json_with_decorated

      expect(json[:id]).to eq(inventory.id)
      expect(json[:name]).to eq('Test Item')
      expect(json[:quantity]).to eq(5) # This was the failing assertion
      expect(json[:price]).to eq("1234.56") # Raw price from object.as_json is a string
      expect(json[:status]).to eq('active')

      # Check decorated attributes
      # With quantity: 5 and low_stock_threshold: 5, alert_badge should be "要補充"
      expect(json[:alert_badge]).to eq(decorated_inventory.alert_badge)
      expect(json[:alert_badge]).to include('要補充')
      expect(json[:formatted_price]).to eq('¥1,235') # 1234.56 rounds to 1235 with precision 0
    end
  end

  describe '#status_badge' do
    it 'returns "有効" for active status' do
      expect(build_stubbed(:inventory, status: 'active').decorate.status_badge).to include('有効')
    end

    it 'returns "アーカイブ" for archived status' do
      expect(build_stubbed(:inventory, status: 'archived').decorate.status_badge).to include('アーカイブ')
    end
  end
end