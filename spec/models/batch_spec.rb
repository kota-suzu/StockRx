# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Batch, type: :model do
  # 関連付けのテスト
  describe 'associations' do
    it { should belong_to(:inventory) }
    it { should have_many(:batch_movements).dependent(:destroy) }
    it { should have_many(:store_inventories).through(:batch_movements) }
  end

  # バリデーションのテスト
  describe 'validations' do
    subject { build(:batch) }
    
    it { should validate_presence_of(:lot_code) }
    it { should validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:initial_quantity).is_greater_than(0).allow_nil }

    describe 'uniqueness' do
      subject { create(:batch) }
      it { should validate_uniqueness_of(:lot_code).scoped_to(:inventory_id).case_insensitive }
    end
    
    describe 'custom validations' do
      it 'validates expiration date is in the future for new records' do
        batch = build(:batch, expires_on: 1.day.ago)
        expect(batch).not_to be_valid
        expect(batch.errors[:expires_on]).to include('must be in the future')
      end
      
      it 'allows past expiration date for existing records' do
        batch = create(:batch, expires_on: 30.days.from_now)
        batch.update(expires_on: 1.day.ago)
        expect(batch).to be_valid
      end
      
      it 'validates quantity cannot exceed initial_quantity' do
        batch = build(:batch, initial_quantity: 100, quantity: 150)
        expect(batch).not_to be_valid
        expect(batch.errors[:quantity]).to include('cannot exceed initial quantity')
      end
    end
  end
  
  # コールバックのテスト
  describe 'callbacks' do
    describe 'before_validation' do
      it 'normalizes lot_code by removing whitespace and uppercasing' do
        batch = build(:batch, lot_code: ' abc-123 ')
        batch.valid?
        expect(batch.lot_code).to eq('ABC-123')
      end
    end
    
    describe 'before_create' do
      it 'sets initial_quantity to quantity if not provided' do
        batch = create(:batch, quantity: 100, initial_quantity: nil)
        expect(batch.initial_quantity).to eq(100)
      end
      
      it 'preserves initial_quantity if provided' do
        batch = create(:batch, quantity: 50, initial_quantity: 100)
        expect(batch.initial_quantity).to eq(100)
      end
    end
    
    describe 'after_update' do
      it 'creates inventory log when quantity changes' do
        batch = create(:batch, quantity: 100)
        expect {
          batch.update!(quantity: 80)
        }.to change(InventoryLog, :count).by(1)
        
        log = InventoryLog.last
        expect(log.operation_type).to eq('batch_adjustment')
        expect(log.delta).to eq(-20)
      end
    end
  end

  # スコープのテスト
  describe 'scopes' do
    let!(:expired_batch) { create(:batch, expires_on: 1.day.ago, quantity: 10) }
    let!(:expiring_soon_batch) { create(:batch, expires_on: 20.days.from_now, quantity: 20) }
    let!(:future_batch) { create(:batch, expires_on: 100.days.from_now, quantity: 30) }
    let!(:no_expiry_batch) { create(:batch, expires_on: nil, quantity: 40) }
    let!(:out_of_stock_batch) { create(:batch, quantity: 0) }
    
    describe '.expired' do
      it 'returns only expired batches' do
        expect(Batch.expired).to include(expired_batch)
        expect(Batch.expired).not_to include(expiring_soon_batch, future_batch, no_expiry_batch)
      end
    end
    
    describe '.not_expired' do
      it 'returns non-expired batches including nil expiry' do
        expect(Batch.not_expired).to include(expiring_soon_batch, future_batch, no_expiry_batch)
        expect(Batch.not_expired).not_to include(expired_batch)
      end
    end
    
    describe '.expiring_soon' do
      it 'returns batches expiring within default 30 days' do
        expect(Batch.expiring_soon).to include(expiring_soon_batch)
        expect(Batch.expiring_soon).not_to include(expired_batch, future_batch, no_expiry_batch)
      end
      
      it 'accepts custom days parameter' do
        expect(Batch.expiring_soon(150)).to include(expiring_soon_batch, future_batch)
        expect(Batch.expiring_soon(10)).not_to include(expiring_soon_batch)
      end
    end
    
    describe '.with_stock' do
      it 'returns batches with positive quantity' do
        expect(Batch.with_stock).to include(expired_batch, expiring_soon_batch, future_batch, no_expiry_batch)
        expect(Batch.with_stock).not_to include(out_of_stock_batch)
      end
    end
    
    describe '.out_of_stock' do
      it 'returns batches with zero quantity' do
        expect(Batch.out_of_stock).to include(out_of_stock_batch)
        expect(Batch.out_of_stock).not_to include(expired_batch, expiring_soon_batch)
      end
    end
    
    describe '.by_expiry' do
      it 'orders by expiration date with nulls last' do
        ordered = Batch.by_expiry
        expect(ordered.first).to eq(expired_batch)
        expect(ordered.last).to eq(no_expiry_batch)
      end
    end
    
    describe '.by_lot_code' do
      it 'orders alphabetically by lot code' do
        batch_a = create(:batch, lot_code: 'AAA')
        batch_z = create(:batch, lot_code: 'ZZZ')
        
        ordered = Batch.by_lot_code
        expect(ordered.index(batch_a)).to be < ordered.index(batch_z)
      end
    end
  end

  # 期限切れ関連メソッドのテスト
  describe '#expired?' do
    context '期限切れの場合' do
      let(:batch) { create(:batch, expires_on: 1.day.ago) }

      it '期限切れと判定されること' do
        expect(batch.expired?).to be true
      end
    end

    context '期限内の場合' do
      let(:batch) { create(:batch, expires_on: 1.day.from_now) }

      it '期限切れでないと判定されること' do
        expect(batch.expired?).to be false
      end
    end

    context '期限日が設定されていない場合' do
      let(:batch) { create(:batch, expires_on: nil) }

      it '期限切れでないと判定されること' do
        expect(batch.expired?).to be false
      end
    end
    
    context '当日が期限日の場合' do
      let(:batch) { create(:batch, expires_on: Date.current) }
      
      it '期限切れでないと判定されること' do
        expect(batch.expired?).to be false
      end
    end
  end

  describe '#expiring_soon?' do
    context '期限切れが近い場合（デフォルト30日以内）' do
      let(:batch) { create(:batch, expires_on: 20.days.from_now) }

      it '期限切れが近いと判定されること' do
        expect(batch.expiring_soon?).to be true
      end
    end

    context 'カスタム日数で期限切れが近い場合' do
      let(:batch) { create(:batch, expires_on: 45.days.from_now) }

      it 'カスタム日数で期限切れが近いと判定されること' do
        expect(batch.expiring_soon?(50)).to be true
        expect(batch.expiring_soon?(40)).to be false
      end
    end

    context '期限切れが近くない場合' do
      let(:batch) { create(:batch, expires_on: 100.days.from_now) }

      it '期限切れが近いと判定されないこと' do
        expect(batch.expiring_soon?).to be false
      end
    end

    context '既に期限切れの場合' do
      let(:batch) { create(:batch, expires_on: 1.day.ago) }

      it '期限切れが近いと判定されないこと' do
        expect(batch.expiring_soon?).to be false
      end
    end

    context '期限日が設定されていない場合' do
      let(:batch) { create(:batch, expires_on: nil) }

      it '期限切れが近いと判定されないこと' do
        expect(batch.expiring_soon?).to be false
      end
    end
  end
  
  # 期限関連の追加メソッド
  describe '#days_until_expiry' do
    it 'returns days until expiration' do
      batch = create(:batch, expires_on: 10.days.from_now)
      expect(batch.days_until_expiry).to eq(10)
    end
    
    it 'returns negative days for expired batches' do
      batch = create(:batch, expires_on: 5.days.ago)
      expect(batch.days_until_expiry).to eq(-5)
    end
    
    it 'returns nil for batches without expiry' do
      batch = create(:batch, expires_on: nil)
      expect(batch.days_until_expiry).to be_nil
    end
  end
  
  describe '#expiry_status' do
    it 'returns expired for past dates' do
      batch = create(:batch, expires_on: 1.day.ago)
      expect(batch.expiry_status).to eq(:expired)
    end
    
    it 'returns expiring_soon for dates within 30 days' do
      batch = create(:batch, expires_on: 15.days.from_now)
      expect(batch.expiry_status).to eq(:expiring_soon)
    end
    
    it 'returns valid for dates beyond 30 days' do
      batch = create(:batch, expires_on: 60.days.from_now)
      expect(batch.expiry_status).to eq(:valid)
    end
    
    it 'returns no_expiry for nil dates' do
      batch = create(:batch, expires_on: nil)
      expect(batch.expiry_status).to eq(:no_expiry)
    end
  end

  # 在庫切れアラート関連メソッドのテスト
  describe '#out_of_stock?' do
    context '在庫切れの場合' do
      let(:batch) { create(:batch, quantity: 0) }

      it '在庫切れと判定されること' do
        expect(batch.out_of_stock?).to be true
      end
    end

    context '在庫がある場合' do
      let(:batch) { create(:batch, quantity: 10) }

      it '在庫切れでないと判定されること' do
        expect(batch.out_of_stock?).to be false
      end
    end
  end

  describe '#low_stock?' do
    context '在庫が少ない場合（デフォルト閾値以下）' do
      let(:batch) { create(:batch, quantity: 3) }

      it '在庫が少ないと判定されること' do
        allow(batch).to receive(:low_stock_threshold).and_return(5)
        expect(batch.low_stock?).to be true
      end
    end

    context '在庫が十分ある場合' do
      let(:batch) { create(:batch, quantity: 20) }

      it '在庫が少ないと判定されないこと' do
        allow(batch).to receive(:low_stock_threshold).and_return(5)
        expect(batch.low_stock?).to be false
      end
    end

    context 'カスタム閾値で在庫が少ない場合' do
      let(:batch) { create(:batch, quantity: 8) }

      it 'カスタム閾値で在庫が少ないと判定されること' do
        expect(batch.low_stock?(10)).to be true
        expect(batch.low_stock?(5)).to be false
      end
    end
  end
  
  # 在庫操作メソッド
  describe 'inventory operations' do
    let(:batch) { create(:batch, quantity: 100, initial_quantity: 100) }
    
    describe '#consume' do
      it 'reduces quantity successfully' do
        result = batch.consume(30)
        expect(result).to be true
        expect(batch.reload.quantity).to eq(70)
      end
      
      it 'fails when consuming more than available' do
        result = batch.consume(150)
        expect(result).to be false
        expect(batch.errors[:base]).to include(/Insufficient quantity/)
      end
      
      it 'creates inventory log' do
        expect {
          batch.consume(20)
        }.to change(InventoryLog, :count).by(1)
      end
    end
    
    describe '#replenish' do
      it 'increases quantity up to initial quantity' do
        batch.update!(quantity: 50)
        result = batch.replenish(30)
        
        expect(result).to be true
        expect(batch.reload.quantity).to eq(80)
      end
      
      it 'prevents exceeding initial quantity' do
        batch.update!(quantity: 90)
        result = batch.replenish(20)
        
        expect(result).to be false
        expect(batch.errors[:base]).to include(/Cannot exceed initial quantity/)
      end
    end
    
    describe '#usage_percentage' do
      it 'calculates percentage of initial quantity used' do
        batch.update!(quantity: 75)
        expect(batch.usage_percentage).to eq(25.0) # 25% used
      end
      
      it 'handles zero initial quantity' do
        batch.update!(initial_quantity: 0)
        expect(batch.usage_percentage).to eq(0)
      end
    end
  end
  
  # バッチ移動と追跡
  describe 'batch movements' do
    let(:batch) { create(:batch, quantity: 100) }
    let(:store) { create(:store) }
    
    describe '#move_to_store' do
      it 'creates batch movement record' do
        expect {
          batch.move_to_store(store, 30)
        }.to change(BatchMovement, :count).by(1)
        
        movement = BatchMovement.last
        expect(movement.batch).to eq(batch)
        expect(movement.store).to eq(store)
        expect(movement.quantity).to eq(30)
      end
      
      it 'updates batch quantity' do
        batch.move_to_store(store, 40)
        expect(batch.reload.quantity).to eq(60)
      end
      
      it 'fails for insufficient quantity' do
        result = batch.move_to_store(store, 150)
        expect(result).to be false
      end
    end
    
    describe '#current_locations' do
      it 'returns stores where batch is distributed' do
        store1 = create(:store)
        store2 = create(:store)
        
        batch.move_to_store(store1, 30)
        batch.move_to_store(store2, 20)
        
        locations = batch.current_locations
        expect(locations.keys).to include(store1, store2)
        expect(locations[store1]).to eq(30)
        expect(locations[store2]).to eq(20)
      end
    end
  end

  # Timecopを活用した包括的なスコープテスト
  describe '期限関連スコープ（Timecop使用）' do
    let(:inventory) { create(:inventory) }

    # テスト用のベース日時を設定（2025年8月15日 14:00 JST）
    let(:base_time) { Time.zone.parse('2025-08-15 14:00:00') }

    # テスト専用のバッチ作成とクリーンアップ
    before do
      # 既存のBatchをクリーンアップ
      Batch.delete_all

      # 各期間のバッチを作成
      create_batches_for_different_periods
    end

    after do
      # テスト後のクリーンアップ
      Batch.delete_all
    end

    describe 'expired スコープ' do
      it '期限切れのバッチのみを返すこと' do
        Timecop.freeze(base_time) do
          expired_batches = Batch.where(inventory: inventory).expired

          # 期限切れバッチが含まれていること
          expired_batch = expired_batches.find_by(lot_code: 'EXPIRED-LOT')
          expect(expired_batch).to be_present

          # すべてのバッチが期限切れであること
          expired_batches.each do |batch|
            expect(batch.expires_on).to be < Date.current
          end

          # 期限切れでないバッチが含まれていないこと
          not_expired_batch = expired_batches.find_by(lot_code: 'FUTURE-LOT')
          expect(not_expired_batch).to be_nil
        end
      end

      it '日付境界での期限切れ判定が正確であること' do
        # 今日が期限日のバッチを作成
        today_expiry_batch = nil
        yesterday_expiry_batch = nil

        Timecop.freeze(base_time) do
          today_expiry_batch = create(:batch,
            inventory: inventory,
            lot_code: 'TODAY-EXPIRY',
            expires_on: Date.current
          )

          yesterday_expiry_batch = create(:batch,
            inventory: inventory,
            lot_code: 'YESTERDAY-EXPIRY',
            expires_on: Date.current - 1.day
          )
        end

        Timecop.freeze(base_time) do
          expired_batches = Batch.where(inventory: inventory).expired

          # 昨日期限切れは含まれる
          expect(expired_batches).to include(yesterday_expiry_batch)

          # 今日期限は含まれない（当日は期限内とみなす）
          expect(expired_batches).not_to include(today_expiry_batch)
        end
      end
    end

    describe 'not_expired スコープ' do
      it '期限切れでないバッチのみを返すこと' do
        Timecop.freeze(base_time) do
          not_expired_batches = Batch.where(inventory: inventory).not_expired

          # 期限内バッチが含まれていること
          future_batch = not_expired_batches.find_by(lot_code: 'FUTURE-LOT')
          expiring_soon_batch = not_expired_batches.find_by(lot_code: 'SOON-LOT')

          expect(future_batch).to be_present
          expect(expiring_soon_batch).to be_present

          # すべてのバッチが期限内であること
          not_expired_batches.each do |batch|
            expect(batch.expires_on.nil? || batch.expires_on >= Date.current).to be true
          end

          # 期限切れバッチが含まれていないこと
          expired_batch = not_expired_batches.find_by(lot_code: 'EXPIRED-LOT')
          expect(expired_batch).to be_nil
        end
      end

      it '期限日がnilのバッチも期限切れでないとして扱うこと' do
        Timecop.freeze(base_time) do
          nil_expiry_batch = create(:batch,
            inventory: inventory,
            lot_code: 'NO-EXPIRY',
            expires_on: nil
          )

          not_expired_batches = Batch.where(inventory: inventory).not_expired
          expect(not_expired_batches).to include(nil_expiry_batch)
        end
      end
    end

    private

    def create_batches_for_different_periods
      Timecop.freeze(base_time) do
        # 期限切れバッチ（30日前に期限切れ）
        create(:batch,
          inventory: inventory,
          lot_code: 'EXPIRED-LOT',
          expires_on: Date.current - 30.days,
          quantity: 25
        )

        # 期限間近バッチ（15日後に期限切れ）
        create(:batch,
          inventory: inventory,
          lot_code: 'SOON-LOT',
          expires_on: Date.current + 15.days,
          quantity: 50
        )

        # 遠い未来のバッチ（180日後に期限切れ）
        create(:batch,
          inventory: inventory,
          lot_code: 'FUTURE-LOT',
          expires_on: Date.current + 180.days,
          quantity: 100
        )
      end
    end
  end
  
  # ビジネスロジックテスト
  describe 'business logic' do
    describe '#calculate_value' do
      it 'calculates batch value based on quantity and inventory price' do
        inventory = create(:inventory, price: 10.50)
        batch = create(:batch, inventory: inventory, quantity: 100)
        
        expect(batch.calculate_value).to eq(1050.00)
      end
    end
    
    describe '#fifo_priority' do
      it 'returns priority based on expiration and creation date' do
        old_batch = create(:batch, expires_on: 30.days.from_now, created_at: 2.days.ago)
        new_batch = create(:batch, expires_on: 30.days.from_now, created_at: 1.day.ago)
        expiring_batch = create(:batch, expires_on: 10.days.from_now, created_at: Time.current)
        
        expect(expiring_batch.fifo_priority).to be > new_batch.fifo_priority
        expect(old_batch.fifo_priority).to be > new_batch.fifo_priority
      end
    end
  end
  
  # パフォーマンステスト
  describe 'performance' do
    it 'handles bulk operations efficiently' do
      batches = create_list(:batch, 100)
      
      start_time = Time.current
      Batch.where(id: batches.map(&:id)).update_all(quantity: 50)
      elapsed_time = (Time.current - start_time) * 1000
      
      expect(elapsed_time).to be < 500
    end
    
    it 'avoids N+1 queries when accessing inventory' do
      batches = create_list(:batch, 5)
      
      expect {
        Batch.includes(:inventory).each do |batch|
          batch.inventory.name
          batch.calculate_value
        end
      }.not_to exceed_query_limit(2)
    end
  end
  
  # セキュリティテスト
  describe 'security' do
    it 'sanitizes lot_code input' do
      batch = build(:batch, lot_code: '<script>alert("XSS")</script>LOT123')
      batch.save!
      
      expect(batch.lot_code).not_to include('<script>')
      expect(batch.lot_code).to include('LOT123')
    end
    
    it 'prevents negative quantity through mass assignment' do
      batch = create(:batch, quantity: 100)
      batch.update(quantity: -10)
      
      expect(batch).not_to be_valid
    end
  end
  
  # 統合シナリオテスト
  describe 'integration scenarios' do
    it 'handles complete batch lifecycle' do
      # 1. Create new batch
      inventory = create(:inventory)
      batch = create(:batch, 
        inventory: inventory,
        lot_code: 'BATCH-2024-001',
        quantity: 1000,
        expires_on: 180.days.from_now
      )
      
      # 2. Distribute to stores
      store1 = create(:store)
      store2 = create(:store)
      
      expect(batch.move_to_store(store1, 400)).to be true
      expect(batch.move_to_store(store2, 300)).to be true
      expect(batch.reload.quantity).to eq(300)
      
      # 3. Consume from batch
      expect(batch.consume(100)).to be true
      expect(batch.quantity).to eq(200)
      
      # 4. Check expiry status over time
      travel_to 150.days.from_now do
        expect(batch.expiring_soon?).to be true
        expect(batch.days_until_expiry).to eq(30)
      end
      
      # 5. Handle expiration
      travel_to 181.days.from_now do
        expect(batch.expired?).to be true
        expect(batch.expiry_status).to eq(:expired)
      end
    end
  end
  
  # Auditable concern integration
  describe 'auditable behavior' do
    it_behaves_like 'auditable'
  end
  
  # エッジケース
  describe 'edge cases' do
    it 'handles concurrent quantity updates safely' do
      batch = create(:batch, quantity: 100)
      
      threads = 5.times.map do
        Thread.new do
          batch.with_lock do
            current_qty = batch.reload.quantity
            batch.update!(quantity: current_qty - 10)
          end
        end
      end
      
      threads.each(&:join)
      expect(batch.reload.quantity).to eq(50)
    end
    
    it 'handles very large quantities' do
      batch = create(:batch, quantity: 999_999_999, initial_quantity: 999_999_999)
      expect(batch).to be_valid
      expect(batch.usage_percentage).to eq(0)
    end
    
    it 'handles precision in date calculations' do
      batch = create(:batch, expires_on: 0.5.days.from_now)
      expect(batch.days_until_expiry).to eq(0)
    end
  end
end