# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryDecorator, type: :decorator do
  let(:inventory) { create(:inventory).decorate }

  describe '#alert_badge' do
    context '在庫がない場合' do
      let(:inventory) { create(:inventory, quantity: 0).decorate }

      it '要補充の警告バッジを返すこと' do
        expect(inventory.alert_badge).to include('要補充')
        expect(inventory.alert_badge).to include('bg-amber-200')
      end
    end

    context '在庫がある場合' do
      let(:inventory) { create(:inventory, quantity: 10).decorate }

      it 'OKのバッジを返すこと' do
        expect(inventory.alert_badge).to include('OK')
        expect(inventory.alert_badge).to include('bg-emerald-200')
      end
    end
  end

  describe '#formatted_price' do
    it '金額を通貨形式でフォーマットすること' do
      inventory = create(:inventory, price: 1234).decorate
      expect(inventory.formatted_price).to eq('¥1,234')
    end
  end

  describe '#status_badge' do
    context 'ステータスがactiveの場合' do
      let(:inventory) { create(:inventory, status: 'active').decorate }

      it '有効のバッジを返すこと' do
        expect(inventory.status_badge).to include('有効')
        expect(inventory.status_badge).to include('bg-blue-200')
      end
    end

    context 'ステータスがarchivedの場合' do
      let(:inventory) { create(:inventory, status: 'archived').decorate }

      it 'アーカイブのバッジを返すこと' do
        expect(inventory.status_badge).to include('アーカイブ')
        expect(inventory.status_badge).to include('bg-gray-200')
      end
    end
  end

  describe '#as_json_with_decorated' do
    it '装飾済みの属性を含めたJSONハッシュを返すこと' do
      inventory = create(:inventory, price: 1000, quantity: 5).decorate
      json = inventory.as_json_with_decorated

      expect(json[:id]).to eq(inventory.id)
      expect(json[:name]).to eq(inventory.name)
      expect(json[:quantity]).to eq(5)
      expect(json[:formatted_price]).to eq('¥1,000')
      expect(json[:alert_status]).to eq('ok')
    end
  end
end
