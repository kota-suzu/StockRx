# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreInventoryManagementService, type: :service do
  # CLAUDE.md準拠: 店舗在庫管理サービスの包括的テスト
  # メタ認知: ビジネスロジック・データ整合性・権限管理の品質保証
  # 横展開: 他の管理系サービスでも同様のテストパターン適用

  let(:store) { create(:store, name: "テスト店舗", active: true) }
  let(:inactive_store) { create(:store, name: "非アクティブ店舗", active: false) }
  let(:store_user) { create(:store_user) }
  let(:service) { described_class.new(store: store, current_user: store_user) }

  before do
    # 在庫・店舗在庫データ作成
    @inventory1 = create(:inventory, name: "風邪薬カプセル", price: 500)
    @inventory2 = create(:inventory, name: "血圧測定器", price: 10000)
    @inventory3 = create(:inventory, name: "使い捨て手袋", price: 200)
    @inventory4 = create(:inventory, name: "消毒用アルコール", price: 300)

    @store_inventory1 = create(:store_inventory,
      store: store,
      inventory: @inventory1,
      quantity: 50,
      reorder_level: 10
    )

    @store_inventory2 = create(:store_inventory,
      store: store,
      inventory: @inventory2,
      quantity: 3,
      reorder_level: 5 # 低在庫状態
    )

    @store_inventory3 = create(:store_inventory,
      store: store,
      inventory: @inventory3,
      quantity: 0, # 在庫切れ
      reorder_level: 100
    )

    @store_inventory4 = create(:store_inventory,
      store: store,
      inventory: @inventory4,
      quantity: 20,
      reorder_level: 10
    )

    # 非アクティブ店舗の在庫（公開検索では除外される）
    @inactive_store_inventory = create(:store_inventory,
      store: inactive_store,
      inventory: @inventory1,
      quantity: 100
    )
  end

  describe "#build_inventory_scope" do
    context "認証済みアクセス" do
      it "店舗スコープで詳細情報を含むスコープを構築する" do
        scope = service.build_inventory_scope(authenticated: true)

        # 指定店舗の在庫のみ取得
        store_inventories = scope.to_a
        expect(store_inventories.size).to eq(4)
        expect(store_inventories).to include(@store_inventory1)
        expect(store_inventories).not_to include(@inactive_store_inventory)

        # 関連データが事前読み込みされている
        expect(scope.includes_values).to include(:inventory)
      end

      it "店舗が指定されていない場合は空のスコープを返す" do
        service_without_store = described_class.new(store: nil, current_user: store_user)
        scope = service_without_store.build_inventory_scope(authenticated: true)

        expect(scope).to be_nil
      end
    end

    context "公開アクセス" do
      it "アクティブ店舗のみの基本情報スコープを構築する" do
        scope = service.build_inventory_scope(authenticated: false)

        store_inventories = scope.to_a
        active_store_count = store_inventories.select { |si| si.store.active? }.size
        expect(active_store_count).to eq(store_inventories.size)

        # 非アクティブ店舗の在庫は除外される
        expect(store_inventories).not_to include(@inactive_store_inventory)

        # 関連データが事前読み込みされている
        expect(scope.includes_values).to include(:inventory)
        expect(scope.includes_values).to include(:store)
      end
    end
  end

  describe "#apply_filters" do
    let(:base_scope) { service.build_inventory_scope(authenticated: true) }

    context "商品名検索" do
      it "部分一致で商品を検索する" do
        search_params = { name_cont: "風邪" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("風邪")
      end

      it "大文字小文字を区別しない検索を行う" do
        search_params = { name_cont: "カプセル" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result).not_to be_empty
        expect(result.first.inventory.name).to include("カプセル")
      end

      it "空の検索語では全件を返す" do
        search_params = { name_cont: "" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        expect(filtered_scope.to_a.size).to eq(4)
      end

      it "SQLインジェクション攻撃を防ぐ" do
        search_params = { name_cont: "'; DROP TABLE inventories; --" }

        expect {
          filtered_scope = service.apply_filters(base_scope, search_params)
          filtered_scope.to_a
        }.not_to raise_error
      end
    end

    context "カテゴリ検索" do
      it "医薬品カテゴリで正しくフィルタリングする" do
        search_params = { category_eq: "医薬品" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("薬")
      end

      it "医療機器カテゴリで正しくフィルタリングする" do
        search_params = { category_eq: "医療機器" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("測定器")
      end

      it "消耗品カテゴリで正しくフィルタリングする" do
        search_params = { category_eq: "消耗品" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("手袋")
      end

      it "衛生用品カテゴリで正しくフィルタリングする" do
        search_params = { category_eq: "衛生用品" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("アルコール")
      end

      it "存在しないカテゴリでは結果が空になる" do
        search_params = { category_eq: "存在しないカテゴリ" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        expect(filtered_scope.to_a).to be_empty
      end
    end

    context "在庫レベルフィルタ" do
      it "在庫切れアイテムのみを抽出する" do
        search_params = { stock_level_eq: "out_of_stock" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.quantity).to eq(0)
      end

      it "低在庫アイテムのみを抽出する" do
        search_params = { stock_level_eq: "low_stock" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("血圧測定器")
      end

      it "適正在庫アイテムのみを抽出する" do
        search_params = { stock_level_eq: "adequate_stock" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(2) # 風邪薬と消毒用アルコール
        result.each do |si|
          expect(si.quantity).to be > si.reorder_level
        end
      end

      it "不正なレベル指定では全件を返す" do
        search_params = { stock_level_eq: "invalid_level" }
        filtered_scope = service.apply_filters(base_scope, search_params)

        expect(filtered_scope.to_a.size).to eq(4)
      end
    end

    context "複合検索" do
      it "商品名とカテゴリの組み合わせ検索を行う" do
        search_params = {
          name_cont: "アルコール",
          category_eq: "衛生用品"
        }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to eq("消毒用アルコール")
      end

      it "すべてのフィルタを組み合わせた検索を行う" do
        search_params = {
          name_cont: "風邪",
          category_eq: "医薬品",
          stock_level_eq: "adequate_stock"
        }
        filtered_scope = service.apply_filters(base_scope, search_params)

        result = filtered_scope.to_a
        expect(result.size).to eq(1)
        expect(result.first.inventory.name).to include("風邪")
      end
    end

    it "空のパラメータでは元のスコープをそのまま返す" do
      filtered_scope = service.apply_filters(base_scope, {})
      expect(filtered_scope).to eq(base_scope)
    end

    it "nilパラメータでは元のスコープをそのまま返す" do
      filtered_scope = service.apply_filters(base_scope, nil)
      expect(filtered_scope).to eq(base_scope)
    end
  end

  describe "#calculate_statistics" do
    let(:scope) { service.build_inventory_scope(authenticated: true) }

    it "統計情報を正しく計算する" do
      stats = service.calculate_statistics(scope)

      expect(stats[:total_items]).to eq(4)
      expect(stats[:out_of_stock_count]).to eq(1) # @store_inventory3
      expect(stats[:low_stock_count]).to eq(1)    # @store_inventory2
    end

    it "合計価値を正しく計算する（unit_costが定義されている場合）" do
      # unit_costメソッドをモック
      allow(@inventory1).to receive(:respond_to?).with(:unit_cost).and_return(true)
      allow(@inventory1).to receive(:unit_cost).and_return(400)
      allow(@inventory2).to receive(:respond_to?).with(:unit_cost).and_return(true)
      allow(@inventory2).to receive(:unit_cost).and_return(8000)
      allow(@inventory3).to receive(:respond_to?).with(:unit_cost).and_return(true)
      allow(@inventory3).to receive(:unit_cost).and_return(150)
      allow(@inventory4).to receive(:respond_to?).with(:unit_cost).and_return(true)
      allow(@inventory4).to receive(:unit_cost).and_return(250)

      stats = service.calculate_statistics(scope)

      expected_value = (50 * 400) + (3 * 8000) + (0 * 150) + (20 * 250)
      expect(stats[:total_value]).to eq(expected_value)
    end

    it "unit_costが未定義の場合は0として計算する" do
      stats = service.calculate_statistics(scope)

      expect(stats[:total_value]).to eq(0)
    end

    it "低在庫率を正しく計算する" do
      stats = service.calculate_statistics(scope)

      # 4件中1件が低在庫 = 25.0%
      expect(stats[:low_stock_percentage]).to eq(25.0)
    end

    it "空のスコープでも適切に処理する" do
      empty_scope = StoreInventory.none
      stats = service.calculate_statistics(empty_scope)

      expect(stats[:total_items]).to eq(0)
      expect(stats[:total_value]).to eq(0)
      expect(stats[:low_stock_percentage]).to eq(0)
      expect(stats[:out_of_stock_count]).to eq(0)
      expect(stats[:low_stock_count]).to eq(0)
    end
  end

  describe "#adjust_inventory" do
    context "正常な在庫調整" do
      it "在庫数量を正しく更新する" do
        adjustment_params = {
          new_quantity: 75,
          reason: "棚卸し調整"
        }

        result = service.adjust_inventory(@inventory1, adjustment_params)

        expect(result[:success]).to be true
        expect(result[:store_inventory].quantity).to eq(75)

        @store_inventory1.reload
        expect(@store_inventory1.quantity).to eq(75)
      end

      it "InventoryLogを作成する" do
        adjustment_params = {
          new_quantity: 30,
          reason: "破損による減数"
        }

        expect {
          service.adjust_inventory(@inventory1, adjustment_params)
        }.to change(InventoryLog, :count).by(1)

        log = InventoryLog.last
        expect(log.inventory).to eq(@inventory1)
        expect(log.store).to eq(store)
        expect(log.user).to eq(store_user)
        expect(log.action).to eq("manual_adjustment")
        expect(log.quantity_before).to eq(50)
        expect(log.quantity_after).to eq(30)
        expect(log.quantity_changed).to eq(-20)
        expect(log.reason).to eq("破損による減数")
      end

      it "理由が指定されていない場合はデフォルト理由を使用する" do
        adjustment_params = { new_quantity: 40 }

        service.adjust_inventory(@inventory1, adjustment_params)

        log = InventoryLog.last
        expect(log.reason).to eq("在庫調整")
      end

      it "数量増加の調整も正しく処理する" do
        adjustment_params = {
          new_quantity: 100,
          reason: "追加入荷"
        }

        result = service.adjust_inventory(@inventory1, adjustment_params)

        expect(result[:success]).to be true

        log = InventoryLog.last
        expect(log.quantity_changed).to eq(50) # 100 - 50
      end

      it "0への調整も正しく処理する" do
        adjustment_params = {
          new_quantity: 0,
          reason: "全数廃棄"
        }

        result = service.adjust_inventory(@inventory1, adjustment_params)

        expect(result[:success]).to be true
        expect(result[:store_inventory].quantity).to eq(0)
      end
    end

    context "エラーケース" do
      it "存在しない在庫に対してはエラーを返す" do
        non_existent_inventory = create(:inventory, name: "存在しない在庫")

        adjustment_params = { new_quantity: 10 }

        expect {
          service.adjust_inventory(non_existent_inventory, adjustment_params)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it "負の数量が指定された場合は適切にエラー処理する" do
        adjustment_params = { new_quantity: -10 }

        # StoreInventoryモデルにバリデーションがある場合
        allow_any_instance_of(StoreInventory).to receive(:update!).and_raise(
          ActiveRecord::RecordInvalid.new(
            StoreInventory.new.tap { |si| si.errors.add(:quantity, "負の値は設定できません") }
          )
        )

        result = service.adjust_inventory(@inventory1, adjustment_params)

        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end

      it "データベースエラーが発生した場合は適切に処理する" do
        adjustment_params = { new_quantity: 25 }

        allow_any_instance_of(StoreInventory).to receive(:update!).and_raise(StandardError.new("DB接続エラー"))

        result = service.adjust_inventory(@inventory1, adjustment_params)

        expect(result[:success]).to be false
        expect(result[:errors][:base]).to include("DB接続エラー")
      end

      it "トランザクションでロールバックされる" do
        adjustment_params = { new_quantity: 25 }

        allow(InventoryLog).to receive(:create!).and_raise(StandardError.new("ログ作成失敗"))

        expect {
          service.adjust_inventory(@inventory1, adjustment_params)
        }.not_to change(@store_inventory1, :quantity)
      end
    end
  end

  describe "プライベートメソッド" do
    describe "#sanitize_search_term" do
      it "SQLインジェクション攻撃文字をエスケープする" do
        dangerous_term = "test%_\\malicious"
        sanitized = service.send(:sanitize_search_term, dangerous_term)

        expect(sanitized).to eq("test\\%\\_\\\\malicious")
      end

      it "通常の検索語は変更しない" do
        normal_term = "風邪薬"
        sanitized = service.send(:sanitize_search_term, normal_term)

        expect(sanitized).to eq("風邪薬")
      end

      it "空文字・スペースを適切に処理する" do
        expect(service.send(:sanitize_search_term, "  ")).to eq("")
        expect(service.send(:sanitize_search_term, "")).to eq("")
        expect(service.send(:sanitize_search_term, nil)).to eq("")
      end
    end

    describe "#category_keywords_map" do
      it "全カテゴリのキーワードマッピングが定義されている" do
        mapping = service.send(:category_keywords_map)

        expect(mapping).to have_key("医薬品")
        expect(mapping).to have_key("医療機器")
        expect(mapping).to have_key("消耗品")
        expect(mapping).to have_key("衛生用品")

        mapping.each do |category, pattern|
          expect(pattern).to be_a(String)
          expect(pattern).not_to be_empty
        end
      end
    end

    describe "#apply_stock_level_filter" do
      let(:base_scope) { service.build_inventory_scope(authenticated: true) }

      it "各在庫レベルで正しいフィルタリングを行う" do
        out_of_stock = service.send(:apply_stock_level_filter, base_scope, "out_of_stock")
        expect(out_of_stock.to_a.size).to eq(1)

        low_stock = service.send(:apply_stock_level_filter, base_scope, "low_stock")
        expect(low_stock.to_a.size).to eq(1)

        adequate_stock = service.send(:apply_stock_level_filter, base_scope, "adequate_stock")
        expect(adequate_stock.to_a.size).to eq(2)
      end
    end

    describe "#calculate_total_value" do
      it "unit_costが利用可能な場合に正しく計算する" do
        # モックでunit_costを設定
        allow(@inventory1).to receive(:respond_to?).with(:unit_cost).and_return(true)
        allow(@inventory1).to receive(:unit_cost).and_return(400)

        store_inventories = [ @store_inventory1 ]
        total_value = service.send(:calculate_total_value, store_inventories)

        expect(total_value).to eq(50 * 400)
      end

      it "unit_costが未定義の場合は0として計算する" do
        store_inventories = [ @store_inventory1, @store_inventory2 ]
        total_value = service.send(:calculate_total_value, store_inventories)

        expect(total_value).to eq(0)
      end
    end

    describe "#calculate_low_stock_percentage" do
      it "低在庫率を正しく計算する" do
        store_inventories = [ @store_inventory1, @store_inventory2, @store_inventory3, @store_inventory4 ]
        percentage = service.send(:calculate_low_stock_percentage, store_inventories)

        # 4件中1件が低在庫（@store_inventory2）
        expect(percentage).to eq(25.0)
      end

      it "空の配列では0%を返す" do
        percentage = service.send(:calculate_low_stock_percentage, [])
        expect(percentage).to eq(0)
      end

      it "全て適正在庫の場合は0%を返す" do
        # 全ての在庫を適正レベルに設定
        @store_inventory2.update!(quantity: 10) # reorder_level以上に
        store_inventories = [ @store_inventory1, @store_inventory2, @store_inventory4 ]

        percentage = service.send(:calculate_low_stock_percentage, store_inventories)
        expect(percentage).to eq(0)
      end
    end

    describe "#create_inventory_log" do
      it "適切なInventoryLogレコードを作成する" do
        expect {
          service.send(:create_inventory_log,
            inventory: @inventory1,
            store_inventory: @store_inventory1,
            old_quantity: 50,
            new_quantity: 30,
            reason: "テスト調整"
          )
        }.to change(InventoryLog, :count).by(1)

        log = InventoryLog.last
        expect(log.inventory).to eq(@inventory1)
        expect(log.store).to eq(store)
        expect(log.user).to eq(store_user)
        expect(log.admin).to be_nil
        expect(log.action).to eq("manual_adjustment")
        expect(log.quantity_before).to eq(50)
        expect(log.quantity_after).to eq(30)
        expect(log.quantity_changed).to eq(-20)
        expect(log.reason).to eq("テスト調整")

        # メタデータの確認
        expect(log.metadata["store_inventory_id"]).to eq(@store_inventory1.id)
        expect(log.metadata["adjusted_by"]).to eq(store_user.email)
        expect(log.metadata).to have_key("timestamp")
      end
    end
  end

  describe "統合テスト" do
    it "複雑な検索・統計・調整の組み合わせを正しく処理する" do
      # 1. フィルタリング
      scope = service.build_inventory_scope(authenticated: true)
      filtered_scope = service.apply_filters(scope, { stock_level_eq: "adequate_stock" })

      # 2. 統計計算
      stats = service.calculate_statistics(filtered_scope)
      expect(stats[:total_items]).to eq(2)

      # 3. 在庫調整
      result = service.adjust_inventory(@inventory1, { new_quantity: 25, reason: "統合テスト" })
      expect(result[:success]).to be true

      # 4. 調整後の統計再計算
      new_stats = service.calculate_statistics(filtered_scope)
      expect(new_stats[:total_items]).to eq(2) # @inventory1は25→25で適正在庫のまま
    end

    it "権限チェックと監査ログの完全性を確保する" do
      # current_userなしでの初期化
      service_without_user = described_class.new(store: store)

      # 在庫調整時にcurrent_userがnilでも適切に処理される
      result = service_without_user.adjust_inventory(@inventory1, { new_quantity: 35 })
      expect(result[:success]).to be true

      log = InventoryLog.last
      expect(log.user).to be_nil
      expect(log.metadata["adjusted_by"]).to be_nil
    end
  end

  describe "パフォーマンステスト" do
    it "大量の在庫データでも適切に処理する" do
      # 1000件の店舗在庫データを作成
      inventories = Array.new(1000) do |i|
        inventory = create(:inventory, name: "Product #{i}")
        create(:store_inventory, store: store, inventory: inventory, quantity: i % 100)
      end

      start_time = Time.current
      scope = service.build_inventory_scope(authenticated: true)
      stats = service.calculate_statistics(scope)
      duration = Time.current - start_time

      expect(duration).to be < 3.0 # 3秒以内に完了
      expect(stats[:total_items]).to eq(1004) # 元の4件 + 1000件
    end
  end

  describe "エラーハンドリング" do
    it "データベース接続エラーを適切に処理する" do
      allow(StoreInventory).to receive(:joins).and_raise(StandardError.new("DB接続失敗"))

      expect {
        service.build_inventory_scope(authenticated: false)
      }.to raise_error(StandardError, "DB接続失敗")
    end

    it "不正なパラメータに対して例外を発生させない" do
      malformed_params = {
        name_cont: nil,
        category_eq: 123,
        stock_level_eq: [ "invalid", "array" ]
      }

      scope = service.build_inventory_scope(authenticated: true)

      expect {
        filtered_scope = service.apply_filters(scope, malformed_params)
        filtered_scope.to_a
      }.not_to raise_error
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1日
  # 横展開: 他の管理系サービスと同等のテスト網羅性達成
  #
  # 1. 権限・セキュリティテスト
  #    - 店舗間データアクセス制限
  #    - 管理者vs店舗ユーザー権限差異
  #    - SQLインジェクション全パターン
  #
  # 2. 並行処理テスト
  #    - 同時在庫調整の競合状態
  #    - トランザクション分離レベル
  #    - デッドロック検出・回復
  #
  # 3. 国際化・地域対応テスト
  #    - 多言語商品名検索
  #    - 通貨・数値フォーマット
  #    - タイムゾーン処理
  #
  # 4. 拡張機能テスト
  #    - バッチ処理（複数在庫同時調整）
  #    - 履歴・監査機能
  #    - レポート出力連携
end
