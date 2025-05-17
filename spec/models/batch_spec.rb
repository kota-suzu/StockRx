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
end
