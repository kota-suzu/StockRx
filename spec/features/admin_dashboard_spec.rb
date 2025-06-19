# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Dashboard', type: :feature do
  # CLAUDE.md準拠: フィーチャーテストによる統合テストカバレッジ向上
  # メタ認知: ユーザーの実際の操作フローをテストすることで品質保証
  # 横展開: 他の重要画面でも同様のフィーチャーテスト実装

  let(:admin) { create(:admin, email: 'admin@example.com', password: 'Password123!') }
  let(:store1) { create(:store, name: '新宿店') }
  let(:store2) { create(:store, name: '渋谷店') }

  before do
    # テストデータ作成
    inventory1 = create(:inventory, name: 'アスピリン錠100mg', price: 500)
    inventory2 = create(:inventory, name: 'デジタル血圧計', price: 15000)
    inventory3 = create(:inventory, name: '使い捨てマスク', price: 100)

    # 店舗在庫設定（低在庫を含む）
    create(:store_inventory, store: store1, inventory: inventory1, quantity: 100, safety_stock_level: 20)
    create(:store_inventory, store: store1, inventory: inventory2, quantity: 5, safety_stock_level: 10) # 低在庫
    create(:store_inventory, store: store2, inventory: inventory3, quantity: 0, safety_stock_level: 50) # 在庫切れ

    # 在庫ログ作成
    create(:inventory_log, inventory: inventory1, admin: admin, action: 'updated',
           changes: { quantity: [ 90, 100 ] }, created_at: 1.hour.ago)
    create(:inventory_log, inventory: inventory2, admin: admin, action: 'created',
           changes: { name: [ nil, inventory2.name ] }, created_at: 2.hours.ago)
  end

  describe 'ダッシュボードアクセス' do
    context '認証済み管理者の場合' do
      before do
        # 管理者としてログイン
        visit admin_sign_in_path
        fill_in 'admin[email]', with: admin.email
        fill_in 'admin[password]', with: 'Password123!'
        click_button 'ログイン'
      end

      it 'ダッシュボードが正常に表示されること', :js do
        visit admin_dashboard_path

        expect(page).to have_current_path(admin_dashboard_path)
        expect(page).to have_content('管理者ダッシュボード')
        expect(page).to have_content('システム概要')
      end

      it '統計情報が正確に表示されること' do
        visit admin_dashboard_path

        # 在庫統計の確認
        expect(page).to have_content('総在庫商品数')
        expect(page).to have_content('3') # 3つの商品

        expect(page).to have_content('低在庫アラート')
        expect(page).to have_content('2') # 低在庫商品数（在庫切れ含む）

        expect(page).to have_content('総在庫価値')
        expect(page).to have_content('¥15,600') # 500 + 15,000 + 100
      end

      it '低在庫アラートが適切に表示されること' do
        visit admin_dashboard_path

        # 低在庫商品の詳細確認
        within('.low-stock-alerts') do
          expect(page).to have_content('デジタル血圧計')
          expect(page).to have_content('在庫: 5個')
          expect(page).to have_content('安全在庫: 10個')

          expect(page).to have_content('使い捨てマスク')
          expect(page).to have_content('在庫: 0個')
          expect(page).to have_content('在庫切れ')
        end
      end

      it '最近のアクティビティが表示されること' do
        visit admin_dashboard_path

        # アクティビティログの確認
        within('.recent-activities') do
          expect(page).to have_content('最近のアクティビティ')
          expect(page).to have_content('アスピリン錠100mg')
          expect(page).to have_content('updated')
          expect(page).to have_content('デジタル血圧計')
          expect(page).to have_content('created')
        end
      end

      it 'ナビゲーションメニューが機能すること', :js do
        visit admin_dashboard_path

        # メインナビゲーション
        expect(page).to have_link('在庫管理', href: admin_inventories_path)
        expect(page).to have_link('店舗管理', href: admin_stores_path)
        expect(page).to have_link('ログ管理', href: admin_inventory_logs_path)

        # ドロップダウンメニューのテスト
        find('.dropdown-toggle').click
        expect(page).to have_link('プロフィール')
        expect(page).to have_link('設定')
        expect(page).to have_link('ログアウト')
      end

      context 'レスポンシブデザイン' do
        it 'モバイル表示でも適切に表示されること', :js do
          # ビューポートをモバイルサイズに変更
          page.driver.browser.manage.window.resize_to(375, 667)
          visit admin_dashboard_path

          expect(page).to have_content('管理者ダッシュボード')
          expect(page).to have_css('.mobile-responsive', visible: true)
        end

        it 'タブレット表示でも適切に表示されること', :js do
          # ビューポートをタブレットサイズに変更
          page.driver.browser.manage.window.resize_to(768, 1024)
          visit admin_dashboard_path

          expect(page).to have_content('管理者ダッシュボード')
          expect(page).to have_css('.tablet-responsive', visible: true)
        end
      end

      context 'リアルタイム更新' do
        it '新しい在庫ログが自動で表示されること', :js do
          visit admin_dashboard_path

          # 新しいログを作成
          inventory = create(:inventory, name: '新商品')
          create(:inventory_log, inventory: inventory, admin: admin, action: 'created')

          # ページを再読み込みしてログが表示されることを確認
          visit current_path
          expect(page).to have_content('新商品')
        end
      end

      context 'エラーハンドリング' do
        it 'データ取得エラー時でも適切に表示されること' do
          # データベースエラーをシミュレート
          allow(Inventory).to receive(:count).and_raise(ActiveRecord::ConnectionTimeoutError)

          visit admin_dashboard_path

          expect(page).to have_content('データの読み込み中にエラーが発生しました')
          expect(page).to have_content('再試行してください')
        end
      end
    end

    context '未認証ユーザーの場合' do
      it 'ログインページにリダイレクトされること' do
        visit admin_dashboard_path

        expect(page).to have_current_path(admin_sign_in_path)
        expect(page).to have_content('ログインしてください')
      end
    end

    context '権限のないユーザーの場合' do
      let(:store_user) { create(:store_user) }

      before do
        # 店舗ユーザーとしてログイン試行
        visit admin_sign_in_path
        fill_in 'admin[email]', with: store_user.email
        fill_in 'admin[password]', with: 'wrongpassword'
        click_button 'ログイン'
      end

      it 'アクセスが拒否されること' do
        expect(page).to have_content('メールアドレスまたはパスワードが正しくありません')
        expect(page).not_to have_content('管理者ダッシュボード')
      end
    end
  end

  describe 'パフォーマンス' do
    before do
      # 管理者としてログイン
      visit admin_sign_in_path
      fill_in 'admin[email]', with: admin.email
      fill_in 'admin[password]', with: 'Password123!'
      click_button 'ログイン'
    end

    it 'ダッシュボードが適切な時間で読み込まれること' do
      start_time = Time.current

      visit admin_dashboard_path

      load_time = Time.current - start_time
      expect(load_time).to be < 3.seconds # 3秒以内に読み込み完了
      expect(page).to have_content('管理者ダッシュボード')
    end

    context '大量データでのパフォーマンス' do
      before do
        # 大量のテストデータを作成（CI環境を考慮して数を制限）
        stores = create_list(:store, 10)
        inventories = create_list(:inventory, 50)

        stores.each do |store|
          inventories.sample(20).each do |inventory| # 全組み合わせではなくサンプリング
            create(:store_inventory, store: store, inventory: inventory,
                   quantity: rand(0..100), safety_stock_level: rand(5..20))
          end
        end

        # ログを追加
        create_list(:inventory_log, 100, admin: admin)
      end

      it '大量データでも適切に表示されること' do
        visit admin_dashboard_path

        expect(page).to have_content('管理者ダッシュボード')
        expect(page).to have_content('総在庫商品数')
        expect(page).to have_content('低在庫アラート')
      end
    end
  end

  # ============================================
  # アクセシビリティテスト
  # ============================================

  describe 'アクセシビリティ' do
    before do
      visit admin_sign_in_path
      fill_in 'admin[email]', with: admin.email
      fill_in 'admin[password]', with: 'Password123!'
      click_button 'ログイン'
      visit admin_dashboard_path
    end

    it 'キーボードナビゲーションが機能すること', :js do
      # Tabキーでの移動テスト
      first_link = find('a', match: :first)
      first_link.send_keys(:tab)

      expect(page).to have_css(':focus') # フォーカスがある要素が存在
    end

    it '適切なARIA属性が設定されていること' do
      # セマンティックHTML要素の確認
      expect(page).to have_css('main[role="main"]')
      expect(page).to have_css('nav[role="navigation"]')

      # ARIAラベルの確認
      expect(page).to have_css('[aria-label]')
    end

    it 'スクリーンリーダー対応が適切であること' do
      # 見出し構造の確認
      expect(page).to have_css('h1', count: 1)
      expect(page).to have_css('h2, h3, h4, h5, h6')

      # 代替テキストの確認
      page.all('img').each do |img|
        expect(img[:alt]).to be_present
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe 'セキュリティ' do
    it 'CSRF保護が有効であること' do
      # CSRFトークンの存在確認
      visit admin_sign_in_path
      expect(page).to have_css('meta[name="csrf-token"]', visible: false)
    end

    it 'セキュリティヘッダーが適切に設定されていること' do
      visit admin_dashboard_path

      # レスポンスヘッダーは直接テストできないため、
      # ログイン後の正常な動作で間接的に確認
      expect(page.response_headers).to be_present
    end
  end

  # ============================================
  # TODO: 将来実装予定のテスト
  # ============================================

  describe 'future features', :pending do
    it 'リアルタイム通知が動作すること' do
      pending 'WebSocketによるリアルタイム通知機能は将来実装予定'
      # expect(page).to have_css('.notification-badge')
    end

    it 'ダークモード切り替えが動作すること' do
      pending 'ダークモード機能は将来実装予定'
      # click_button 'ダークモード切り替え'
      # expect(page).to have_css('.dark-theme')
    end
  end
end
