# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreInventoriesHelper, type: :helper do
  # CLAUDE.md準拠: 店舗在庫ヘルパーの包括的テスト
  # メタ認知: UIコンポーネントの一貫性とセキュリティ考慮の検証
  # 横展開: 他の在庫関連ヘルパーでも同様のテストパターン適用

  let(:store) { create(:store) }

  # ============================================
  # store_type_icon メソッドのテスト
  # ============================================

  describe "#store_type_icon" do
    context "既知の店舗タイプ" do
      it "pharmacy タイプで適切なアイコンクラスを返す" do
        expect(helper.store_type_icon("pharmacy")).to eq("fas fa-prescription-bottle-alt")
      end

      it "warehouse タイプで適切なアイコンクラスを返す" do
        expect(helper.store_type_icon("warehouse")).to eq("fas fa-warehouse")
      end

      it "headquarters タイプで適切なアイコンクラスを返す" do
        expect(helper.store_type_icon("headquarters")).to eq("fas fa-building")
      end
    end

    context "未知の店舗タイプ" do
      it "デフォルトアイコンクラスを返す" do
        expect(helper.store_type_icon("unknown")).to eq("fas fa-store")
      end

      it "空文字列でもデフォルトアイコンクラスを返す" do
        expect(helper.store_type_icon("")).to eq("fas fa-store")
      end

      it "nilでもデフォルトアイコンクラスを返す" do
        expect(helper.store_type_icon(nil)).to eq("fas fa-store")
      end
    end

    context "Font Awesome整合性" do
      %w[pharmacy warehouse headquarters unknown].each do |type|
        it "#{type} タイプのアイコンがFont Awesome形式" do
          icon_class = helper.store_type_icon(type)
          expect(icon_class).to start_with("fas fa-")
        end
      end
    end
  end

  # ============================================
  # stock_status_badge メソッドのテスト
  # ============================================

  describe "#stock_status_badge" do
    context "在庫切れ（0個）" do
      it "在庫切れバッジを表示する" do
        result = helper.stock_status_badge(0)
        expect(result).to include("在庫切れ")
        expect(result).to include("badge bg-danger")
      end
    end

    context "在庫少（1-10個）" do
      it "1個の場合、在庫少バッジを表示する" do
        result = helper.stock_status_badge(1)
        expect(result).to include("在庫少")
        expect(result).to include("badge bg-warning text-dark")
      end

      it "10個の場合、在庫少バッジを表示する" do
        result = helper.stock_status_badge(10)
        expect(result).to include("在庫少")
        expect(result).to include("badge bg-warning text-dark")
      end
    end

    context "在庫あり（11個以上）" do
      it "11個の場合、在庫ありバッジを表示する" do
        result = helper.stock_status_badge(11)
        expect(result).to include("在庫あり")
        expect(result).to include("badge bg-success")
      end

      it "大量在庫でも在庫ありバッジを表示する" do
        result = helper.stock_status_badge(1000)
        expect(result).to include("在庫あり")
        expect(result).to include("badge bg-success")
      end
    end

    context "HTMLの安全性" do
      it "HTMLタグとして安全な文字列を返す" do
        result = helper.stock_status_badge(5)
        expect(result).to be_html_safe
      end

      it "正しいHTML構造を持つ" do
        result = helper.stock_status_badge(0)
        expect(result).to match(/<span[^>]*class="[^"]*badge[^"]*"[^>]*>/)
        expect(result).to match(/<\/span>/)
      end
    end

    context "境界値テスト" do
      it "負数の在庫数でも適切に処理される" do
        result = helper.stock_status_badge(-1)
        expect(result).to include("在庫あり") # case文のelse節
      end
    end
  end

  # ============================================
  # sort_link メソッドのテスト
  # ============================================

  describe "#sort_link" do
    before do
      # Controllerのインスタンス変数設定
      assign(:store, store)

      # request オブジェクトのモック
      allow(helper).to receive(:request).and_return(
        double(query_parameters: {})
      )
    end

    context "初回ソート（パラメータなし）" do
      before do
        allow(helper).to receive(:params).and_return({})
      end

      it "昇順ソートリンクを生成する" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("sort=name")
        expect(result).to include("direction=asc")
        expect(result).to include("fa-sort")
      end

      it "適切なdata属性を持つ" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include('data-turbo-action="replace"')
      end
    end

    context "昇順ソート中の同一カラム" do
      before do
        allow(helper).to receive(:params).and_return(
          { sort: "name", direction: "asc" }
        )
      end

      it "降順ソートリンクを生成する" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("direction=desc")
        expect(result).to include("fa-sort-up")
      end
    end

    context "降順ソート中の同一カラム" do
      before do
        allow(helper).to receive(:params).and_return(
          { sort: "name", direction: "desc" }
        )
      end

      it "昇順ソートリンクを生成する" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("direction=asc")
        expect(result).to include("fa-sort-down")
      end
    end

    context "異なるカラムのソート" do
      before do
        allow(helper).to receive(:params).and_return(
          { sort: "price", direction: "desc" }
        )
      end

      it "新しいカラムで昇順ソートリンクを生成する" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("sort=name")
        expect(result).to include("direction=asc")
        expect(result).to include("fa-sort")
      end
    end

    context "既存パラメータの保持" do
      before do
        allow(helper).to receive(:params).and_return({})
        allow(helper).to receive(:request).and_return(
          double(query_parameters: { search: "test", filter: "active" })
        )
      end

      it "既存のクエリパラメータを保持する" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("search=test")
        expect(result).to include("filter=active")
        expect(result).to include("sort=name")
      end
    end

    context "HTMLの安全性" do
      it "HTMLエスケープされた安全な文字列を返す" do
        result = helper.sort_link("<script>alert('XSS')</script>", "name")
        expect(result).not_to include("<script>")
        expect(result).to be_html_safe
      end
    end

    context "CSSクラスとスタイル" do
      it "適切なCSSクラスが設定される" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("text-decoration-none")
        expect(result).to include("text-dark")
      end
    end
  end

  # ============================================
  # public_stock_display メソッドのテスト
  # ============================================

  describe "#public_stock_display" do
    context "在庫なし（0個）" do
      it "在庫なしを表示する" do
        expect(helper.public_stock_display(0)).to eq("在庫なし")
      end
    end

    context "残りわずか（1-5個）" do
      it "1個の場合、残りわずかを表示する" do
        expect(helper.public_stock_display(1)).to eq("残りわずか")
      end

      it "5個の場合、残りわずかを表示する" do
        expect(helper.public_stock_display(5)).to eq("残りわずか")
      end
    end

    context "在庫少（6-20個）" do
      it "6個の場合、在庫少を表示する" do
        expect(helper.public_stock_display(6)).to eq("在庫少")
      end

      it "20個の場合、在庫少を表示する" do
        expect(helper.public_stock_display(20)).to eq("在庫少")
      end
    end

    context "在庫あり（21個以上）" do
      it "21個の場合、在庫ありを表示する" do
        expect(helper.public_stock_display(21)).to eq("在庫あり")
      end

      it "大量在庫でも在庫ありを表示する" do
        expect(helper.public_stock_display(1000)).to eq("在庫あり")
      end
    end

    context "セキュリティ考慮" do
      it "具体的な数量を表示しない" do
        [ 0, 5, 10, 50, 100 ].each do |quantity|
          result = helper.public_stock_display(quantity)
          expect(result).not_to match(/\d+/)
        end
      end
    end

    context "境界値テスト" do
      it "負数でも適切に処理される" do
        expect(helper.public_stock_display(-1)).to eq("在庫あり")
      end
    end
  end

  # ============================================
  # last_updated_display メソッドのテスト
  # ============================================

  describe "#last_updated_display" do
    context "有効な日時" do
      it "相対的な時間表示を返す" do
        time = 2.hours.ago
        result = helper.last_updated_display(time)
        expect(result).to include("2時間")
        expect(result).to include("前")
      end

      it "tooltipとして完全な日時を含む" do
        time = Time.current
        result = helper.last_updated_display(time)
        expect(result).to include('data-bs-toggle="tooltip"')
        expect(result).to include('title=')
      end

      it "HTML安全な文字列を返す" do
        result = helper.last_updated_display(1.day.ago)
        expect(result).to be_html_safe
      end

      it "spanタグで囲まれている" do
        result = helper.last_updated_display(1.hour.ago)
        expect(result).to match(/<span[^>]*>.*<\/span>/)
      end
    end

    context "nilの日時" do
      it "データなしを表示する" do
        expect(helper.last_updated_display(nil)).to eq("データなし")
      end
    end

    context "様々な時間差での表示" do
      it "数秒前の表示" do
        result = helper.last_updated_display(30.seconds.ago)
        expect(result).to include("1分未満")
      end

      it "数分前の表示" do
        result = helper.last_updated_display(5.minutes.ago)
        expect(result).to include("5分")
      end

      it "数日前の表示" do
        result = helper.last_updated_display(3.days.ago)
        expect(result).to include("3日")
      end

      it "数ヶ月前の表示" do
        result = helper.last_updated_display(2.months.ago)
        expect(result).to include("2ヶ月")
      end
    end

    context "ローカライゼーション" do
      it "日本語形式で日時を表示する" do
        time = Time.zone.local(2024, 1, 15, 14, 30, 0)
        result = helper.last_updated_display(time)
        # titleに含まれる完全な日時形式を確認
        expect(result).to include("2024")
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "store_type_icon は高速" do
      start_time = Time.current
      1000.times do
        helper.store_type_icon("pharmacy")
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 50 # 50ms以内
    end

    it "stock_status_badge は高速" do
      start_time = Time.current
      1000.times do
        helper.stock_status_badge(5)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "public_stock_display は高速" do
      start_time = Time.current
      1000.times do
        helper.public_stock_display(15)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 50 # 50ms以内
    end
  end

  # ============================================
  # Bootstrap整合性テスト
  # ============================================

  describe "Bootstrap consistency" do
    context "バッジクラス" do
      it "Bootstrap 5のバッジクラスを使用する" do
        badge_html = helper.stock_status_badge(0)
        expect(badge_html).to include("badge")
        expect(badge_html).to match(/bg-(danger|warning|success)/)
      end

      it "警告バッジには適切なテキスト色を設定する" do
        warning_badge = helper.stock_status_badge(5)
        expect(warning_badge).to include("text-dark")
      end
    end

    context "tooltipの設定" do
      it "Bootstrap 5のtooltip属性を使用する" do
        result = helper.last_updated_display(1.hour.ago)
        expect(result).to include("data-bs-toggle")
        expect(result).not_to include("data-toggle") # Bootstrap 4形式でない
      end
    end
  end

  # ============================================
  # 国際化・アクセシビリティテスト
  # ============================================

  describe "internationalization and accessibility" do
    context "日本語表示" do
      it "在庫状態が日本語で表示される" do
        expect(helper.stock_status_badge(0)).to include("在庫切れ")
        expect(helper.stock_status_badge(5)).to include("在庫少")
        expect(helper.stock_status_badge(50)).to include("在庫あり")
      end

      it "公開用在庫表示が日本語で表示される" do
        expect(helper.public_stock_display(0)).to eq("在庫なし")
        expect(helper.public_stock_display(3)).to eq("残りわずか")
        expect(helper.public_stock_display(10)).to eq("在庫少")
        expect(helper.public_stock_display(100)).to eq("在庫あり")
      end
    end

    context "アクセシビリティ" do
      it "ソートリンクには視覚的なアイコンが含まれる" do
        result = helper.sort_link("商品名", "name")
        expect(result).to include("fa-sort")
      end

      it "最終更新日時にはtooltipで完全な情報を提供する" do
        time = 1.day.ago
        result = helper.last_updated_display(time)
        expect(result).to include("title=")
      end
    end
  end

  # ============================================
  # エッジケースとエラーハンドリング
  # ============================================

  describe "edge cases and error handling" do
    context "極端な値" do
      it "非常に大きな在庫数でも適切に処理される" do
        result = helper.stock_status_badge(999999)
        expect(result).to include("在庫あり")
      end

      it "非常に古い日時でも適切に処理される" do
        old_time = 10.years.ago
        result = helper.last_updated_display(old_time)
        expect(result).to include("前")
      end
    end

    context "特殊文字の処理" do
      it "ソートリンクでXSS攻撃を防ぐ" do
        malicious_text = "<script>alert('XSS')</script>"
        result = helper.sort_link(malicious_text, "name")
        expect(result).not_to include("<script>")
      end
    end

    context "未来の日時" do
      it "未来の日時でも適切に処理される" do
        future_time = 1.hour.from_now
        expect {
          helper.last_updated_display(future_time)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security considerations" do
    context "在庫数の情報漏洩防止" do
      it "public_stock_displayは具体的な数量を露出しない" do
        test_cases = [
          { quantity: 0, expected: "在庫なし" },
          { quantity: 3, expected: "残りわずか" },
          { quantity: 15, expected: "在庫少" },
          { quantity: 100, expected: "在庫あり" }
        ]

        test_cases.each do |test_case|
          result = helper.public_stock_display(test_case[:quantity])
          expect(result).to eq(test_case[:expected])
          expect(result).not_to include(test_case[:quantity].to_s)
        end
      end
    end

    context "ソートリンクのセキュリティ" do
      before do
        assign(:store, store)
        allow(helper).to receive(:request).and_return(
          double(query_parameters: {})
        )
      end

      it "SQLインジェクション対策済みのパラメータを生成する" do
        malicious_column = "'; DROP TABLE inventories; --"
        result = helper.sort_link("Test", malicious_column)
        # URLエンコードされることを確認
        expect(result).not_to include("DROP TABLE")
      end
    end
  end
end
