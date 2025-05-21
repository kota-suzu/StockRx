# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Inventory, type: :model do
  # 関連付けのテスト
  describe 'associations' do
    it { should have_many(:batches).dependent(:destroy) }
  end

  # バリデーションのテスト
  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_numericality_of(:price).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
  end

  # enumのテスト
  describe 'enums' do
    it { should define_enum_for(:status).with_values(active: 0, archived: 1) }
  end

  # CSVインポート機能のテスト
  describe '.import_from_csv' do
    let(:csv_content) do
      <<~CSV
        name,quantity,price,status
        商品A,100,1000,active
        商品B,50,1500,active
        商品C,30,2000,archived
      CSV
    end

    let(:file) do
      temp_file = Tempfile.new([ 'inventories', '.csv' ])
      temp_file.write(csv_content)
      temp_file.rewind
      temp_file
    end

    after do
      file.close
      file.unlink
    end

    it 'CSVデータを一括インポートできること' do
      result = Inventory.import_from_csv(file.path)

      expect(result[:imported]).to eq(3)
      expect(result[:invalid]).to be_empty

      expect(Inventory.count).to eq(3)
      expect(Inventory.find_by(name: '商品A')).not_to be_nil
      expect(Inventory.find_by(name: '商品B')).not_to be_nil
      expect(Inventory.find_by(name: '商品C')).not_to be_nil
    end

    context '不正なデータがある場合' do
      let(:invalid_csv_content) do
        <<~CSV
          name,quantity,price,status
          ,100,1000,active
          商品B,-50,1500,active
          商品C,30,-2000,invalid_status
        CSV
      end

      let(:invalid_file) do
        temp_file = Tempfile.new([ 'invalid_inventories', '.csv' ])
        temp_file.write(invalid_csv_content)
        temp_file.rewind
        temp_file
      end

      after do
        invalid_file.close
        invalid_file.unlink
      end

      it '無効なレコードを報告すること' do
        result = Inventory.import_from_csv(invalid_file.path)

        expect(result[:imported]).to eq(0)
        expect(result[:invalid].size).to eq(3)
      end
    end
  end

  # スコープのテスト
  describe 'scopes' do
    describe '.active' do
      it '有効な在庫のみ返すこと' do
        active_inventory = create(:inventory, status: 'active')
        archived_inventory = create(:inventory, status: 'archived')

        expect(Inventory.active).to include(active_inventory)
        expect(Inventory.active).not_to include(archived_inventory)
      end
    end

    describe '.out_of_stock' do
      it '在庫切れの商品のみを返すこと' do
        out_of_stock = create(:inventory, quantity: 0)
        in_stock = create(:inventory, quantity: 10)

        expect(Inventory.out_of_stock).to include(out_of_stock)
        expect(Inventory.out_of_stock).not_to include(in_stock)
      end
    end

    describe '.low_stock' do
      it '在庫が少ない商品のみを返すこと' do
        low_stock = create(:inventory, quantity: 3)
        sufficient_stock = create(:inventory, quantity: 10)
        out_of_stock = create(:inventory, quantity: 0)

        expect(Inventory.low_stock).to include(low_stock)
        expect(Inventory.low_stock).not_to include(sufficient_stock)
        expect(Inventory.low_stock).not_to include(out_of_stock)
      end

      it 'カスタム閾値で在庫が少ない商品を返すこと' do
        low_stock = create(:inventory, quantity: 8)

        expect(Inventory.low_stock(10)).to include(low_stock)
        expect(Inventory.low_stock(5)).not_to include(low_stock)
      end
    end
  end

  # 基本的な機能のテスト
  describe '#total_batch_quantity' do
    it 'バッチの合計数量を正しく計算すること' do
      inventory = create(:inventory, quantity: 0)
      create(:batch, inventory: inventory, quantity: 30)
      create(:batch, inventory: inventory, quantity: 20)

      expect(inventory.total_batch_quantity).to eq(50)
    end
  end

  # 在庫アラート機能のテスト
  describe '#out_of_stock?' do
    it '在庫が0の場合はtrueを返すこと' do
      inventory = create(:inventory, quantity: 0)
      expect(inventory.out_of_stock?).to be true
    end

    it '在庫がある場合はfalseを返すこと' do
      inventory = create(:inventory, quantity: 5)
      expect(inventory.out_of_stock?).to be false
    end
  end

  describe '#low_stock?' do
    it 'デフォルト閾値以下の場合はtrueを返すこと' do
      inventory = create(:inventory, quantity: 3)
      allow(inventory).to receive(:low_stock_threshold).and_return(5)
      expect(inventory.low_stock?).to be true
    end

    it 'デフォルト閾値より多い場合はfalseを返すこと' do
      inventory = create(:inventory, quantity: 10)
      allow(inventory).to receive(:low_stock_threshold).and_return(5)
      expect(inventory.low_stock?).to be false
    end

    it 'カスタム閾値で判定できること' do
      inventory = create(:inventory, quantity: 8)
      expect(inventory.low_stock?(10)).to be true
      expect(inventory.low_stock?(5)).to be false
    end
  end

  describe '#expired_batches' do
    it '期限切れのバッチのみを返すこと' do
      inventory = create(:inventory)
      expired_batch = create(:batch, inventory: inventory, expires_on: 1.day.ago)
      valid_batch = create(:batch, inventory: inventory, expires_on: 1.day.from_now)

      expect(inventory.expired_batches).to include(expired_batch)
      expect(inventory.expired_batches).not_to include(valid_batch)
    end
  end

  describe '#expiring_soon_batches' do
    it '期限切れが近いバッチのみを返すこと' do
      inventory = create(:inventory)
      expiring_soon_batch = create(:batch, inventory: inventory, expires_on: 20.days.from_now)
      not_expiring_soon_batch = create(:batch, inventory: inventory, expires_on: 100.days.from_now)
      already_expired_batch = create(:batch, inventory: inventory, expires_on: 1.day.ago)

      expect(inventory.expiring_soon_batches).to include(expiring_soon_batch)
      expect(inventory.expiring_soon_batches).not_to include(not_expiring_soon_batch)
      expect(inventory.expiring_soon_batches).not_to include(already_expired_batch)
    end

    it 'カスタム日数で期限切れが近いバッチを返すこと' do
      inventory = create(:inventory)
      batch = create(:batch, inventory: inventory, expires_on: 45.days.from_now)

      expect(inventory.expiring_soon_batches(50)).to include(batch)
      expect(inventory.expiring_soon_batches(40)).not_to include(batch)
    end
  end
end
