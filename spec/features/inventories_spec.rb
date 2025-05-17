# frozen_string_literal: true

require 'rails_helper'

RSpec.feature 'Inventory UI + API', type: :feature do
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

    # 管理者としてログイン
    visit new_admin_session_path
    fill_in 'メールアドレス', with: 'admin@example.com'
    fill_in 'パスワード', with: 'Password1234!'
    click_button 'ログイン'
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

  scenario 'JSONフォーマットで在庫一覧を取得できる' do
    # APIをテスト
    visit inventories_path(format: :json)

    # JSONレスポンスを解析
    json = JSON.parse(page.body)

    # 検証
    expect(json).to be_an(Array)
    expect(json.size).to eq(3) # 3つの在庫アイテム

    # 在庫切れ商品のalert_statusがlowになっていることを確認
    low_stock_item = json.find { |item| item['name'] == 'アセトアミノフェン' }
    expect(low_stock_item['alert_status']).to eq('low')

    # 正常在庫のalert_statusがokになっていることを確認
    normal_stock_item = json.find { |item| item['name'] == 'アスピリン' }
    expect(normal_stock_item['alert_status']).to eq('ok')
  end

  scenario 'API V1エンドポイントからJSON形式で在庫一覧を取得できる' do
    visit api_v1_inventories_path(format: :json)

    # JSONレスポンスを解析
    json = JSON.parse(page.body)

    # 検証
    expect(json).to be_an(Array)
    expect(json.size).to eq(3)

    # バッチ情報も含まれていることを確認
    item_with_batches = json.find { |item| item['name'] == 'アスピリン' }
    expect(item_with_batches['batches']).to be_an(Array)
    expect(item_with_batches['batches'].size).to eq(2)

    # バッチの期限情報が正しいことを確認
    lot001 = item_with_batches['batches'].find { |batch| batch['lot_code'] == 'LOT001' }
    expect(lot001['expired']).to be(false)

    lot002 = item_with_batches['batches'].find { |batch| batch['lot_code'] == 'LOT002' }
    expect(lot002['expired']).to be(false)
  end
end
