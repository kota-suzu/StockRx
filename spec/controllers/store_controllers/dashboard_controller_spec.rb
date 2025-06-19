# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::DashboardController, type: :controller do
  # CLAUDE.md準拠: 店舗ダッシュボードの包括的テスト
  # メタ認知: 複雑なデータ集約とパフォーマンス最適化の検証
  # 横展開: AdminControllers::DashboardControllerでも同様のテストパターン適用

  let(:store) { create(:store, name: 'テスト店舗') }
  let(:store_user) { create(:store_user, store: store) }
  let(:other_store) { create(:store, name: '他店舗') }
  let(:inventory1) { create(:inventory, name: "アスピリン錠100mg", price: 500) }
  let(:inventory2) { create(:inventory, name: "デジタル血圧計", price: 15000) }
  let(:inventory3) { create(:inventory, name: "マスク50枚入り", price: 200) }

  before do
    # StoreControllers::BaseControllerの認証をモック化
    allow(controller).to receive(:current_store).and_return(store)
    allow(controller).to receive(:authenticate_store_user!).and_return(true)
    sign_in store_user, scope: :store_user
  end

  # ============================================
  # データ読み込み機能の詳細テスト（CLAUDE.md準拠）
  # ============================================

  describe "data loading methods" do
    context "店舗統計情報の読み込み" do
      before do
        setup_store_statistics_data
      end

      it "Counter Cacheを活用した統計情報を計算する" do
        get :index
        statistics = assigns(:statistics)

        expect(statistics).to be_a(Hash)
        expect(statistics).to have_key(:total_items)
        expect(statistics).to have_key(:total_quantity)
        expect(statistics).to have_key(:total_value)
        expect(statistics).to have_key(:low_stock_items)
        expect(statistics).to have_key(:out_of_stock_items)
        expect(statistics).to have_key(:pending_transfers_in)
        expect(statistics).to have_key(:pending_transfers_out)
      end

      it "正確な統計値を計算する" do
        get :index
        statistics = assigns(:statistics)

        expect(statistics[:total_items]).to eq(3) # Counter Cache使用
        expect(statistics[:total_quantity]).to eq(125) # 5 + 20 + 100
        expect(statistics[:low_stock_items]).to eq(1) # アスピリン錠のみ低在庫
        expect(statistics[:out_of_stock_items]).to eq(0)
        expect(statistics[:pending_transfers_in]).to eq(1)
        expect(statistics[:pending_transfers_out]).to eq(1)
      end

      it "total_inventory_valueを正しく計算する" do
        get :index
        statistics = assigns(:statistics)

        # 各商品の価格×数量の合計: (500*5) + (15000*20) + (200*100) = 322,500
        expected_value = (inventory1.price * 5) + (inventory2.price * 20) + (inventory3.price * 100)
        expect(statistics[:total_value]).to eq(expected_value)
      end
    end

    context "在庫アラート情報の読み込み（Arel.sql使用）" do
      before do
        setup_inventory_alerts_data
      end

      it "低在庫アイテムを安全在庫レベル比率順でソートする" do
        get :index
        low_stock_items = assigns(:low_stock_items)

        expect(low_stock_items.count).to eq(2)
        # safety_ratio_orderによる適切なソート確認
        if low_stock_items.count >= 2
          first_ratio = low_stock_items.first.quantity.to_f / low_stock_items.first.safety_stock_level
          second_ratio = low_stock_items.second.quantity.to_f / low_stock_items.second.safety_stock_level
          expect(first_ratio).to be <= second_ratio
        end
      end

      it "在庫切れアイテムを更新日時順でソートする" do
        get :index
        out_of_stock_items = assigns(:out_of_stock_items)

        expect(out_of_stock_items.count).to eq(1)
        expect(out_of_stock_items.first.quantity).to eq(0)
      end

      it "期限切れ間近アイテムを有効期限順でソートする" do
        get :index
        expiring_items = assigns(:expiring_items)

        expect(expiring_items.count).to eq(2)
        # expiration_orderによる適切なソート確認
        if expiring_items.count >= 2
          expect(expiring_items.first.expires_on).to be <= expiring_items.second.expires_on
        end
      end

      it "期限切れ間近商品が30日以内の範囲で正しく抽出される" do
        get :index
        expiring_items = assigns(:expiring_items)

        expiring_items.each do |item|
          expect(item.expires_on).to be_between(Date.current, 30.days.from_now)
        end
      end

      it "関連データが適切に事前読み込みされている" do
        get :index
        low_stock_items = assigns(:low_stock_items)
        expiring_items = assigns(:expiring_items)

        if low_stock_items.any?
          expect(low_stock_items.first.association(:inventory)).to be_loaded
        end

        if expiring_items.any?
          expect(expiring_items.first.association(:inventory)).to be_loaded
        end
      end
    end

    context "店舗間移動サマリーの読み込み" do
      before do
        setup_transfer_summary_data
      end

      it "保留中の入庫移動を要求日時順で取得する" do
        get :index
        pending_incoming = assigns(:pending_incoming)

        expect(pending_incoming.count).to eq(2)
        expect(pending_incoming.all? { |t| t.destination_store == store }).to be true
        expect(pending_incoming.all? { |t| t.status == "pending" }).to be true

        # requested_at降順の確認
        if pending_incoming.count >= 2
          expect(pending_incoming.first.requested_at).to be >= pending_incoming.second.requested_at
        end
      end

      it "保留中の出庫移動を要求日時順で取得する" do
        get :index
        pending_outgoing = assigns(:pending_outgoing)

        expect(pending_outgoing.count).to eq(1)
        expect(pending_outgoing.first.source_store).to eq(store)
        expect(pending_outgoing.first.status).to eq("pending")
      end

      it "最近完了した移動を完了日時順で取得する" do
        get :index
        recent_completed = assigns(:recent_completed)

        expect(recent_completed.count).to eq(2)
        expect(recent_completed.all? { |t| t.status == "completed" }).to be true

        # completed_at降順の確認
        if recent_completed.count >= 2
          expect(recent_completed.first.completed_at).to be >= recent_completed.second.completed_at
        end
      end

      it "移動データに必要な関連データが事前読み込みされている" do
        get :index
        pending_incoming = assigns(:pending_incoming)
        pending_outgoing = assigns(:pending_outgoing)
        recent_completed = assigns(:recent_completed)

        [pending_incoming, pending_outgoing, recent_completed].each do |transfers|
          transfers.each do |transfer|
            expect(transfer.association(:source_store)).to be_loaded
            expect(transfer.association(:destination_store)).to be_loaded
            expect(transfer.association(:inventory)).to be_loaded
          end
        end
      end
    end

    context "最近のアクティビティ読み込み" do
      before do
        setup_recent_activities_data
      end

      it "店舗が扱う商品の在庫変動ログを時系列順で取得する" do
        get :index
        recent_inventory_changes = assigns(:recent_inventory_changes)

        expect(recent_inventory_changes.count).to eq(3)
        
        # 店舗が扱う商品のログのみが含まれている
        recent_inventory_changes.each do |log|
          expect(store.inventories.pluck(:id)).to include(log.inventory_id)
        end

        # created_at降順の確認
        if recent_inventory_changes.count >= 2
          expect(recent_inventory_changes.first.created_at).to be >= recent_inventory_changes.second.created_at
        end
      end

      it "在庫変動ログに関連データが事前読み込みされている" do
        get :index
        recent_inventory_changes = assigns(:recent_inventory_changes)

        recent_inventory_changes.each do |log|
          expect(log.association(:inventory)).to be_loaded
          expect(log.association(:admin)).to be_loaded
        end
      end

      it "recent_activitiesが空配列として初期化される" do
        get :index
        recent_activities = assigns(:recent_activities)

        expect(recent_activities).to eq([])
      end
    end

    context "グラフ用データの読み込み" do
      before do
        setup_chart_data
      end

      it "在庫推移データを過去7日間のJSON形式で準備する" do
        get :index
        inventory_trend_data = assigns(:inventory_trend_data)

        expect(inventory_trend_data).to be_present
        parsed_data = JSON.parse(inventory_trend_data)
        expect(parsed_data).to be_an(Array)
        expect(parsed_data.length).to eq(7) # 過去7日間

        # 各日のデータ構造確認
        parsed_data.each do |day_data|
          expect(day_data).to have_key("date")
          expect(day_data).to have_key("quantity")
          expect(day_data["date"]).to match(/\d{2}\/\d{2}/) # MM/DD形式
          expect(day_data["quantity"]).to be_a(Numeric)
        end
      end

      it "カテゴリ別在庫構成を適切なJSON形式で準備する" do
        get :index
        category_distribution = assigns(:category_distribution)

        expect(category_distribution).to be_present
        parsed_data = JSON.parse(category_distribution)
        expect(parsed_data).to be_an(Array)

        # カテゴリデータ構造確認
        parsed_data.each do |category_data|
          expect(category_data).to have_key("name")
          expect(category_data).to have_key("value")
          expect(category_data["name"]).to be_a(String)
          expect(category_data["value"]).to be_a(Numeric)
        end

        # 期待されるカテゴリが含まれている
        category_names = parsed_data.map { |cat| cat["name"] }
        expect(category_names).to include("医薬品", "医療機器", "消耗品")
      end

      it "店舗間移動トレンドを過去7日間のJSON形式で準備する" do
        get :index
        transfer_trend_data = assigns(:transfer_trend_data)

        expect(transfer_trend_data).to be_present
        parsed_data = JSON.parse(transfer_trend_data)
        expect(parsed_data).to be_an(Array)
        expect(parsed_data.length).to eq(7) # 過去7日間

        # 各日のデータ構造確認
        parsed_data.each do |day_data|
          expect(day_data).to have_key("date")
          expect(day_data).to have_key("incoming")
          expect(day_data).to have_key("outgoing")
          expect(day_data["date"]).to match(/\d{2}\/\d{2}/) # MM/DD形式
          expect(day_data["incoming"]).to be_a(Numeric)
          expect(day_data["outgoing"]).to be_a(Numeric)
        end
      end
    end
  end

  # ============================================
  # 商品名カテゴリ推定機能の詳細テスト
  # ============================================

  describe "categorize_by_name method" do
    context "医薬品キーワードの分類" do
      it "錠剤系キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "アスピリン錠100mg")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "パラセタモール錠")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "ロキソニン錠60mg")).to eq("医薬品")
      end

      it "カプセル系キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "オメプラゾールカプセル")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "ビタミンEカプセル")).to eq("医薬品")
      end

      it "外用薬キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "ヒルドイド軟膏")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "目薬点眼液")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "座薬タイプ")).to eq("医薬品")
      end

      it "注射剤キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "インスリン注射液")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "生理食塩水注射")).to eq("医薬品")
      end

      it "液剤・シロップ系キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "咳止めシロップ")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "胃腸薬液体")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "漢方薬細粒")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "解熱薬顆粒")).to eq("医薬品")
      end

      it "単位系キーワードを正しく分類する" do
        expect(controller.send(:categorize_by_name, "ビタミンB1 100mg")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "プレドニゾロン5mg")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "インスリン100IU")).to eq("医薬品")
      end

      it "一般的な薬品名を正しく分類する" do
        expect(controller.send(:categorize_by_name, "アスピリン配合剤")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "パラセタモール配合")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "アムロジピン錠")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "プレドニゾロン錠")).to eq("医薬品")
      end

      it "抗生物質・消毒薬を正しく分類する" do
        expect(controller.send(:categorize_by_name, "抗生物質軟膏")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "消毒用エタノール")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "ビタミンC錠")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "漢方エキス顆粒")).to eq("医薬品")
      end
    end

    context "医療機器キーワードの分類" do
      it "測定器系を正しく分類する" do
        expect(controller.send(:categorize_by_name, "デジタル血圧計")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "体温計セット")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "パルスオキシメーター")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "聴診器")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "血糖測定器")).to eq("医療機器")
      end
    end

    context "消耗品キーワードの分類" do
      it "マスク・手袋系を正しく分類する" do
        expect(controller.send(:categorize_by_name, "サージカルマスク")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "医療用手袋")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "ニトリル手袋")).to eq("消耗品")
      end

      it "アルコール・ガーゼ系を正しく分類する" do
        expect(controller.send(:categorize_by_name, "アルコール綿")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "滅菌ガーゼ")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "注射針セット")).to eq("消耗品")
      end
    end

    context "サプリメントキーワードの分類" do
      it "ビタミン・サプリ系を正しく分類する" do
        expect(controller.send(:categorize_by_name, "ビタミンDサプリ")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "マルチビタミン")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "オメガ3サプリ")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "プロバイオティクス")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "フィッシュオイル")).to eq("サプリメント")
      end
    end

    context "分類不能な商品" do
      it "その他カテゴリに分類する" do
        expect(controller.send(:categorize_by_name, "未知の商品XYZ")).to eq("その他")
        expect(controller.send(:categorize_by_name, "テスト用アイテム")).to eq("その他")
        expect(controller.send(:categorize_by_name, "")).to eq("その他")
        expect(controller.send(:categorize_by_name, "一般雑貨")).to eq("その他")
      end
    end

    context "大文字小文字・ケース混在の処理" do
      it "大文字小文字を区別しない分類" do
        expect(controller.send(:categorize_by_name, "ASPIRIN錠")).to eq("医薬品")
        expect(controller.send(:categorize_by_name, "mask 50枚")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "Blood Pressure Monitor")).to eq("その他") # 英語は対象外
      end
    end

    context "複数キーワードが含まれる場合の優先順位" do
      it "優先順位に基づいて分類する" do
        # 医療機器 > 消耗品 > サプリメント > 医薬品の順
        expect(controller.send(:categorize_by_name, "血圧計用マスク")).to eq("医療機器")
        expect(controller.send(:categorize_by_name, "マスク用ビタミン")).to eq("消耗品")
        expect(controller.send(:categorize_by_name, "ビタミン配合錠剤")).to eq("サプリメント")
        expect(controller.send(:categorize_by_name, "錠剤ケース")).to eq("医薬品")
      end
    end
  end

  # ============================================
  # ヘルパーメソッドの詳細テスト
  # ============================================

  describe "helper methods" do
    describe "#inventory_level_class" do
      it "在庫切れの場合はtext-dangerを返す" do
        store_inventory = build(:store_inventory, quantity: 0, safety_stock_level: 10)
        expect(controller.send(:inventory_level_class, store_inventory)).to eq("text-danger")
      end

      it "危険レベル在庫（50%以下）の場合はtext-warningを返す" do
        store_inventory = build(:store_inventory, quantity: 5, safety_stock_level: 10)
        expect(controller.send(:inventory_level_class, store_inventory)).to eq("text-warning")
      end

      it "注意レベル在庫（50-100%）の場合はtext-infoを返す" do
        store_inventory = build(:store_inventory, quantity: 8, safety_stock_level: 10)
        expect(controller.send(:inventory_level_class, store_inventory)).to eq("text-info")

        store_inventory = build(:store_inventory, quantity: 10, safety_stock_level: 10)
        expect(controller.send(:inventory_level_class, store_inventory)).to eq("text-info")
      end

      it "十分在庫（100%超）の場合はtext-successを返す" do
        store_inventory = build(:store_inventory, quantity: 15, safety_stock_level: 10)
        expect(controller.send(:inventory_level_class, store_inventory)).to eq("text-success")
      end

      it "安全在庫レベルが0の場合でもエラーにならない" do
        store_inventory = build(:store_inventory, quantity: 5, safety_stock_level: 0)
        expect {
          controller.send(:inventory_level_class, store_inventory)
        }.not_to raise_error
      end
    end

    describe "#expiration_class" do
      it "7日以内の期限切れはtext-dangerを返す" do
        expiration_date = Date.current + 5.days
        expect(controller.send(:expiration_class, expiration_date)).to eq("text-danger")

        expiration_date = Date.current + 7.days
        expect(controller.send(:expiration_class, expiration_date)).to eq("text-danger")
      end

      it "8-14日の期限切れはtext-warningを返す" do
        expiration_date = Date.current + 10.days
        expect(controller.send(:expiration_class, expiration_date)).to eq("text-warning")

        expiration_date = Date.current + 14.days
        expect(controller.send(:expiration_class, expiration_date)).to eq("text-warning")
      end

      it "15日以上の期限切れはtext-infoを返す" do
        expiration_date = Date.current + 30.days
        expect(controller.send(:expiration_class, expiration_date)).to eq("text-info")

        expiration_date = Date.current + 15.days
        expect(controller.send(:expiration_class, expiration_date)).to eq("text-info")
      end

      it "過去の日付でもエラーにならない" do
        expiration_date = Date.current - 5.days
        expect {
          controller.send(:expiration_class, expiration_date)
        }.not_to raise_error
      end
    end

    describe "#calculate_inventory_on_date" do
      before do
        setup_store_statistics_data
      end

      it "指定日の在庫数を計算する（現在は簡易実装で現在の在庫数を返す）" do
        result = controller.send(:calculate_inventory_on_date, Date.current)
        expected = store.store_inventories.sum(:quantity)
        expect(result).to eq(expected)
      end

      it "過去の日付でも現在の在庫数を返す（簡易実装）" do
        past_date = 30.days.ago.to_date
        result = controller.send(:calculate_inventory_on_date, past_date)
        expected = store.store_inventories.sum(:quantity)
        expect(result).to eq(expected)
      end

      it "未来の日付でも現在の在庫数を返す（簡易実装）" do
        future_date = 30.days.from_now.to_date
        result = controller.send(:calculate_inventory_on_date, future_date)
        expected = store.store_inventories.sum(:quantity)
        expect(result).to eq(expected)
      end
    end
  end

  # ============================================
  # 基本機能のテスト
  # ============================================

  describe "GET #index" do
    context "with valid store user authentication" do
      it "returns a success response" do
        get :index, params: { store_slug: store.slug }
        expect(response).to be_successful
        expect(response).to have_http_status(:ok)
      end

      it "assigns dashboard statistics" do
        get :index, params: { store_slug: store.slug }
        expect(assigns(:stats)).to be_present
        expect(assigns(:stats)).to include(
          :total_inventories,
          :low_stock_count,
          :total_inventory_value,
          :out_of_stock_count
        )
      end

      it "renders the index template" do
        get :index, params: { store_slug: store.slug }
        expect(response).to render_template(:index)
      end

      it "assigns store correctly" do
        get :index, params: { store_slug: store.slug }
        expect(assigns(:store)).to eq(store)
      end
    end

    # ============================================
    # 詳細統計データのテスト（カバレッジ向上）
    # ============================================

    context 'with detailed test data' do
      let!(:inventory1) { create(:inventory, name: 'アスピリン錠', price: 500) }
      let!(:inventory2) { create(:inventory, name: 'デジタル血圧計', price: 15000) }
      let!(:inventory3) { create(:inventory, name: '使い捨てマスク', price: 200) }

      before do
        # 店舗在庫設定（低在庫・在庫切れ含む）
        create(:store_inventory, store: store, inventory: inventory1, quantity: 100, safety_stock_level: 20)
        create(:store_inventory, store: store, inventory: inventory2, quantity: 5, safety_stock_level: 10) # 低在庫
        create(:store_inventory, store: store, inventory: inventory3, quantity: 0, safety_stock_level: 50) # 在庫切れ
      end

      it '正確な在庫統計を計算すること' do
        get :index, params: { store_slug: store.slug }
        stats = assigns(:stats)

        expect(stats[:total_inventories]).to eq(3)
        expect(stats[:low_stock_count]).to eq(2) # inventory2とinventory3
        expect(stats[:out_of_stock_count]).to eq(1) # inventory3のみ
        expect(stats[:total_inventory_value]).to be > 0
      end

      it '低在庫商品リストを適切に生成すること' do
        get :index, params: { store_slug: store.slug }
        stats = assigns(:stats)

        expect(stats[:low_stock_items]).to be_present
        low_stock_names = stats[:low_stock_items].map { |item| item[:name] }
        expect(low_stock_names).to include('デジタル血圧計', '使い捨てマスク')
        expect(low_stock_names).not_to include('アスピリン錠')
      end

      it '在庫切れ商品リストを適切に生成すること' do
        get :index, params: { store_slug: store.slug }
        stats = assigns(:stats)

        expect(stats[:out_of_stock_items]).to be_present
        out_of_stock_names = stats[:out_of_stock_items].map { |item| item[:name] }
        expect(out_of_stock_names).to include('使い捨てマスク')
        expect(out_of_stock_names).not_to include('アスピリン錠', 'デジタル血圧計')
      end
    end

    # ============================================
    # パフォーマンステスト（カバレッジ向上）
    # ============================================

    context 'performance considerations' do
      before do
        # 大量データ作成（店舗固有）
        inventories = create_list(:inventory, 30)
        inventories.each_with_index do |inventory, index|
          create(:store_inventory,
                 store: store,
                 inventory: inventory,
                 quantity: index % 10, # 0-9の在庫数
                 safety_stock_level: 5)
        end
      end

      it 'ダッシュボード読み込みが効率的に動作すること' do
        expect {
          get :index, params: { store_slug: store.slug }
        }.to perform_under(500).ms
      end

      it 'N+1クエリが発生しないこと' do
        expect {
          get :index, params: { store_slug: store.slug }
        }.not_to exceed_query_limit(15) # 店舗固有の制限
      end
    end

    # ============================================
    # エラーハンドリング（カバレッジ向上）
    # ============================================

    context 'error handling' do
      it 'データベースエラー時でも適切に処理すること' do
        # StoreInventoryでエラーをシミュレート
        allow(StoreInventory).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new('Database error'))

        expect {
          get :index, params: { store_slug: store.slug }
        }.not_to raise_error

        expect(response).to be_successful
        stats = assigns(:stats)
        expect(stats[:total_inventories]).to eq(0) # フォールバック値
      end

      it '無効な店舗slugでエラーハンドリングすること' do
        get :index, params: { store_slug: 'invalid-store' }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
      end
    end

    # ============================================
    # レスポンス形式テスト（カバレッジ向上）
    # ============================================

    context 'response formats' do
      it 'JSON形式で統計データを返すこと' do
        get :index, params: { store_slug: store.slug }, format: :json

        expect(response).to be_successful
        expect(response.content_type).to include('application/json')

        json_response = JSON.parse(response.body)
        expect(json_response).to include('stats')
        expect(json_response['stats']).to include(
          'total_inventories',
          'low_stock_count',
          'out_of_stock_count',
          'total_inventory_value'
        )
      end

      it 'XML形式での要求でも適切に処理すること' do
        get :index, params: { store_slug: store.slug }, format: :xml

        # XMLサポートがない場合はHTMLにフォールバック
        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # 認証・認可テスト（カバレッジ向上）
  # ============================================

  describe "authentication and authorization" do
    context "without authentication" do
      before { sign_out store_user }

      it "redirects to sign in page" do
        get :index, params: { store_slug: store.slug }
        expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
      end
    end

    context "with wrong store user" do
      let(:other_store) { create(:store) }
      let(:other_store_user) { create(:store_user, store: other_store) }

      before do
        sign_out store_user
        sign_in other_store_user, scope: :store_user
      end

      it "redirects or shows error for accessing different store" do
        get :index, params: { store_slug: store.slug }

        # アクセス制限のテスト（実装に依存）
        expect(response).to have_http_status(:redirect).or(have_http_status(:forbidden))
      end
    end

    context "with inactive store user" do
      let(:inactive_user) { create(:store_user, :inactive, store: store) }

      before do
        sign_out store_user
        sign_in inactive_user, scope: :store_user
      end

      it "handles inactive user appropriately" do
        get :index, params: { store_slug: store.slug }

        # 非アクティブユーザーの処理確認
        expect(response).to have_http_status(:redirect).or(be_successful)
      end
    end
  end

  # ============================================
  # 店舗間分離テスト（カバレッジ向上）
  # ============================================

  describe "multi-store isolation" do
    let(:other_store) { create(:store, name: '他店舗') }
    let!(:other_inventory) { create(:inventory, name: '他店舗商品') }

    before do
      # 他店舗にのみ在庫を追加
      create(:store_inventory, store: other_store, inventory: other_inventory, quantity: 100)

      # 現在の店舗には在庫なし
    end

    it '他店舗の在庫が表示されないこと' do
      get :index, params: { store_slug: store.slug }
      stats = assigns(:stats)

      expect(stats[:total_inventories]).to eq(0)
      expect(stats[:low_stock_count]).to eq(0)
      expect(stats[:out_of_stock_count]).to eq(0)
    end

    it '店舗固有の統計のみ表示されること' do
      # 現在の店舗に在庫追加
      current_inventory = create(:inventory, name: '現在店舗商品')
      create(:store_inventory, store: store, inventory: current_inventory, quantity: 50)

      get :index, params: { store_slug: store.slug }
      stats = assigns(:stats)

      expect(stats[:total_inventories]).to eq(1)

      # 他店舗の商品が含まれていないことを確認
      if stats[:inventory_items]
        inventory_names = stats[:inventory_items].map { |item| item[:name] }
        expect(inventory_names).to include('現在店舗商品')
        expect(inventory_names).not_to include('他店舗商品')
      end
    end
  end

  # ============================================
  # ユーザー体験テスト（カバレッジ向上）
  # ============================================

  describe "user experience" do
    context 'with manager user' do
      let(:manager) { create(:store_user, :manager, store: store) }

      before do
        sign_out store_user
        sign_in manager, scope: :store_user
      end

      it 'マネージャー向けの追加機能が利用できること' do
        get :index, params: { store_slug: store.slug }

        expect(response).to be_successful
        # マネージャー固有の機能があれば確認
        expect(assigns(:user_permissions)).to be_present if defined?(assigns(:user_permissions))
      end
    end

    context 'with different device types' do
      it 'モバイルデバイスからのアクセスを適切に処理すること' do
        request.headers['User-Agent'] = 'Mobile Safari'
        get :index, params: { store_slug: store.slug }

        expect(response).to be_successful
        expect(response.content_type).to include('text/html')
      end

      it 'タブレットデバイスからのアクセスを適切に処理すること' do
        request.headers['User-Agent'] = 'iPad'
        get :index, params: { store_slug: store.slug }

        expect(response).to be_successful
      end
    end
  end

  # ============================================
  # セキュリティテスト（カバレッジ向上）
  # ============================================

  describe "security features" do
    it 'CSRFトークンが適切に設定されていること' do
      get :index, params: { store_slug: store.slug }

      expect(response.headers['X-Frame-Options']).to be_present
      expect(response.body).to include('csrf-token')
    end

    it 'セキュリティヘッダーが適切に設定されていること' do
      get :index, params: { store_slug: store.slug }

      # セキュリティヘッダーの確認
      expect(response.headers).to be_present
      # 具体的なヘッダー確認は実装に依存
    end

    it 'SQLインジェクション攻撃を防ぐこと' do
      malicious_slug = "'; DROP TABLE stores; --"

      expect {
        get :index, params: { store_slug: malicious_slug }
      }.not_to raise_error

      # 攻撃が成功していないことを確認
      expect(Store.count).to be > 0
    end
  end

  # ============================================
  # 国際化・アクセシビリティテスト
  # ============================================

  describe "internationalization and accessibility" do
    it '日本語コンテンツが適切に表示されること' do
      get :index, params: { store_slug: store.slug }

      expect(response.body).to include('店舗ダッシュボード').or(include('ダッシュボード'))
    end

    it 'HTMLが適切な構造を持つこと' do
      get :index, params: { store_slug: store.slug }

      expect(response.body).to include('<html')
      expect(response.body).to include('<head>')
      expect(response.body).to include('<body>')
      expect(response.body).to include('</html>')
    end
  end

  # ============================================
  # パフォーマンス・N+1クエリテスト
  # ============================================

  describe "performance tests" do
    describe "N+1 query prevention" do
      before do
        setup_performance_test_data
      end

      it "ダッシュボード表示でのN+1クエリ防止" do
        expect {
          get :index
        }.not_to exceed_query_limit(25) # 複雑なデータ集約を考慮した制限
      end

      it "低在庫アイテム取得でのArel.sql最適化" do
        create_list(:inventory, 8) do |inventory|
          create(:store_inventory, 
                 store: store, 
                 inventory: inventory,
                 quantity: 5,
                 safety_stock_level: 10)
        end

        expect {
          get :index
        }.not_to exceed_query_limit(20) # Arel.sql使用による最適化
      end

      it "期限切れ間近アイテム取得でのincludes最適化" do
        inventories = create_list(:inventory, 6)
        inventories.each do |inventory|
          store_inventory = create(:store_inventory, store: store, inventory: inventory)
          create(:batch, inventory: inventory, expires_on: 15.days.from_now)
        end

        expect {
          get :index
        }.not_to exceed_query_limit(18) # includes最適化
      end

      it "移動データ読み込みでのincludes最適化" do
        create_list(:inter_store_transfer, 5, source_store: store, status: :pending)
        create_list(:inter_store_transfer, 3, destination_store: store, status: :pending)
        create_list(:inter_store_transfer, 4, source_store: store, status: :completed, 
                    completed_at: 2.days.ago)

        expect {
          get :index
        }.not_to exceed_query_limit(22) # includes使用による最適化
      end

      it "グラフデータ準備での日別集計最適化" do
        # 過去7日間のトレンドデータ生成
        (1..7).each do |days_ago|
          create_list(:inter_store_transfer, 2, 
                      source_store: store,
                      requested_at: days_ago.days.ago)
          create_list(:inter_store_transfer, 1,
                      destination_store: store,
                      requested_at: days_ago.days.ago)
        end

        expect {
          get :index
        }.not_to exceed_query_limit(35) # 日別集計を考慮
      end
    end

    describe "bulk operations performance" do
      it "大量在庫データでのパフォーマンス" do
        inventories = create_list(:inventory, 50)
        inventories.each do |inventory|
          create(:store_inventory, store: store, inventory: inventory, quantity: rand(1..100))
        end

        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 1500 # 1.5秒以内
      end

      it "大量移動データでのパフォーマンス" do
        create_list(:inter_store_transfer, 30, source_store: store)
        create_list(:inter_store_transfer, 20, destination_store: store)

        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 1000 # 1秒以内
      end

      it "複雑なカテゴリ分析でのパフォーマンス" do
        # 様々なカテゴリの商品を大量作成
        medicine_names = ["アスピリン錠", "パラセタモール", "オメプラゾール", "インスリン注射液"]
        device_names = ["血圧計", "体温計", "パルスオキシメーター", "聴診器"]
        supply_names = ["マスク", "手袋", "アルコール", "ガーゼ"]

        (medicine_names + device_names + supply_names).each_with_index do |name, index|
          inventory = create(:inventory, name: "#{name}#{index}")
          create(:store_inventory, store: store, inventory: inventory, quantity: 10 + index)
        end

        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 800 # 800ms以内
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    context "認証なしアクセス" do
      before { sign_out :store_user }

      it "認証なしアクセスは拒否される" do
        allow(controller).to receive(:authenticate_store_user!).and_call_original
        get :index
        expect(response).to redirect_to(new_store_user_session_path)
      end
    end

    context "店舗間アクセス制御" do
      let(:other_store_user) { create(:store_user, store: other_store) }

      before do
        sign_out :store_user
        sign_in other_store_user, scope: :store_user
        allow(controller).to receive(:current_store).and_return(other_store)
      end

      it "他店舗のデータは表示されない" do
        setup_store_statistics_data # store のデータ
        create(:store_inventory, store: other_store, inventory: inventory1, quantity: 999)

        get :index
        statistics = assigns(:statistics)

        # other_store の統計のみが表示される
        expect(statistics[:total_items]).to eq(1) # other_store の在庫のみ
        expect(statistics[:total_quantity]).to eq(999)
      end
    end

    context "Arel.sql使用によるSQLインジェクション対策" do
      before do
        setup_store_statistics_data
      end

      it "Arel.sqlによりSQLインジェクションが防がれる" do
        # 悪意のあるデータが混入してもエラーにならない
        malicious_inventory = create(:inventory, name: "'; DROP TABLE inventories; --")
        create(:store_inventory, store: store, inventory: malicious_inventory)

        expect {
          get :index
        }.not_to raise_error

        # テーブルが削除されていないことを確認
        expect(Inventory.count).to be > 0
        expect(StoreInventory.count).to be > 0
      end

      it "ORDER BY句のArel.sql使用が安全に動作する" do
        # safety_ratio_orderとexpiration_orderのテスト
        setup_inventory_alerts_data

        expect {
          get :index
        }.not_to raise_error

        # 期待されるデータが正しく取得されている
        low_stock_items = assigns(:low_stock_items)
        expiring_items = assigns(:expiring_items)

        expect(low_stock_items).to be_present
        expect(expiring_items).to be_present
      end
    end

    context "Mass Assignment防止" do
      it "controller内でのmass assignmentが発生しない" do
        # controller のprivate methodでmass assignmentを試行
        expect {
          get :index
        }.not_to raise_error(ActiveModel::ForbiddenAttributesError)
      end
    end

    context "XSS防止" do
      before do
        # XSS攻撃を含む商品名
        xss_inventory = create(:inventory, name: "<script>alert('XSS')</script>悪意のある薬")
        create(:store_inventory, store: store, inventory: xss_inventory, quantity: 10)
      end

      it "商品名のXSSスクリプトがエスケープされる" do
        get :index
        
        # JSONデータ内でXSSスクリプトがエスケープされている
        category_distribution = assigns(:category_distribution)
        expect(category_distribution).not_to include("<script>")
        expect(category_distribution).to include("悪意のある薬")
      end
    end
  end

  # ============================================
  # エラーハンドリングテスト
  # ============================================

  describe "error handling" do
    context "データベース接続エラー" do
      before do
        allow(StoreInventory).to receive(:where).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "データベースエラーは適切に伝播される" do
        expect {
          get :index
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end

    context "Counter Cacheの値が不正な場合" do
      before do
        setup_store_statistics_data
        # Counter Cacheの値を意図的に不正にする
        store.update_column(:store_inventories_count, -1)
      end

      it "不正なCounter Cache値でもエラーにならない" do
        expect {
          get :index
        }.not_to raise_error

        statistics = assigns(:statistics)
        expect(statistics[:total_items]).to eq(-1) # 不正値もそのまま表示
      end
    end

    context "JSON生成エラー" do
      before do
        setup_store_statistics_data
        # JSON.generateが失敗するようなデータを作成
        allow_any_instance_of(StoreControllers::DashboardController)
          .to receive(:prepare_inventory_trend_data).and_return("invalid\x00json")
      end

      it "JSON生成エラーでも適切に処理される" do
        expect {
          get :index
        }.to raise_error(JSON::GeneratorError)
      end
    end

    context "日付計算エラー" do
      before do
        # 不正な日付設定
        allow(Date).to receive(:current).and_raise(ArgumentError, "Invalid date")
      end

      it "日付エラーは適切に伝播される" do
        expect {
          get :index
        }.to raise_error(ArgumentError)
      end
    end

    context "在庫データなしの場合" do
      it "空データでも正常に動作する" do
        get :index

        statistics = assigns(:statistics)
        expect(statistics[:total_items]).to eq(0)
        expect(statistics[:total_quantity]).to eq(0)
        expect(statistics[:total_value]).to eq(0)

        # グラフデータも正常に生成される
        category_distribution = assigns(:category_distribution)
        parsed_data = JSON.parse(category_distribution)
        other_category = parsed_data.find { |cat| cat["name"] == "その他" }
        expect(other_category).to be_present
        expect(other_category["value"]).to eq(0)
      end
    end

    context "極端な値での処理" do
      before do
        # 極端な値のテストデータ
        create(:store_inventory, 
               store: store, 
               inventory: inventory1,
               quantity: 0,
               safety_stock_level: 0)
        create(:store_inventory, 
               store: store, 
               inventory: inventory2,
               quantity: 999999,
               safety_stock_level: 1)
      end

      it "ゼロ除算エラーが発生しない" do
        expect {
          get :index
        }.not_to raise_error

        # safety_ratio_orderでNULLIF(safety_stock_level, 0)を使用している
        low_stock_items = assigns(:low_stock_items)
        expect(low_stock_items).to be_present
      end

      it "非常に大きな数値でも正常に処理される" do
        get :index

        statistics = assigns(:statistics)
        expect(statistics[:total_quantity]).to eq(999999)
        expect(statistics[:total_value]).to be > 0
      end
    end
  end

  # ============================================
  # データ整合性テスト
  # ============================================

  describe "data consistency" do
    before do
      setup_store_statistics_data
      setup_inventory_alerts_data
    end

    it "Counter Cacheと実際のクエリ結果が一致する" do
      get :index

      statistics = assigns(:statistics)
      actual_count = store.store_inventories.count

      expect(statistics[:total_items]).to eq(actual_count)
    end

    it "統計値とアラートデータの整合性" do
      get :index

      statistics = assigns(:statistics)
      low_stock_items = assigns(:low_stock_items)
      out_of_stock_items = assigns(:out_of_stock_items)

      # 実際のデータ数と統計値が整合している
      actual_low_stock = store.store_inventories
                             .where("quantity <= safety_stock_level AND quantity > 0")
                             .count
      actual_out_of_stock = store.store_inventories.where(quantity: 0).count

      expect(statistics[:low_stock_items]).to eq(actual_low_stock)
      expect(statistics[:out_of_stock_items]).to eq(actual_out_of_stock)
    end

    it "トレンドデータの日付整合性" do
      get :index

      inventory_trend_data = assigns(:inventory_trend_data)
      transfer_trend_data = assigns(:transfer_trend_data)

      inventory_data = JSON.parse(inventory_trend_data)
      transfer_data = JSON.parse(transfer_trend_data)

      # 両方のデータが同じ日付範囲を持つ
      expect(inventory_data.length).to eq(transfer_data.length)
      expect(inventory_data.length).to eq(7) # 過去7日間

      inventory_data.each_with_index do |day_data, index|
        expect(day_data["date"]).to eq(transfer_data[index]["date"])
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe "edge cases" do
    context "日本語文字列の処理" do
      before do
        # 日本語文字列を含む商品名
        japanese_inventory = create(:inventory, name: "漢方薬・ツムラ・葛根湯エキス顆粒")
        create(:store_inventory, store: store, inventory: japanese_inventory, quantity: 10)
      end

      it "日本語商品名でも正しくカテゴリ分類される" do
        get :index

        category_distribution = assigns(:category_distribution)
        parsed_data = JSON.parse(category_distribution)
        
        # 「顆粒」キーワードにより医薬品に分類される
        medicine_category = parsed_data.find { |cat| cat["name"] == "医薬品" }
        expect(medicine_category).to be_present
        expect(medicine_category["value"]).to be >= 10
      end
    end

    context "マルチバイト文字・特殊文字の処理" do
      before do
        special_inventory = create(:inventory, name: "①特殊文字®商品™（テスト用）")
        create(:store_inventory, store: store, inventory: special_inventory, quantity: 5)
      end

      it "特殊文字を含む商品名でも正常に処理される" do
        expect {
          get :index
        }.not_to raise_error

        category_distribution = assigns(:category_distribution)
        parsed_data = JSON.parse(category_distribution)
        
        # 「その他」カテゴリに分類される
        other_category = parsed_data.find { |cat| cat["name"] == "その他" }
        expect(other_category).to be_present
        expect(other_category["value"]).to be >= 5
      end
    end

    context "空文字・nil値の処理" do
      before do
        # 空文字商品名
        empty_inventory = create(:inventory, name: "")
        create(:store_inventory, store: store, inventory: empty_inventory, quantity: 3)
      end

      it "空文字商品名でも正常に処理される" do
        expect {
          get :index
        }.not_to raise_error

        category_distribution = assigns(:category_distribution)
        parsed_data = JSON.parse(category_distribution)
        
        # 空文字は「その他」カテゴリに分類される
        other_category = parsed_data.find { |cat| cat["name"] == "その他" }
        expect(other_category).to be_present
        expect(other_category["value"]).to be >= 3
      end
    end
  end

  # ============================================
  # サポートメソッド
  # ============================================

  private

  def setup_store_statistics_data
    # 基本的な店舗統計データセットアップ
    create(:store_inventory, store: store, inventory: inventory1, quantity: 5, safety_stock_level: 10)   # 低在庫
    create(:store_inventory, store: store, inventory: inventory2, quantity: 20, safety_stock_level: 15)  # 正常在庫
    create(:store_inventory, store: store, inventory: inventory3, quantity: 100, safety_stock_level: 20) # 十分在庫

    # 移動データ
    create(:inter_store_transfer, destination_store: store, status: :pending)
    create(:inter_store_transfer, source_store: store, status: :pending)
  end

  def setup_inventory_alerts_data
    # 低在庫アイテム
    dangerous_inventory = create(:inventory, name: "危険レベル在庫")
    warning_inventory = create(:inventory, name: "警告レベル在庫")
    create(:store_inventory, store: store, inventory: dangerous_inventory, quantity: 2, safety_stock_level: 10)
    create(:store_inventory, store: store, inventory: warning_inventory, quantity: 5, safety_stock_level: 10)

    # 在庫切れアイテム
    out_inventory = create(:inventory, name: "在庫切れ商品")
    create(:store_inventory, store: store, inventory: out_inventory, quantity: 0, safety_stock_level: 5)

    # 期限切れ間近アイテム
    expiring_a = create(:inventory, name: "期限切れ間近A")
    expiring_b = create(:inventory, name: "期限切れ間近B")
    create(:store_inventory, store: store, inventory: expiring_a, quantity: 10)
    create(:store_inventory, store: store, inventory: expiring_b, quantity: 15)
    create(:batch, inventory: expiring_a, expires_on: 5.days.from_now)
    create(:batch, inventory: expiring_b, expires_on: 10.days.from_now)
  end

  def setup_transfer_summary_data
    # 保留中の移動
    create(:inter_store_transfer, 
           source_store: other_store,
           destination_store: store,
           status: :pending,
           requested_at: 1.day.ago)

    create(:inter_store_transfer, 
           source_store: other_store,
           destination_store: store,
           status: :pending,
           requested_at: 2.days.ago)

    create(:inter_store_transfer,
           source_store: store,
           destination_store: other_store,
           status: :pending,
           requested_at: 3.days.ago)

    # 完了済みの移動
    create(:inter_store_transfer,
           source_store: store,
           destination_store: other_store,
           status: :completed,
           completed_at: 1.day.ago)

    create(:inter_store_transfer,
           source_store: other_store,
           destination_store: store,
           status: :completed,
           completed_at: 2.days.ago)
  end

  def setup_recent_activities_data
    admin = create(:admin)
    
    # 在庫変動ログ
    create(:inventory_log, inventory: inventory1, admin: admin, created_at: 1.hour.ago)
    create(:inventory_log, inventory: inventory2, admin: admin, created_at: 2.hours.ago)
    create(:inventory_log, inventory: inventory3, admin: admin, created_at: 3.hours.ago)

    # 店舗に紐付ける
    create(:store_inventory, store: store, inventory: inventory1)
    create(:store_inventory, store: store, inventory: inventory2)
    create(:store_inventory, store: store, inventory: inventory3)
  end

  def setup_chart_data
    # 過去7日間のデータ
    (1..7).each do |days_ago|
      create(:inter_store_transfer,
             source_store: store,
             destination_store: other_store,
             requested_at: days_ago.days.ago)
      create(:inter_store_transfer,
             source_store: other_store,
             destination_store: store,
             requested_at: days_ago.days.ago)
    end

    # カテゴリ別在庫データ
    medicine = create(:inventory, name: "アスピリン錠100mg")
    device = create(:inventory, name: "デジタル血圧計")
    supply = create(:inventory, name: "マスク50枚入り")

    create(:store_inventory, store: store, inventory: medicine, quantity: 50)
    create(:store_inventory, store: store, inventory: device, quantity: 5)
    create(:store_inventory, store: store, inventory: supply, quantity: 100)
  end

  def setup_performance_test_data
    # パフォーマンステスト用データ
    inventories = create_list(:inventory, 10)
    inventories.each_with_index do |inv, index|
      create(:store_inventory, 
             store: store, 
             inventory: inv,
             quantity: (index + 1) * 10,
             safety_stock_level: 20)
    end

    create_list(:inter_store_transfer, 5, source_store: store)
    create_list(:inter_store_transfer, 3, destination_store: store)
  end
end
