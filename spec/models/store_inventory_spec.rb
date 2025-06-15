# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreInventory, type: :model do
  describe 'associations' do
    it { should belong_to(:store) }
    it { should belong_to(:inventory) }
  end

  describe 'validations' do
    subject { build(:store_inventory) }

    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:reserved_quantity) }
    it { should validate_numericality_of(:reserved_quantity).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:safety_stock_level) }
    it { should validate_numericality_of(:safety_stock_level).is_greater_than_or_equal_to(0) }
    it { should validate_uniqueness_of(:store_id).scoped_to(:inventory_id) }

    describe 'custom validations' do
      describe 'reserved_quantity_not_exceed_quantity' do
        it 'allows reserved_quantity less than or equal to quantity' do
          store_inventory = build(:store_inventory, quantity: 10, reserved_quantity: 5)
          expect(store_inventory).to be_valid
        end

        it 'rejects reserved_quantity greater than quantity' do
          store_inventory = build(:store_inventory, quantity: 5, reserved_quantity: 10)
          expect(store_inventory).not_to be_valid
          expect(store_inventory.errors[:reserved_quantity]).to include('は在庫数を超えることはできません')
        end
      end

      describe 'quantity_sufficient_for_reservation' do
        it 'rejects quantity reduction below reserved_quantity' do
          store_inventory = create(:store_inventory, quantity: 10, reserved_quantity: 5)
          store_inventory.quantity = 3

          expect(store_inventory).not_to be_valid
          expect(store_inventory.errors[:quantity]).to include('は予約済み数量（5）以上である必要があります')
        end
      end
    end
  end

  describe 'callbacks' do
    describe 'before_update :update_last_updated_at' do
      it 'updates last_updated_at when quantity changes' do
        store_inventory = create(:store_inventory, quantity: 10)
        expect {
          store_inventory.update!(quantity: 15)
        }.to change { store_inventory.last_updated_at }
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
    end
  end

  describe 'scopes' do
    let!(:store1) { create(:store) }
    let!(:store2) { create(:store) }
    let!(:inventory1) { create(:inventory) }
    let!(:inventory2) { create(:inventory) }

    let!(:available_item) { create(:store_inventory, store: store1, inventory: inventory1, quantity: 10, reserved_quantity: 5) }
    let!(:fully_reserved_item) { create(:store_inventory, store: store1, inventory: inventory2, quantity: 10, reserved_quantity: 10) }
    let!(:low_stock_item) { create(:store_inventory, store: store2, inventory: inventory1, quantity: 3, safety_stock_level: 5) }
    let!(:critical_stock_item) { create(:store_inventory, store: store2, inventory: inventory2, quantity: 1, safety_stock_level: 5) }
    let!(:out_of_stock_item) { create(:store_inventory, store: store1, quantity: 0) }
    let!(:overstocked_item) { create(:store_inventory, :excess_stock, store: store2) }

    describe '.available' do
      it 'returns items with available quantity' do
        expect(StoreInventory.available).to include(available_item)
        expect(StoreInventory.available).not_to include(fully_reserved_item)
      end
    end

    describe '.low_stock' do
      it 'returns items with quantity below or equal to safety level' do
        expect(StoreInventory.low_stock).to include(low_stock_item, critical_stock_item)
        expect(StoreInventory.low_stock).not_to include(available_item)
      end
    end

    describe '.critical_stock' do
      it 'returns items with quantity below half of safety level' do
        expect(StoreInventory.critical_stock).to include(critical_stock_item)
        expect(StoreInventory.critical_stock).not_to include(low_stock_item)
      end
    end

    describe '.out_of_stock' do
      it 'returns items with zero quantity' do
        expect(StoreInventory.out_of_stock).to include(out_of_stock_item)
        expect(StoreInventory.out_of_stock).not_to include(available_item)
      end
    end

    describe '.overstocked' do
      it 'returns items with quantity above 3x safety level' do
        expect(StoreInventory.overstocked).to include(overstocked_item)
        expect(StoreInventory.overstocked).not_to include(available_item)
      end
    end

    describe '.by_store' do
      it 'returns items for specified store' do
        expect(StoreInventory.by_store(store1)).to include(available_item, fully_reserved_item)
        expect(StoreInventory.by_store(store1)).not_to include(low_stock_item)
      end
    end

    describe '.by_inventory' do
      it 'returns items for specified inventory' do
        expect(StoreInventory.by_inventory(inventory1)).to include(available_item, low_stock_item)
        expect(StoreInventory.by_inventory(inventory1)).not_to include(fully_reserved_item)
      end
    end
  end

  describe 'instance methods' do
    let(:store_inventory) { create(:store_inventory, quantity: 10, reserved_quantity: 3, safety_stock_level: 5) }
    let(:inventory) { store_inventory.inventory }

    before do
      allow(inventory).to receive(:price).and_return(100)
    end

    describe '#available_quantity' do
      it 'returns quantity minus reserved_quantity' do
        expect(store_inventory.available_quantity).to eq(7) # 10 - 3
      end
    end

    describe '#stock_level_status' do
      it 'returns :out_of_stock when quantity is zero' do
        store_inventory.quantity = 0
        expect(store_inventory.stock_level_status).to eq(:out_of_stock)
      end

      it 'returns :critical when quantity is below half of safety level' do
        store_inventory.quantity = 2
        store_inventory.safety_stock_level = 5
        expect(store_inventory.stock_level_status).to eq(:critical)
      end

      it 'returns :low when quantity is below or equal to safety level' do
        store_inventory.quantity = 5
        store_inventory.safety_stock_level = 5
        expect(store_inventory.stock_level_status).to eq(:low)
      end

      it 'returns :optimal when quantity is within safe range' do
        store_inventory.quantity = 8
        store_inventory.safety_stock_level = 5
        expect(store_inventory.stock_level_status).to eq(:optimal)
      end

      it 'returns :excess when quantity is above 2x safety level' do
        store_inventory.quantity = 15
        store_inventory.safety_stock_level = 5
        expect(store_inventory.stock_level_status).to eq(:excess)
      end
    end

    describe '#stock_level_status_text' do
      it 'returns Japanese text for each status' do
        {
          out_of_stock: '在庫切れ',
          critical: '危険在庫',
          low: '低在庫',
          optimal: '適正在庫',
          excess: '過剰在庫'
        }.each do |status, text|
          allow(store_inventory).to receive(:stock_level_status).and_return(status)
          expect(store_inventory.stock_level_status_text).to eq(text)
        end
      end
    end

    describe 'value calculations' do
      describe '#inventory_value' do
        it 'calculates total inventory value' do
          expect(store_inventory.inventory_value).to eq(1000) # 10 * 100
        end
      end

      describe '#reserved_value' do
        it 'calculates reserved inventory value' do
          expect(store_inventory.reserved_value).to eq(300) # 3 * 100
        end
      end

      describe '#available_value' do
        it 'calculates available inventory value' do
          expect(store_inventory.available_value).to eq(700) # 7 * 100
        end
      end
    end

    describe '#days_of_stock_remaining' do
      it 'calculates days based on default daily usage' do
        # Default usage is 10% of safety_stock_level = 0.5, but minimum 1.0
        expect(store_inventory.days_of_stock_remaining).to eq(7.0) # 7 available / 1.0 daily
      end

      it 'calculates days based on custom daily usage' do
        expect(store_inventory.days_of_stock_remaining(2.0)).to eq(3.5) # 7 available / 2.0 daily
      end

      it 'returns infinity when daily usage is zero' do
        expect(store_inventory.days_of_stock_remaining(0)).to eq(Float::INFINITY)
      end
    end

    describe 'stock assessment methods' do
      describe '#needs_replenishment?' do
        it 'returns true when quantity is below or equal to safety level' do
          store_inventory.quantity = 5
          store_inventory.safety_stock_level = 5
          expect(store_inventory.needs_replenishment?).to be true
        end

        it 'returns false when quantity is above safety level' do
          store_inventory.quantity = 10
          store_inventory.safety_stock_level = 5
          expect(store_inventory.needs_replenishment?).to be false
        end
      end

      describe '#needs_urgent_replenishment?' do
        it 'returns true when quantity is below half of safety level' do
          store_inventory.quantity = 2
          store_inventory.safety_stock_level = 5
          expect(store_inventory.needs_urgent_replenishment?).to be true
        end

        it 'returns false when quantity is above half of safety level' do
          store_inventory.quantity = 3
          store_inventory.safety_stock_level = 5
          expect(store_inventory.needs_urgent_replenishment?).to be false
        end
      end

      describe '#max_transferable_quantity' do
        it 'returns available quantity' do
          expect(store_inventory.max_transferable_quantity).to eq(7) # 10 - 3
        end
      end
    end
  end

  describe 'class methods' do
    let!(:store) { create(:store) }
    let!(:inventory1) { create(:inventory, price: 100) }
    let!(:inventory2) { create(:inventory, price: 200) }
    let!(:store_inv1) { create(:store_inventory, store: store, inventory: inventory1, quantity: 10, reserved_quantity: 2) }
    let!(:store_inv2) { create(:store_inventory, store: store, inventory: inventory2, quantity: 5, reserved_quantity: 1, safety_stock_level: 3) }

    describe '.store_summary' do
      it 'returns comprehensive store statistics' do
        summary = StoreInventory.store_summary(store)

        expect(summary[:total_items]).to eq(2)
        expect(summary[:total_value]).to eq(2000) # (10*100) + (5*200)
        expect(summary[:available_value]).to eq(1800) # (8*100) + (4*200)
        expect(summary[:reserved_value]).to eq(400) # (2*100) + (1*200)
        expect(summary[:low_stock_count]).to eq(1) # store_inv2 (5 <= 3 is false, but we need items where quantity <= safety_stock_level)
      end
    end

    describe '.inventory_across_stores' do
      let!(:store2) { create(:store) }
      let!(:store2_inv) { create(:store_inventory, store: store2, inventory: inventory1, quantity: 15, reserved_quantity: 5) }

      it 'returns inventory status across all stores' do
        result = StoreInventory.inventory_across_stores(inventory1)

        expect(result).to have(2).items

        store1_data = result.find { |r| r[:store] == store }
        expect(store1_data[:quantity]).to eq(10)
        expect(store1_data[:available_quantity]).to eq(8)
        expect(store1_data[:reserved_quantity]).to eq(2)

        store2_data = result.find { |r| r[:store] == store2 }
        expect(store2_data[:quantity]).to eq(15)
        expect(store2_data[:available_quantity]).to eq(10)
        expect(store2_data[:reserved_quantity]).to eq(5)
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:store_inventory)).to be_valid
    end

    it 'has working traits' do
      expect(build(:store_inventory, :low_stock)).to be_valid
      expect(build(:store_inventory, :critical_stock)).to be_valid
      expect(build(:store_inventory, :out_of_stock)).to be_valid
      expect(build(:store_inventory, :excess_stock)).to be_valid
    end
  end

  # TODO: Phase 2以降で実装予定のテスト
  #
  # 🔴 Phase 2 優先実装項目:
  # 1. 在庫移動履歴機能テスト
  #    - transfer_logsアソシエーション
  #    - 移動履歴の詳細記録・監査証跡
  #    期待効果: 在庫変動の完全なトレーサビリティ確保
  #
  # 2. 自動補充機能テスト
  #    - アラート通知の自動発信
  #    - 他店舗からの移動提案ロジック
  #    期待効果: 在庫切れリスクの事前回避
  #
  # 🟡 Phase 3 重要実装項目:
  # 3. 在庫予測・分析機能テスト
  #    - 売上データ連携による消費予測精度
  #    - 季節変動・ABC分析統合
  #    期待効果: データドリブンな在庫最適化
  #
  # 🟢 Phase 4 推奨実装項目:
  # 4. リアルタイム在庫同期テスト
  #    - ActionCableによる即座更新
  #    - 同時編集制御・競合回避
  #    期待効果: 複数管理者での安全な在庫管理
end
