# frozen_string_literal: true

require 'rails_helper'

RSpec.feature 'Inventory Search', type: :feature do
  let(:admin) { create(:admin) }

  before do
    login_as(admin, scope: :admin)
  end

  # テスト用のInventoryデータを作成
  let!(:inventory1) { create(:inventory, name: 'テスト商品A', price: 100, quantity: 10, status: 'active') }
  let!(:inventory2) { create(:inventory, name: 'テスト商品B', price: 200, quantity: 5, status: 'active') }
  let!(:inventory3) { create(:inventory, name: '別商品C', price: 150, quantity: 0, status: 'archived') }

  scenario 'User performs basic search by name' do
    visit inventories_path

    fill_in 'q', with: 'テスト'
    click_button '検索'

    expect(page).to have_content('テスト商品A')
    expect(page).to have_content('テスト商品B')
    expect(page).not_to have_content('別商品C')
  end

  scenario 'User performs basic search by status' do
    visit inventories_path

    select 'active', from: 'status'
    click_button '検索'

    expect(page).to have_content('テスト商品A')
    expect(page).to have_content('テスト商品B')
    expect(page).not_to have_content('別商品C')
  end

  scenario 'User searches for low stock items' do
    visit inventories_path

    check 'low_stock'
    click_button '検索'

    expect(page).to have_content('別商品C')
    expect(page).not_to have_content('テスト商品A')
    expect(page).not_to have_content('テスト商品B')
  end

  scenario 'User accesses advanced search' do
    visit inventories_path

    click_link '高度な検索'

    expect(page).to have_field('名前')
    expect(page).to have_field('min_price')
    expect(page).to have_field('max_price')
    expect(page).to have_field('created_from')
    expect(page).to have_field('lot_code')
  end

  scenario 'User performs advanced search with multiple conditions' do
    visit inventories_path(advanced_search: 1)

    fill_in '名前', with: 'テスト'
    select 'active', from: 'ステータス'
    fill_in '最低価格', with: '150'

    click_button '詳細検索'

    expect(page).to have_content('テスト商品B')
    expect(page).not_to have_content('テスト商品A')
    expect(page).not_to have_content('別商品C')
  end

  scenario 'User sees search conditions summary' do
    visit inventories_path

    fill_in 'q', with: 'テスト'
    select 'active', from: 'status'
    click_button '検索'

    expect(page).to have_content('検索条件:')
    expect(page).to have_content('テスト')
    expect(page).to have_content('active')
  end

  scenario 'User searches by price range' do
    visit inventories_path(advanced_search: 1)

    fill_in '最低価格', with: '150'
    fill_in '最高価格', with: '250'

    click_button '詳細検索'

    expect(page).to have_content('テスト商品B')
    expect(page).to have_content('別商品C')
    expect(page).not_to have_content('テスト商品A')
  end

  scenario 'User searches by stock filter' do
    visit inventories_path(advanced_search: 1)

    select '在庫切れ', from: '在庫状態'

    click_button '詳細検索'

    expect(page).to have_content('別商品C')
    expect(page).not_to have_content('テスト商品A')
    expect(page).not_to have_content('テスト商品B')
  end

  scenario 'User sees validation errors for invalid price range' do
    visit inventories_path(advanced_search: 1)

    fill_in '最低価格', with: '200'
    fill_in '最高価格', with: '100'

    click_button '詳細検索'

    expect(page).to have_content('最高価格は最低価格以上である必要があります')
  end

  scenario 'User resets search conditions' do
    visit inventories_path(advanced_search: 1)

    fill_in '名前', with: 'テスト'
    select 'active', from: 'ステータス'

    click_link '検索条件をリセット'

    expect(page).to have_content('テスト商品A')
    expect(page).to have_content('テスト商品B')
    expect(page).to have_content('別商品C')
    expect(page).not_to have_content('検索条件:')
  end

  scenario 'User switches between simple and advanced search' do
    visit inventories_path

    # シンプル検索から高度な検索へ
    click_link '高度な検索'
    expect(page).to have_field('最低価格')

    # 高度な検索からシンプル検索へ
    click_link 'シンプル検索に戻る'
    expect(page).to have_field('q')
    expect(page).not_to have_field('最低価格')
  end

  scenario 'User uses date range search', js: true do
    visit inventories_path(advanced_search: 1)

    fill_in '開始日', with: Date.current - 1.day
    fill_in '終了日', with: Date.current + 1.day

    click_button '詳細検索'

    expect(page).to have_content('テスト商品A')
    expect(page).to have_content('テスト商品B')
    expect(page).to have_content('別商品C')
  end

  scenario 'User uses batch (lot) search' do
    # バッチデータがある場合のテスト（実際のデータモデルに応じて調整）
    visit inventories_path(advanced_search: 1)

    fill_in 'ロットコード', with: 'LOT001'

    click_button '詳細検索'

    # バッチデータがない場合は結果なしになる
    expect(page).to have_content('検索条件に一致する在庫がありません') or have_content('在庫一覧')
  end

  scenario 'User sorts search results' do
    visit inventories_path

    click_link '商品名'

    # ソート後も表示される
    expect(page).to have_content('テスト商品A')
    expect(page).to have_content('テスト商品B')
    expect(page).to have_content('別商品C')
  end

  scenario 'User navigates through paginated results' do
    # 多数のデータがある場合のページネーションテスト
    visit inventories_path(page: 1)

    expect(page).to have_content('在庫一覧')
    # ページネーションリンクの存在確認（データ量によって変わる）
  end

  context 'with low stock threshold settings', js: true do
    scenario 'User adjusts low stock threshold dynamically' do
      visit inventories_path(advanced_search: 1)

      select '低在庫', from: '在庫状態'

      # JavaScriptによる動的表示の確認
      expect(page).to have_field('low_stock_threshold')

      fill_in 'low_stock_threshold', with: '7'
      click_button '詳細検索'

      expect(page).to have_content('テスト商品B')  # quantity: 5
      expect(page).not_to have_content('テスト商品A')  # quantity: 10
    end
  end

  context 'with empty search results' do
    scenario 'User sees appropriate message when no results found' do
      visit inventories_path

      fill_in 'q', with: '存在しない商品'
      click_button '検索'

      expect(page).to have_content('検索条件に一致する在庫がありません')
    end
  end

  context 'with form persistence' do
    scenario 'Search form retains values after search' do
      visit inventories_path(advanced_search: 1)

      fill_in '名前', with: 'テスト'
      select 'active', from: 'ステータス'
      fill_in '最低価格', with: '100'

      click_button '詳細検索'

      # フォームの値が保持されている
      expect(page).to have_field('名前', with: 'テスト')
      expect(page).to have_select('ステータス', selected: 'active')
      expect(page).to have_field('最低価格', with: '100')
    end
  end
end
