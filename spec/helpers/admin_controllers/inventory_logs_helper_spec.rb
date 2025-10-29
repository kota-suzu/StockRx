# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::InventoryLogsHelper, type: :helper do
  # CLAUDE.md準拠: 在庫ログヘルパーの包括的テスト
  # メタ認知: 在庫管理ビジネスロジックの正確性とUI一貫性の検証
  # 横展開: 他の管理画面ヘルパーとの統一的なパターン適用

  # テストデータのセットアップ
  let(:inventory_log) { build(:inventory_log, quantity_change: 50, created_at: 2.hours.ago) }
  let(:inventory_log_negative) { build(:inventory_log, quantity_change: -30) }
  let(:inventory_log_large) { build(:inventory_log, quantity_change: 150) }

  # ============================================
  # inventory_log_action_icon メソッドのテスト
  # ============================================

  describe "#inventory_log_action_icon" do
    context "日本語アクション" do
      it "入荷のアイコンを返す" do
        expect(helper.inventory_log_action_icon("入荷")).to eq("bi bi-box-arrow-in-down text-success")
      end

      it "出荷のアイコンを返す" do
        expect(helper.inventory_log_action_icon("出荷")).to eq("bi bi-box-arrow-up text-primary")
      end

      it "調整のアイコンを返す" do
        expect(helper.inventory_log_action_icon("調整")).to eq("bi bi-tools text-warning")
      end

      it "移動のアイコンを返す" do
        expect(helper.inventory_log_action_icon("移動")).to eq("bi bi-arrow-left-right text-info")
      end

      it "廃棄のアイコンを返す" do
        expect(helper.inventory_log_action_icon("廃棄")).to eq("bi bi-trash text-danger")
      end

      it "棚卸のアイコンを返す" do
        expect(helper.inventory_log_action_icon("棚卸")).to eq("bi bi-clipboard-check text-secondary")
      end

      it "期限切れのアイコンを返す" do
        expect(helper.inventory_log_action_icon("期限切れ")).to eq("bi bi-calendar-x text-danger")
      end

      it "返品のアイコンを返す" do
        expect(helper.inventory_log_action_icon("返品")).to eq("bi bi-arrow-return-left text-warning")
      end
    end

    context "英語アクション" do
      it "receiptのアイコンを返す" do
        expect(helper.inventory_log_action_icon("receipt")).to eq("bi bi-box-arrow-in-down text-success")
        expect(helper.inventory_log_action_icon("received")).to eq("bi bi-box-arrow-in-down text-success")
      end

      it "shipmentのアイコンを返す" do
        expect(helper.inventory_log_action_icon("shipment")).to eq("bi bi-box-arrow-up text-primary")
        expect(helper.inventory_log_action_icon("shipped")).to eq("bi bi-box-arrow-up text-primary")
      end

      it "adjustmentのアイコンを返す" do
        expect(helper.inventory_log_action_icon("adjustment")).to eq("bi bi-tools text-warning")
        expect(helper.inventory_log_action_icon("adjusted")).to eq("bi bi-tools text-warning")
      end

      it "transferのアイコンを返す" do
        expect(helper.inventory_log_action_icon("transfer")).to eq("bi bi-arrow-left-right text-info")
        expect(helper.inventory_log_action_icon("transferred")).to eq("bi bi-arrow-left-right text-info")
      end

      it "disposalのアイコンを返す" do
        expect(helper.inventory_log_action_icon("disposal")).to eq("bi bi-trash text-danger")
        expect(helper.inventory_log_action_icon("disposed")).to eq("bi bi-trash text-danger")
      end

      it "stocktakingのアイコンを返す" do
        expect(helper.inventory_log_action_icon("stocktaking")).to eq("bi bi-clipboard-check text-secondary")
        expect(helper.inventory_log_action_icon("counted")).to eq("bi bi-clipboard-check text-secondary")
      end

      it "expiredのアイコンを返す" do
        expect(helper.inventory_log_action_icon("expired")).to eq("bi bi-calendar-x text-danger")
      end

      it "returnのアイコンを返す" do
        expect(helper.inventory_log_action_icon("return")).to eq("bi bi-arrow-return-left text-warning")
        expect(helper.inventory_log_action_icon("returned")).to eq("bi bi-arrow-return-left text-warning")
      end
    end

    context "大文字小文字の処理" do
      it "大文字小文字を区別しない" do
        expect(helper.inventory_log_action_icon("RECEIPT")).to eq("bi bi-box-arrow-in-down text-success")
        expect(helper.inventory_log_action_icon("Receipt")).to eq("bi bi-box-arrow-in-down text-success")
      end
    end

    context "未定義のアクション" do
      it "デフォルトアイコンを返す" do
        expect(helper.inventory_log_action_icon("unknown")).to eq("bi bi-journal-text text-muted")
        expect(helper.inventory_log_action_icon("")).to eq("bi bi-journal-text text-muted")
        expect(helper.inventory_log_action_icon(nil)).to eq("bi bi-journal-text text-muted")
      end
    end
  end

  # ============================================
  # inventory_log_action_name メソッドのテスト
  # ============================================

  describe "#inventory_log_action_name" do
    context "英語から日本語への変換" do
      it "英語アクションを日本語に変換する" do
        expect(helper.inventory_log_action_name("receipt")).to eq("入荷")
        expect(helper.inventory_log_action_name("received")).to eq("入荷")
        expect(helper.inventory_log_action_name("shipment")).to eq("出荷")
        expect(helper.inventory_log_action_name("shipped")).to eq("出荷")
        expect(helper.inventory_log_action_name("adjustment")).to eq("調整")
        expect(helper.inventory_log_action_name("adjusted")).to eq("調整")
        expect(helper.inventory_log_action_name("transfer")).to eq("移動")
        expect(helper.inventory_log_action_name("transferred")).to eq("移動")
        expect(helper.inventory_log_action_name("disposal")).to eq("廃棄")
        expect(helper.inventory_log_action_name("disposed")).to eq("廃棄")
        expect(helper.inventory_log_action_name("stocktaking")).to eq("棚卸")
        expect(helper.inventory_log_action_name("counted")).to eq("棚卸")
        expect(helper.inventory_log_action_name("expired")).to eq("期限切れ")
        expect(helper.inventory_log_action_name("return")).to eq("返品")
        expect(helper.inventory_log_action_name("returned")).to eq("返品")
      end
    end

    context "日本語アクション" do
      it "既に日本語の場合はそのまま返す" do
        expect(helper.inventory_log_action_name("入荷")).to eq("入荷")
        expect(helper.inventory_log_action_name("出荷")).to eq("出荷")
      end
    end

    context "大文字小文字の処理" do
      it "大文字小文字を区別しない" do
        expect(helper.inventory_log_action_name("RECEIPT")).to eq("入荷")
        expect(helper.inventory_log_action_name("Receipt")).to eq("入荷")
      end
    end

    context "未定義のアクション" do
      it "humanizeした文字列を返す" do
        expect(helper.inventory_log_action_name("custom_action")).to eq("Custom action")
        expect(helper.inventory_log_action_name("bulk_update")).to eq("Bulk update")
      end
    end

    context "エッジケース" do
      it "空文字列やnilを処理する" do
        expect(helper.inventory_log_action_name("")).to eq("")
        expect(helper.inventory_log_action_name(nil)).to eq("")
      end
    end
  end

  # ============================================
  # quantity_change_badge_class メソッドのテスト
  # ============================================

  describe "#quantity_change_badge_class" do
    it "正の数量変化に成功バッジクラスを返す" do
      expect(helper.quantity_change_badge_class(50)).to eq("badge bg-success")
      expect(helper.quantity_change_badge_class(1)).to eq("badge bg-success")
    end

    it "負の数量変化に危険バッジクラスを返す" do
      expect(helper.quantity_change_badge_class(-30)).to eq("badge bg-danger")
      expect(helper.quantity_change_badge_class(-1)).to eq("badge bg-danger")
    end

    it "ゼロの数量変化にセカンダリバッジクラスを返す" do
      expect(helper.quantity_change_badge_class(0)).to eq("badge bg-secondary")
    end
  end

  # ============================================
  # quantity_change_display メソッドのテスト
  # ============================================

  describe "#quantity_change_display" do
    it "正の数量変化にプラス記号を付ける" do
      expect(helper.quantity_change_display(50)).to eq("+50")
      expect(helper.quantity_change_display(1)).to eq("+1")
    end

    it "負の数量変化はそのまま表示" do
      expect(helper.quantity_change_display(-30)).to eq("-30")
      expect(helper.quantity_change_display(-1)).to eq("-1")
    end

    it "ゼロの数量変化は±0で表示" do
      expect(helper.quantity_change_display(0)).to eq("±0")
    end
  end

  # ============================================
  # inventory_log_importance_level メソッドのテスト
  # ============================================

  describe "#inventory_log_importance_level" do
    it "100を超える変動は高重要度" do
      expect(helper.inventory_log_importance_level(inventory_log_large)).to eq("high")

      large_negative = build(:inventory_log, quantity_change: -150)
      expect(helper.inventory_log_importance_level(large_negative)).to eq("high")
    end

    it "負の変動は中重要度" do
      expect(helper.inventory_log_importance_level(inventory_log_negative)).to eq("medium")

      small_negative = build(:inventory_log, quantity_change: -5)
      expect(helper.inventory_log_importance_level(small_negative)).to eq("medium")
    end

    it "通常の正の変動は低重要度" do
      expect(helper.inventory_log_importance_level(inventory_log)).to eq("low")

      small_positive = build(:inventory_log, quantity_change: 10)
      expect(helper.inventory_log_importance_level(small_positive)).to eq("low")
    end

    it "ゼロ変動は低重要度" do
      zero_log = build(:inventory_log, quantity_change: 0)
      expect(helper.inventory_log_importance_level(zero_log)).to eq("low")
    end
  end

  # ============================================
  # inventory_log_importance_badge メソッドのテスト
  # ============================================

  describe "#inventory_log_importance_badge" do
    it "高重要度ログに重要バッジを表示" do
      result = helper.inventory_log_importance_badge(inventory_log_large)
      expect(result).to include('<span class="badge bg-danger ms-2">重要</span>')
    end

    it "中重要度ログに注意バッジを表示" do
      result = helper.inventory_log_importance_badge(inventory_log_negative)
      expect(result).to include('<span class="badge bg-warning text-dark ms-2">注意</span>')
    end

    it "低重要度ログはバッジなし" do
      result = helper.inventory_log_importance_badge(inventory_log)
      expect(result).to eq("")
    end
  end

  # ============================================
  # inventory_log_time_ago メソッドのテスト
  # ============================================

  describe "#inventory_log_time_ago" do
    it "時刻を相対表示に変換" do
      allow(helper).to receive(:time_ago_in_words).with(inventory_log.created_at, include_seconds: false).and_return("約2時間")
      result = helper.inventory_log_time_ago(inventory_log.created_at)
      expect(result).to eq("約2時間前")
    end

    it "nilの場合は不明を返す" do
      expect(helper.inventory_log_time_ago(nil)).to eq("不明")
    end
  end

  # ============================================
  # inventory_log_action_options メソッドのテスト
  # ============================================

  describe "#inventory_log_action_options" do
    it "フィルタ用のアクションオプションを返す" do
      options = helper.inventory_log_action_options

      expect(options).to be_an(Array)
      expect(options.first).to eq([ "すべてのアクション", "" ])
      expect(options).to include([ "入荷", "receipt" ])
      expect(options).to include([ "出荷", "shipment" ])
      expect(options).to include([ "調整", "adjustment" ])
      expect(options).to include([ "移動", "transfer" ])
      expect(options).to include([ "廃棄", "disposal" ])
      expect(options).to include([ "棚卸", "stocktaking" ])
      expect(options).to include([ "期限切れ", "expired" ])
      expect(options).to include([ "返品", "return" ])
    end

    it "適切な数のオプションを持つ" do
      options = helper.inventory_log_action_options
      expect(options.length).to eq(9) # すべて + 8アクション
    end
  end

  # ============================================
  # inventory_log_period_options メソッドのテスト
  # ============================================

  describe "#inventory_log_period_options" do
    it "期間フィルタ用のオプションを返す" do
      options = helper.inventory_log_period_options

      expect(options).to be_an(Array)
      expect(options.first).to eq([ "すべての期間", "" ])
      expect(options).to include([ "今日", "today" ])
      expect(options).to include([ "昨日", "yesterday" ])
      expect(options).to include([ "今週", "this_week" ])
      expect(options).to include([ "先週", "last_week" ])
      expect(options).to include([ "今月", "this_month" ])
      expect(options).to include([ "先月", "last_month" ])
      expect(options).to include([ "過去7日間", "7_days" ])
      expect(options).to include([ "過去30日間", "30_days" ])
      expect(options).to include([ "過去90日間", "90_days" ])
    end

    it "適切な数のオプションを持つ" do
      options = helper.inventory_log_period_options
      expect(options.length).to eq(11) # すべて + 10期間
    end
  end

  # ============================================
  # format_inventory_log_description メソッドのテスト
  # ============================================

  describe "#format_inventory_log_description" do
    context "通常の説明文" do
      it "短い説明文はそのまま返す" do
        description = "通常の入荷処理"
        expect(helper.format_inventory_log_description(description)).to eq("通常の入荷処理")
      end

      it "HTMLタグを除去する" do
        description = "<p>HTMLタグを含む<strong>説明文</strong></p>"
        expect(helper.format_inventory_log_description(description)).to eq("HTMLタグを含む説明文")
      end

      it "長い説明文を省略する" do
        long_description = "あ" * 150
        result = helper.format_inventory_log_description(long_description, 100)
        expect(result).to eq("あ" * 97 + "...")
        expect(result.length).to eq(100)
      end
    end

    context "エッジケース" do
      it "空文字列の場合は説明なしを返す" do
        expect(helper.format_inventory_log_description("")).to eq("説明なし")
        expect(helper.format_inventory_log_description(nil)).to eq("説明なし")
        expect(helper.format_inventory_log_description("   ")).to eq("説明なし")
      end

      it "カスタム最大文字数を適用する" do
        description = "長い説明文のテストです"
        result = helper.format_inventory_log_description(description, 10)
        expect(result).to eq("長い説明文のテ...")
      end
    end
  end

  # ============================================
  # inventory_log_csv_headers メソッドのテスト
  # ============================================

  describe "#inventory_log_csv_headers" do
    it "適切なCSVヘッダーを返す" do
      headers = helper.inventory_log_csv_headers
      expected_headers = [
        "日時", "商品名", "アクション", "数量変化", "変化後在庫",
        "実行者", "説明", "店舗", "ロット番号"
      ]
      expect(headers).to eq(expected_headers)
    end

    it "配列形式で返す" do
      headers = helper.inventory_log_csv_headers
      expect(headers).to be_an(Array)
      expect(headers.length).to eq(9)
    end
  end

  # ============================================
  # calculate_inventory_log_stats メソッドのテスト
  # ============================================

  describe "#calculate_inventory_log_stats" do
    let(:logs) do
      # モックデータの作成
      logs_mock = double("ActiveRecord::Relation")

      # 基本的なcount
      allow(logs_mock).to receive(:count).and_return(100)

      # where条件付きcount
      receipt_logs = double("ActiveRecord::Relation")
      allow(receipt_logs).to receive(:count).and_return(40)
      allow(logs_mock).to receive(:where).with(action: "receipt").and_return(receipt_logs)

      shipment_logs = double("ActiveRecord::Relation")
      allow(shipment_logs).to receive(:count).and_return(30)
      allow(logs_mock).to receive(:where).with(action: "shipment").and_return(shipment_logs)

      adjustment_logs = double("ActiveRecord::Relation")
      allow(adjustment_logs).to receive(:count).and_return(20)
      allow(logs_mock).to receive(:where).with(action: "adjustment").and_return(adjustment_logs)

      # 数量集計用
      positive_logs = double("ActiveRecord::Relation")
      allow(positive_logs).to receive(:sum).with(:quantity_change).and_return(500)
      allow(logs_mock).to receive(:where).with("quantity_change > 0").and_return(positive_logs)

      negative_logs = double("ActiveRecord::Relation")
      allow(negative_logs).to receive(:sum).with(:quantity_change).and_return(-300)
      allow(negative_logs).to receive(:abs).and_return(300)
      allow(logs_mock).to receive(:where).with("quantity_change < 0").and_return(negative_logs)

      # 日別集計
      daily_stats = double("ActiveRecord::Relation")
      allow(daily_stats).to receive(:count).and_return({ Date.today => 15, Date.yesterday => 10 })
      allow(daily_stats).to receive(:max_by).and_yield(Date.today, 15).and_return([ Date.today, 15 ])
      allow(logs_mock).to receive(:group_by_day).with(:created_at).and_return(daily_stats)

      # 最近のアクティビティ
      recent_logs = double("ActiveRecord::Relation")
      allow(recent_logs).to receive(:count).and_return(25)
      allow(logs_mock).to receive(:where).with(created_at: 24.hours.ago..Time.current).and_return(recent_logs)

      logs_mock
    end

    it "統計情報を計算する" do
      stats = helper.calculate_inventory_log_stats(logs)

      expect(stats[:total_logs]).to eq(100)
      expect(stats[:receipts_count]).to eq(40)
      expect(stats[:shipments_count]).to eq(30)
      expect(stats[:adjustments_count]).to eq(20)
      expect(stats[:total_quantity_in]).to eq(500)
      expect(stats[:total_quantity_out]).to eq(300)
      expect(stats[:most_active_day]).to eq(Date.today)
      expect(stats[:recent_activity]).to eq(25)
    end

    it "ハッシュ形式で結果を返す" do
      stats = helper.calculate_inventory_log_stats(logs)
      expect(stats).to be_a(Hash)
      expect(stats.keys).to include(:total_logs, :receipts_count, :shipments_count, :adjustments_count)
    end
  end

  # ============================================
  # inventory_log_summary_cards メソッドのテスト
  # ============================================

  describe "#inventory_log_summary_cards" do
    let(:stats) do
      {
        total_logs: 100,
        receipts_count: 40,
        shipments_count: 30,
        adjustments_count: 20
      }
    end

    it "サマリーカードのHTMLを生成する" do
      result = helper.inventory_log_summary_cards(stats)

      expect(result).to include('class="row g-3 mb-4"')
      expect(result).to include("総ログ数")
      expect(result).to include("100")
      expect(result).to include("入荷回数")
      expect(result).to include("40")
      expect(result).to include("出荷回数")
      expect(result).to include("30")
      expect(result).to include("調整回数")
      expect(result).to include("20")
    end

    it "適切なBootstrapクラスを含む" do
      result = helper.inventory_log_summary_cards(stats)

      expect(result).to include("col-md-3")
      expect(result).to include("card")
      expect(result).to include("card-body")
      expect(result).to include("text-center")
    end

    it "アイコンを含む" do
      result = helper.inventory_log_summary_cards(stats)

      expect(result).to include("bi-journal-text")
      expect(result).to include("bi-box-arrow-in-down")
      expect(result).to include("bi-box-arrow-up")
      expect(result).to include("bi-tools")
    end

    it "HTML安全な文字列を返す" do
      result = helper.inventory_log_summary_cards(stats)
      expect(result).to be_html_safe
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "各ヘルパーメソッドは高速に実行される" do
      start_time = Time.current
      100.times do
        helper.inventory_log_action_icon("receipt")
        helper.inventory_log_action_name("shipment")
        helper.quantity_change_badge_class(50)
        helper.quantity_change_display(-30)
        helper.inventory_log_importance_level(inventory_log)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # HTML安全性テスト
  # ============================================

  describe "HTML safety" do
    it "inventory_log_importance_badgeの結果はHTML安全" do
      result = helper.inventory_log_importance_badge(inventory_log_large)
      expect(result).to be_html_safe
    end

    it "inventory_log_summary_cardsの結果はHTML安全" do
      stats = { total_logs: 100, receipts_count: 40, shipments_count: 30, adjustments_count: 20 }
      result = helper.inventory_log_summary_cards(stats)
      expect(result).to be_html_safe
    end
  end

  # ============================================
  # XSS対策テスト
  # ============================================

  describe "XSS protection" do
    it "説明文のHTMLタグを適切に除去する" do
      malicious_description = '<script>alert("XSS")</script>悪意のあるスクリプト'
      result = helper.format_inventory_log_description(malicious_description)

      expect(result).not_to include('<script>')
      expect(result).to eq('alert("XSS")悪意のあるスクリプト')
    end

    it "複雑なHTMLタグを除去する" do
      complex_html = '<div onclick="malicious()"><p>内容</p><img src="x" onerror="alert()"></div>'
      result = helper.format_inventory_log_description(complex_html)

      expect(result).not_to include('<div')
      expect(result).not_to include('onclick')
      expect(result).not_to include('onerror')
      expect(result).to eq('内容')
    end
  end

  # ============================================
  # エッジケーステスト
  # ============================================

  describe "edge cases" do
    it "非常に大きな数量変化でも処理できる" do
      huge_log = build(:inventory_log, quantity_change: 999_999_999)
      expect(helper.inventory_log_importance_level(huge_log)).to eq("high")
      expect(helper.quantity_change_display(999_999_999)).to eq("+999999999")
    end

    it "非常に小さな負の数量変化でも処理できる" do
      tiny_negative_log = build(:inventory_log, quantity_change: -1)
      expect(helper.inventory_log_importance_level(tiny_negative_log)).to eq("medium")
      expect(helper.quantity_change_display(-1)).to eq("-1")
    end

    it "nilや空の統計でもサマリーカードを生成できる" do
      empty_stats = {
        total_logs: nil,
        receipts_count: 0,
        shipments_count: nil,
        adjustments_count: 0
      }

      result = helper.inventory_log_summary_cards(empty_stats)
      expect(result).to include("0") # nil値は0として表示される
      expect(result).to be_html_safe
    end
  end
end
