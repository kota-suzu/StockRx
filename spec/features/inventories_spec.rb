# frozen_string_literal: true

require 'rails_helper'

# TODO: UIテスト環境の設定を見直す
RSpec.feature 'Inventory UI + API', type: :feature, js: true do
  let!(:admin) { create(:admin, email: 'admin@example.com', password: 'Password1234!') }

  # 在庫データの作成
  let!(:active_inventory) { create(:inventory, name: 'アスピリン', quantity: 100, price: 500, status: 'active') }
  let!(:low_inventory) { create(:inventory, name: 'アセトアミノフェン', quantity: 0, price: 300, status: 'active') }
  let!(:archived_inventory) { create(:inventory, name: '過去商品', quantity: 5, price: 1000, status: 'archived') }

  before do
    # バッチデータを作成
    create(:batch, inventory: active_inventory, lot_code: 'LOT001', quantity: 50, expires_on: 1.year.from_now)
    create(:batch, inventory: active_inventory, lot_code: 'LOT002', quantity: 50, expires_on: 2.months.from_now)
    create(:batch, inventory: low_inventory, lot_code: 'LOT003', quantity: 0, expires_on: 1.month.from_now)

    # 管理者としてログイン（Deviseヘルパーを使用）
    sign_in admin
  end

  scenario '在庫一覧ページが表示され、在庫切れ商品が強調表示される' do
    visit inventories_path

    expect(page).to have_content('在庫一覧')
    expect(page).to have_content('アスピリン')
    expect(page).to have_content('アセトアミノフェン')

    # 在庫切れ商品のバッジが表示される
    within('tr', text: 'アセトアミノフェン') do
      expect(page).to have_css('.text-red-600', text: '要補充')
    end

    # 在庫十分な商品は正常と表示
    within('tr', text: 'アスピリン') do
      expect(page).to have_content('OK')
    end
  end

  scenario '在庫詳細ページで商品情報とロットが表示される' do
    visit inventory_path(active_inventory)

    expect(page).to have_content('アスピリン')
    expect(page).to have_content('100')
    expect(page).to have_content('¥500')

    # ロット情報
    expect(page).to have_content('LOT001')
    expect(page).to have_content('LOT002')
    expect(page).to have_content('50') # 数量

    # 期限間近のロットが強調表示
    expect(page).to have_css('.bg-yellow-50')
  end

  scenario '新規在庫を登録できる' do
    visit inventories_path
    click_link '新規登録'

    within('turbo-frame#modal') do
      fill_in '商品名', with: 'ロキソニン'
      fill_in '在庫数', with: '75'
      fill_in '単価', with: '450'
      click_button '登録する'
    end

    # 登録成功後リダイレクト
    expect(page).to have_content('在庫が正常に登録されました')
    expect(page).to have_content('ロキソニン')
  end

  scenario '在庫情報を編集できる' do
    visit inventory_path(active_inventory)
    click_link '編集'

    within('turbo-frame#modal') do
      fill_in '在庫数', with: '120'
      click_button '更新する'
    end

    expect(page).to have_content('在庫が正常に更新されました')
    expect(page).to have_content('120')
  end


end
