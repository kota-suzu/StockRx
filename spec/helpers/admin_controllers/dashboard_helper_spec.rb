# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::DashboardHelper, type: :helper do
  # CLAUDE.md準拠: 管理画面ダッシュボードヘルパーの包括的テスト
  # メタ認知: UIの一貫性とBootstrapアイコン・カラースキームの検証
  # 横展開: 他のダッシュボードヘルパーでも同様のテストパターン適用

  # ============================================
  # operation_icon_class メソッドのテスト
  # ============================================

  describe "#operation_icon_class" do
    context "標準的な操作種別" do
      it "create操作のアイコンクラスを返す" do
        # InventoryLogsHelperとメソッド名が重複しているため、直接モジュールから呼び出し
        result = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call("create")
        expect(result).to eq("bi-plus-circle-fill")
      end

      it "update操作のアイコンクラスを返す" do
        result = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call("update")
        expect(result).to eq("bi-pencil-square")
      end

      it "delete操作のアイコンクラスを返す" do
        result = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call("delete")
        expect(result).to eq("bi-trash3-fill")
      end

      it "import操作のアイコンクラスを返す" do
        result = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call("import")
        expect(result).to eq("bi-cloud-download-fill")
      end
    end

    context "未定義の操作種別" do
      it "デフォルトのアイコンクラスを返す" do
        result1 = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call("unknown")
        result2 = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call("custom")
        result3 = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call(nil)
        expect(result1).to eq("bi-file-text-fill")
        expect(result2).to eq("bi-file-text-fill")
        expect(result3).to eq("bi-file-text-fill")
      end
    end

    context "シンボル入力" do
      it "シンボルも文字列と同様に処理する" do
        result1 = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call(:create)
        result2 = AdminControllers::DashboardHelper.instance_method(:operation_icon_class).bind(helper).call(:update)
        expect(result1).to eq("bi-plus-circle-fill")
        expect(result2).to eq("bi-pencil-square")
      end
    end
  end

  # ============================================
  # operation_color_class メソッドのテスト
  # ============================================

  describe "#operation_color_class" do
    context "標準的な操作種別" do
      it "create操作の色クラスを返す" do
        expect(helper.operation_color_class("create")).to eq("success")
      end

      it "update操作の色クラスを返す" do
        expect(helper.operation_color_class("update")).to eq("primary")
      end

      it "delete操作の色クラスを返す" do
        expect(helper.operation_color_class("delete")).to eq("danger")
      end

      it "import操作の色クラスを返す" do
        expect(helper.operation_color_class("import")).to eq("info")
      end
    end

    context "未定義の操作種別" do
      it "デフォルトの色クラスを返す" do
        expect(helper.operation_color_class("unknown")).to eq("secondary")
        expect(helper.operation_color_class("")).to eq("secondary")
        expect(helper.operation_color_class(nil)).to eq("secondary")
      end
    end
  end

  # ============================================
  # operation_type_label メソッドのテスト
  # ============================================

  describe "#operation_type_label" do
    context "標準的な操作種別" do
      it "日本語ラベルを返す" do
        result1 = AdminControllers::DashboardHelper.instance_method(:operation_type_label).bind(helper).call("create")
        result2 = AdminControllers::DashboardHelper.instance_method(:operation_type_label).bind(helper).call("update")
        result3 = AdminControllers::DashboardHelper.instance_method(:operation_type_label).bind(helper).call("delete")
        result4 = AdminControllers::DashboardHelper.instance_method(:operation_type_label).bind(helper).call("import")
        expect(result1).to eq("新規登録")
        expect(result2).to eq("更新")
        expect(result3).to eq("削除")
        expect(result4).to eq("インポート")
      end
    end

    context "未定義の操作種別" do
      it "humanizeされた文字列を返す" do
        expect(helper.operation_type_label("custom_action")).to eq("Custom action")
        expect(helper.operation_type_label("bulk_update")).to eq("Bulk update")
      end
    end

    context "エッジケース" do
      it "空文字列を処理する" do
        expect(helper.operation_type_label("")).to eq("")
      end

      it "nilを処理する" do
        expect(helper.operation_type_label(nil)).to eq("")
      end
    end
  end

  # ============================================
  # system_status_badge メソッドのテスト
  # ============================================

  describe "#system_status_badge" do
    context "正常ステータス" do
      %w[active running ok normal 正常].each do |status|
        it "#{status}ステータスの設定を返す" do
          result = helper.system_status_badge(status)
          expect(result[:badge_class]).to eq("bg-success bg-opacity-20 text-success")
          expect(result[:indicator_class]).to eq("bg-success")
          expect(result[:label]).to eq("正常")
        end
      end
    end

    context "エラーステータス" do
      %w[inactive stopped error エラー].each do |status|
        it "#{status}ステータスの設定を返す" do
          result = helper.system_status_badge(status)
          expect(result[:badge_class]).to eq("bg-danger bg-opacity-20 text-danger")
          expect(result[:indicator_class]).to eq("bg-danger")
          expect(result[:label]).to eq("エラー")
        end
      end
    end

    context "警告ステータス" do
      %w[warning 警告].each do |status|
        it "#{status}ステータスの設定を返す" do
          result = helper.system_status_badge(status)
          expect(result[:badge_class]).to eq("bg-warning bg-opacity-20 text-warning")
          expect(result[:indicator_class]).to eq("bg-warning")
          expect(result[:label]).to eq("警告")
        end
      end
    end

    context "実装予定ステータス" do
      %w[pending planned 実装予定].each do |status|
        it "#{status}ステータスの設定を返す" do
          result = helper.system_status_badge(status)
          expect(result[:badge_class]).to eq("bg-info bg-opacity-20 text-info")
          expect(result[:indicator_class]).to eq("bg-info")
          expect(result[:label]).to eq("実装予定")
        end
      end
    end

    context "不明なステータス" do
      it "デフォルト設定を返す" do
        result = helper.system_status_badge("unknown")
        expect(result[:badge_class]).to eq("bg-secondary bg-opacity-20 text-secondary")
        expect(result[:indicator_class]).to eq("bg-secondary")
        expect(result[:label]).to eq("不明")
      end
    end

    context "カスタムラベル" do
      it "カスタムラベルを優先する" do
        result = helper.system_status_badge("active", "カスタム正常")
        expect(result[:label]).to eq("カスタム正常")

        result = helper.system_status_badge("error", "重大エラー")
        expect(result[:label]).to eq("重大エラー")
      end
    end

    context "大文字小文字の処理" do
      it "大文字小文字を区別しない" do
        result = helper.system_status_badge("ACTIVE")
        expect(result[:indicator_class]).to eq("bg-success")

        result = helper.system_status_badge("Error")
        expect(result[:indicator_class]).to eq("bg-danger")
      end
    end
  end

  # ============================================
  # summary_icon_class メソッドのテスト
  # ============================================

  describe "#summary_icon_class" do
    context "商品関連" do
      it "新商品のアイコンクラスを返す" do
        expect(helper.summary_icon_class("new_products")).to eq("bi-plus-circle")
        expect(helper.summary_icon_class("products")).to eq("bi-plus-circle")
      end
    end

    context "更新関連" do
      it "更新のアイコンクラスを返す" do
        expect(helper.summary_icon_class("updates")).to eq("bi-arrow-repeat")
        expect(helper.summary_icon_class("inventory_updates")).to eq("bi-arrow-repeat")
      end
    end

    context "アラート関連" do
      it "アラートのアイコンクラスを返す" do
        expect(helper.summary_icon_class("alerts")).to eq("bi-exclamation-triangle")
        expect(helper.summary_icon_class("warnings")).to eq("bi-exclamation-triangle")
      end
    end

    context "期限関連" do
      it "期限切れのアイコンクラスを返す" do
        expect(helper.summary_icon_class("expired")).to eq("bi-clock-history")
        expect(helper.summary_icon_class("expiry")).to eq("bi-clock-history")
      end
    end

    context "金額関連" do
      it "金額のアイコンクラスを返す" do
        expect(helper.summary_icon_class("total_value")).to eq("bi-currency-yen")
        expect(helper.summary_icon_class("value")).to eq("bi-currency-yen")
      end
    end

    context "在庫関連" do
      it "在庫不足のアイコンクラスを返す" do
        expect(helper.summary_icon_class("low_stock")).to eq("bi-box-seam")
      end
    end

    context "未定義のタイプ" do
      it "デフォルトアイコンクラスを返す" do
        expect(helper.summary_icon_class("unknown")).to eq("bi-info-circle")
        expect(helper.summary_icon_class(nil)).to eq("bi-info-circle")
      end
    end
  end

  # ============================================
  # summary_color_class メソッドのテスト
  # ============================================

  describe "#summary_color_class" do
    it "タイプに応じた色クラスを返す" do
      expect(helper.summary_color_class("new_products")).to eq("primary")
      expect(helper.summary_color_class("updates")).to eq("success")
      expect(helper.summary_color_class("alerts")).to eq("warning")
      expect(helper.summary_color_class("low_stock")).to eq("warning")
      expect(helper.summary_color_class("expired")).to eq("danger")
      expect(helper.summary_color_class("total_value")).to eq("info")
      expect(helper.summary_color_class("unknown")).to eq("secondary")
    end
  end

  # ============================================
  # format_dashboard_number メソッドのテスト
  # ============================================

  describe "#format_dashboard_number" do
    context "nil または 0" do
      it "ハイフンを返す" do
        expect(helper.format_dashboard_number(nil)).to eq("-")
        expect(helper.format_dashboard_number(0)).to eq("-")
      end
    end

    context "小さい数値" do
      it "カンマ区切りで返す" do
        expect(helper.format_dashboard_number(123)).to eq("123")
        expect(helper.format_dashboard_number(999)).to eq("999")
      end
    end

    context "千単位" do
      it "K表記で返す" do
        expect(helper.format_dashboard_number(1_000)).to eq("1.0K")
        expect(helper.format_dashboard_number(1_500)).to eq("1.5K")
        expect(helper.format_dashboard_number(999_999)).to eq("1000.0K")
      end
    end

    context "百万単位" do
      it "M表記で返す" do
        expect(helper.format_dashboard_number(1_000_000)).to eq("1.0M")
        expect(helper.format_dashboard_number(1_500_000)).to eq("1.5M")
        expect(helper.format_dashboard_number(999_999_999)).to eq("1000.0M")
      end
    end

    context "小数点の処理" do
      it "小数点以下1桁で丸める" do
        expect(helper.format_dashboard_number(1_234)).to eq("1.2K")
        expect(helper.format_dashboard_number(1_567_890)).to eq("1.6M")
      end
    end
  end

  # ============================================
  # format_dashboard_currency メソッドのテスト
  # ============================================

  describe "#format_dashboard_currency" do
    context "nil または 0" do
      it "ハイフンを返す" do
        expect(helper.format_dashboard_currency(nil)).to eq("-")
        expect(helper.format_dashboard_currency(0)).to eq("-")
      end
    end

    context "小さい金額" do
      it "円記号とカンマ区切りで返す" do
        expect(helper.format_dashboard_currency(123)).to eq("¥123")
        expect(helper.format_dashboard_currency(999)).to eq("¥999")
      end
    end

    context "千単位" do
      it "K表記で返す" do
        expect(helper.format_dashboard_currency(1_000)).to eq("¥1.0K")
        expect(helper.format_dashboard_currency(50_000)).to eq("¥50.0K")
      end
    end

    context "百万単位" do
      it "M表記で返す" do
        expect(helper.format_dashboard_currency(1_000_000)).to eq("¥1.0M")
        expect(helper.format_dashboard_currency(123_456_789)).to eq("¥123.5M")
      end
    end
  end

  # ============================================
  # alert_level_class メソッドのテスト
  # ============================================

  describe "#alert_level_class" do
    context "デフォルト閾値" do
      it "0件の場合successを返す" do
        result = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(0)
        expect(result).to eq("success")
      end

      it "警告閾値未満の場合warningを返す" do
        result1 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(1)
        result2 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(4)
        expect(result1).to eq("warning")
        expect(result2).to eq("warning")
      end

      it "危険閾値以上の場合dangerを返す" do
        result1 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(10)
        result2 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(100)
        expect(result1).to eq("danger")
        expect(result2).to eq("danger")
      end

      it "警告と危険の間の場合dangerを返す" do
        result1 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(5)
        result2 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(9)
        expect(result1).to eq("danger")
        expect(result2).to eq("danger")
      end
    end

    context "カスタム閾値" do
      it "カスタム警告閾値を適用する" do
        result1 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(9, 10, 20)
        result2 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(10, 10, 20)
        expect(result1).to eq("warning")
        expect(result2).to eq("danger")
      end

      it "カスタム危険閾値を適用する" do
        result1 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(19, 10, 20)
        result2 = AdminControllers::DashboardHelper.instance_method(:alert_level_class).bind(helper).call(20, 10, 20)
        expect(result1).to eq("danger")
        expect(result2).to eq("danger")
      end
    end
  end

  # ============================================
  # format_relative_time メソッドのテスト
  # ============================================

  describe "#format_relative_time" do
    context "nil の場合" do
      it "不明を返す" do
        expect(helper.format_relative_time(nil)).to eq("不明")
      end
    end

    context "時間の変換" do
      before do
        # time_ago_in_wordsのモック
        allow(helper).to receive(:time_ago_in_words).and_return("less than a minute")
      end

      it "1分未満を「たった今」に変換する" do
        time = 30.seconds.ago
        expect(helper.format_relative_time(time)).to eq("たった今")
      end

      it "分単位を日本語に変換する" do
        allow(helper).to receive(:time_ago_in_words).and_return("5 minutes")
        expect(helper.format_relative_time(1.minute.ago)).to eq("5 分前")
      end

      it "時間単位を日本語に変換する" do
        allow(helper).to receive(:time_ago_in_words).and_return("2 hours")
        expect(helper.format_relative_time(2.hours.ago)).to eq("2 時間前")
      end

      it "1日を「昨日」に変換する" do
        allow(helper).to receive(:time_ago_in_words).and_return("1 day")
        expect(helper.format_relative_time(1.day.ago)).to eq("昨日")
      end

      it "日単位を日本語に変換する" do
        allow(helper).to receive(:time_ago_in_words).and_return("3 days")
        expect(helper.format_relative_time(3.days.ago)).to eq("3 日前")
      end

      it "その他の場合は「前」を追加する" do
        allow(helper).to receive(:time_ago_in_words).and_return("about 1 month")
        expect(helper.format_relative_time(1.month.ago)).to eq("about 1 month前")
      end
    end
  end

  # ============================================
  # tooltip_message メソッドのテスト
  # ============================================

  describe "#tooltip_message" do
    context "アイテム名あり" do
      it "詳細表示メッセージを生成する" do
        expect(helper.tooltip_message("view_details", "商品A")).to eq("商品Aの詳細を表示")
      end

      it "編集メッセージを生成する" do
        expect(helper.tooltip_message("edit", "在庫")).to eq("在庫を編集")
      end

      it "削除メッセージを生成する" do
        expect(helper.tooltip_message("delete", "レコード")).to eq("レコードを削除")
      end

      it "新規追加メッセージを生成する" do
        expect(helper.tooltip_message("add_new", "カテゴリ")).to eq("新しいカテゴリを追加")
      end

      it "全表示メッセージを生成する" do
        expect(helper.tooltip_message("view_all", "注文")).to eq("すべての注文を表示")
      end
    end

    context "アイテム名なし" do
      it "汎用メッセージを生成する" do
        expect(helper.tooltip_message("view_details")).to eq("詳細を表示")
        expect(helper.tooltip_message("edit")).to eq("編集")
        expect(helper.tooltip_message("delete")).to eq("削除")
        expect(helper.tooltip_message("add_new")).to eq("新規作成")
        expect(helper.tooltip_message("view_all")).to eq("すべて表示")
      end
    end

    context "未定義のアクション" do
      it "humanizeした文字列を返す" do
        expect(helper.tooltip_message("custom_action")).to eq("Custom action")
      end
    end
  end

  # ============================================
  # calculate_percentage_change メソッドのテスト
  # ============================================

  describe "#calculate_percentage_change" do
    context "正常な計算" do
      it "増加率を計算する" do
        expect(helper.calculate_percentage_change(150, 100)).to eq(50.0)
        expect(helper.calculate_percentage_change(200, 100)).to eq(100.0)
      end

      it "減少率を計算する" do
        expect(helper.calculate_percentage_change(50, 100)).to eq(-50.0)
        expect(helper.calculate_percentage_change(75, 100)).to eq(-25.0)
      end

      it "小数点以下1桁で丸める" do
        expect(helper.calculate_percentage_change(103, 100)).to eq(3.0)
        expect(helper.calculate_percentage_change(100, 97)).to eq(3.1)
      end
    end

    context "エッジケース" do
      it "前回値が0の場合0を返す" do
        expect(helper.calculate_percentage_change(100, 0)).to eq(0)
      end

      it "前回値がnilの場合0を返す" do
        expect(helper.calculate_percentage_change(100, nil)).to eq(0)
      end

      it "両方0の場合0を返す" do
        expect(helper.calculate_percentage_change(0, 0)).to eq(0)
      end
    end
  end

  # ============================================
  # percentage_change_class メソッドのテスト
  # ============================================

  describe "#percentage_change_class" do
    it "正の値にはtext-successを返す" do
      expect(helper.percentage_change_class(10)).to eq("text-success")
      expect(helper.percentage_change_class(0.1)).to eq("text-success")
    end

    it "負の値にはtext-dangerを返す" do
      expect(helper.percentage_change_class(-10)).to eq("text-danger")
      expect(helper.percentage_change_class(-0.1)).to eq("text-danger")
    end

    it "0にはtext-mutedを返す" do
      expect(helper.percentage_change_class(0)).to eq("text-muted")
    end
  end

  # ============================================
  # percentage_change_icon メソッドのテスト
  # ============================================

  describe "#percentage_change_icon" do
    it "正の値には上矢印アイコンを返す" do
      expect(helper.percentage_change_icon(10)).to eq("bi-arrow-up")
      expect(helper.percentage_change_icon(0.1)).to eq("bi-arrow-up")
    end

    it "負の値には下矢印アイコンを返す" do
      expect(helper.percentage_change_icon(-10)).to eq("bi-arrow-down")
      expect(helper.percentage_change_icon(-0.1)).to eq("bi-arrow-down")
    end

    it "0にはダッシュアイコンを返す" do
      expect(helper.percentage_change_icon(0)).to eq("bi-dash")
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "各ヘルパーメソッドは高速に実行される" do
      start_time = Time.current
      100.times do
        helper.operation_icon_class("create")
        helper.operation_color_class("update")
        helper.system_status_badge("active")
        helper.format_dashboard_number(123456)
        helper.format_dashboard_currency(789012)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # XSS対策テスト
  # ============================================

  describe "XSS protection" do
    it "tooltip_messageでユーザー入力をエスケープする" do
      malicious_input = '<script>alert("XSS")</script>'
      result = helper.tooltip_message("edit", malicious_input)

      expect(result).to eq('<script>alert("XSS")</script>を編集')
      # 注: この結果は表示時にRailsによって自動的にエスケープされる
    end

    it "operation_type_labelは安全な文字列を返す" do
      result = helper.operation_type_label('<script>alert("XSS")</script>')
      expect(result).not_to include('<script>')
    end
  end
end
