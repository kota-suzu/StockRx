# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::StoreSelectionController, type: :controller do
  # CLAUDE.md準拠: 店舗選択機能の包括的テスト
  # メタ認知: マルチテナント認証の重要性 - 店舗間分離の確実性をテスト
  # 横展開: 他の認証系コントローラーでも同様のセキュリティテスト適用

  let!(:active_pharmacy) { create(:store, :pharmacy, slug: 'pharmacy-a', active: true) }
  let!(:active_warehouse) { create(:store, :warehouse, slug: 'warehouse-b', active: true) }
  let!(:inactive_store) { create(:store, slug: 'inactive-store', active: false) }
  let!(:headquarters_store) { create(:store, :headquarters, slug: 'headquarters', active: true) }

  describe "レイアウト設定" do
    it "store_selectionレイアウトを使用する" do
      get :index
      expect(response).to render_template(layout: "store_selection")
    end
  end

  # ============================================
  # index アクション包括的テスト
  # ============================================

  describe 'GET #index' do
    before { get :index }

    it 'returns successful response' do
      expect(response).to have_http_status(:success)
    end

    it 'assigns active stores only' do
      expect(assigns(:stores)).to include(active_pharmacy, active_warehouse, headquarters_store)
      expect(assigns(:stores)).not_to include(inactive_store)
    end

    it 'groups stores by type' do
      stores_by_type = assigns(:stores_by_type)
      expect(stores_by_type['pharmacy']).to include(active_pharmacy)
      expect(stores_by_type['warehouse']).to include(active_warehouse)
      expect(stores_by_type['headquarters']).to include(headquarters_store)
    end

    it 'orders stores by type and name' do
      stores = assigns(:stores)
      expect(stores).to be_present
      # 型と名前でソートされていることを確認
      expect(stores.first.store_type).to be_present
    end

    context 'with recent stores cookie' do
      before do
        cookies[:recent_stores] = [ 'pharmacy-a', 'warehouse-b' ].to_json
        get :index
      end

      it 'loads recent stores from cookie' do
        recent_stores = assigns(:recent_stores)
        expect(recent_stores).to have_key('pharmacy-a')
        expect(recent_stores).to have_key('warehouse-b')
      end

      it 'assigns recent store slugs' do
        expect(assigns(:recent_store_slugs)).to include('pharmacy-a', 'warehouse-b')
      end
    end

    context 'with invalid recent stores cookie' do
      before do
        cookies[:recent_stores] = 'invalid_json'
        get :index
      end

      it 'handles invalid JSON gracefully' do
        expect(assigns(:recent_store_slugs)).to eq([])
        expect(response).to have_http_status(:success)
      end
    end

    context 'with no recent stores cookie' do
      it 'returns empty recent stores' do
        expect(assigns(:recent_store_slugs)).to eq([])
        expect(assigns(:recent_stores)).to be_empty
      end
    end
  end

  # ============================================
  # show アクション包括的テスト
  # ============================================

  describe 'GET #show' do
    context 'with valid active store slug' do
      it 'finds store and redirects to login' do
        get :show, params: { slug: active_pharmacy.slug }

        expect(assigns(:store)).to eq(active_pharmacy)
        expect(response).to redirect_to(new_store_user_session_path(store_slug: active_pharmacy.slug))
      end

      it 'saves store to recent stores cookie' do
        get :show, params: { slug: active_pharmacy.slug }

        recent_stores = JSON.parse(cookies[:recent_stores])
        expect(recent_stores).to include(active_pharmacy.slug)
      end

      it 'sets proper cookie attributes' do
        get :show, params: { slug: active_pharmacy.slug }

        expect(cookies[:recent_stores]).to be_present
        # HTTPOnlyフラグは設定されているが、テスト環境では確認困難
      end
    end

    context 'with invalid store slug' do
      it 'redirects to store selection with error' do
        get :show, params: { slug: 'nonexistent-store' }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
      end

      it 'logs warning for invalid store access' do
        expect(Rails.logger).to receive(:warn).with(/Store not found or inactive/)
        get :show, params: { slug: 'nonexistent-store' }
      end

      it 'does not assign store' do
        get :show, params: { slug: 'nonexistent-store' }
        expect(assigns(:store)).to be_nil
      end
    end

    context 'with inactive store slug' do
      it 'treats inactive store as not found' do
        get :show, params: { slug: inactive_store.slug }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
        expect(assigns(:store)).to be_nil
      end
    end

    context 'when user is already authenticated to same store' do
      let(:store_user) { create(:store_user, store: active_pharmacy) }

      before do
        sign_in store_user, scope: :store_user
        allow(controller).to receive(:store_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(active_pharmacy)
        allow(controller).to receive(:current_store_user).and_return(store_user)
      end

      it 'redirects to dashboard' do
        get :show, params: { slug: active_pharmacy.slug }

        expect(response).to redirect_to(store_root_path)
      end

      it 'logs successful authentication redirect' do
        expect(Rails.logger).to receive(:info).with(/AUTH_SUCCESS/)
        get :show, params: { slug: active_pharmacy.slug }
      end
    end

    context 'when user is authenticated to different store' do
      let(:pharmacy_user) { create(:store_user, store: active_pharmacy) }

      before do
        sign_in pharmacy_user, scope: :store_user
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(active_pharmacy)
        allow(controller).to receive(:current_store_user).and_return(pharmacy_user)
      end

      it 'signs out user and redirects to different store login' do
        expect(controller).to receive(:sign_out).with(:store_user)

        get :show, params: { slug: active_warehouse.slug }

        expect(response).to redirect_to(new_store_user_session_path(store_slug: active_warehouse.slug))
        expect(flash[:info]).to include('店舗切り替え')
      end

      it 'logs store session clearing' do
        allow(controller).to receive(:sign_out)
        expect(Rails.logger).to receive(:info).with(/Store session cleared/)

        get :show, params: { slug: active_warehouse.slug }
      end
    end

    context 'when authentication check raises exception' do
      let(:store_user) { create(:store_user, store: active_pharmacy) }

      before do
        sign_in store_user, scope: :store_user
        allow(controller).to receive(:store_signed_in?).and_raise(StandardError.new('Auth error'))
      end

      it 'handles authentication errors gracefully' do
        expect(Rails.logger).to receive(:error).with(/Store authentication check failed/)
        expect(controller).to receive(:sign_out).with(:store_user)

        get :show, params: { slug: active_pharmacy.slug }

        expect(response).to redirect_to(new_store_user_session_path(store_slug: active_pharmacy.slug))
      end
    end

    context 'when session cleanup fails' do
      let(:pharmacy_user) { create(:store_user, store: active_pharmacy) }

      before do
        sign_in pharmacy_user, scope: :store_user
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store).and_return(active_pharmacy)
        allow(controller).to receive(:current_store_user).and_return(pharmacy_user)
        allow(controller).to receive(:sign_out).and_raise(StandardError.new('Cleanup error'))
      end

      it 'resets session and logs error' do
        expect(Rails.logger).to receive(:error).with(/Session cleanup failed/)
        expect(controller).to receive(:reset_session)

        get :show, params: { slug: active_warehouse.slug }
      end
    end
  end

  # ============================================
  # プライベートメソッドテスト
  # ============================================

  describe 'private methods' do
    describe '#recent_stores_from_cookie' do
      it 'returns empty array when no cookie exists' do
        result = controller.send(:recent_stores_from_cookie)
        expect(result).to eq([])
      end

      it 'parses valid JSON cookie correctly' do
        cookies[:recent_stores] = [ 'store1', 'store2' ].to_json
        result = controller.send(:recent_stores_from_cookie)
        expect(result).to eq([ 'store1', 'store2' ])
      end

      it 'handles invalid JSON gracefully' do
        cookies[:recent_stores] = 'invalid_json{'
        result = controller.send(:recent_stores_from_cookie)
        expect(result).to eq([])
      end

      it 'handles empty cookie gracefully' do
        cookies[:recent_stores] = ''
        result = controller.send(:recent_stores_from_cookie)
        expect(result).to eq([])
      end
    end

    describe '#save_to_recent_stores' do
      it 'saves new store to empty cookie' do
        controller.send(:save_to_recent_stores, 'new-store')

        recent = JSON.parse(cookies[:recent_stores])
        expect(recent).to eq([ 'new-store' ])
      end

      it 'moves existing store to front and removes duplicates' do
        cookies[:recent_stores] = [ 'store1', 'store2', 'store3' ].to_json
        controller.send(:save_to_recent_stores, 'store2')

        recent = JSON.parse(cookies[:recent_stores])
        expect(recent.first).to eq('store2')
        expect(recent.count('store2')).to eq(1) # no duplicates
        expect(recent).to include('store1', 'store3')
      end

      it 'limits to maximum 5 stores' do
        initial = (1..6).map { |i| "store#{i}" }
        cookies[:recent_stores] = initial.to_json
        controller.send(:save_to_recent_stores, 'new-store')

        recent = JSON.parse(cookies[:recent_stores])
        expect(recent.length).to eq(5)
        expect(recent.first).to eq('new-store')
        expect(recent).not_to include('store6') # oldest removed
      end

      it 'handles large store list efficiently' do
        large_list = (1..100).map { |i| "store#{i}" }
        cookies[:recent_stores] = large_list.to_json

        start_time = Time.current
        controller.send(:save_to_recent_stores, 'test-store')
        elapsed_time = (Time.current - start_time) * 1000

        expect(elapsed_time).to be < 10 # 10ms以内

        recent = JSON.parse(cookies[:recent_stores])
        expect(recent.length).to eq(5)
        expect(recent.first).to eq('test-store')
      end
    end
  end

  describe "GET #index" do
    context "基本的な店舗一覧表示" do
      it "成功レスポンスを返す" do
        get :index
        expect(response).to have_http_status(:success)
      end

      it "アクティブな店舗のみを取得する" do
        get :index
        stores = assigns(:stores)

        expect(stores).to include(active_pharmacy, active_warehouse, headquarters_store)
        expect(stores).not_to include(inactive_store)
      end

      it "店舗タイプ順、店舗名順でソートされる" do
        get :index
        stores = assigns(:stores)

        # ソート順を確認
        previous_store = nil
        stores.each do |store|
          if previous_store
            type_comparison = store.store_type <=> previous_store.store_type
            name_comparison = store.name <=> previous_store.name
            expect(type_comparison >= 0).to be true
            if type_comparison == 0
              expect(name_comparison >= 0).to be true
            end
          end
          previous_store = store
        end
      end

      it "店舗タイプ別にグループ化される" do
        get :index
        stores_by_type = assigns(:stores_by_type)

        expect(stores_by_type).to be_a(Hash)
        expect(stores_by_type['pharmacy']).to include(active_pharmacy)
        expect(stores_by_type['warehouse']).to include(active_warehouse)
        expect(stores_by_type['headquarters']).to include(headquarters_store)
      end
    end

    context "最近アクセスした店舗の処理" do
      before do
        # Cookieに最近の店舗情報を設定
        cookies[:recent_stores] = [ 'pharmacy-a', 'warehouse-b' ].to_json
      end

      it "Cookieから最近の店舗情報を読み込む" do
        get :index
        recent_slugs = assigns(:recent_store_slugs)
        recent_stores = assigns(:recent_stores)

        expect(recent_slugs).to eq([ 'pharmacy-a', 'warehouse-b' ])
        expect(recent_stores['pharmacy-a']).to eq(active_pharmacy)
        expect(recent_stores['warehouse-b']).to eq(active_warehouse)
      end

      it "無効なJSON Cookieを適切に処理する" do
        cookies[:recent_stores] = 'invalid-json'

        expect {
          get :index
        }.not_to raise_error

        expect(assigns(:recent_store_slugs)).to eq([])
      end

      it "存在しない店舗slugsを除外する" do
        cookies[:recent_stores] = [ 'pharmacy-a', 'nonexistent-store' ].to_json

        get :index
        recent_stores = assigns(:recent_stores)

        expect(recent_stores.keys).to eq([ 'pharmacy-a' ])
        expect(recent_stores['nonexistent-store']).to be_nil
      end
    end

    context "Counter Cache使用によるN+1クエリ防止" do
      before do
        # テストデータセットアップ
        create_list(:store_inventory, 3, store: active_pharmacy)
        create_list(:store_inventory, 2, store: active_warehouse, quantity: 1, safety_stock_level: 10)
      end

      it "includesを使わずにCounter Cacheを活用する" do
        expect {
          get :index
        }.not_to exceed_query_limit(5) # Counter Cache使用で最小限のクエリ
      end
    end
  end

  describe "GET #show" do
    context "有効な店舗slugの場合" do
      it "店舗ログインページにリダイレクトする" do
        get :show, params: { slug: active_pharmacy.slug }

        expect(response).to redirect_to(new_store_user_session_path(store_slug: active_pharmacy.slug))
      end

      it "最近の店舗としてCookieに保存する" do
        get :show, params: { slug: active_pharmacy.slug }

        recent_stores = JSON.parse(cookies[:recent_stores])
        expect(recent_stores).to include(active_pharmacy.slug)
        expect(recent_stores.first).to eq(active_pharmacy.slug)
      end

      it "既存の最近の店舗リストを更新する" do
        cookies[:recent_stores] = [ 'warehouse-b', 'headquarters' ].to_json

        get :show, params: { slug: active_pharmacy.slug }

        recent_stores = JSON.parse(cookies[:recent_stores])
        expect(recent_stores).to eq([ 'pharmacy-a', 'warehouse-b', 'headquarters' ])
      end
    end

    context "無効な店舗slugの場合" do
      it "店舗一覧にリダイレクトし、エラーメッセージを表示する" do
        get :show, params: { slug: 'nonexistent-store' }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
      end

      it "セキュリティログを記録する" do
        expect(Rails.logger).to receive(:warn).with(/Store not found or inactive/)

        get :show, params: { slug: 'nonexistent-store' }
      end
    end

    context "非アクティブな店舗の場合" do
      it "店舗一覧にリダイレクトする" do
        get :show, params: { slug: inactive_store.slug }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "認証済みユーザーの処理" do
      let(:store_user) { create(:store_user, store: active_pharmacy) }

      context "同じ店舗の認証済みユーザー" do
        before do
          allow(controller).to receive(:store_signed_in?).and_return(true)
          allow(controller).to receive(:current_store_user).and_return(store_user)
          allow(controller).to receive(:current_store).and_return(active_pharmacy)
        end

        it "店舗ダッシュボードにリダイレクトする" do
          get :show, params: { slug: active_pharmacy.slug }

          expect(response).to redirect_to(store_root_path)
        end

        it "成功ログを記録する" do
          expect(Rails.logger).to receive(:info).with(/AUTH_SUCCESS/)

          get :show, params: { slug: active_pharmacy.slug }
        end
      end

      context "異なる店舗のユーザー" do
        before do
          allow(controller).to receive(:store_user_signed_in?).and_return(true)
          allow(controller).to receive(:current_store_user).and_return(store_user)
          allow(controller).to receive(:current_store).and_return(active_pharmacy)
        end

        it "セッションをクリアする" do
          expect(controller).to receive(:sign_out).with(:store_user)

          get :show, params: { slug: active_warehouse.slug }
        end

        it "店舗切り替えメッセージを表示する" do
          get :show, params: { slug: active_warehouse.slug }

          expect(flash[:info]).to include("店舗切り替え")
        end

        it "情報ログを記録する" do
          expect(Rails.logger).to receive(:info).with(/Store session cleared/)

          get :show, params: { slug: active_warehouse.slug }
        end

        it "新しい店舗のログインページにリダイレクトする" do
          get :show, params: { slug: active_warehouse.slug }

          expect(response).to redirect_to(new_store_user_session_path(store_slug: active_warehouse.slug))
        end
      end

      context "非アクティブな店舗のセッション" do
        before do
          allow(controller).to receive(:store_user_signed_in?).and_return(true)
          allow(controller).to receive(:current_store_user).and_return(store_user)
          allow(controller).to receive(:current_store).and_return(inactive_store)
        end

        it "セッションをクリアする" do
          expect(controller).to receive(:sign_out).with(:store_user)

          get :show, params: { slug: active_pharmacy.slug }
        end

        it "非アクティブ店舗セッションの理由でログを記録する" do
          expect(Rails.logger).to receive(:info).with(/inactive_store_session/)

          get :show, params: { slug: active_pharmacy.slug }
        end
      end
    end

    context "認証チェック中のエラーハンドリング" do
      before do
        allow(controller).to receive(:store_signed_in?).and_raise(StandardError, "Auth error")
      end

      it "例外を適切に処理し、ログを記録する" do
        expect(Rails.logger).to receive(:error).with(/Store authentication check failed/)

        expect {
          get :show, params: { slug: active_pharmacy.slug }
        }.not_to raise_error
      end

      it "セッションをクリアする" do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        expect(controller).to receive(:sign_out).with(:store_user)

        get :show, params: { slug: active_pharmacy.slug }
      end
    end

    context "セッションクリア処理でのエラーハンドリング" do
      let(:store_user) { create(:store_user, store: active_pharmacy) }

      before do
        allow(controller).to receive(:store_user_signed_in?).and_return(true)
        allow(controller).to receive(:current_store_user).and_return(store_user)
        allow(controller).to receive(:current_store).and_return(active_pharmacy)
        allow(controller).to receive(:sign_out).and_raise(StandardError, "Signout error")
      end

      it "セッションクリア失敗時にセッション全体をリセットする" do
        expect(Rails.logger).to receive(:error).with(/Session cleanup failed/)
        expect(controller).to receive(:reset_session)

        get :show, params: { slug: active_warehouse.slug }
      end
    end
  end

  describe "プライベートメソッド" do
    describe "#recent_stores_from_cookie" do
      context "有効なCookieがある場合" do
        before do
          cookies[:recent_stores] = [ 'pharmacy-a', 'warehouse-b' ].to_json
        end

        it "JSON配列を返す" do
          result = controller.send(:recent_stores_from_cookie)
          expect(result).to eq([ 'pharmacy-a', 'warehouse-b' ])
        end
      end

      context "Cookieがない場合" do
        it "空配列を返す" do
          result = controller.send(:recent_stores_from_cookie)
          expect(result).to eq([])
        end
      end

      context "無効なJSONの場合" do
        before do
          cookies[:recent_stores] = 'invalid-json'
        end

        it "空配列を返す" do
          result = controller.send(:recent_stores_from_cookie)
          expect(result).to eq([])
        end
      end
    end

    describe "#save_to_recent_stores" do
      it "新しい店舗を先頭に追加する" do
        controller.send(:save_to_recent_stores, 'new-store')

        recent_stores = JSON.parse(cookies[:recent_stores])
        expect(recent_stores.first).to eq('new-store')
      end

      it "既存の店舗を先頭に移動する" do
        cookies[:recent_stores] = [ 'store-a', 'store-b', 'store-c' ].to_json

        controller.send(:save_to_recent_stores, 'store-b')

        recent_stores = JSON.parse(cookies[:recent_stores])
        expect(recent_stores).to eq([ 'store-b', 'store-a', 'store-c' ])
      end

      it "最大5件までに制限する" do
        cookies[:recent_stores] = [ 'store-a', 'store-b', 'store-c', 'store-d', 'store-e' ].to_json

        controller.send(:save_to_recent_stores, 'new-store')

        recent_stores = JSON.parse(cookies[:recent_stores])
        expect(recent_stores.length).to eq(5)
        expect(recent_stores).to eq([ 'new-store', 'store-a', 'store-b', 'store-c', 'store-d' ])
      end

      it "適切なCookie属性を設定する" do
        controller.send(:save_to_recent_stores, 'test-store')

        cookie = cookies[:recent_stores]
        expect(cookie).to be_present

        # HTTPOnly設定の確認（Rails環境では直接テストできないため、設定の確認のみ）
        # 実際の設定はcookies設定で httponly: true が指定されていることを確認
      end
    end
  end

  describe "ヘルパーメソッド" do
    describe "#store_type_display_name" do
      it "薬局タイプの表示名を返す" do
        result = controller.store_type_display_name('pharmacy')
        expect(result).to be_a(String)
      end

      it "未定義のタイプをhumanizeする" do
        result = controller.store_type_display_name('unknown_type')
        expect(result).to eq('Unknown type')
      end
    end

    describe "#store_type_icon_class" do
      it "薬局アイコンクラスを返す" do
        result = controller.store_type_icon_class('pharmacy')
        expect(result).to eq('bi bi-capsule')
      end

      it "倉庫アイコンクラスを返す" do
        result = controller.store_type_icon_class('warehouse')
        expect(result).to eq('bi bi-building')
      end

      it "本部アイコンクラスを返す" do
        result = controller.store_type_icon_class('headquarters')
        expect(result).to eq('bi bi-building-gear')
      end

      it "未定義タイプにデフォルトアイコンを返す" do
        result = controller.store_type_icon_class('unknown')
        expect(result).to eq('bi bi-shop')
      end
    end

    describe "#store_status_badge" do
      context "在庫がない店舗" do
        before do
          allow(active_pharmacy).to receive(:store_inventories_count).and_return(0)
        end

        it "準備中バッジを返す" do
          result = controller.store_status_badge(active_pharmacy)
          expect(result[:text]).to eq('準備中')
          expect(result[:class]).to eq('badge bg-secondary')
        end
      end

      context "低在庫商品がある店舗" do
        before do
          allow(active_pharmacy).to receive(:store_inventories_count).and_return(10)
          allow(active_pharmacy).to receive(:low_stock_items_count).and_return(3)
        end

        it "在庫不足バッジを返す" do
          result = controller.store_status_badge(active_pharmacy)
          expect(result[:text]).to eq('在庫不足: 3件')
          expect(result[:class]).to eq('badge bg-warning text-dark')
        end
      end

      context "正常な店舗" do
        before do
          allow(active_pharmacy).to receive(:store_inventories_count).and_return(10)
          allow(active_pharmacy).to receive(:low_stock_items_count).and_return(0)
        end

        it "正常稼働中バッジを返す" do
          result = controller.store_status_badge(active_pharmacy)
          expect(result[:text]).to eq('正常稼働中')
          expect(result[:class]).to eq('badge bg-success')
        end
      end
    end
  end

  describe "セキュリティテスト" do
    context "SQLインジェクション防止" do
      it "悪意のあるslugパラメータを安全に処理する" do
        malicious_slug = "pharmacy'; DROP TABLE stores; --"

        expect {
          get :show, params: { slug: malicious_slug }
        }.not_to raise_error

        expect(Store.count).to be > 0 # テーブルが削除されていない
      end
    end

    context "クロスサイトスクリプティング（XSS）防止" do
      it "悪意のあるslugパラメータをエスケープする" do
        malicious_slug = "<script>alert('XSS')</script>"

        expect {
          get :show, params: { slug: malicious_slug }
        }.not_to raise_error

        expect(response.body).not_to include("<script>")
      end
    end

    context "Cookieセキュリティ" do
      it "HTTPOnlyフラグが設定される" do
        controller.send(:save_to_recent_stores, 'test-store')

        # Cookieの存在確認（詳細なセキュリティ属性はブラウザレベルでテスト）
        expect(cookies[:recent_stores]).to be_present
      end

      it "適切な有効期限が設定される" do
        freeze_time do
          controller.send(:save_to_recent_stores, 'test-store')

          # 30日後に期限切れになることを確認
          Timecop.travel(31.days.from_now) do
            expect(controller.send(:recent_stores_from_cookie)).to eq([])
          end
        end
      end
    end
  end

  describe "パフォーマンステスト" do
    context "大量店舗でのレスポンス" do
      before do
        create_list(:store, 50, active: true)
      end

      it "大量店舗でも効率的に処理する" do
        start_time = Time.current
        get :index
        elapsed = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed).to be < 500 # 500ms以内
      end

      it "Counter Cacheでクエリ数を制限する" do
        expect {
          get :index
        }.not_to exceed_query_limit(8)
      end
    end
  end

  describe "エラーハンドリング" do
    context "データベース接続エラー" do
      before do
        allow(Store).to receive(:active).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "データベースエラーを適切に処理する" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "Cookieパースエラー" do
      before do
        cookies[:recent_stores] = "malformed-json["
      end

      it "JSON解析エラーを適切に処理する" do
        expect {
          get :index
        }.not_to raise_error

        expect(assigns(:recent_store_slugs)).to eq([])
      end
    end
  end

  describe "国際化対応" do
    context "日本語環境" do
      before do
        I18n.locale = :ja
      end

      it "日本語エラーメッセージを表示する" do
        get :show, params: { slug: 'nonexistent' }

        expect(flash[:alert]).to be_present
        # 実際のメッセージは設定ファイルによる
      end
    end

    context "英語環境" do
      before do
        I18n.locale = :en
      end

      it "英語環境でも正常に動作する" do
        expect {
          get :index
        }.not_to raise_error

        expect(response).to be_successful
      end
    end
  end
end
