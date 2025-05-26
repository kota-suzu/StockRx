# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InventoriesHelper, type: :helper do
  describe '#inventory_row_class' do
    let(:inventory) { create(:inventory, quantity: quantity) }

    context '在庫数が0以下の場合' do
      let(:quantity) { 0 }

      it '在庫切れのスタイルクラスを返す' do
        expect(helper.inventory_row_class(inventory)).to eq('bg-red-50')
      end
    end

    context '在庫数がlow_stock?の場合' do
      let(:quantity) { 5 }

      before do
        allow(inventory).to receive(:low_stock?).and_return(true)
      end

      it '在庫不足のスタイルクラスを返す' do
        expect(helper.inventory_row_class(inventory)).to eq('bg-yellow-50')
      end
    end

    context '正常な在庫数の場合' do
      let(:quantity) { 100 }

      before do
        allow(inventory).to receive(:low_stock?).and_return(false)
      end

      it '空文字を返す' do
        expect(helper.inventory_row_class(inventory)).to eq('')
      end
    end
  end

  describe '#sort_direction_for' do
    context '現在のソートが指定列でascの場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'name', direction: 'asc' })
      end

      it 'descを返す' do
        expect(helper.sort_direction_for('name')).to eq('desc')
      end
    end

    context '現在のソートが指定列でないかdescの場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'price', direction: 'desc' })
      end

      it 'ascを返す' do
        expect(helper.sort_direction_for('name')).to eq('asc')
      end
    end

    context 'paramsが空の場合' do
      before do
        allow(helper).to receive(:params).and_return({})
      end

      it 'ascを返す' do
        expect(helper.sort_direction_for('name')).to eq('asc')
      end
    end
  end

  describe '#sort_icon_for' do
    context '現在のソート列でasc方向の場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'name', direction: 'asc' })
      end

      it '上向き矢印アイコンを返す' do
        result = helper.sort_icon_for('name')
        expect(result).to have_tag('i.fas.fa-sort-up.ml-1.text-blue-600')
      end
    end

    context '現在のソート列でdesc方向の場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'name', direction: 'desc' })
      end

      it '下向き矢印アイコンを返す' do
        result = helper.sort_icon_for('name')
        expect(result).to have_tag('i.fas.fa-sort-down.ml-1.text-blue-600')
      end
    end

    context '現在のソート列でない場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'price', direction: 'asc' })
      end

      it 'ソートアイコンを返す' do
        result = helper.sort_icon_for('name')
        expect(result).to have_tag('i.fas.fa-sort.ml-1.text-gray-400')
      end
    end
  end

  describe '#batch_row_class' do
    let(:batch) { build(:batch) }

    context 'バッチが期限切れの場合' do
      before do
        allow(batch).to receive(:expired?).and_return(true)
      end

      it '期限切れのスタイルクラスを返す' do
        expect(helper.batch_row_class(batch)).to eq('bg-red-50')
      end
    end

    context 'バッチが期限切れ間近の場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it '期限切れ間近のスタイルクラスを返す' do
        expect(helper.batch_row_class(batch)).to eq('bg-yellow-50')
      end
    end

    context 'バッチが正常な場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it '空文字を返す' do
        expect(helper.batch_row_class(batch)).to eq('')
      end
    end
  end
end 