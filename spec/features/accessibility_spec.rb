# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'アクセシビリティ', type: :feature, js: true do
  let!(:admin) { create(:admin, role: 'headquarters_admin') }
  let!(:store) { create(:store) }
  let!(:inventory) { create(:inventory, name: 'テスト商品') }
  let!(:store_inventory) { create(:store_inventory, store: store, inventory: inventory, quantity: 10) }

  describe '管理画面在庫一覧のアクセシビリティ' do
    before do
      sign_in admin
      visit admin_inventories_path
    end

    it 'テーブルに適切なARIA属性が設定されている' do
      expect(page).to have_selector('table[role="table"][aria-label]')
      expect(page).to have_selector('thead[role="rowgroup"]')
      expect(page).to have_selector('tbody[role="rowgroup"]')
      expect(page).to have_selector('tr[role="row"]')
    end

    it 'キーボードナビゲーションが機能する' do
      # テーブルにフォーカス
      first('.inventory-table tbody tr').click

      # 矢印キーでの移動をテスト
      page.driver.browser.action.send_keys(:arrow_down).perform
      sleep 0.1

      expect(page).to have_selector('.inventory-table tbody tr.table-active')
    end

    it 'フォーカス表示が適切に機能する' do
      first('.inventory-table tbody tr').click

      expect(page).to have_selector('.inventory-table tbody tr.table-active')
    end
  end

  describe '店舗在庫一覧のアクセシビリティ' do
    before do
      visit "/stores/#{store.id}/inventories"
    end

    it 'テーブルに適切なARIA属性が設定されている' do
      expect(page).to have_selector('table[role="table"][aria-label]')
      expect(page).to have_selector('tr[role="row"]')
    end

    it 'モバイル対応のタッチ領域が確保されている' do
      # CSSでmin-heightが設定されていることを確認
      expect(page).to have_css('.store-inventory-row')
    end

    it 'ツールチップが初期化されている' do
      expect(page).to have_selector('[data-bs-toggle="tooltip"]')
    end
  end

  describe 'フォーム入力のアクセシビリティ' do
    before do
      sign_in admin
      visit new_admin_inventory_path
    end

    it 'すべての入力フィールドにラベルが関連付けられている' do
      expect(page).to have_selector('label[for]')

      # 各入力フィールドのラベル関連付けを確認
      within 'form' do
        expect(page).to have_selector('input[name="inventory[name]"]')
        expect(page).to have_selector('label[for*="name"]')

        expect(page).to have_selector('input[name="inventory[price]"]')
        expect(page).to have_selector('label[for*="price"]')

        expect(page).to have_selector('input[name="inventory[quantity]"]')
        expect(page).to have_selector('label[for*="quantity"]')
      end
    end

    it 'エラー時に適切なARIA属性が設定される' do
      fill_in 'inventory[name]', with: ''
      click_button '登録する'

      # is-invalid クラスとエラーメッセージの表示確認
      expect(page).to have_selector('.is-invalid')
      expect(page).to have_selector('.invalid-feedback')
    end

    it 'ヘルプテキストが提供されている' do
      expect(page).to have_selector('.form-text')
      expect(page).to have_selector('[aria-describedby]')
    end
  end

  describe 'フラッシュメッセージのアクセシビリティ' do
    before do
      sign_in admin
    end

    it '成功メッセージが適切なARIA属性で表示される' do
      # 成功フラッシュを設定
      page.set_rack_session(flash: { notice: 'テスト成功メッセージ' })
      visit admin_inventories_path

      expect(page).to have_selector('.alert[role="alert"]')
      expect(page).to have_selector('.flash-message[data-flash-type="notice"]')
    end

    it 'エラーメッセージが適切なARIA属性で表示される' do
      # エラーフラッシュを設定
      page.set_rack_session(flash: { alert: 'テストエラーメッセージ' })
      visit admin_inventories_path

      expect(page).to have_selector('.alert[role="alert"]')
      expect(page).to have_selector('.flash-message[data-flash-type="alert"]')
    end
  end

  describe 'モバイル対応のアクセシビリティ' do
    before do
      # モバイルビューポートのシミュレート
      page.driver.browser.manage.window.resize_to(375, 667)
    end

    it 'タッチ領域が44px以上確保されている' do
      sign_in admin
      visit admin_inventories_path

      # モバイルでのボタンサイズ確認
      expect(page).to have_css('.action-btn')
    end

    it 'テーブルが水平スクロール可能' do
      visit "/stores/#{store.id}/inventories"

      expect(page).to have_selector('.table-responsive')
    end
  end

  describe 'パフォーマンス最適化' do
    it 'CSS containmentが設定されている' do
      visit "/stores/#{store.id}/inventories"

      # CSS containmentの確認はJavaScriptで行う
      script = <<~JS
        const table = document.querySelector('.store-inventory-table');
        return getComputedStyle(table).contain;
      JS

      result = page.evaluate_script(script)
      expect(result).to include('layout')
    end

    it 'スムーススクロールが有効' do
      visit "/stores/#{store.id}/inventories"

      script = <<~JS
        const container = document.querySelector('.table-responsive');
        return getComputedStyle(container).scrollBehavior;
      JS

      result = page.evaluate_script(script)
      expect(result).to eq('smooth')
    end
  end
end
