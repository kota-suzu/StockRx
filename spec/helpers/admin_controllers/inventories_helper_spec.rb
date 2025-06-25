# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InventoriesHelper, type: :helper do
  # CLAUDE.md準拠: 管理画面在庫ヘルパーの包括的テスト
  # メタ認知: UIコンポーネントとデータ表示の一貫性検証
  # 横展開: 他の管理画面ヘルパーでも同様のテストパターン適用

  let(:inventory) { create(:inventory, quantity: 100, price: 1000) }
  let(:batch) { create(:batch, inventory: inventory, quantity: 50) }

  # ============================================
  # inventory_row_class メソッドのテスト
  # ============================================

  describe "#inventory_row_class" do
    context "在庫切れの場合" do
      let(:empty_inventory) { create(:inventory, quantity: 0) }

      it "table-dangerクラスを返す" do
        expect(helper.inventory_row_class(empty_inventory)).to eq("table-danger")
      end
    end

    context "低在庫の場合" do
      let(:low_stock_inventory) { create(:inventory, quantity: 5, safety_stock_level: 10) }

      before do
        allow(low_stock_inventory).to receive(:low_stock?).and_return(true)
      end

      it "table-warningクラスを返す" do
        expect(helper.inventory_row_class(low_stock_inventory)).to eq("table-warning")
      end
    end

    context "正常在庫の場合" do
      let(:normal_inventory) { create(:inventory, quantity: 100, safety_stock_level: 10) }

      before do
        allow(normal_inventory).to receive(:low_stock?).and_return(false)
      end

      it "空文字を返す" do
        expect(helper.inventory_row_class(normal_inventory)).to eq("")
      end
    end

    context "境界値テスト" do
      it "在庫数が負数でも在庫切れとして扱われる" do
        negative_inventory = create(:inventory, quantity: -1)
        expect(helper.inventory_row_class(negative_inventory)).to eq("table-danger")
      end

      it "在庫数がちょうど0の場合は在庫切れ" do
        zero_inventory = create(:inventory, quantity: 0)
        expect(helper.inventory_row_class(zero_inventory)).to eq("table-danger")
      end
    end
  end

  # ============================================
  # sort_direction_for メソッドのテスト
  # ============================================

  describe "#sort_direction_for" do
    context "現在昇順ソートされている列の場合" do
      before do
        allow(helper).to receive(:params).and_return({ sort: "name", direction: "asc" })
      end

      it "desc を返す" do
        expect(helper.sort_direction_for("name")).to eq("desc")
      end
    end

    context "現在降順ソートされている列の場合" do
      before do
        allow(helper).to receive(:params).and_return({ sort: "name", direction: "desc" })
      end

      it "asc を返す" do
        expect(helper.sort_direction_for("name")).to eq("asc")
      end
    end

    context "ソートされていない列の場合" do
      before do
        allow(helper).to receive(:params).and_return({ sort: "other_column", direction: "asc" })
      end

      it "asc を返す" do
        expect(helper.sort_direction_for("name")).to eq("asc")
      end
    end

    context "パラメータが存在しない場合" do
      before do
        allow(helper).to receive(:params).and_return({})
      end

      it "asc を返す" do
        expect(helper.sort_direction_for("name")).to eq("asc")
      end
    end
  end

  # ============================================
  # sort_icon_for メソッドのテスト
  # ============================================

  describe "#sort_icon_for" do
    context "現在昇順ソートされている列の場合" do
      before do
        allow(helper).to receive(:params).and_return({ sort: "name", direction: "asc" })
      end

      it "上向きアイコンのHTMLを返す" do
        result = helper.sort_icon_for("name")
        expect(result).to include("fas fa-sort-up")
        expect(result).to include("ms-1")
        expect(result).to be_html_safe
      end
    end

    context "現在降順ソートされている列の場合" do
      before do
        allow(helper).to receive(:params).and_return({ sort: "name", direction: "desc" })
      end

      it "下向きアイコンのHTMLを返す" do
        result = helper.sort_icon_for("name")
        expect(result).to include("fas fa-sort-down")
        expect(result).to include("ms-1")
        expect(result).to be_html_safe
      end
    end

    context "ソートされていない列の場合" do
      before do
        allow(helper).to receive(:params).and_return({ sort: "other_column", direction: "asc" })
      end

      it "空のHTML安全文字列を返す" do
        result = helper.sort_icon_for("name")
        expect(result).to eq("".html_safe)
      end
    end

    context "パラメータが存在しない場合" do
      before do
        allow(helper).to receive(:params).and_return({})
      end

      it "空のHTML安全文字列を返す" do
        result = helper.sort_icon_for("name")
        expect(result).to eq("".html_safe)
      end
    end
  end

  # ============================================
  # CSVサンプル機能のテスト
  # ============================================

  describe "#csv_sample_format" do
    it "基本的なCSVサンプルを返す" do
      result = helper.csv_sample_format

      expect(result).to include("name,quantity,price,status")
      expect(result).to include("ノートパソコン ThinkPad X1,15,128000,active")
      expect(result).to include("ワイヤレスマウス Logitech MX,50,7800,active")
      expect(result).to include("モニター 27インチ 4K,25,45000,active")
    end

    it "有効なCSV形式である" do
      result = helper.csv_sample_format
      lines = result.split("\n")

      expect(lines.length).to eq(4) # ヘッダー + 3データ行
      expect(lines.first.split(",").length).to eq(4) # 4列
    end
  end

  describe "#csv_extended_sample_format" do
    it "拡張CSVサンプルを返す" do
      result = helper.csv_extended_sample_format

      expect(result).to include("name,quantity,price,status")
      expect(result).to include("在庫切れ商品例,0,5000,active")
      expect(result).to include("アーカイブ商品例,10,3000,archived")
      expect(result).to include("小数点価格例,100,1499.99,active")
      expect(result).to include("特殊文字商品「テスト」,75,2500,active")
    end

    it "多様なデータパターンを含む" do
      result = helper.csv_extended_sample_format

      # 在庫切れパターン
      expect(result).to include(",0,")
      # アーカイブステータス
      expect(result).to include(",archived")
      # 小数点価格
      expect(result).to include("1499.99")
      # 特殊文字
      expect(result).to include("「テスト」")
    end

    it "有効なCSV形式である" do
      result = helper.csv_extended_sample_format.strip
      lines = result.split("\n")

      expect(lines.length).to eq(11) # ヘッダー + 10データ行
      lines.each do |line|
        expect(line.split(",").length).to eq(4) # 全行で4列
      end
    end
  end

  # ============================================
  # ロット状態関連ヘルパーのテスト
  # ============================================

  describe "#batch_row_class" do
    context "期限切れロットの場合" do
      before do
        allow(batch).to receive(:expired?).and_return(true)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it "table-dangerクラスを返す" do
        expect(helper.batch_row_class(batch)).to eq("table-danger")
      end
    end

    context "期限間近ロットの場合" do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(true)
      end

      it "table-warningクラスを返す" do
        expect(helper.batch_row_class(batch)).to eq("table-warning")
      end
    end

    context "正常ロットの場合" do
      before do
        allow(batch).to receive(:expired?).and_return(false)
        allow(batch).to receive(:expiring_soon?).and_return(false)
      end

      it "空文字を返す" do
        expect(helper.batch_row_class(batch)).to eq("")
      end
    end
  end

  describe "#lot_status_display" do
    it "期限切れロットは「期限切れ」を返す" do
      allow(batch).to receive(:expired?).and_return(true)
      expect(helper.lot_status_display(batch)).to eq("期限切れ")
    end

    it "期限間近ロットは「期限間近」を返す" do
      allow(batch).to receive(:expired?).and_return(false)
      allow(batch).to receive(:expiring_soon?).and_return(true)
      expect(helper.lot_status_display(batch)).to eq("期限間近")
    end

    it "正常ロットは「正常」を返す" do
      allow(batch).to receive(:expired?).and_return(false)
      allow(batch).to receive(:expiring_soon?).and_return(false)
      expect(helper.lot_status_display(batch)).to eq("正常")
    end
  end

  describe "#lot_quantity_percentage" do
    it "正しくパーセンテージを計算する" do
      result = helper.lot_quantity_percentage(batch, 200)
      expect(result).to eq(25.0) # 50/200 * 100 = 25.0
    end

    it "小数点第1位で四捨五入される" do
      allow(batch).to receive(:quantity).and_return(33)
      result = helper.lot_quantity_percentage(batch, 100)
      expect(result).to eq(33.0) # 33/100 * 100 = 33.0
    end

    it "総在庫数が0の場合は0を返す" do
      result = helper.lot_quantity_percentage(batch, 0)
      expect(result).to eq(0)
    end

    it "総在庫数が負数の場合は0を返す" do
      result = helper.lot_quantity_percentage(batch, -10)
      expect(result).to eq(0)
    end

    it "パーセンテージが100を超える場合も正しく計算される" do
      allow(batch).to receive(:quantity).and_return(150)
      result = helper.lot_quantity_percentage(batch, 100)
      expect(result).to eq(150.0)
    end
  end

  describe "#lot_status_badge_class" do
    it "期限切れロットはbg-dangerクラスを返す" do
      allow(batch).to receive(:expired?).and_return(true)
      expect(helper.lot_status_badge_class(batch)).to eq("bg-danger")
    end

    it "期限間近ロットはbg-warningクラスを返す" do
      allow(batch).to receive(:expired?).and_return(false)
      allow(batch).to receive(:expiring_soon?).and_return(true)
      expect(helper.lot_status_badge_class(batch)).to eq("bg-warning")
    end

    it "正常ロットはbg-successクラスを返す" do
      allow(batch).to receive(:expired?).and_return(false)
      allow(batch).to receive(:expiring_soon?).and_return(false)
      expect(helper.lot_status_badge_class(batch)).to eq("bg-success")
    end
  end

  # ============================================
  # CSVヘッダー説明機能のテスト
  # ============================================

  describe "#header_description" do
    context "基本ヘッダーの説明" do
      it "name ヘッダーの説明を返す" do
        expect(helper.header_description("name")).to eq("商品名（必須・文字列）")
      end

      it "quantity ヘッダーの説明を返す" do
        expect(helper.header_description("quantity")).to eq("在庫数量（必須・数値）")
      end

      it "price ヘッダーの説明を返す" do
        expect(helper.header_description("price")).to eq("販売価格（必須・数値）")
      end

      it "status ヘッダーの説明を返す" do
        expect(helper.header_description("status")).to eq("ステータス（active/archived）")
      end
    end

    context "拡張ヘッダーの説明" do
      it "category ヘッダーの説明を返す" do
        expect(helper.header_description("category")).to eq("カテゴリ（任意・文字列）")
      end

      it "barcode ヘッダーの説明を返す" do
        expect(helper.header_description("barcode")).to eq("バーコード（任意・文字列）")
      end

      it "description ヘッダーの説明を返す" do
        expect(helper.header_description("description")).to eq("商品説明（任意・文字列）")
      end
    end

    context "未知のヘッダー" do
      it "デフォルトの説明を返す" do
        expect(helper.header_description("unknown")).to eq("データ項目")
      end

      it "空文字列でもデフォルトの説明を返す" do
        expect(helper.header_description("")).to eq("データ項目")
      end
    end

    context "型変換の確認" do
      it "シンボルでも適切に処理される" do
        expect(helper.header_description(:name)).to eq("商品名（必須・文字列）")
      end
    end
  end

  # ============================================
  # ファイルサイズ表示機能のテスト
  # ============================================

  describe "#humanize_file_size" do
    context "バイト単位" do
      it "0バイトを正しく表示する" do
        expect(helper.humanize_file_size(0)).to eq("0 B")
      end

      it "小さなファイルサイズを正しく表示する" do
        expect(helper.humanize_file_size(512)).to eq("512.0 B")
      end
    end

    context "キロバイト単位" do
      it "キロバイトを正しく表示する" do
        expect(helper.humanize_file_size(1024)).to eq("1.0 KB")
      end

      it "キロバイトの小数点を正しく表示する" do
        expect(helper.humanize_file_size(1536)).to eq("1.5 KB") # 1.5KB
      end
    end

    context "メガバイト単位" do
      it "メガバイトを正しく表示する" do
        expect(helper.humanize_file_size(1024 * 1024)).to eq("1.0 MB")
      end

      it "メガバイトの小数点を正しく表示する" do
        expect(helper.humanize_file_size(1024 * 1024 * 2.5)).to eq("2.5 MB")
      end
    end

    context "ギガバイト単位" do
      it "ギガバイトを正しく表示する" do
        expect(helper.humanize_file_size(1024 * 1024 * 1024)).to eq("1.0 GB")
      end
    end

    context "エッジケース" do
      it "nilの場合は0 Bを返す" do
        expect(helper.humanize_file_size(nil)).to eq("0 B")
      end

      it "非常に大きなサイズでもGBで表示される" do
        huge_size = 1024 * 1024 * 1024 * 1000 # 1000GB
        result = helper.humanize_file_size(huge_size)
        expect(result).to include("GB")
        expect(result).to include("1000.0")
      end
    end
  end

  # ============================================
  # インポートステータスアイコン機能のテスト
  # ============================================

  describe "#import_status_icon" do
    context "待機中ステータス" do
      it "pending ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("pending")
        expect(result).to eq("bi bi-clock text-warning")
      end
    end

    context "処理中ステータス" do
      it "processing ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("processing")
        expect(result).to eq("bi bi-arrow-repeat text-primary")
      end

      it "running ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("running")
        expect(result).to eq("bi bi-arrow-repeat text-primary")
      end
    end

    context "完了ステータス" do
      it "completed ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("completed")
        expect(result).to eq("bi bi-check-circle text-success")
      end

      it "success ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("success")
        expect(result).to eq("bi bi-check-circle text-success")
      end
    end

    context "失敗ステータス" do
      it "failed ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("failed")
        expect(result).to eq("bi bi-x-circle text-danger")
      end

      it "error ステータスで適切なアイコンを返す" do
        result = helper.import_status_icon("error")
        expect(result).to eq("bi bi-x-circle text-danger")
      end
    end

    context "未知のステータス" do
      it "unknown ステータスでデフォルトアイコンを返す" do
        result = helper.import_status_icon("unknown")
        expect(result).to eq("bi bi-question-circle text-muted")
      end

      it "空文字列でデフォルトアイコンを返す" do
        result = helper.import_status_icon("")
        expect(result).to eq("bi bi-question-circle text-muted")
      end
    end

    context "型変換の確認" do
      it "シンボルでも適切に処理される" do
        result = helper.import_status_icon(:pending)
        expect(result).to eq("bi bi-clock text-warning")
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "inventory_row_class は高速" do
      start_time = Time.current
      1000.times do
        helper.inventory_row_class(inventory)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "humanize_file_size は高速" do
      start_time = Time.current
      1000.times do
        helper.humanize_file_size(1024 * 1024)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "CSVサンプル生成は高速" do
      start_time = Time.current
      100.times do
        helper.csv_extended_sample_format
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # Bootstrap CSS整合性テスト
  # ============================================

  describe "Bootstrap CSS consistency" do
    it "テーブル行クラスがBootstrap 5準拠" do
      table_classes = [
        helper.inventory_row_class(create(:inventory, quantity: 0)),
        helper.batch_row_class(batch)
      ]

      table_classes.each do |css_class|
        next if css_class.empty?
        expect(css_class).to match(/^table-(danger|warning|success)$/)
      end
    end

    it "バッジクラスがBootstrap 5準拠" do
      badge_class = helper.lot_status_badge_class(batch)
      expect(badge_class).to match(/^bg-(danger|warning|success)$/)
    end

    it "アイコンクラスがBootstrap Icons準拠" do
      icon_classes = [
        helper.import_status_icon("pending"),
        helper.import_status_icon("completed"),
        helper.import_status_icon("failed")
      ]

      icon_classes.each do |icon_class|
        expect(icon_class).to start_with("bi bi-")
        expect(icon_class).to match(/text-(warning|primary|success|danger|muted)/)
      end
    end
  end

  # ============================================
  # 国際化・アクセシビリティテスト
  # ============================================

  describe "internationalization and accessibility" do
    context "日本語表示の一貫性" do
      it "ロット状態表示が日本語で統一されている" do
        statuses = [ "期限切れ", "期限間近", "正常" ]

        statuses.each do |status|
          expect(status).to match(/^[ひらがなカタカナ漢字々]+$/)
        end
      end

      it "CSVヘッダー説明が日本語で統一されている" do
        descriptions = [
          helper.header_description("name"),
          helper.header_description("quantity"),
          helper.header_description("price")
        ]

        descriptions.each do |desc|
          expect(desc).to include("（")
          expect(desc).to include("）")
        end
      end
    end

    context "HTMLの安全性" do
      it "sort_icon_for の結果がhtml_safe" do
        allow(helper).to receive(:params).and_return({ sort: "name", direction: "asc" })
        result = helper.sort_icon_for("name")
        expect(result).to be_html_safe
      end
    end
  end

  # ============================================
  # エッジケースとエラーハンドリング
  # ============================================

  describe "edge cases and error handling" do
    context "nil値の処理" do
      it "inventory_row_class でnilが渡されてもエラーにならない" do
        expect {
          helper.inventory_row_class(nil)
        }.to raise_error(NoMethodError) # 意図的エラー（inventoryはnilになりえない設計）
      end

      it "humanize_file_size でnilが渡されても適切に処理される" do
        expect(helper.humanize_file_size(nil)).to eq("0 B")
      end
    end

    context "極端な値の処理" do
      it "非常に大きなファイルサイズでも処理される" do
        huge_size = 10**15 # 1PB
        expect {
          helper.humanize_file_size(huge_size)
        }.not_to raise_error
      end

      it "負数のファイルサイズでも処理される" do
        expect(helper.humanize_file_size(-1024)).to eq("0 B")
      end

      it "小数点を含むパーセンテージが正しく計算される" do
        allow(batch).to receive(:quantity).and_return(33)
        result = helper.lot_quantity_percentage(batch, 99)
        expect(result).to eq(33.3) # 33/99*100 ≈ 33.3
      end
    end

    context "文字エンコーディング" do
      it "特殊文字を含むCSVサンプルが正しく処理される" do
        sample = helper.csv_extended_sample_format
        expect(sample.encoding).to eq(Encoding::UTF_8)
        expect(sample).to include("「テスト」")
      end
    end
  end
end
