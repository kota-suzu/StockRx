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
      # テスト前に既存のInventoryをクリア
      Inventory.destroy_all

      result = Inventory.import_from_csv(file)

      expect(result[:valid_count]).to eq(3)
      expect(result[:invalid_records]).to be_empty

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
        result = Inventory.import_from_csv(invalid_file)

        expect(result[:valid_count]).to eq(0)
        expect(result[:invalid_records].size).to eq(3)
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

  # ShipmentManagement統合テスト
  describe 'ShipmentManagement integration' do
    let(:inventory) { create(:inventory, quantity: 100) }

    describe '#create_shipment' do
      it '有効な出荷を作成できること' do
        result = inventory.create_shipment(20, "東京都", { tracking_number: "TEST123" })

        expect(result).to be true
        expect(inventory.shipments.count).to eq(1)
        expect(inventory.reload.quantity).to eq(80) # 在庫が減少
      end

      it '在庫不足の場合は失敗すること' do
        result = inventory.create_shipment(150, "東京都")

        expect(result).to be false
        expect(inventory.shipments.count).to eq(0)
        expect(inventory.reload.quantity).to eq(100) # 在庫は変わらず
      end
    end

    describe '#create_receipt' do
      it '有効な入荷を作成できること' do
        result = inventory.create_receipt(50, "サプライヤーA", { purchase_order: "PO123" })

        expect(result).to be true
        expect(inventory.receipts.count).to eq(1)
        expect(inventory.reload.quantity).to eq(150) # 在庫が増加
      end
    end

    describe '#cancel_shipment' do
      let!(:shipment) { create(:shipment, inventory: inventory, quantity: 20, shipment_status: :pending) }

      before do
        inventory.update!(quantity: 80) # 出荷済み状態をシミュレート
      end

      it '出荷準備中の出荷をキャンセルできること' do
        result = inventory.cancel_shipment(shipment.id, "顧客都合")

        expect(result).to be true
        expect(shipment.reload.cancelled?).to be true
        expect(inventory.reload.quantity).to eq(100) # 在庫が戻る
      end
    end
  end

  # TODO: ShipmentManagement統合テストの拡張
  # 1. 複雑なシナリオテスト
  #    - 複数出荷・入荷の同時処理テスト
  #    - 在庫移動の連鎖テスト
  #    - バッチ管理との連携テスト
  #
  # 2. エラーハンドリングテスト
  #    - トランザクション失敗時のロールバックテスト
  #    - 外部キー制約違反の処理テスト
  #    - 並行処理での競合状態テスト
  #
  # 3. パフォーマンステスト
  #    - 大量データでの処理性能テスト
  #    - メモリ使用量の最適化テスト
  #    - データベース負荷テスト
end
