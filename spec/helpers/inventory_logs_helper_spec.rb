# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLogsHelper, type: :helper do
  # CLAUDE.md準拠: 在庫ログヘルパーの包括的テスト
  # メタ認知: ログ表示の一貫性とUI/UXの品質保証
  # 横展開: 他のログ系ヘルパー（AuditLog等）でも同様のパターン適用

  let(:admin) { create(:admin) }
  let(:inventory) { create(:inventory) }
  let(:inventory_log) { create(:inventory_log, inventory: inventory, admin: admin) }

  # ============================================
  # operation_badge_class メソッドのテスト
  # ============================================

  describe "#operation_badge_class" do
    context "追加・作成操作" do
      it "add操作で成功バッジクラスを返す" do
        expect(helper.operation_badge_class("add")).to eq("badge bg-success bg-opacity-20 text-success")
      end

      it "create操作で成功バッジクラスを返す" do
        expect(helper.operation_badge_class("create")).to eq("badge bg-success bg-opacity-20 text-success")
      end
    end

    context "削除操作" do
      it "remove操作で危険バッジクラスを返す" do
        expect(helper.operation_badge_class("remove")).to eq("badge bg-danger bg-opacity-20 text-danger")
      end

      it "delete操作で危険バッジクラスを返す" do
        expect(helper.operation_badge_class("delete")).to eq("badge bg-danger bg-opacity-20 text-danger")
      end
    end

    context "調整・更新操作" do
      it "adjust操作でプライマリーバッジクラスを返す" do
        expect(helper.operation_badge_class("adjust")).to eq("badge bg-primary bg-opacity-20 text-primary")
      end

      it "update操作でプライマリーバッジクラスを返す" do
        expect(helper.operation_badge_class("update")).to eq("badge bg-primary bg-opacity-20 text-primary")
      end
    end

    context "インポート操作" do
      it "import操作で情報バッジクラスを返す" do
        expect(helper.operation_badge_class("import")).to eq("badge bg-info bg-opacity-20 text-info")
      end
    end

    context "その他の操作" do
      it "未知の操作でセカンダリーバッジクラスを返す" do
        expect(helper.operation_badge_class("unknown")).to eq("badge bg-secondary bg-opacity-20 text-secondary")
      end

      it "空文字列でセカンダリーバッジクラスを返す" do
        expect(helper.operation_badge_class("")).to eq("badge bg-secondary bg-opacity-20 text-secondary")
      end

      it "nilでセカンダリーバッジクラスを返す" do
        expect(helper.operation_badge_class(nil)).to eq("badge bg-secondary bg-opacity-20 text-secondary")
      end
    end

    context "型変換" do
      it "シンボルでも適切に処理される" do
        expect(helper.operation_badge_class(:create)).to eq("badge bg-success bg-opacity-20 text-success")
      end
    end
  end

  # ============================================
  # operation_icon_class メソッドのテスト
  # ============================================

  describe "#operation_icon_class" do
    context "操作種別ごとのアイコン" do
      it "add操作でプラスアイコンを返す" do
        expect(helper.operation_icon_class("add")).to eq("bi-plus-circle-fill text-success")
      end

      it "remove操作でゴミ箱アイコンを返す" do
        expect(helper.operation_icon_class("remove")).to eq("bi-trash3-fill text-danger")
      end

      it "adjust操作で鉛筆アイコンを返す" do
        expect(helper.operation_icon_class("adjust")).to eq("bi-pencil-square text-primary")
      end

      it "import操作でダウンロードアイコンを返す" do
        expect(helper.operation_icon_class("import")).to eq("bi-cloud-download-fill text-info")
      end

      it "その他の操作でファイルアイコンを返す" do
        expect(helper.operation_icon_class("other")).to eq("bi-file-text-fill text-secondary")
      end
    end

    context "Bootstrap Icons準拠" do
      %w[add remove adjust import other].each do |operation|
        it "#{operation}のアイコンがBootstrap Icons形式" do
          icon_class = helper.operation_icon_class(operation)
          expect(icon_class).to start_with("bi-")
          expect(icon_class).to match(/text-(success|danger|primary|info|secondary)/)
        end
      end
    end
  end

  # ============================================
  # operation_type_label メソッドのテスト
  # ============================================

  describe "#operation_type_label" do
    context "基本的な操作種別" do
      it "add/createで追加・新規登録を返す" do
        expect(helper.operation_type_label("add")).to eq("追加・新規登録")
        expect(helper.operation_type_label("create")).to eq("追加・新規登録")
      end

      it "remove/deleteで削除を返す" do
        expect(helper.operation_type_label("remove")).to eq("削除")
        expect(helper.operation_type_label("delete")).to eq("削除")
      end

      it "adjust/updateで調整・更新を返す" do
        expect(helper.operation_type_label("adjust")).to eq("調整・更新")
        expect(helper.operation_type_label("update")).to eq("調整・更新")
      end
    end

    context "拡張操作種別" do
      it "exportでエクスポートを返す" do
        expect(helper.operation_type_label("export")).to eq("エクスポート")
      end

      it "transferで移動を返す" do
        expect(helper.operation_type_label("transfer")).to eq("移動")
      end

      it "countで棚卸を返す" do
        expect(helper.operation_type_label("count")).to eq("棚卸")
      end
    end

    context "未定義の操作種別" do
      it "未知の操作でhumanize形式を返す" do
        expect(helper.operation_type_label("custom_operation")).to eq("Custom operation")
      end
    end
  end

  # ============================================
  # operation_type_short_label メソッドのテスト
  # ============================================

  describe "#operation_type_short_label" do
    it "短縮形のラベルを返す" do
      expect(helper.operation_type_short_label("add")).to eq("追加")
      expect(helper.operation_type_short_label("remove")).to eq("削除")
      expect(helper.operation_type_short_label("adjust")).to eq("更新")
      expect(helper.operation_type_short_label("import")).to eq("インポート")
      expect(helper.operation_type_short_label("other")).to eq("other")
    end
  end

  # ============================================
  # inventory_log_filter_links メソッドのテスト
  # ============================================

  describe "#inventory_log_filter_links" do
    context "フィルターリンクの生成" do
      it "ボタングループを生成する" do
        result = helper.inventory_log_filter_links
        expect(result).to include('class="btn-group mb-3"')
        expect(result).to include('role="group"')
      end

      it "全てのフィルターオプションを含む" do
        result = helper.inventory_log_filter_links
        expect(result).to include("全て")
        expect(result).to include("追加")
        expect(result).to include("更新")
        expect(result).to include("削除")
        expect(result).to include("インポート")
      end

      it "各フィルターに適切なアイコンを含む" do
        result = helper.inventory_log_filter_links
        expect(result).to include("bi-list")
        expect(result).to include("bi-plus-circle")
        expect(result).to include("bi-pencil-square")
        expect(result).to include("bi-trash")
        expect(result).to include("bi-download")
      end
    end

    context "アクティブ状態の表示" do
      it "現在のフィルターがアクティブクラスを持つ" do
        result = helper.inventory_log_filter_links("create")
        expect(result).to match(/<a[^>]*class="[^"]*active[^"]*"[^>]*>.*追加/)
      end

      it "フィルターなしの場合、全てがアクティブ" do
        result = helper.inventory_log_filter_links(nil)
        expect(result).to match(/<a[^>]*class="[^"]*active[^"]*"[^>]*>.*全て/)
      end
    end

    context "HTMLの安全性" do
      it "HTML安全な文字列を返す" do
        result = helper.inventory_log_filter_links
        expect(result).to be_html_safe
      end
    end
  end

  # ============================================
  # log_importance_class メソッドのテスト
  # ============================================

  describe "#log_importance_class" do
    it "削除操作で危険ボーダークラスを返す" do
      log = build(:inventory_log, operation_type: "delete")
      expect(helper.log_importance_class(log)).to eq("border-start border-danger border-3")
    end

    it "インポート操作で情報ボーダークラスを返す" do
      log = build(:inventory_log, operation_type: "import")
      expect(helper.log_importance_class(log)).to eq("border-start border-info border-3")
    end

    it "作成操作で成功ボーダークラスを返す" do
      log = build(:inventory_log, operation_type: "create")
      expect(helper.log_importance_class(log)).to eq("border-start border-success border-3")
    end

    it "その他の操作で空文字を返す" do
      log = build(:inventory_log, operation_type: "update")
      expect(helper.log_importance_class(log)).to eq("")
    end
  end

  # ============================================
  # format_log_details メソッドのテスト
  # ============================================

  describe "#format_log_details" do
    context "詳細情報のフォーマット" do
      it "数量変更を含む" do
        log = build(:inventory_log, quantity_changed: 10)
        expect(helper.format_log_details(log)).to include("数量: 10")
      end

      it "備考を含む（切り詰めあり）" do
        long_note = "あ" * 100
        log = build(:inventory_log, note: long_note)
        result = helper.format_log_details(log)
        expect(result).to include("備考:")
        expect(result.length).to be < 100
      end

      it "バッチIDを含む" do
        log = build(:inventory_log, batch_id: 123)
        expect(helper.format_log_details(log)).to include("バッチ: 123")
      end

      it "複数の詳細を | で結合する" do
        log = build(:inventory_log,
          quantity_changed: 5,
          note: "テスト",
          batch_id: 456
        )
        result = helper.format_log_details(log)
        expect(result).to eq("数量: 5 | 備考: テスト | バッチ: 456")
      end
    end

    context "空の詳細" do
      it "全ての詳細が空の場合、空文字を返す" do
        log = build(:inventory_log,
          quantity_changed: nil,
          note: nil,
          batch_id: nil
        )
        expect(helper.format_log_details(log)).to eq("")
      end
    end
  end

  # ============================================
  # format_log_timestamp メソッドのテスト
  # ============================================

  describe "#format_log_timestamp" do
    context "相対時間表示" do
      it "1日以内の場合、相対時間を表示" do
        timestamp = 2.hours.ago
        result = helper.format_log_timestamp(timestamp)
        expect(result).to include("時間前")
      end

      it "数分前の表示" do
        timestamp = 30.minutes.ago
        result = helper.format_log_timestamp(timestamp)
        expect(result).to include("分前")
      end
    end

    context "絶対時間表示" do
      it "1日より前の場合、日付形式で表示" do
        timestamp = 2.days.ago
        result = helper.format_log_timestamp(timestamp)
        expect(result).to match(/\d{4}\/\d{2}\/\d{2}/)
      end
    end

    context "nilの処理" do
      it "nilの場合、不明を返す" do
        expect(helper.format_log_timestamp(nil)).to eq("不明")
      end
    end
  end

  # ============================================
  # format_log_user メソッドのテスト
  # ============================================

  describe "#format_log_user" do
    context "管理者ログ" do
      it "adminが存在する場合、メールアドレスを返す" do
        log = build(:inventory_log, admin: admin)
        expect(helper.format_log_user(log)).to eq(admin.email)
      end
    end

    context "将来の拡張対応" do
      it "userメソッドが存在し、nameがある場合、名前を返す" do
        user = double("User", name: "テストユーザー", email: "test@example.com")
        log = double("Log", admin: nil, user: user)
        allow(log).to receive(:respond_to?).with(:admin).and_return(true)
        allow(log).to receive(:respond_to?).with(:user).and_return(true)

        expect(helper.format_log_user(log)).to eq("テストユーザー")
      end

      it "userメソッドが存在し、nameがない場合、メールを返す" do
        user = double("User", name: nil, email: "test@example.com")
        log = double("Log", admin: nil, user: user)
        allow(log).to receive(:respond_to?).with(:admin).and_return(true)
        allow(log).to receive(:respond_to?).with(:user).and_return(true)

        expect(helper.format_log_user(log)).to eq("test@example.com")
      end
    end

    context "システムログ" do
      it "adminもuserもない場合、システムを返す" do
        log = build(:inventory_log, admin: nil)
        allow(log).to receive(:respond_to?).with(:user).and_return(false)

        expect(helper.format_log_user(log)).to eq("システム")
      end
    end
  end

  # ============================================
  # operation_count_badge メソッドのテスト
  # ============================================

  describe "#operation_count_badge" do
    context "カウントが0の場合" do
      it "空文字を返す" do
        expect(helper.operation_count_badge("create", 0)).to eq("")
      end
    end

    context "カウントが正の場合" do
      it "create操作で成功バッジを返す" do
        result = helper.operation_count_badge("create", 10)
        expect(result).to include("badge bg-success")
        expect(result).to include("10")
      end

      it "update操作でプライマリーバッジを返す" do
        result = helper.operation_count_badge("update", 5)
        expect(result).to include("badge bg-primary")
        expect(result).to include("5")
      end

      it "delete操作で危険バッジを返す" do
        result = helper.operation_count_badge("delete", 3)
        expect(result).to include("badge bg-danger")
        expect(result).to include("3")
      end

      it "import操作で情報バッジを返す" do
        result = helper.operation_count_badge("import", 100)
        expect(result).to include("badge bg-info")
        expect(result).to include("100")
      end

      it "その他の操作でセカンダリーバッジを返す" do
        result = helper.operation_count_badge("other", 7)
        expect(result).to include("badge bg-secondary")
        expect(result).to include("7")
      end
    end

    context "HTMLの安全性" do
      it "HTML安全な文字列を返す" do
        result = helper.operation_count_badge("create", 10)
        expect(result).to be_html_safe
      end
    end
  end

  # ============================================
  # group_logs_by_date メソッドのテスト
  # ============================================

  describe "#group_logs_by_date" do
    it "日付でログをグループ化する" do
      log1 = create(:inventory_log, created_at: Date.today)
      log2 = create(:inventory_log, created_at: Date.today)
      log3 = create(:inventory_log, created_at: 1.day.ago)

      logs = [ log1, log2, log3 ]
      grouped = helper.group_logs_by_date(logs)

      expect(grouped.keys.first).to eq(Date.today)
      expect(grouped[Date.today].count).to eq(2)
      expect(grouped[1.day.ago.to_date].count).to eq(1)
    end

    it "新しい日付順にソートする" do
      log_old = create(:inventory_log, created_at: 3.days.ago)
      log_new = create(:inventory_log, created_at: Date.today)

      logs = [ log_old, log_new ]
      grouped = helper.group_logs_by_date(logs)

      expect(grouped.keys.first).to eq(Date.today)
      expect(grouped.keys.last).to eq(3.days.ago.to_date)
    end
  end

  # ============================================
  # today_log? メソッドのテスト
  # ============================================

  describe "#today_log?" do
    it "今日のログの場合trueを返す" do
      log = build(:inventory_log, created_at: Time.current)
      expect(helper.today_log?(log)).to be_truthy
    end

    it "昨日のログの場合falseを返す" do
      log = build(:inventory_log, created_at: 1.day.ago)
      expect(helper.today_log?(log)).to be_falsey
    end

    it "時刻が深夜0時直前でも正しく判定する" do
      log = build(:inventory_log, created_at: Date.today.end_of_day)
      expect(helper.today_log?(log)).to be_truthy
    end
  end

  # ============================================
  # log_period_links メソッドのテスト
  # ============================================

  describe "#log_period_links" do
    it "期間フィルターのボタングループを生成する" do
      result = helper.log_period_links
      expect(result).to include('class="btn-group btn-group-sm mb-3"')
      expect(result).to include('role="group"')
    end

    it "全ての期間オプションを含む" do
      result = helper.log_period_links
      expect(result).to include("今日")
      expect(result).to include("今週")
      expect(result).to include("今月")
      expect(result).to include("全期間")
    end

    it "現在の期間がアクティブクラスを持つ" do
      result = helper.log_period_links("week")
      expect(result).to match(/<a[^>]*class="[^"]*active[^"]*"[^>]*>今週/)
    end

    it "各リンクが適切なパラメータを含む" do
      result = helper.log_period_links
      expect(result).to include('period=today')
      expect(result).to include('period=week')
      expect(result).to include('period=month')
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "operation_badge_class は高速" do
      start_time = Time.current
      1000.times do
        %w[add remove adjust import other].each do |op|
          helper.operation_badge_class(op)
        end
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "format_log_details は高速" do
      log = build(:inventory_log,
        quantity_changed: 10,
        note: "テスト" * 20,
        batch_id: 123
      )

      start_time = Time.current
      1000.times do
        helper.format_log_details(log)
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # Bootstrap整合性テスト
  # ============================================

  describe "Bootstrap consistency" do
    it "バッジクラスがBootstrap 5準拠" do
      %w[add remove adjust import other].each do |op|
        badge_class = helper.operation_badge_class(op)
        expect(badge_class).to include("badge")
        expect(badge_class).to match(/bg-(success|danger|primary|info|secondary)/)
        expect(badge_class).to include("bg-opacity-20")
      end
    end

    it "ボタングループがBootstrap 5準拠" do
      filter_links = helper.inventory_log_filter_links
      expect(filter_links).to include("btn-group")
      expect(filter_links).to include("btn-outline-primary")
    end
  end

  # ============================================
  # 国際化対応テスト
  # ============================================

  describe "internationalization" do
    it "日本語ラベルが適切に表示される" do
      expect(helper.operation_type_label("create")).to include("追加")
      expect(helper.operation_type_label("delete")).to include("削除")
      expect(helper.operation_type_label("update")).to include("更新")
    end

    it "時間表記が日本語形式" do
      timestamp = 3.hours.ago
      result = helper.format_log_timestamp(timestamp)
      expect(result).to match(/時間前/)
    end
  end

  # ============================================
  # エッジケーステスト
  # ============================================

  describe "edge cases" do
    it "非常に長い備考を適切に切り詰める" do
      log = build(:inventory_log, note: "あ" * 1000)
      result = helper.format_log_details(log)
      expect(result.length).to be < 100
      expect(result).to include("...")
    end

    it "特殊文字を含む操作種別を処理する" do
      expect { helper.operation_badge_class("test_operation!@#") }.not_to raise_error
    end

    it "大量のログをグループ化してもメモリ効率的" do
      logs = 1000.times.map { |i| build(:inventory_log, created_at: i.days.ago) }

      expect {
        helper.group_logs_by_date(logs)
      }.not_to raise_error
    end
  end

  # ============================================
  # XSS対策テスト
  # ============================================

  describe "XSS protection" do
    it "ユーザー入力を含むログ詳細をエスケープする" do
      malicious_note = '<script>alert("XSS")</script>'
      log = build(:inventory_log, note: malicious_note)

      result = helper.format_log_details(log)
      expect(result).not_to include('<script>')
      expect(result).to include('&lt;script&gt;')
    end
  end
end
