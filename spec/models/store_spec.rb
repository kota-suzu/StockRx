# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Store, type: :model do
  describe 'associations' do
    it { should have_many(:store_inventories).dependent(:destroy) }
    it { should have_many(:inventories).through(:store_inventories) }
    it { should have_many(:admins).dependent(:restrict_with_error) }
    it { should have_many(:store_users).dependent(:destroy) }
    it { should have_many(:outgoing_transfers).class_name('InterStoreTransfer').with_foreign_key('source_store_id') }
    it { should have_many(:incoming_transfers).class_name('InterStoreTransfer').with_foreign_key('destination_store_id') }
  end

  describe 'validations' do
    subject { build(:store) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_presence_of(:code) }
    it { should validate_length_of(:code).is_at_most(20) }
    it { should validate_uniqueness_of(:code).case_insensitive }
    it { should validate_presence_of(:store_type) }
    # slugは自動生成されるため、presence validationは不要
    # slugのuniqueness validationは小文字のみ許可するため、独自テストで検証
    describe 'slug uniqueness validation' do
      it 'validates uniqueness of slug' do
        create(:store, slug: 'test-store')
        duplicate = build(:store, slug: 'test-store')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:slug]).to include('has already been taken')
      end
    end
    # enum定義により自動的にvalidationが適用される

    describe 'code format validation' do
      it 'allows alphanumeric characters, hyphens, and underscores' do
        valid_codes = [ 'ST001', 'STORE-01', 'STORE_01', 'ABC123' ]
        valid_codes.each do |code|
          store = build(:store, code: code)
          expect(store).to be_valid
        end
      end

      it 'rejects codes with invalid characters' do
        invalid_codes = [ 'ST 001', 'ST@01', 'ST.01', 'ST#01' ]
        invalid_codes.each do |code|
          store = build(:store, code: code)
          expect(store).not_to be_valid
          expect(store.errors[:code]).to include('は英数字、ハイフン、アンダースコアのみ使用できます')
        end
      end
    end

    describe 'email format validation' do
      it 'allows valid email formats' do
        valid_emails = [ 'test@example.com', 'store.01@domain.co.jp', nil, '' ]
        valid_emails.each do |email|
          store = build(:store, email: email)
          expect(store).to be_valid
        end
      end

      it 'rejects invalid email formats' do
        store = build(:store, email: 'invalid-email')
        expect(store).not_to be_valid
      end
    end

    describe 'slug format validation' do
      it 'allows lowercase alphanumeric characters and hyphens' do
        valid_slugs = [ 'st001', 'store-01', 'abc123', 'pharmacy-tokyo' ]
        valid_slugs.each do |slug|
          store = build(:store, slug: slug)
          expect(store).to be_valid
        end
      end

      it 'rejects slugs with invalid characters' do
        invalid_slugs = [ 'ST001', 'store_01', 'store.01', 'store#01', 'store 01' ]
        invalid_slugs.each do |slug|
          store = build(:store, slug: slug)
          expect(store).not_to be_valid
          expect(store.errors[:slug]).to include('は小文字英数字とハイフンのみ使用できます')
        end
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:store_type).backed_by_column_of_type(:string).with_values(pharmacy: 'pharmacy', warehouse: 'warehouse', headquarters: 'headquarters') }
  end

  describe 'scopes' do
    let!(:active_store) { create(:store, active: true) }
    let!(:inactive_store) { create(:store, active: false) }
    let!(:tokyo_store) { create(:store, :tokyo) }
    let!(:osaka_store) { create(:store, :osaka) }
    let!(:pharmacy_store) { create(:store, :pharmacy) }
    let!(:warehouse_store) { create(:store, :warehouse) }

    describe '.active' do
      it 'returns only active stores' do
        expect(Store.active).to include(active_store)
        expect(Store.active).not_to include(inactive_store)
      end
    end

    describe '.inactive' do
      it 'returns only inactive stores' do
        expect(Store.inactive).to include(inactive_store)
        expect(Store.inactive).not_to include(active_store)
      end
    end

    describe '.by_region' do
      it 'returns stores in specified region' do
        expect(Store.by_region('東京都')).to include(tokyo_store)
        expect(Store.by_region('東京都')).not_to include(osaka_store)
      end

      it 'returns all stores when region is blank' do
        expect(Store.by_region('')).to eq(Store.all)
        expect(Store.by_region(nil)).to eq(Store.all)
      end
    end

    describe '.by_type' do
      it 'returns stores of specified type' do
        expect(Store.by_type('pharmacy')).to include(pharmacy_store)
        expect(Store.by_type('pharmacy')).not_to include(warehouse_store)
      end
    end
  end

  describe 'instance methods' do
    let(:store) { create(:store, code: 'ST001', name: '中央薬局') }

    describe '#display_name' do
      it 'returns code and name combination' do
        expect(store.display_name).to eq('ST001 - 中央薬局')
      end
    end

    describe '#total_inventory_value' do
      context 'when store has inventories' do
        it 'calculates total inventory value correctly' do
          inventory1 = create(:inventory, price: 1000)
          inventory2 = create(:inventory, price: 2000)
          create(:store_inventory, store: store, inventory: inventory1, quantity: 10)
          create(:store_inventory, store: store, inventory: inventory2, quantity: 5)

          expect(store.total_inventory_value).to eq(20000) # (1000*10) + (2000*5)
        end
      end

      context 'when store has no inventories' do
        it 'returns 0' do
          expect(store.total_inventory_value).to eq(0)
        end
      end
    end

    describe '#low_stock_items_count' do
      it 'counts items where quantity is below safety level' do
        inventory1 = create(:inventory)
        inventory2 = create(:inventory)
        inventory3 = create(:inventory)

        create(:store_inventory, store: store, inventory: inventory1, quantity: 5, safety_stock_level: 10) # low stock
        create(:store_inventory, store: store, inventory: inventory2, quantity: 15, safety_stock_level: 10) # normal stock
        create(:store_inventory, store: store, inventory: inventory3, quantity: 3, safety_stock_level: 5) # low stock

        expect(store.low_stock_items_count).to eq(2)
      end
    end

    describe '#out_of_stock_items_count' do
      it 'counts items with zero quantity' do
        inventory1 = create(:inventory)
        inventory2 = create(:inventory)

        create(:store_inventory, store: store, inventory: inventory1, quantity: 0)
        create(:store_inventory, store: store, inventory: inventory2, quantity: 5)

        expect(store.out_of_stock_items_count).to eq(1)
      end
    end

    describe '#available_items_count' do
      it 'counts items with available quantity (not reserved)' do
        inventory1 = create(:inventory)
        inventory2 = create(:inventory)
        inventory3 = create(:inventory)

        create(:store_inventory, store: store, inventory: inventory1, quantity: 10, reserved_quantity: 5) # available
        create(:store_inventory, store: store, inventory: inventory2, quantity: 10, reserved_quantity: 10) # not available
        create(:store_inventory, store: store, inventory: inventory3, quantity: 5, reserved_quantity: 0) # available

        expect(store.available_items_count).to eq(2)
      end
    end
  end

  describe 'class methods' do
    describe '.generate_code' do
      it 'generates unique store codes' do
        code1 = Store.generate_code('ST')
        code2 = Store.generate_code('ST')

        expect(code1).to match(/\AST\w{6}\z/)
        expect(code2).to match(/\AST\w{6}\z/)
        expect(code1).not_to eq(code2)
      end

      it 'avoids collision with existing codes' do
        existing_code = 'ST123456'
        create(:store, code: existing_code)

        allow(SecureRandom).to receive(:alphanumeric).and_return('123456', '789012')

        new_code = Store.generate_code('ST')
        expect(new_code).to eq('ST789012')
      end
    end

    describe '.active_stores_stats' do
      before do
        store1 = create(:store, :with_inventories, active: true)
        store2 = create(:store, :with_inventories, active: true)
        create(:store, :with_inventories, active: false) # inactive store should be excluded
      end

      it 'returns statistics for active stores only' do
        stats = Store.active_stores_stats

        expect(stats[:total_stores]).to eq(2)
        expect(stats[:total_inventory_value]).to be > 0
        expect(stats[:average_inventory_per_store]).to be_present
      end
    end
  end

  describe 'callbacks' do
    describe '#generate_slug' do
      it 'generates slug from code on creation' do
        store = build(:store, code: 'ST-001', slug: nil)
        store.save
        expect(store.slug).to eq('st-001')
      end

      it 'does not override existing slug' do
        store = build(:store, code: 'ST-001', slug: 'custom-slug')
        store.save
        expect(store.slug).to eq('custom-slug')
      end

      it 'handles slug collisions by adding numbers' do
        create(:store, code: 'ST-001', slug: 'st-001')
        store = build(:store, code: 'ST-001', slug: nil)
        store.save
        expect(store.slug).to eq('st-001-1')
      end

      it 'removes special characters from slug' do
        store = build(:store, code: 'ST_001!@#', slug: nil)
        store.save
        expect(store.slug).to eq('st-001')
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:store)).to be_valid
    end

    it 'has working traits' do
      expect(build(:store, :pharmacy)).to be_valid
      expect(build(:store, :warehouse)).to be_valid
      expect(build(:store, :headquarters)).to be_valid
      expect(build(:store, :inactive)).to be_valid
    end
  end
end
