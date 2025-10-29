# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvExportService, type: :service do
  # CLAUDE.md準拠: CSV出力サービスの包括的テスト
  # メタ認知: データ変換・フォーマット・監査ログの品質保証
  # 横展開: 他のエクスポート系サービスでも同様のテストパターン適用

  let(:store) { create(:store, name: "テスト店舗") }
  let(:admin) { create(:admin) }
  let(:service) { described_class.new(store: store, current_user: admin) }

  before do
    # 在庫・店舗在庫データ作成
    @inventory1 = create(:inventory, name: "風邪薬カプセル", price: 500)
    @inventory2 = create(:inventory, name: "血圧測定器", price: 10000)
    @inventory3 = create(:inventory, name: "使い捨て手袋", price: 200)

    @store_inventory1 = create(:store_inventory,
      store: store,
      inventory: @inventory1,
      quantity: 50,
      reserved_quantity: 5,
      reorder_level: 10
    )

    @store_inventory2 = create(:store_inventory,
      store: store,
      inventory: @inventory2,
      quantity: 3,
      reserved_quantity: 1,
      reorder_level: 2
    )

    @store_inventory3 = create(:store_inventory,
      store: store,
      inventory: @inventory3,
      quantity: 0,
      reserved_quantity: 0,
      reorder_level: 100
    )

    # Currentクラスのモック
    allow(Current).to receive(:request).and_return(
      double(remote_ip: "192.168.1.1", user_agent: "RSpec Test Agent")
    )

    # ログモック
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "#generate_inventory_csv" do
    context "正常なCSV生成" do
      it "適切なCSVデータを生成する" do
        store_inventories = [ @store_inventory1, @store_inventory2, @store_inventory3 ]
        csv_data = service.generate_inventory_csv(store_inventories)

        expect(csv_data).to be_a(String)
        expect(csv_data).to include("店舗名,商品ID,商品名")
        expect(csv_data).to include("テスト店舗")
        expect(csv_data).to include("風邪薬カプセル")
        expect(csv_data).to include("血圧測定器")
        expect(csv_data).to include("使い捨て手袋")
      end

      it "CSVヘッダーが正しく設定される" do
        csv_data = service.generate_inventory_csv([ @store_inventory1 ])
        lines = csv_data.split("\n")
        header = lines.first

        expect(header).to include("店舗名")
        expect(header).to include("商品ID")
        expect(header).to include("商品名")
        expect(header).to include("カテゴリ")
        expect(header).to include("現在在庫")
        expect(header).to include("予約済み在庫")
        expect(header).to include("利用可能在庫")
        expect(header).to include("発注点")
        expect(header).to include("在庫状態")
        expect(header).to include("回転日数")
        expect(header).to include("最終更新日")
        expect(header).to include("備考")
      end

      it "データ行が正しくフォーマットされる" do
        csv_data = service.generate_inventory_csv([ @store_inventory1 ])
        lines = csv_data.split("\n")
        data_line = lines[1]

        expect(data_line).to include("テスト店舗")
        expect(data_line).to include(@inventory1.id.to_s)
        expect(data_line).to include("風邪薬カプセル")
        expect(data_line).to include("医薬品")  # カテゴリ推定
        expect(data_line).to include("50")      # 現在在庫
        expect(data_line).to include("5")       # 予約済み
        expect(data_line).to include("45")      # 利用可能在庫
        expect(data_line).to include("10")      # 発注点
        expect(data_line).to include("適正在庫") # 在庫状態
      end

      it "空のコレクションでも適切に処理する" do
        csv_data = service.generate_inventory_csv([])

        expect(csv_data).to be_a(String)
        expect(csv_data).to include("店舗名,商品ID,商品名")
        expect(csv_data.split("\n").size).to eq(1) # ヘッダーのみ
      end

      it "監査ログが記録される" do
        expect(Rails.logger).to receive(:info).with(
          hash_including(
            event: "csv_export",
            user_id: admin.id,
            store_id: store.id,
            record_count: 2
          ).to_json
        )

        service.generate_inventory_csv([ @store_inventory1, @store_inventory2 ])
      end
    end

    context "UTF-8エンコーディング" do
      it "日本語文字が正しく処理される" do
        japanese_inventory = create(:inventory, name: "漢方薬：桂枝湯エキス顆粒")
        japanese_store_inventory = create(:store_inventory,
          store: store,
          inventory: japanese_inventory,
          quantity: 10
        )

        csv_data = service.generate_inventory_csv([ japanese_store_inventory ])

        expect(csv_data.encoding).to eq(Encoding::UTF_8)
        expect(csv_data).to include("漢方薬：桂枝湯エキス顆粒")
      end
    end
  end

  describe "#generate_inventory_csv_stream" do
    context "ストリーミングCSV生成" do
      it "Enumeratorを返す（ブロックなし）" do
        store_inventories = StoreInventory.where(id: [ @store_inventory1.id, @store_inventory2.id ])
        result = service.generate_inventory_csv_stream(store_inventories)

        expect(result).to be_a(Enumerator)
        lines = result.to_a
        expect(lines.first).to include("店舗名,商品ID,商品名")
        expect(lines.size).to eq(3) # ヘッダー + 2データ行
      end

      it "ブロック付きで呼び出される場合" do
        store_inventories = StoreInventory.where(id: [ @store_inventory1.id, @store_inventory2.id ])
        lines = []

        service.generate_inventory_csv_stream(store_inventories) do |line|
          lines << line
        end

        expect(lines.first).to include("店舗名,商品ID,商品名")
        expect(lines.size).to eq(3) # ヘッダー + 2データ行
      end

      it "大量データでGCが呼ばれる" do
        # バッチサイズを小さくしてテスト
        allow(service).to receive(:batch_size).and_return(2)
        store_inventories = StoreInventory.where(id: [ @store_inventory1.id, @store_inventory2.id ])

        expect(GC).to receive(:start).at_least(:once)

        service.generate_inventory_csv_stream(store_inventories).to_a
      end

      it "監査ログが記録される" do
        store_inventories = StoreInventory.where(id: [ @store_inventory1.id ])

        expect(Rails.logger).to receive(:info).with(
          hash_including(
            event: "csv_export",
            user_id: admin.id,
            store_id: store.id,
            record_count: 1
          ).to_json
        )

        service.generate_inventory_csv_stream(store_inventories).to_a
      end
    end
  end

  describe "#generate_filename" do
    it "デフォルトのプレフィックスでファイル名を生成する" do
      allow(Time).to receive(:current).and_return(Time.parse("2024-12-25 14:30:45"))

      filename = service.generate_filename

      expect(filename).to eq("inventory_export_store_#{store.id}_20241225_143045.csv")
    end

    it "カスタムプレフィックスでファイル名を生成する" do
      allow(Time).to receive(:current).and_return(Time.parse("2024-12-25 14:30:45"))

      filename = service.generate_filename(prefix: "custom_export")

      expect(filename).to eq("custom_export_store_#{store.id}_20241225_143045.csv")
    end

    it "店舗指定なしの場合に適切なファイル名を生成する" do
      service_without_store = described_class.new(current_user: admin)
      allow(Time).to receive(:current).and_return(Time.parse("2024-12-25 14:30:45"))

      filename = service_without_store.generate_filename

      expect(filename).to eq("inventory_export_all_stores_20241225_143045.csv")
    end
  end

  describe "プライベートメソッド" do
    describe "#calculate_available_quantity" do
      it "利用可能在庫を正しく計算する" do
        available = service.send(:calculate_available_quantity, @store_inventory1)
        expect(available).to eq(45) # 50 - 5
      end

      it "予約済み在庫がnilの場合を適切に処理する" do
        @store_inventory1.reserved_quantity = nil
        available = service.send(:calculate_available_quantity, @store_inventory1)
        expect(available).to eq(50)
      end

      it "負の値にならないよう制限する" do
        @store_inventory1.quantity = 5
        @store_inventory1.reserved_quantity = 10
        available = service.send(:calculate_available_quantity, @store_inventory1)
        expect(available).to eq(0)
      end
    end

    describe "#categorize_by_name" do
      it "医薬品カテゴリを正しく判定する" do
        expect(service.send(:categorize_by_name, "風邪薬")).to eq("医薬品")
        expect(service.send(:categorize_by_name, "解熱鎮痛剤錠")).to eq("医薬品")
        expect(service.send(:categorize_by_name, "目薬")).to eq("医薬品")
        expect(service.send(:categorize_by_name, "軟膏")).to eq("医薬品")
      end

      it "医療機器カテゴリを正しく判定する" do
        expect(service.send(:categorize_by_name, "血圧測定器")).to eq("医療機器")
        expect(service.send(:categorize_by_name, "検査装置")).to eq("医療機器")
        expect(service.send(:categorize_by_name, "診断機器")).to eq("医療機器")
      end

      it "消耗品カテゴリを正しく判定する" do
        expect(service.send(:categorize_by_name, "使い捨て手袋")).to eq("消耗品")
        expect(service.send(:categorize_by_name, "ガーゼ")).to eq("消耗品")
        expect(service.send(:categorize_by_name, "注射器")).to eq("消耗品")
      end

      it "衛生用品カテゴリを正しく判定する" do
        expect(service.send(:categorize_by_name, "消毒液")).to eq("衛生用品")
        expect(service.send(:categorize_by_name, "アルコール")).to eq("衛生用品")
        expect(service.send(:categorize_by_name, "洗浄剤")).to eq("衛生用品")
      end

      it "その他カテゴリを正しく判定する" do
        expect(service.send(:categorize_by_name, "一般雑貨")).to eq("その他")
        expect(service.send(:categorize_by_name, "")).to eq("その他")
        expect(service.send(:categorize_by_name, nil)).to eq("その他")
      end
    end

    describe "#extract_stock_status_text" do
      it "在庫切れ状態を正しく判定する" do
        @store_inventory3.quantity = 0
        status = service.send(:extract_stock_status_text, @store_inventory3)
        expect(status).to eq("在庫切れ")
      end

      it "在庫不足状態を正しく判定する" do
        @store_inventory2.quantity = 2
        @store_inventory2.reorder_level = 5
        status = service.send(:extract_stock_status_text, @store_inventory2)
        expect(status).to eq("在庫不足")
      end

      it "適正在庫状態を正しく判定する" do
        status = service.send(:extract_stock_status_text, @store_inventory1)
        expect(status).to eq("適正在庫")
      end

      it "発注点が設定されていない場合を適切に処理する" do
        @store_inventory1.reorder_level = nil
        status = service.send(:extract_stock_status_text, @store_inventory1)
        expect(status).to eq("適正在庫")
      end
    end

    describe "#calculate_turnover_days" do
      it "回転日数を計算する" do
        turnover = service.send(:calculate_turnover_days, @store_inventory1)
        expect(turnover).to include("日")
      end

      it "在庫0の場合にN/Aを返す" do
        turnover = service.send(:calculate_turnover_days, @store_inventory3)
        expect(turnover).to eq("N/A")
      end

      it "消費量が0の場合にN/Aを返す" do
        @store_inventory1.reorder_level = 0
        turnover = service.send(:calculate_turnover_days, @store_inventory1)
        expect(turnover).to eq("N/A")
      end
    end

    describe "#estimate_weekly_consumption" do
      it "週間消費量を推定する" do
        consumption = service.send(:estimate_weekly_consumption, @store_inventory1)
        expect(consumption).to eq(5.0) # reorder_level(10) / 2
      end

      it "最小値を確保する" do
        @store_inventory1.reorder_level = 0
        consumption = service.send(:estimate_weekly_consumption, @store_inventory1)
        expect(consumption).to eq(1.0) # 最小値
      end
    end

    describe "#format_notes" do
      it "期限切れ商品の警告を追加する" do
        allow(service).to receive(:inventory_has_expired_batches?).and_return(true)
        allow(service).to receive(:long_term_stock?).and_return(false)

        notes = service.send(:format_notes, @store_inventory1)
        expect(notes).to include("期限切れ商品あり")
      end

      it "長期在庫の警告を追加する" do
        allow(service).to receive(:inventory_has_expired_batches?).and_return(false)
        allow(service).to receive(:long_term_stock?).and_return(true)

        notes = service.send(:format_notes, @store_inventory1)
        expect(notes).to include("長期在庫")
      end

      it "複数の警告を組み合わせる" do
        allow(service).to receive(:inventory_has_expired_batches?).and_return(true)
        allow(service).to receive(:long_term_stock?).and_return(true)

        notes = service.send(:format_notes, @store_inventory1)
        expect(notes).to eq("期限切れ商品あり, 長期在庫")
      end

      it "警告がない場合は空文字を返す" do
        allow(service).to receive(:inventory_has_expired_batches?).and_return(false)
        allow(service).to receive(:long_term_stock?).and_return(false)

        notes = service.send(:format_notes, @store_inventory1)
        expect(notes).to eq("")
      end
    end

    describe "#build_csv_row" do
      it "nilの場合はフォールバック行を返す" do
        row = service.send(:build_csv_row, nil)
        expect(row).to eq(Array.new(12, "N/A"))
      end

      it "inventoryがnilの場合はフォールバック行を返す" do
        store_inventory = double(inventory: nil, store: store)
        row = service.send(:build_csv_row, store_inventory)
        expect(row).to eq(Array.new(12, "N/A"))
      end

      it "storeがnilの場合はフォールバック行を返す" do
        inventory = double(name: "Test")
        store_inventory = double(inventory: inventory, store: nil)
        row = service.send(:build_csv_row, store_inventory)
        expect(row).to eq(Array.new(12, "N/A"))
      end

      it "正常なデータで適切な行を返す" do
        row = service.send(:build_csv_row, @store_inventory1)
        expect(row.size).to eq(12)
        expect(row[0]).to eq("テスト店舗")
        expect(row[1]).to eq(@inventory1.id)
        expect(row[2]).to eq("風邪薬カプセル")
      end
    end

    describe "#build_fallback_csv_row" do
      it "12個のN/A要素を持つ配列を返す" do
        row = service.send(:build_fallback_csv_row)
        expect(row).to eq(Array.new(12, "N/A"))
        expect(row.size).to eq(12)
      end
    end

    describe "#process_inventories_in_batches" do
      it "ActiveRecord::Relationの場合はfind_in_batchesを使用する" do
        store_inventories = StoreInventory.where(id: [ @store_inventory1.id, @store_inventory2.id ])
        csv = CSV.new("")

        expect(store_inventories).to receive(:find_in_batches).and_call_original

        service.send(:process_inventories_in_batches, store_inventories, csv)
      end

      it "配列の場合はeach_sliceを使用する" do
        store_inventories = [ @store_inventory1, @store_inventory2 ]
        csv = CSV.new("")

        # each_sliceが呼ばれることを確認
        expect(store_inventories).to receive(:each_slice).and_call_original

        service.send(:process_inventories_in_batches, store_inventories, csv)
      end

      it "バッチサイズに達した場合GCが呼ばれる（配列）" do
        allow(service).to receive(:batch_size).and_return(2)
        store_inventories = [ @store_inventory1, @store_inventory2 ]
        csv = CSV.new("")

        expect(GC).to receive(:start).at_least(:once)

        service.send(:process_inventories_in_batches, store_inventories, csv)
      end
    end

    describe "#inventory_has_expired_batches?" do
      it "期限切れバッチがない場合はfalseを返す" do
        # batchesメソッドが定義されていない場合
        allow(@store_inventory1.inventory).to receive(:respond_to?).with(:batches).and_return(false)

        result = service.send(:inventory_has_expired_batches?, @store_inventory1)
        expect(result).to be false
      end

      it "期限切れバッチがある場合はtrueを返す" do
        expired_batch = double(expiration_date: 1.day.ago)
        valid_batch = double(expiration_date: 30.days.from_now)
        batches = [ expired_batch, valid_batch ]

        allow(@store_inventory1.inventory).to receive(:respond_to?).with(:batches).and_return(true)
        allow(@store_inventory1.inventory).to receive(:batches).and_return(batches)

        result = service.send(:inventory_has_expired_batches?, @store_inventory1)
        expect(result).to be true
      end
    end

    describe "#long_term_stock?" do
      it "90日以上前の更新は長期在庫と判定する" do
        @store_inventory1.updated_at = 91.days.ago

        result = service.send(:long_term_stock?, @store_inventory1)
        expect(result).to be true
      end

      it "90日以内の更新は長期在庫と判定しない" do
        @store_inventory1.updated_at = 89.days.ago

        result = service.send(:long_term_stock?, @store_inventory1)
        expect(result).to be false
      end
    end

    describe "#log_export_event" do
      it "エクスポートイベントをログに記録する" do
        expect(Rails.logger).to receive(:info).with(
          include('"event":"csv_export"')
        )

        service.send(:log_export_event, 5)
      end

      it "current_userがnilの場合はログを記録しない" do
        service_without_user = described_class.new(store: store)

        expect(Rails.logger).not_to receive(:info)

        service_without_user.send(:log_export_event, 5)
      end
    end

    describe "#create_audit_log" do
      context "AuditLogが定義されている場合" do
        before do
          # AuditLogクラスのモック
          audit_log_class = double('AuditLog')
          allow(audit_log_class).to receive(:create!)
          stub_const('AuditLog', audit_log_class)
        end

        it "監査ログを作成する" do
          expect(AuditLog).to receive(:create!).with(
            hash_including(
              user: admin,
              action: "csv_export",
              details: hash_including(
                store_id: store.id,
                record_count: 5
              )
            )
          )

          service.send(:create_audit_log, 5)
        end

        it "監査ログ作成失敗時にエラーログを出力する" do
          allow(AuditLog).to receive(:create!).and_raise(StandardError.new("DB Error"))

          expect(Rails.logger).to receive(:error).with(
            include("Failed to create audit log for CSV export")
          )

          expect {
            service.send(:create_audit_log, 5)
          }.not_to raise_error
        end
      end

      context "AuditLogが定義されていない場合" do
        it "例外を発生させずに処理を継続する" do
          expect {
            service.send(:create_audit_log, 5)
          }.not_to raise_error
        end
      end
    end
  end

  describe "エラーハンドリング" do
    it "無効なデータでも例外を発生させない" do
      invalid_store_inventory = create(:store_inventory,
        store: nil,
        inventory: nil,
        quantity: nil
      )

      expect {
        service.generate_inventory_csv([ invalid_store_inventory ])
      }.not_to raise_error
    end

    it "ネストした関連オブジェクトがnilでも適切に処理する" do
      @store_inventory1.store = nil
      @store_inventory1.inventory = nil

      expect {
        csv_data = service.generate_inventory_csv([ @store_inventory1 ])
        expect(csv_data).to be_a(String)
      }.not_to raise_error
    end
  end

  describe "パフォーマンステスト" do
    it "大量データでも適切に処理する" do
      # 1000件の店舗在庫データを作成
      store_inventories = Array.new(1000) do |i|
        inventory = create(:inventory, name: "Product #{i}")
        create(:store_inventory, store: store, inventory: inventory, quantity: i + 1)
      end

      start_time = Time.current
      csv_data = service.generate_inventory_csv(store_inventories)
      duration = Time.current - start_time

      expect(duration).to be < 5.0 # 5秒以内に完了
      expect(csv_data).to be_a(String)
      expect(csv_data.split("\n").size).to eq(1001) # ヘッダー + 1000行
    end
  end

  describe "セキュリティテスト" do
    it "SQLインジェクション攻撃を防ぐ" do
      malicious_inventory = create(:inventory, name: "'; DROP TABLE inventories; --")
      malicious_store_inventory = create(:store_inventory,
        store: store,
        inventory: malicious_inventory,
        quantity: 10
      )

      csv_data = service.generate_inventory_csv([ malicious_store_inventory ])

      # SQLインジェクションコードがエスケープされて出力される
      expect(csv_data).to include("'; DROP TABLE inventories; --")
      expect(csv_data).not_to include("DROP TABLE")
    end

    it "XSS攻撃を防ぐ" do
      xss_inventory = create(:inventory, name: "<script>alert('XSS')</script>")
      xss_store_inventory = create(:store_inventory,
        store: store,
        inventory: xss_inventory,
        quantity: 10
      )

      csv_data = service.generate_inventory_csv([ xss_store_inventory ])

      # スクリプトタグがエスケープされて出力される
      expect(csv_data).to include("<script>alert('XSS')</script>")
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1日
  # 横展開: 他のエクスポート系サービスと同等のテスト網羅性達成
  #
  # 1. 国際化対応テスト
  #    - 多言語ヘッダー対応
  #    - 文字エンコーディング変換テスト
  #    - タイムゾーン変換テスト
  #
  # 2. フォーマットバリエーションテスト
  #    - 区切り文字の変更（カンマ、タブ、セミコロン）
  #    - 文字列クォート処理
  #    - 改行コード変換（Windows、Unix）
  #
  # 3. 権限・アクセス制御テスト
  #    - 店舗別データアクセス制限
  #    - 管理者権限による出力項目変更
  #    - データマスキング機能
  #
  # 4. 統合テスト
  #    - 実際のコントローラーからの呼び出し
  #    - ファイルダウンロード機能
  #    - ActionCable通知連携
end
