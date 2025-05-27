# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Batch, type: :model do
  # 関連付けのテスト
  describe 'associations' do
    it { should belong_to(:inventory) }
  end

  # バリデーションのテスト
  describe 'validations' do
    it { should validate_presence_of(:lot_code) }
    it { should validate_numericality_of(:quantity).is_greater_than_or_equal_to(0) }

    describe 'uniqueness' do
      subject { create(:batch) }
      it { should validate_uniqueness_of(:lot_code).scoped_to(:inventory_id).case_insensitive }
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

  # ============================================
  # Timecopを活用した包括的なスコープテスト
  # ============================================
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

    describe 'expiring_soon スコープ' do
      it 'デフォルト30日以内に期限切れのバッチを返すこと' do
        Timecop.freeze(base_time) do
          expiring_soon_batches = Batch.where(inventory: inventory).expiring_soon

          # 期限間近バッチが含まれていること
          soon_batch = expiring_soon_batches.find_by(lot_code: 'SOON-LOT')
          expect(soon_batch).to be_present

          # すべてのバッチが30日以内に期限切れであること
          expiring_soon_batches.each do |batch|
            expect(batch.expires_on).to be_between(Date.current, Date.current + 30.days)
          end

          # 既に期限切れや遠い未来のバッチが含まれていないこと
          expired_batch = expiring_soon_batches.find_by(lot_code: 'EXPIRED-LOT')
          future_batch = expiring_soon_batches.find_by(lot_code: 'FUTURE-LOT')

          expect(expired_batch).to be_nil
          expect(future_batch).to be_nil
        end
      end

      it 'カスタム日数での期限間近判定が正しく動作すること' do
        Timecop.freeze(base_time) do
          # 60日間近のバッチを作成
          custom_soon_batch = create(:batch,
            inventory: inventory,
            lot_code: 'CUSTOM-SOON',
            expires_on: Date.current + 45.days
          )

          # 60日でのスコープ
          expiring_soon_60_batches = Batch.where(inventory: inventory).expiring_soon(60)
          expect(expiring_soon_60_batches).to include(custom_soon_batch)

          # 30日でのスコープ（含まれない）
          expiring_soon_30_batches = Batch.where(inventory: inventory).expiring_soon(30)
          expect(expiring_soon_30_batches).not_to include(custom_soon_batch)
        end
      end

      it '時間境界での期限間近判定が正確であること' do
        boundary_time = Time.zone.parse('2025-08-31 23:59:59')

        # 30日後の境界にあるバッチを作成
        boundary_batch = nil
        just_over_batch = nil

        Timecop.freeze(base_time) do
          boundary_batch = create(:batch,
            inventory: inventory,
            lot_code: 'BOUNDARY-LOT',
            expires_on: Date.current + 30.days  # ちょうど30日後
          )

          just_over_batch = create(:batch,
            inventory: inventory,
            lot_code: 'JUST-OVER-LOT',
            expires_on: Date.current + 31.days  # 31日後
          )
        end

        Timecop.freeze(base_time) do
          expiring_soon_batches = Batch.where(inventory: inventory).expiring_soon(30)

          # 30日後は含まれる
          expect(expiring_soon_batches).to include(boundary_batch)

          # 31日後は含まれない
          expect(expiring_soon_batches).not_to include(just_over_batch)
        end
      end
    end

    describe 'クラスメソッドとスコープの組み合わせテスト' do
      it '複数のスコープを組み合わせて正しい結果が得られること' do
        Timecop.freeze(base_time) do
          # 期限切れでなく、在庫がある（quantity > 0）バッチ
          valid_batches = Batch.where(inventory: inventory)
                             .not_expired
                             .where('quantity > 0')

          # 期限切れバッチは含まれない
          expired_batch = valid_batches.find_by(lot_code: 'EXPIRED-LOT')
          expect(expired_batch).to be_nil

          # 期限内で在庫があるバッチは含まれる
          future_batch = valid_batches.find_by(lot_code: 'FUTURE-LOT')
          expect(future_batch).to be_present
        end
      end

      it '期限切れ間近で在庫切れのバッチを正しく識別できること' do
        Timecop.freeze(base_time) do
          # 期限間近で在庫切れのバッチを作成
          soon_out_of_stock = create(:batch,
            inventory: inventory,
            lot_code: 'SOON-OUT',
            expires_on: Date.current + 15.days,
            quantity: 0
          )

          # 期限間近のバッチ（在庫ありなし問わず）
          expiring_soon_all = Batch.where(inventory: inventory).expiring_soon
          expect(expiring_soon_all).to include(soon_out_of_stock)

          # 在庫切れバッチ
          out_of_stock_all = Batch.where(inventory: inventory).out_of_stock
          expect(out_of_stock_all).to include(soon_out_of_stock)
        end
      end
    end

    describe '時間帯をまたいだテスト' do
      it '日付変更時刻前後での期限判定が一貫していること' do
        # 日付変更前後の時刻でテスト
        late_night = Time.zone.parse('2025-08-15 23:59:59')
        early_morning = Time.zone.parse('2025-08-16 00:00:01')

        # 2025-08-15に期限切れするバッチ
        expiring_today_batch = nil

        Timecop.freeze(late_night) do
          expiring_today_batch = create(:batch,
            inventory: inventory,
            lot_code: 'EXPIRING-TODAY',
            expires_on: Date.current  # 2025-08-15
          )

          # 23:59:59時点では期限内
          not_expired_batches = Batch.where(inventory: inventory).not_expired
          expect(not_expired_batches).to include(expiring_today_batch)
        end

        Timecop.freeze(early_morning) do
          # 00:00:01時点では期限切れ
          expired_batches = Batch.where(inventory: inventory).expired
          expect(expired_batches).to include(expiring_today_batch)
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
end
