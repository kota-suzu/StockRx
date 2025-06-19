# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InventoriesHelper, type: :helper do
  describe '#inventory_row_class' do
    let(:inventory) { create(:inventory, quantity: quantity) }

    context '在庫数が0以下の場合' do
      let(:quantity) { 0 }

      it '在庫切れのスタイルクラスを返す' do
        expect(helper.inventory_row_class(inventory)).to eq('table-danger')
      end
    end

    context '在庫数がlow_stock?の場合' do
      let(:quantity) { 5 }

      before do
        allow(inventory).to receive(:low_stock?).and_return(true)
      end

      it '在庫不足のスタイルクラスを返す' do
        expect(helper.inventory_row_class(inventory)).to eq('table-warning')
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
        expect(result).to include('fas')
        expect(result).to include('fa-sort-up')
        expect(result).to include('ms-1')
      end
    end

    context '現在のソート列でdesc方向の場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'name', direction: 'desc' })
      end

      it '下向き矢印アイコンを返す' do
        result = helper.sort_icon_for('name')
        expect(result).to include('fas')
        expect(result).to include('fa-sort-down')
        expect(result).to include('ms-1')
      end
    end

    context '現在のソート列でない場合' do
      before do
        allow(helper).to receive(:params).and_return({ sort: 'price', direction: 'asc' })
      end

      it '空文字を返す' do
        result = helper.sort_icon_for('name')
        expect(result).to eq('')
      end
    end
  end

  describe '#batch_row_class' do
    let(:batch) { build(:batch) }

    context 'ロットが期限切れの場合' do
      before do
        allow(batch).to receive(:expired?).and_return(true)
      end

      it '期限切れのスタイルクラスを返す' do
        expect(helper.batch_row_class(batch)).to eq('table-danger')
      end
    end

    context 'ロットが期限切れ間近の場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it '期限切れ間近のスタイルクラスを返す' do
        expect(helper.batch_row_class(batch)).to eq('table-warning')
      end
    end

    context 'ロットが正常な場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it '空文字を返す' do
        expect(helper.batch_row_class(batch)).to eq('')
      end
    end
  end

  describe '#lot_status_display' do
    let(:batch) { build(:batch) }

    context 'ロットが期限切れの場合' do
      before do
        allow(batch).to receive(:expired?).and_return(true)
      end

      it '「期限切れ」を返す' do
        expect(helper.lot_status_display(batch)).to eq('期限切れ')
      end
    end

    context 'ロットが期限間近の場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it '「期限間近」を返す' do
        expect(helper.lot_status_display(batch)).to eq('期限間近')
      end
    end

    context 'ロットが正常な場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it '「正常」を返す' do
        expect(helper.lot_status_display(batch)).to eq('正常')
      end
    end
  end

  describe '#lot_quantity_percentage' do
    let(:batch) { build(:batch, quantity: 25) }

    context '総在庫数が100の場合' do
      it '正しいパーセンテージを返す' do
        expect(helper.lot_quantity_percentage(batch, 100)).to eq(25.0)
      end
    end

    context '総在庫数が0の場合' do
      it '0を返す' do
        expect(helper.lot_quantity_percentage(batch, 0)).to eq(0)
      end
    end

    context 'ロット数量が総在庫数より大きい場合' do
      it '100%を超えるパーセンテージを返す' do
        expect(helper.lot_quantity_percentage(batch, 20)).to eq(125.0)
      end
    end
  end

  describe '#lot_status_badge_class' do
    let(:batch) { build(:batch) }

    context 'ロットが期限切れの場合' do
      before do
        allow(batch).to receive(:expired?).and_return(true)
      end

      it 'デンジャーバッジクラスを返す' do
        expect(helper.lot_status_badge_class(batch)).to eq('bg-danger')
      end
    end

    context 'ロットが期限間近の場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it 'ワーニングバッジクラスを返す' do
        expect(helper.lot_status_badge_class(batch)).to eq('bg-warning')
      end
    end

    context 'ロットが正常な場合' do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it 'サクセスバッジクラスを返す' do
        expect(helper.lot_status_badge_class(batch)).to eq('bg-success')
      end
    end
  end
end
