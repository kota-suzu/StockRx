# frozen_string_literal: true

require "rails_helper"

RSpec.describe "StoreInventories", type: :request do
  let(:store) { create(:store, active: true) }
  let(:inactive_store) { create(:store, active: false) }

  describe "GET /stores/:store_id/inventories" do
    before do
      # テストデータの作成
      5.times do
        inventory = create(:inventory, status: :active)
        create(:store_inventory, store: store, inventory: inventory, quantity: rand(0..100))
      end
    end

    context "HTML形式のリクエスト" do
      it "正常に在庫一覧を表示する" do
        get store_inventories_path(store)

        expect(response).to have_http_status(:success)
        expect(response.body).to include(store.name)
        expect(response.body).to include("在庫一覧")
      end

      it "統計情報を表示する" do
        get store_inventories_path(store)

        expect(response.body).to include("取扱商品数")
        expect(response.body).to include("カテゴリ数")
        expect(response.body).to include("最終更新")
      end

      it "検索フォームを含む" do
        get store_inventories_path(store)

        expect(response.body).to include("商品名・SKUで検索")
        expect(response.body).to include("検索")
      end

      it "在庫状態バッジを表示する" do
        # 在庫切れ商品を作成
        out_of_stock = create(:inventory, status: :active)
        create(:store_inventory, store: store, inventory: out_of_stock, quantity: 0)

        get store_inventories_path(store)

        expect(response.body).to include("在庫切れ")
      end
    end

    context "JSON形式のリクエスト" do
      it "JSON形式でデータを返す" do
        get store_inventories_path(store, format: :json)

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json).to include(
          "store" => hash_including("id" => store.id, "name" => store.name),
          "statistics" => hash_including("total_items", "categories"),
          "inventories" => be_an(Array),
          "pagination" => hash_including("current_page", "total_pages")
        )
      end

      it "機密情報（価格など）を含まない" do
        get store_inventories_path(store, format: :json)

        json = JSON.parse(response.body)
        inventory_data = json["inventories"].first

        expect(inventory_data).not_to have_key("price")
        expect(inventory_data).not_to have_key("cost")
        expect(inventory_data).not_to have_key("supplier")
      end
    end

    context "エラーハンドリング" do
      it "存在しない店舗の場合404を返す" do
        get store_inventories_path(999999)

        expect(response).to redirect_to(stores_path)
        follow_redirect!
        expect(response.body).to include("指定された店舗が見つかりません")
      end

      it "非アクティブな店舗の場合アクセスを拒否する" do
        get store_inventories_path(inactive_store)

        expect(response).to redirect_to(stores_path)
        follow_redirect!
        expect(response.body).to include("この店舗は現在利用できません")
      end
    end

    context "ページネーション" do
      before do
        # 30件の在庫を追加
        30.times do
          inventory = create(:inventory, status: :active)
          create(:store_inventory, store: store, inventory: inventory)
        end
      end

      it "ページ指定が機能する" do
        get store_inventories_path(store, page: 2)

        expect(response).to have_http_status(:success)
        expect(response.body).to include("page=2")
      end

      it "1ページあたりの表示件数を制限する" do
        get store_inventories_path(store, per_page: 100, format: :json)

        json = JSON.parse(response.body)
        # 最大50件に制限される
        expect(json["inventories"].count).to be <= 50
      end
    end

    context "ソート機能" do
      before do
        create(:store_inventory,
               store: store,
               inventory: create(:inventory, name: "AAA商品", status: :active))
        create(:store_inventory,
               store: store,
               inventory: create(:inventory, name: "ZZZ商品", status: :active))
      end

      it "商品名でソートできる" do
        get store_inventories_path(store, sort: "inventories.name", direction: "asc", format: :json)

        json = JSON.parse(response.body)
        names = json["inventories"].map { |i| i["name"] }

        expect(names.first).to include("AAA")
        expect(names.last).to include("ZZZ")
      end

      it "不正なソートパラメータは無視される" do
        get store_inventories_path(store, sort: "inventories.price", format: :json)

        expect(response).to have_http_status(:success)
        # デフォルトのソート（name）が適用される
      end
    end
  end

  describe "GET /stores/:store_id/inventories/search" do
    let!(:test_inventory) { create(:inventory, name: "テスト薬品ABC", sku: "TEST123", status: :active) }

    before do
      create(:store_inventory, store: store, inventory: test_inventory)
    end

    it "商品名で検索できる" do
      get search_store_inventories_path(store, q: "テスト", format: :json)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json["count"]).to eq(1)
      expect(json["items"].first["name"]).to eq("テスト薬品ABC")
    end

    it "SKUで検索できる" do
      get search_store_inventories_path(store, q: "TEST", format: :json)

      json = JSON.parse(response.body)
      expect(json["count"]).to eq(1)
    end

    it "検索結果が0件の場合も正常に処理する" do
      get search_store_inventories_path(store, q: "存在しない商品", format: :json)

      json = JSON.parse(response.body)
      expect(json["count"]).to eq(0)
      expect(json["items"]).to be_empty
    end

    it "空の検索キーワードはエラーを返す" do
      get search_store_inventories_path(store, q: "", format: :json)

      expect(response).to have_http_status(:bad_request)
      json = JSON.parse(response.body)
      expect(json["error"]).to be_present
    end

    it "特殊文字を含む検索でもエラーにならない" do
      get search_store_inventories_path(store, q: "%_\\", format: :json)

      expect(response).to have_http_status(:success)
    end
  end

  # TODO: Phase 3 - セキュリティテストの追加
  #   - レート制限の統合テスト
  #   - XSS/SQLインジェクション対策の確認
  #   - セッションハイジャック対策

  # TODO: Phase 4 - パフォーマンステストの追加
  #   - 大量データでの応答時間
  #   - 同時アクセス時の挙動
  #   - キャッシュの効果測定
end
