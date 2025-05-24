# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Receipt, type: :model do
  describe 'associations' do
    it { should belong_to(:inventory).required }
  end

  describe 'validations' do
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_presence_of(:source) }
    it { should validate_presence_of(:receipt_date) }
    it { should validate_presence_of(:receipt_status) }
    it { should validate_numericality_of(:cost_per_unit).is_greater_than_or_equal_to(0).allow_nil }
  end

  describe 'enums' do
    it { should define_enum_for(:receipt_status).with_values(expected: 0, partial: 1, completed: 2, rejected: 3, delayed: 4) }
  end

  describe '#total_cost' do
    context 'cost_per_unitが設定されている場合' do
      let(:receipt) { create(:receipt, quantity: 100, cost_per_unit: 10.0) }

      it '総コストを正しく計算すること' do
        expect(receipt.total_cost).to eq(1000.0)
      end
    end

    context 'cost_per_unitがnilの場合' do
      let(:receipt) { create(:receipt, cost_per_unit: nil) }

      it 'nilを返すこと' do
        expect(receipt.total_cost).to be_nil
      end
    end
  end

  describe '#can_reject?' do
    context '入荷予定の場合' do
      let(:receipt) { create(:receipt, receipt_status: :expected) }

      it '拒否可能であること' do
        expect(receipt.can_reject?).to be true
      end
    end

    context '入荷完了の場合' do
      let(:receipt) { create(:receipt, receipt_status: :completed) }

      it '拒否不可能であること' do
        expect(receipt.can_reject?).to be false
      end
    end
  end

  describe '#formatted_receipt_date' do
    let(:receipt) { create(:receipt, receipt_date: Date.parse('2025-05-23')) }

    it '日本語形式で日付をフォーマットすること' do
      expect(receipt.formatted_receipt_date).to eq('2025年05月23日')
    end
  end

  describe 'scopes' do
    describe '.recent' do
      it '作成日時順で取得すること' do
        old_receipt = create(:receipt, created_at: 1.day.ago)
        new_receipt = create(:receipt, created_at: 1.hour.ago)

        expect(Receipt.recent.first).to eq(new_receipt)
      end
    end

    describe '.by_status' do
      it '指定されたステータスの入荷のみ取得すること' do
        completed_receipt = create(:receipt, receipt_status: :completed)
        expected_receipt = create(:receipt, receipt_status: :expected)

        expect(Receipt.by_status(:completed)).to include(completed_receipt)
        expect(Receipt.by_status(:completed)).not_to include(expected_receipt)
      end
    end

    describe '.by_source' do
      it '指定された仕入先の入荷のみ取得すること' do
        supplier_a_receipt = create(:receipt, source: "サプライヤーA")
        supplier_b_receipt = create(:receipt, source: "サプライヤーB")

        expect(Receipt.by_source("サプライヤーA")).to include(supplier_a_receipt)
        expect(Receipt.by_source("サプライヤーA")).not_to include(supplier_b_receipt)
      end
    end
  end

  # TODO: 入荷管理テストの拡張
  # 1. 品質管理テスト
  #    - 品質チェック項目のバリデーションテスト
  #    - 不良品率の計算テスト
  #    - ロット品質履歴の追跡テスト
  #
  # 2. 供給業者評価テスト
  #    - 納期遵守率の計算テスト
  #    - 品質評価の自動算出テスト
  #    - 供給業者ランキングテスト
  #
  # 3. コスト分析テスト
  #    - 単価変動の分析テスト
  #    - 大量購入割引の適用テスト
  #    - 為替レート影響の計算テスト
end
