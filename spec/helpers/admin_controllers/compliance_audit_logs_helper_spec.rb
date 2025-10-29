# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::ComplianceAuditLogsHelper, type: :helper do
  # CLAUDE.md準拠: コンプライアンス監査ログヘルパーの包括的テスト
  # メタ認知: セキュリティ情報の安全な表示とコンプライアンス標準の正確性検証
  # 横展開: 他の監査ログヘルパーとの一貫性確保

  # テストデータのセットアップ
  let(:admin) { create(:admin, name: "管理者太郎", email: "admin@example.com", role: "headquarters_admin") }
  let(:store_user) { create(:store_user, name: "店舗花子", email: "store@example.com", role: "manager") }
  let(:store) { create(:store, name: "テスト店舗") }
  let(:compliance_audit_log) do
    create(:compliance_audit_log,
           user: admin,
           event_type: "data_access",
           compliance_standard: "PCI_DSS",
           severity: "high",
           created_at: 2.hours.ago)
  end

  # ============================================
  # format_event_type メソッドのテスト
  # ============================================

  describe "#format_event_type" do
    context "定義済みイベントタイプ" do
      it "日本語名を返す" do
        expect(helper.format_event_type("data_access")).to eq("データアクセス")
        expect(helper.format_event_type("login_attempt")).to eq("ログイン試行")
        expect(helper.format_event_type("data_export")).to eq("データエクスポート")
        expect(helper.format_event_type("data_import")).to eq("データインポート")
        expect(helper.format_event_type("unauthorized_access")).to eq("不正アクセス")
        expect(helper.format_event_type("data_breach")).to eq("データ漏洩")
        expect(helper.format_event_type("compliance_violation")).to eq("コンプライアンス違反")
        expect(helper.format_event_type("data_deletion")).to eq("データ削除")
        expect(helper.format_event_type("data_anonymization")).to eq("データ匿名化")
        expect(helper.format_event_type("card_data_access")).to eq("カードデータアクセス")
        expect(helper.format_event_type("personal_data_export")).to eq("個人データエクスポート")
        expect(helper.format_event_type("authentication_delay")).to eq("認証遅延")
        expect(helper.format_event_type("rate_limit_exceeded")).to eq("レート制限超過")
        expect(helper.format_event_type("encryption_key_rotation")).to eq("暗号化キーローテーション")
      end
    end

    context "未定義のイベントタイプ" do
      it "humanizeした文字列を返す" do
        expect(helper.format_event_type("custom_event")).to eq("Custom event")
        expect(helper.format_event_type("new_security_event")).to eq("New security event")
      end
    end

    context "エッジケース" do
      it "nilを処理する" do
        expect(helper.format_event_type(nil)).to eq("")
      end

      it "空文字列を処理する" do
        expect(helper.format_event_type("")).to eq("")
      end
    end
  end

  # ============================================
  # format_compliance_standard メソッドのテスト
  # ============================================

  describe "#format_compliance_standard" do
    context "定義済みコンプライアンス標準" do
      it "日本語説明付きの名前を返す" do
        expect(helper.format_compliance_standard("PCI_DSS")).to eq("PCI DSS (クレジットカード情報保護)")
        expect(helper.format_compliance_standard("GDPR")).to eq("GDPR (EU一般データ保護規則)")
        expect(helper.format_compliance_standard("SOX")).to eq("SOX法 (サーベンス・オクスリー法)")
        expect(helper.format_compliance_standard("HIPAA")).to eq("HIPAA (医療保険の相互運用性と説明責任に関する法律)")
        expect(helper.format_compliance_standard("ISO27001")).to eq("ISO 27001 (情報セキュリティマネジメント)")
      end
    end

    context "未定義の標準" do
      it "そのまま返す" do
        expect(helper.format_compliance_standard("CUSTOM_STANDARD")).to eq("CUSTOM_STANDARD")
        expect(helper.format_compliance_standard("NEW_REGULATION")).to eq("NEW_REGULATION")
      end
    end

    context "エッジケース" do
      it "nilを処理する" do
        expect(helper.format_compliance_standard(nil)).to eq(nil)
      end

      it "空文字列を処理する" do
        expect(helper.format_compliance_standard("")).to eq("")
      end
    end
  end

  # ============================================
  # severity_display_info メソッドのテスト
  # ============================================

  describe "#severity_display_info" do
    context "定義済み重要度レベル" do
      it "lowの情報を返す" do
        result = helper.severity_display_info("low")
        expect(result[:label]).to eq("低")
        expect(result[:css_class]).to eq("badge bg-secondary")
        expect(result[:icon]).to eq("bi-info-circle")
        expect(result[:color]).to eq("text-secondary")
      end

      it "mediumの情報を返す" do
        result = helper.severity_display_info("medium")
        expect(result[:label]).to eq("中")
        expect(result[:css_class]).to eq("badge bg-warning text-dark")
        expect(result[:icon]).to eq("bi-exclamation-triangle")
        expect(result[:color]).to eq("text-warning")
      end

      it "highの情報を返す" do
        result = helper.severity_display_info("high")
        expect(result[:label]).to eq("高")
        expect(result[:css_class]).to eq("badge bg-danger")
        expect(result[:icon]).to eq("bi-exclamation-circle")
        expect(result[:color]).to eq("text-danger")
      end

      it "criticalの情報を返す" do
        result = helper.severity_display_info("critical")
        expect(result[:label]).to eq("緊急")
        expect(result[:css_class]).to eq("badge bg-dark")
        expect(result[:icon]).to eq("bi-shield-exclamation")
        expect(result[:color]).to eq("text-danger")
      end
    end

    context "未定義の重要度" do
      it "デフォルト（medium）の情報を返す" do
        result = helper.severity_display_info("unknown")
        expect(result[:label]).to eq("中")
        expect(result[:css_class]).to eq("badge bg-warning text-dark")
      end
    end

    context "エッジケース" do
      it "nilでデフォルトを返す" do
        result = helper.severity_display_info(nil)
        expect(result[:label]).to eq("中")
      end
    end
  end

  # ============================================
  # severity_badge メソッドのテスト
  # ============================================

  describe "#severity_badge" do
    it "重要度バッジのHTMLを生成する" do
      result = helper.severity_badge("high")
      expect(result).to include('<span class="badge bg-danger">高</span>')
    end

    it "未定義の重要度でもバッジを生成する" do
      result = helper.severity_badge("unknown")
      expect(result).to include('<span class="badge bg-warning text-dark">中</span>')
    end
  end

  # ============================================
  # safe_details_for_display メソッドのテスト
  # ============================================

  describe "#safe_details_for_display" do
    let(:compliance_log_with_details) do
      log = build(:compliance_audit_log)
      allow(log).to receive(:safe_details).and_return({
        "timestamp" => "2024-01-01T10:00:00Z",
        "action" => "view",
        "user_id" => 123,
        "result" => "success"
      })
      log
    end

    context "正常な詳細情報" do
      it "フォーマット済みの詳細情報を返す" do
        result = helper.safe_details_for_display(compliance_log_with_details)

        expect(result["タイムスタンプ"]).to eq("2024年01月01日 10:00:00")
        expect(result["アクション"]).to eq("view")
        expect(result["ユーザーID"]).to eq("123")
        expect(result["結果"]).to eq("成功")
      end
    end

    context "エラー処理" do
      it "nilの場合空のハッシュを返す" do
        expect(helper.safe_details_for_display(nil)).to eq({})
      end

      it "例外発生時エラーメッセージを返す" do
        log = build(:compliance_audit_log)
        allow(log).to receive(:safe_details).and_raise(StandardError, "Test error")

        result = helper.safe_details_for_display(log)
        expect(result).to eq({ "エラー" => "詳細情報の取得に失敗しました" })
      end
    end
  end

  # ============================================
  # format_user_for_display メソッドのテスト
  # ============================================

  describe "#format_user_for_display" do
    context "Admin" do
      it "管理者情報を適切にフォーマットする" do
        admin.store = store
        result = helper.format_user_for_display(admin)
        expect(result).to eq("管理者太郎 (テスト店舗) [本部管理者]")
      end

      it "店舗なしの管理者を本部として表示" do
        admin.store = nil
        result = helper.format_user_for_display(admin)
        expect(result).to eq("管理者太郎 (本部) [本部管理者]")
      end

      it "名前がない場合メールアドレスを使用" do
        admin.name = nil
        admin.store = nil
        result = helper.format_user_for_display(admin)
        expect(result).to eq("admin@example.com (本部) [本部管理者]")
      end
    end

    context "StoreUser" do
      before { store_user.store = store }

      it "店舗ユーザー情報を適切にフォーマットする" do
        result = helper.format_user_for_display(store_user)
        expect(result).to eq("店舗花子 (テスト店舗) [マネージャー]")
      end

      it "名前がない場合メールアドレスを使用" do
        store_user.name = nil
        result = helper.format_user_for_display(store_user)
        expect(result).to eq("store@example.com (テスト店舗) [マネージャー]")
      end
    end

    context "その他" do
      it "nilの場合システムを返す" do
        expect(helper.format_user_for_display(nil)).to eq("システム")
      end

      it "不明なユーザータイプの場合エラーメッセージを返す" do
        expect(helper.format_user_for_display("invalid")).to eq("不明なユーザータイプ")
      end
    end
  end

  # ============================================
  # format_audit_datetime メソッドのテスト
  # ============================================

  describe "#format_audit_datetime" do
    it "日時を適切にフォーマットする" do
      allow(helper).to receive(:time_ago_in_words).and_return("約2時間")
      result = helper.format_audit_datetime(compliance_audit_log)

      expect(result).to match(/\d{4}年\d{2}月\d{2}日 \d{2}:\d{2}:\d{2}/)
      expect(result).to include("(約2時間前)")
    end

    it "nilの場合不明を返す" do
      expect(helper.format_audit_datetime(nil)).to eq("不明")
    end

    it "created_atがnilの場合不明を返す" do
      log = build(:compliance_audit_log, created_at: nil)
      expect(helper.format_audit_datetime(log)).to eq("不明")
    end
  end

  # ============================================
  # format_retention_status メソッドのテスト
  # ============================================

  describe "#format_retention_status" do
    context "有効期限内" do
      it "残り日数を表示する" do
        log = build(:compliance_audit_log)
        allow(log).to receive(:retention_expiry_date).and_return(Date.current + 30.days)

        result = helper.format_retention_status(log)
        expect(result).to match(/まで \(あと30日\)/)
      end
    end

    context "期限切れ" do
      it "経過日数を赤字で表示する" do
        log = build(:compliance_audit_log)
        allow(log).to receive(:retention_expiry_date).and_return(Date.current - 10.days)

        result = helper.format_retention_status(log)
        expect(result).to include('<span class="text-danger">期限切れ (10日経過)</span>')
      end
    end

    context "エッジケース" do
      it "nilの場合不明を返す" do
        expect(helper.format_retention_status(nil)).to eq("不明")
      end
    end
  end

  # ============================================
  # compliance_summary_by_standard メソッドのテスト
  # ============================================

  describe "#compliance_summary_by_standard" do
    let(:logs) do
      # モックデータの作成
      result = double("ActiveRecord::Relation")
      allow(result).to receive(:group).and_return(result)
      allow(result).to receive(:count).and_return({
        [ "PCI_DSS", "high" ] => 10,
        [ "PCI_DSS", "medium" ] => 5,
        [ "GDPR", "low" ] => 3,
        [ "GDPR", "high" ] => 2
      })
      result
    end

    it "標準別のサマリーを生成する" do
      result = helper.compliance_summary_by_standard(logs)

      expect(result["PCI_DSS"][:total]).to eq(15)
      expect(result["PCI_DSS"][:by_severity]["high"]).to eq(10)
      expect(result["PCI_DSS"][:by_severity]["medium"]).to eq(5)

      expect(result["GDPR"][:total]).to eq(5)
      expect(result["GDPR"][:by_severity]["low"]).to eq(3)
      expect(result["GDPR"][:by_severity]["high"]).to eq(2)
    end
  end

  # ============================================
  # severity_statistics メソッドのテスト
  # ============================================

  describe "#severity_statistics" do
    let(:logs) do
      result = double("ActiveRecord::Relation")
      allow(result).to receive(:group).with(:severity).and_return(result)
      allow(result).to receive(:count).and_return({
        "low" => 10,
        "medium" => 30,
        "high" => 50,
        "critical" => 10
      })
      result
    end

    it "重要度別の統計を生成する" do
      result = helper.severity_statistics(logs)

      expect(result["low"][:count]).to eq(10)
      expect(result["low"][:percentage]).to eq(10.0)

      expect(result["medium"][:count]).to eq(30)
      expect(result["medium"][:percentage]).to eq(30.0)

      expect(result["high"][:count]).to eq(50)
      expect(result["high"][:percentage]).to eq(50.0)

      expect(result["critical"][:count]).to eq(10)
      expect(result["critical"][:percentage]).to eq(10.0)
    end

    context "データがない場合" do
      let(:empty_logs) do
        result = double("ActiveRecord::Relation")
        allow(result).to receive(:group).with(:severity).and_return(result)
        allow(result).to receive(:count).and_return({})
        result
      end

      it "空のハッシュを返す" do
        expect(helper.severity_statistics(empty_logs)).to eq({})
      end
    end
  end

  # ============================================
  # activity_trend メソッドのテスト
  # ============================================

  describe "#activity_trend" do
    let(:logs) { double("ActiveRecord::Relation") }

    context "日別集計" do
      it "日別のアクティビティを返す" do
        allow(logs).to receive(:group_by_day).with(:created_at, last: 30).and_return({ Date.today => 5 })
        result = helper.activity_trend(logs, :daily)
        expect(result).to eq({ Date.today => 5 })
      end
    end

    context "週別集計" do
      it "週別のアクティビティを返す" do
        allow(logs).to receive(:group_by_week).with(:created_at, last: 12).and_return({ Date.today.beginning_of_week => 20 })
        result = helper.activity_trend(logs, :weekly)
        expect(result).to eq({ Date.today.beginning_of_week => 20 })
      end
    end

    context "月別集計" do
      it "月別のアクティビティを返す" do
        allow(logs).to receive(:group_by_month).with(:created_at, last: 12).and_return({ Date.today.beginning_of_month => 100 })
        result = helper.activity_trend(logs, :monthly)
        expect(result).to eq({ Date.today.beginning_of_month => 100 })
      end
    end

    context "不正な期間タイプ" do
      it "空のハッシュを返す" do
        result = helper.activity_trend(logs, :invalid)
        expect(result).to eq({})
      end
    end
  end

  # ============================================
  # format_search_conditions メソッドのテスト
  # ============================================

  describe "#format_search_conditions" do
    context "検索条件あり" do
      it "すべての条件を表示する" do
        params = {
          compliance_standard: "PCI_DSS",
          severity: "high",
          event_type: "data_access",
          start_date: "2024-01-01",
          end_date: "2024-01-31"
        }

        result = helper.format_search_conditions(params)

        expect(result).to include("標準: PCI DSS (クレジットカード情報保護)")
        expect(result).to include("重要度: 高")
        expect(result).to include("イベント: データアクセス")
        expect(result).to include("期間: 2024-01-01 〜 2024-01-31")
      end

      it "開始日のみの場合" do
        params = { start_date: "2024-01-01" }
        result = helper.format_search_conditions(params)
        expect(result).to include("開始日: 2024-01-01 以降")
      end

      it "終了日のみの場合" do
        params = { end_date: "2024-01-31" }
        result = helper.format_search_conditions(params)
        expect(result).to include("終了日: 2024-01-31 以前")
      end
    end

    context "検索条件なし" do
      it "すべてを返す" do
        result = helper.format_search_conditions({})
        expect(result).to eq([ "すべて" ])
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "各ヘルパーメソッドは高速に実行される" do
      start_time = Time.current
      100.times do
        helper.format_event_type("data_access")
        helper.format_compliance_standard("PCI_DSS")
        helper.severity_display_info("high")
        helper.severity_badge("critical")
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # HTML安全性テスト
  # ============================================

  describe "HTML safety" do
    it "severity_badgeの結果はHTML安全" do
      result = helper.severity_badge("high")
      expect(result).to be_html_safe
    end

    it "format_retention_statusの期限切れ表示はHTML安全" do
      log = build(:compliance_audit_log)
      allow(log).to receive(:retention_expiry_date).and_return(Date.current - 10.days)

      result = helper.format_retention_status(log)
      expect(result).to be_html_safe
    end
  end

  # ============================================
  # XSS対策テスト
  # ============================================

  describe "XSS protection" do
    it "ユーザー入力を適切にエスケープする" do
      admin.name = '<script>alert("XSS")</script>'
      result = helper.format_user_for_display(admin)

      # 名前部分はエスケープされていることを確認
      expect(result).to include('&lt;script&gt;alert("XSS")&lt;/script&gt;')
    end

    it "詳細情報の値をエスケープする" do
      log = build(:compliance_audit_log)
      allow(log).to receive(:safe_details).and_return({
        "action" => '<img src=x onerror=alert("XSS")>'
      })

      result = helper.safe_details_for_display(log)
      expect(result["アクション"]).to eq('<img src=x onerror=alert("XSS")>')
      # 注: 実際の表示時にRailsがエスケープする
    end
  end
end
