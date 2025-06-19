# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreInventory, type: :model do
  # CLAUDE.md準拠: 店舗在庫管理の包括的テスト
  # メタ認知: 複雑な在庫ビジネスロジックとパフォーマンス最適化の品質保証
  # 横展開: 他の在庫関連モデルでも同様のテストパターン適用

  let(:store) { create(:store) }
  let(:inventory) { create(:inventory, price: 100) }
  let(:store_inventory) { create(:store_inventory, store: store, inventory: inventory, quantity: 50, reserved_quantity: 10, safety_stock_level: 20) }

  describe 'associations' do
    it { should belong_to(:store) }
    it { should belong_to(:inventory) }
    it { should have_many(:inventory_logs).through(:inventory) }
  end

  describe 'validations' do
    subject { build(:store_inventory) }

    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:reserved_quantity) }
    it { should validate_numericality_of(:reserved_quantity).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:safety_stock_level) }
    it { should validate_numericality_of(:safety_stock_level).is_greater_than_or_equal_to(0) }
    it { should validate_uniqueness_of(:store_id).scoped_to(:inventory_id).with_message("この店舗には既に同じ商品の在庫が登録されています") }

    describe 'custom validations' do
      describe 'reserved_quantity_not_exceed_quantity' do
        it 'allows reserved_quantity less than or equal to quantity' do
          store_inventory = build(:store_inventory, quantity: 10, reserved_quantity: 5)
          expect(store_inventory).to be_valid
        end

        it 'allows reserved_quantity equal to quantity' do
          store_inventory = build(:store_inventory, quantity: 10, reserved_quantity: 10)
          expect(store_inventory).to be_valid
        end

        it 'rejects reserved_quantity greater than quantity' do
          store_inventory = build(:store_inventory, quantity: 5, reserved_quantity: 10)
          expect(store_inventory).not_to be_valid
          expect(store_inventory.errors[:reserved_quantity]).to include('は在庫数を超えることはできません')
        end

        it 'handles nil values gracefully' do
          store_inventory = build(:store_inventory, quantity: nil, reserved_quantity: 5)
          store_inventory.valid?
          # Should not raise error, other validations will catch nil quantity
          expect(store_inventory.errors[:reserved_quantity]).not_to include('は在庫数を超えることはできません')
        end
      end

      describe 'quantity_sufficient_for_reservation' do
        it 'rejects quantity reduction below reserved_quantity' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.quantity = 3

          expect(store_inventory).not_to be_valid
          expect(store_inventory.errors[:quantity]).to include('は予約済み数量（5）以上である必要があります')
        end

        it 'allows quantity reduction to exactly reserved_quantity' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.quantity = 5

          expect(store_inventory).to be_valid
        end

        it 'allows quantity increase' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.quantity = 15

          expect(store_inventory).to be_valid
        end

        it 'handles nil reserved_quantity gracefully' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.reserved_quantity = nil
          store_inventory.quantity = 3

          store_inventory.valid?
          expect(store_inventory.errors[:quantity]).not_to include(/は予約済み数量/)
        end

        it 'handles nil quantity gracefully' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.quantity = nil

          store_inventory.valid?
          # Should not crash, but will be invalid due to presence validation
          expect(store_inventory).not_to be_valid
        end

        it 'only validates when quantity changed' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.safety_stock_level = 25

          expect(store_inventory).to be_valid
        end
      end
    end
  end

  # スコープテスト
  describe 'scopes' do
    before do
      @available_item = create(:store_inventory, quantity: 20, reserved_quantity: 5, safety_stock_level: 10)
      @low_stock_item = create(:store_inventory, quantity: 8, reserved_quantity: 0, safety_stock_level: 10)
      @critical_item = create(:store_inventory, quantity: 3, reserved_quantity: 0, safety_stock_level: 10)
      @out_of_stock_item = create(:store_inventory, quantity: 0, reserved_quantity: 0, safety_stock_level: 5)
      @overstocked_item = create(:store_inventory, quantity: 100, reserved_quantity: 0, safety_stock_level: 10)
      @fully_reserved_item = create(:store_inventory, quantity: 15, reserved_quantity: 15, safety_stock_level: 10)
    end

    describe '.available' do
      it 'returns items with available quantity' do
        expect(StoreInventory.available).to include(@available_item, @low_stock_item, @critical_item, @overstocked_item)
        expect(StoreInventory.available).not_to include(@out_of_stock_item, @fully_reserved_item)
      end
    end

    describe '.low_stock' do
      it 'returns items at or below safety stock level' do
        expect(StoreInventory.low_stock).to include(@low_stock_item, @critical_item, @out_of_stock_item)
        expect(StoreInventory.low_stock).not_to include(@available_item, @overstocked_item, @fully_reserved_item)
      end
    end

    describe '.critical_stock' do
      it 'returns items at or below 50% of safety stock level' do
        expect(StoreInventory.critical_stock).to include(@critical_item, @out_of_stock_item)
        expect(StoreInventory.critical_stock).not_to include(@available_item, @low_stock_item, @overstocked_item, @fully_reserved_item)
      end
    end

    describe '.out_of_stock' do
      it 'returns items with zero quantity' do
        expect(StoreInventory.out_of_stock).to include(@out_of_stock_item)
        expect(StoreInventory.out_of_stock).not_to include(@available_item, @low_stock_item, @critical_item, @overstocked_item, @fully_reserved_item)
      end
    end

    describe '.overstocked' do
      it 'returns items with more than 3x safety stock level' do
        expect(StoreInventory.overstocked).to include(@overstocked_item)
        expect(StoreInventory.overstocked).not_to include(@available_item, @low_stock_item, @critical_item, @out_of_stock_item, @fully_reserved_item)
      end
    end

    describe '.by_store and .by_inventory' do
      it 'filters by store' do
        expect(StoreInventory.by_store(@available_item.store)).to include(@available_item)
        expect(StoreInventory.by_store(@available_item.store)).not_to include(@low_stock_item)
      end

      it 'filters by inventory' do
        expect(StoreInventory.by_inventory(@available_item.inventory)).to include(@available_item)
        expect(StoreInventory.by_inventory(@available_item.inventory)).not_to include(@low_stock_item)
      end
    end
    
    describe '.recent' do
      it 'orders by created_at desc' do
        old_item = create(:store_inventory, created_at: 2.days.ago)
        new_item = create(:store_inventory, created_at: 1.hour.ago)
        
        expect(StoreInventory.recent.first).to eq(new_item)
        expect(StoreInventory.recent.last).to eq(old_item)
      end
    end
    
    describe '.needs_reorder' do
      it 'returns items that need reordering' do
        need_reorder = create(:store_inventory, quantity: 5, safety_stock_level: 20, reorder_level: 15)
        no_need = create(:store_inventory, quantity: 25, safety_stock_level: 10, reorder_level: 15)
        
        expect(StoreInventory.needs_reorder).to include(need_reorder)
        expect(StoreInventory.needs_reorder).not_to include(no_need)
      end
    end
  end

  # インスタンスメソッドテスト
  describe '#available_quantity' do
    it 'calculates available quantity correctly' do
      expect(store_inventory.available_quantity).to eq(40) # 50 - 10
    end

    it 'handles zero reserved quantity' do
      store_inventory.reserved_quantity = 0
      expect(store_inventory.available_quantity).to eq(50)
    end

    it 'handles fully reserved inventory' do
      store_inventory.reserved_quantity = 50
      expect(store_inventory.available_quantity).to eq(0)
    end
    
    it 'returns negative when over-reserved' do
      store_inventory.reserved_quantity = 60
      expect(store_inventory.available_quantity).to eq(-10)
    end
  end

  describe '#stock_level_status' do
    it 'returns out_of_stock when quantity is zero' do
      store_inventory.quantity = 0
      expect(store_inventory.stock_level_status).to eq(:out_of_stock)
    end

    it 'returns critical when quantity is at or below 50% of safety stock' do
      store_inventory.quantity = 10 # 50% of 20
      store_inventory.safety_stock_level = 20
      expect(store_inventory.stock_level_status).to eq(:critical)
    end

    it 'returns low when quantity is at or below safety stock level' do
      store_inventory.quantity = 20 # Equal to safety stock
      store_inventory.safety_stock_level = 20
      expect(store_inventory.stock_level_status).to eq(:low)
    end

    it 'returns optimal when quantity is between safety stock and 2x safety stock' do
      store_inventory.quantity = 30 # Between 20 and 40
      store_inventory.safety_stock_level = 20
      expect(store_inventory.stock_level_status).to eq(:optimal)
    end

    it 'returns excess when quantity is above 2x safety stock level' do
      store_inventory.quantity = 50 # Above 2x 20
      store_inventory.safety_stock_level = 20
      expect(store_inventory.stock_level_status).to eq(:excess)
    end

    it 'handles edge case of exactly 50% safety stock' do
      store_inventory.quantity = 10
      store_inventory.safety_stock_level = 20
      expect(store_inventory.stock_level_status).to eq(:critical)
    end

    it 'handles edge case of exactly 2x safety stock' do
      store_inventory.quantity = 40
      store_inventory.safety_stock_level = 20
      expect(store_inventory.stock_level_status).to eq(:optimal)
    end
  end

  describe '#stock_level_status_text' do
    it 'returns correct Japanese text for each status' do
      expect(StoreInventory.new(quantity: 0, safety_stock_level: 20).stock_level_status_text).to eq("在庫切れ")
      expect(StoreInventory.new(quantity: 5, safety_stock_level: 20).stock_level_status_text).to eq("危険在庫")
      expect(StoreInventory.new(quantity: 15, safety_stock_level: 20).stock_level_status_text).to eq("低在庫")
      expect(StoreInventory.new(quantity: 30, safety_stock_level: 20).stock_level_status_text).to eq("適正在庫")
      expect(StoreInventory.new(quantity: 60, safety_stock_level: 20).stock_level_status_text).to eq("過剰在庫")
    end
  end

  describe 'value calculations' do
    describe '#inventory_value' do
      it 'calculates total inventory value correctly' do
        expect(store_inventory.inventory_value).to eq(5000) # 50 * 100
      end

      it 'handles zero quantity' do
        store_inventory.quantity = 0
        expect(store_inventory.inventory_value).to eq(0)
      end
      
      it 'handles decimal prices' do
        inventory.update!(price: 99.99)
        expect(store_inventory.inventory_value).to eq(4999.50) # 50 * 99.99
      end
    end

    describe '#reserved_value' do
      it 'calculates reserved value correctly' do
        expect(store_inventory.reserved_value).to eq(1000) # 10 * 100
      end

      it 'handles zero reserved quantity' do
        store_inventory.reserved_quantity = 0
        expect(store_inventory.reserved_value).to eq(0)
      end
    end

    describe '#available_value' do
      it 'calculates available value correctly' do
        expect(store_inventory.available_value).to eq(4000) # 40 * 100
      end

      it 'handles fully reserved inventory' do
        store_inventory.reserved_quantity = 50
        expect(store_inventory.available_value).to eq(0)
      end
    end
  end
  
  # 在庫操作メソッド
  describe 'inventory operations' do
    describe '#reserve' do
      it 'reserves quantity successfully' do
        result = store_inventory.reserve(15)
        expect(result).to be true
        expect(store_inventory.reload.reserved_quantity).to eq(25) # 10 + 15
      end
      
      it 'fails when exceeding available quantity' do
        result = store_inventory.reserve(45) # Available: 40
        expect(result).to be false
        expect(store_inventory.errors[:base]).to include(/予約可能数量を超えています/)
      end
      
      it 'creates inventory log on success' do
        expect {
          store_inventory.reserve(10)
        }.to change(InventoryLog, :count).by(1)
        
        log = InventoryLog.last
        expect(log.operation_type).to eq('reserve')
        expect(log.delta).to eq(-10)
      end
    end
    
    describe '#release_reservation' do
      it 'releases reserved quantity' do
        store_inventory.update!(reserved_quantity: 20)
        result = store_inventory.release_reservation(15)
        
        expect(result).to be true
        expect(store_inventory.reload.reserved_quantity).to eq(5)
      end
      
      it 'fails when releasing more than reserved' do
        store_inventory.update!(reserved_quantity: 10)
        result = store_inventory.release_reservation(15)
        
        expect(result).to be false
        expect(store_inventory.errors[:base]).to include(/予約数量を超えています/)
      end
    end
    
    describe '#adjust_quantity' do
      it 'increases quantity' do
        result = store_inventory.adjust_quantity(20, reason: 'Stock correction')
        expect(result).to be true
        expect(store_inventory.reload.quantity).to eq(70)
      end
      
      it 'decreases quantity' do
        result = store_inventory.adjust_quantity(-10, reason: 'Damage')
        expect(result).to be true
        expect(store_inventory.reload.quantity).to eq(40)
      end
      
      it 'fails when reducing below reserved' do
        store_inventory.update!(reserved_quantity: 45)
        result = store_inventory.adjust_quantity(-10)
        
        expect(result).to be false
      end
      
      it 'creates inventory log with reason' do
        store_inventory.adjust_quantity(10, reason: 'Found during audit')
        
        log = InventoryLog.last
        expect(log.operation_type).to eq('adjustment')
        expect(log.notes).to eq('Found during audit')
      end
    end
  end

  describe 'callbacks' do
    describe 'before_update :update_last_updated_at' do
      it 'updates last_updated_at when quantity changes' do
        freeze_time do
          store_inventory = create(:store_inventory, quantity: 10)
          original_time = store_inventory.last_updated_at

          travel 1.hour do
            store_inventory.update!(quantity: 15)
            expect(store_inventory.last_updated_at).to be > original_time
          end
        end
      end

      it 'does not update last_updated_at when quantity does not change' do
        store_inventory = create(:store_inventory, quantity: 10, safety_stock_level: 5)
        original_time = store_inventory.last_updated_at

        store_inventory.update!(safety_stock_level: 10)
        expect(store_inventory.last_updated_at).to eq(original_time)
      end
    end

    describe 'after_commit :check_stock_alerts' do
      it 'logs stock alert information on create' do
        expect(Rails.logger).to receive(:info).with(/在庫アラートチェック/)
        create(:store_inventory)
      end

      it 'logs stock alert information on update' do
        store_inventory = create(:store_inventory)
        expect(Rails.logger).to receive(:info).with(/在庫アラートチェック/)
        store_inventory.update!(quantity: 20)
      end
      
      it 'triggers alert for low stock' do
        expect(StockAlertJob).to receive(:perform_later)
        create(:store_inventory, quantity: 5, safety_stock_level: 20)
      end
      
      it 'triggers alert for out of stock' do
        expect(StockAlertJob).to receive(:perform_later)
        create(:store_inventory, quantity: 0)
      end
    end
  end
  
  # 複雑なビジネスロジック
  describe 'business logic' do
    describe '#days_of_stock_remaining' do
      it 'calculates based on daily usage rate' do
        store_inventory.update!(daily_usage_rate: 5)
        expect(store_inventory.days_of_stock_remaining).to eq(8) # 40 available / 5 per day
      end
      
      it 'returns infinity when no usage' do
        store_inventory.update!(daily_usage_rate: 0)
        expect(store_inventory.days_of_stock_remaining).to eq(Float::INFINITY)
      end
      
      it 'returns 0 when no available stock' do
        store_inventory.update!(reserved_quantity: 50, daily_usage_rate: 5)
        expect(store_inventory.days_of_stock_remaining).to eq(0)
      end
    end
    
    describe '#reorder_quantity' do
      it 'calculates optimal reorder quantity' do
        store_inventory.update!(
          safety_stock_level: 20,
          reorder_level: 30,
          max_stock_level: 100,
          lead_time_days: 7,
          daily_usage_rate: 5
        )
        
        # Should order enough to reach max level considering lead time usage
        expected = 100 - store_inventory.quantity + (7 * 5)
        expect(store_inventory.reorder_quantity).to eq(expected)
      end
    end
    
    describe '#needs_reorder?' do
      it 'returns true when below reorder level' do
        store_inventory.update!(quantity: 25, reorder_level: 30)
        expect(store_inventory.needs_reorder?).to be true
      end
      
      it 'returns false when above reorder level' do
        store_inventory.update!(quantity: 35, reorder_level: 30)
        expect(store_inventory.needs_reorder?).to be false
      end
      
      it 'considers reserved quantity' do
        store_inventory.update!(quantity: 40, reserved_quantity: 20, reorder_level: 30)
        expect(store_inventory.needs_reorder?).to be true # Available: 20 < 30
      end
    end
  end
  
  # パフォーマンステスト
  describe 'performance' do
    it 'handles bulk updates efficiently' do
      items = create_list(:store_inventory, 100)
      
      start_time = Time.current
      StoreInventory.where(id: items.map(&:id)).update_all(quantity: 100)
      elapsed_time = (Time.current - start_time) * 1000
      
      expect(elapsed_time).to be < 500 # Under 500ms
    end
    
    it 'avoids N+1 queries when accessing inventory details' do
      items = create_list(:store_inventory, 5)
      
      expect {
        StoreInventory.includes(:inventory, :store).each do |si|
          si.inventory.name
          si.store.name
          si.inventory_value
        end
      }.not_to exceed_query_limit(3)
    end
  end
  
  # セキュリティテスト
  describe 'security' do
    it 'prevents negative quantity through mass assignment' do
      store_inventory.update(quantity: -10)
      expect(store_inventory).not_to be_valid
    end
    
    it 'sanitizes user input in adjust_quantity reason' do
      malicious_reason = '<script>alert("XSS")</script>Stock adjustment'
      store_inventory.adjust_quantity(10, reason: malicious_reason)
      
      log = InventoryLog.last
      expect(log.notes).not_to include('<script>')
    end
  end
  
  # 統合シナリオテスト
  describe 'integration scenarios' do
    it 'handles complete inventory cycle' do
      # 1. Initial stock
      si = create(:store_inventory, quantity: 100, reserved_quantity: 0, safety_stock_level: 20)
      
      # 2. Customer reserves items
      expect(si.reserve(30)).to be true
      expect(si.available_quantity).to eq(70)
      
      # 3. Stock adjustment for damage
      expect(si.adjust_quantity(-10, reason: 'Water damage')).to be true
      expect(si.quantity).to eq(90)
      
      # 4. Check if reorder needed
      si.update!(reorder_level: 80)
      expect(si.needs_reorder?).to be true
      
      # 5. Receive new stock
      expect(si.adjust_quantity(50, reason: 'New delivery')).to be true
      expect(si.quantity).to eq(140)
      
      # 6. Release some reservations
      expect(si.release_reservation(10)).to be true
      expect(si.reserved_quantity).to eq(20)
      
      # 7. Check final status
      expect(si.stock_level_status).to eq(:excess)
      expect(si.available_quantity).to eq(120)
    end
  end
  
  # Timestampable concern integration
  describe 'timestampable behavior' do
    it_behaves_like 'timestampable'
  end
  
  # エッジケース
  describe 'edge cases' do
    it 'handles concurrent updates safely' do
      threads = 5.times.map do
        Thread.new do
          store_inventory.with_lock do
            current_qty = store_inventory.reload.quantity
            store_inventory.update!(quantity: current_qty + 10)
          end
        end
      end
      
      threads.each(&:join)
      expect(store_inventory.reload.quantity).to eq(100) # 50 + (5 * 10)
    end
    
    it 'handles very large quantities' do
      store_inventory.update!(quantity: 999_999_999)
      expect(store_inventory.inventory_value).to eq(99_999_999_900)
    end
    
    it 'handles precision in calculations' do
      inventory.update!(price: 0.01)
      store_inventory.update!(quantity: 3)
      expect(store_inventory.inventory_value).to eq(0.03)
    end
  end
end