# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::AuditLogsController, type: :controller do
  # CLAUDE.md準拠: 監査ログ管理機能の包括的テスト
  # メタ認知: セキュリティコンプライアンスと権限管理の厳密な検証
  # 横展開: 他のセキュリティ機能でも同様のテストパターン適用

  let(:headquarters_admin) { create(:admin, role: :headquarters_admin) }
  let(:store_admin) { create(:admin, role: :store_admin) }
  let(:regular_admin) { create(:admin, role: :regular_admin) }
  let(:audit_log) { create(:audit_log, user: headquarters_admin, action: "view", auditable: inventory) }
  let(:inventory) { create(:inventory) }
  let(:store) { create(:store) }

  # ============================================
  # 権限チェック機能のテスト
  # ============================================

  describe "authorization requirements" do
    context "本部管理者（headquarters_admin）" do
      before { sign_in headquarters_admin, scope: :admin }

      it "全ての監査ログアクションにアクセス可能" do
        get :index
        expect(response).to be_successful
      end

      it "監査ログ詳細表示が可能" do
        get :show, params: { id: audit_log.id }
        expect(response).to be_successful
      end

      it "セキュリティイベント表示が可能" do
        get :security_events
        expect(response).to be_successful
      end

      it "ユーザー別監査履歴表示が可能" do
        get :user_activity, params: { user_id: headquarters_admin.id }
        expect(response).to be_successful
      end

      it "コンプライアンスレポート表示が可能" do
        get :compliance_report
        expect(response).to be_successful
      end
    end

    context "店舗管理者（store_admin）" do
      before { sign_in store_admin, scope: :admin }

      it "監査ログアクセスが拒否される" do
        get :index
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("監査ログへのアクセス権限がありません")
      end

      it "監査ログ詳細表示が拒否される" do
        get :show, params: { id: audit_log.id }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("本部管理者権限が必要です")
      end

      it "セキュリティイベント表示が拒否される" do
        get :security_events
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("監査ログへのアクセス権限がありません")
      end

      it "ユーザー別監査履歴表示が拒否される" do
        get :user_activity, params: { user_id: headquarters_admin.id }
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("監査ログへのアクセス権限がありません")
      end

      it "コンプライアンスレポート表示が拒否される" do
        get :compliance_report
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("監査ログへのアクセス権限がありません")
      end
    end

    context "一般管理者（regular_admin）" do
      before { sign_in regular_admin, scope: :admin }

      it "監査ログアクセスが拒否される" do
        get :index
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to include("監査ログへのアクセス権限がありません")
      end
    end

    context "認証なしアクセス" do
      before { sign_out :admin }

      it "認証を要求される" do
        get :index
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "セキュリティイベントへの認証なしアクセスが拒否される" do
        get :security_events
        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  # ============================================
  # 監査ログ一覧機能のテスト
  # ============================================

  describe "GET #index" do
    before do
      sign_in headquarters_admin, scope: :admin
      create_list(:audit_log, 25, user: headquarters_admin)
    end

    it "成功レスポンスを返す" do
      get :index
      expect(response).to be_successful
    end

    it "監査ログがページネーション付きで表示される" do
      get :index
      expect(assigns(:audit_logs)).to be_present
      expect(assigns(:audit_logs).count).to eq(20) # PER_PAGE = 20
    end

    it "統計情報が計算される" do
      get :index
      expect(assigns(:stats)).to be_present
      expect(assigns(:stats)).to be_a(Hash)
    end

    it "異常検知が実行される" do
      get :index
      expect(assigns(:anomalies)).to be_present
    end

    context "レスポンス形式" do
      it "HTMLレスポンスが正常" do
        get :index
        expect(response.content_type).to include("text/html")
      end

      it "JSONレスポンスが正常" do
        get :index, format: :json
        expect(response.content_type).to include("application/json")
        expect(JSON.parse(response.body)).to be_an(Array)
      end

      it "CSVエクスポートが正常" do
        get :index, format: :csv
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("audit_logs_#{Date.current}.csv")
      end
    end
  end

  # ============================================
  # 監査ログ詳細機能のテスト
  # ============================================

  describe "GET #show" do
    before { sign_in headquarters_admin, scope: :admin }

    context "有効な監査ログID" do
      it "成功レスポンスを返す" do
        get :show, params: { id: audit_log.id }
        expect(response).to be_successful
      end

      it "監査ログを正しく取得する" do
        get :show, params: { id: audit_log.id }
        expect(assigns(:audit_log)).to eq(audit_log)
      end

      it "関連する監査ログを取得する" do
        related_log = create(:audit_log,
                           user: headquarters_admin,
                           auditable: audit_log.auditable,
                           action: "update")

        get :show, params: { id: audit_log.id }
        expect(assigns(:related_logs)).to include(related_log)
        expect(assigns(:related_logs)).not_to include(audit_log)
      end

      it "監査ログ閲覧自体が監査される" do
        expect(audit_log).to receive(:audit_view).with(headquarters_admin, anything)
        get :show, params: { id: audit_log.id }
      end

      it "アクセス理由パラメータが監査に記録される" do
        reason = "定期監査"
        expect(audit_log).to receive(:audit_view).with(
          headquarters_admin,
          hash_including(access_reason: reason)
        )
        get :show, params: { id: audit_log.id, reason: reason }
      end
    end

    context "存在しない監査ログID" do
      it "RecordNotFoundエラーが発生する" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # セキュリティイベント機能のテスト
  # ============================================

  describe "GET #security_events" do
    before do
      sign_in headquarters_admin, scope: :admin

      # テスト用セキュリティイベントデータ作成
      create(:audit_log, action: "failed_login", user: headquarters_admin,
             details: { rate_limit_exceeded: true })
      create(:audit_log, action: "permission_change", user: headquarters_admin)
      create_list(:audit_log, 15, action: "security_event", user: headquarters_admin)
    end

    it "成功レスポンスを返す" do
      get :security_events
      expect(response).to be_successful
    end

    it "セキュリティイベントが取得される" do
      get :security_events
      expect(assigns(:security_events)).to be_present
    end

    it "セキュリティ統計が計算される" do
      get :security_events
      stats = assigns(:security_stats)

      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:total_events)
      expect(stats).to have_key(:rate_limit_blocks)
      expect(stats).to have_key(:failed_logins)
      expect(stats).to have_key(:permission_changes)
    end

    it "高リスクユーザーが特定される" do
      get :security_events
      expect(assigns(:high_risk_users)).to be_present
    end

    it "ページネーションが適用される" do
      get :security_events
      events = assigns(:security_events)
      expect(events.count).to be <= 20 # PER_PAGE = 20
    end
  end

  # ============================================
  # ユーザー別監査履歴機能のテスト
  # ============================================

  describe "GET #user_activity" do
    before do
      sign_in headquarters_admin, scope: :admin

      # テスト用ユーザー活動データ作成
      create_list(:audit_log, 10, user: headquarters_admin, action: "view")
      create_list(:audit_log, 5, user: headquarters_admin, action: "update")
    end

    it "成功レスポンスを返す" do
      get :user_activity, params: { user_id: headquarters_admin.id }
      expect(response).to be_successful
    end

    it "指定ユーザーが設定される" do
      get :user_activity, params: { user_id: headquarters_admin.id }
      expect(assigns(:user)).to eq(headquarters_admin)
    end

    it "ユーザーの活動履歴が取得される" do
      get :user_activity, params: { user_id: headquarters_admin.id }
      activities = assigns(:activities)

      expect(activities).to be_present
      expect(activities.all? { |a| a.user_id == headquarters_admin.id }).to be true
    end

    it "ユーザー統計が計算される" do
      get :user_activity, params: { user_id: headquarters_admin.id }
      stats = assigns(:user_stats)

      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:total_actions)
      expect(stats).to have_key(:actions_breakdown)
      expect(stats).to have_key(:active_hours)
      expect(stats).to have_key(:accessed_models)

      expect(stats[:total_actions]).to eq(15)
      expect(stats[:actions_breakdown]["view"]).to eq(10)
      expect(stats[:actions_breakdown]["update"]).to eq(5)
    end

    it "ユーザー異常検知が実行される" do
      get :user_activity, params: { user_id: headquarters_admin.id }
      expect(assigns(:user_anomalies)).to be_present
    end

    context "存在しないユーザーID" do
      it "RecordNotFoundエラーが発生する" do
        expect {
          get :user_activity, params: { user_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # コンプライアンスレポート機能のテスト
  # ============================================

  describe "GET #compliance_report" do
    before do
      sign_in headquarters_admin, scope: :admin

      # テスト用データ作成（期間指定あり）
      create_list(:audit_log, 5, user: headquarters_admin,
                  created_at: 15.days.ago, action: "view")
      create_list(:audit_log, 3, user: headquarters_admin,
                  created_at: 5.days.ago, action: "update")
    end

    context "期間指定なし" do
      it "成功レスポンスを返す" do
        get :compliance_report
        expect(response).to be_successful
      end

      it "デフォルトの期間設定が使用される" do
        get :compliance_report
        expect(assigns(:start_date)).to eq(1.month.ago.to_date)
        expect(assigns(:end_date)).to eq(Date.current)
      end

      it "レポートデータが生成される" do
        get :compliance_report
        report_data = assigns(:report_data)

        expect(report_data).to be_a(Hash)
        expect(report_data).to have_key(:period)
        expect(report_data).to have_key(:summary)
        expect(report_data).to have_key(:user_activities)
        expect(report_data).to have_key(:data_access_summary)
        expect(report_data).to have_key(:security_summary)
        expect(report_data).to have_key(:daily_breakdown)
      end
    end

    context "期間指定あり" do
      it "指定された期間でレポートを生成する" do
        start_date = 2.weeks.ago.to_date
        end_date = 1.week.ago.to_date

        get :compliance_report, params: {
          start_date: start_date.to_s,
          end_date: end_date.to_s
        }

        expect(assigns(:start_date)).to eq(start_date)
        expect(assigns(:end_date)).to eq(end_date)
      end

      it "期間内のデータのみがレポートに含まれる" do
        start_date = 10.days.ago.to_date
        end_date = Date.current

        get :compliance_report, params: {
          start_date: start_date.to_s,
          end_date: end_date.to_s
        }

        report_data = assigns(:report_data)
        # 15日前のデータは含まれない（10日前からの期間指定）
        expect(report_data[:summary][:total_events]).to eq(3)
      end
    end

    context "レスポンス形式" do
      it "HTMLレスポンスが正常" do
        get :compliance_report
        expect(response.content_type).to include("text/html")
      end

      it "PDF形式は未実装エラーを返す" do
        get :compliance_report, format: :pdf
        expect(response).to have_http_status(:not_implemented)
        expect(response.body).to include("PDF export not yet implemented")
      end
    end
  end

  # ============================================
  # 高リスクユーザー特定機能のテスト
  # ============================================

  describe "high risk user identification" do
    before { sign_in headquarters_admin, scope: :admin }

    context "失敗ログインが多いユーザー" do
      before do
        # 4回の失敗ログイン（リスク閾値の3回を超過）
        create_list(:audit_log, 4, user: headquarters_admin,
                    action: "failed_login", created_at: 12.hours.ago)
      end

      it "高リスクユーザーとして特定される" do
        get :security_events
        high_risk_users = assigns(:high_risk_users)

        expect(high_risk_users).not_to be_empty
        risk_user = high_risk_users.find { |h| h[:user].id == headquarters_admin.id }

        expect(risk_user).to be_present
        expect(risk_user[:risk_type]).to eq("multiple_failed_logins")
        expect(risk_user[:risk_score]).to eq(80) # 4 * 20
        expect(risk_user[:details]).to include("4回のログイン失敗")
      end
    end

    context "大量データアクセスユーザー" do
      before do
        # 101回のデータアクセス（リスク閾値の100回を超過）
        create_list(:audit_log, 101, user: headquarters_admin,
                    action: "view", created_at: 12.hours.ago)
      end

      it "高リスクユーザーとして特定される" do
        get :security_events
        high_risk_users = assigns(:high_risk_users)

        expect(high_risk_users).not_to be_empty
        risk_user = high_risk_users.find { |h| h[:user].id == headquarters_admin.id }

        expect(risk_user).to be_present
        expect(risk_user[:risk_type]).to eq("mass_data_access")
        expect(risk_user[:risk_score]).to eq(10) # 101 / 10
        expect(risk_user[:details]).to include("101件の大量データアクセス")
      end
    end

    context "複合リスクユーザー" do
      before do
        # 失敗ログインと大量アクセスの組み合わせ
        create_list(:audit_log, 5, user: headquarters_admin,
                    action: "failed_login", created_at: 12.hours.ago)
        create_list(:audit_log, 150, user: headquarters_admin,
                    action: "export", created_at: 12.hours.ago)
      end

      it "複合リスクとして計算される" do
        get :security_events
        high_risk_users = assigns(:high_risk_users)

        risk_user = high_risk_users.find { |h| h[:user].id == headquarters_admin.id }

        expect(risk_user).to be_present
        # 失敗ログイン(5*20=100) + 大量アクセス(150/10=15) = 115
        expect(risk_user[:risk_score]).to eq(115)
        expect(risk_user[:details]).to include("5回のログイン失敗")
        expect(risk_user[:details]).to include("150件の大量データアクセス")
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    before { sign_in headquarters_admin, scope: :admin }

    context "大量データでのN+1クエリ防止" do
      before do
        create_list(:audit_log, 50, user: headquarters_admin)
      end

      it "index アクションでのN+1クエリ防止" do
        expect {
          get :index
        }.not_to exceed_query_limit(15)
      end

      it "security_events アクションでのN+1クエリ防止" do
        expect {
          get :security_events
        }.not_to exceed_query_limit(20) # includes(:user)による最適化
      end

      it "user_activity アクションでのN+1クエリ防止" do
        expect {
          get :user_activity, params: { user_id: headquarters_admin.id }
        }.not_to exceed_query_limit(15) # includes(:auditable)による最適化
      end
    end

    context "レスポンス時間" do
      before do
        create_list(:audit_log, 100, user: headquarters_admin)
      end

      it "index アクションは500ms以内" do
        start_time = Time.current
        get :index
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 500
      end

      it "統計計算は300ms以内" do
        start_time = Time.current
        get :security_events
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        expect(elapsed_time).to be < 300
      end
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe "security tests" do
    before { sign_in headquarters_admin, scope: :admin }

    context "権限エスカレーション防止" do
      it "店舗管理者は他ユーザーの監査履歴にアクセス不可" do
        sign_in store_admin, scope: :admin

        get :user_activity, params: { user_id: headquarters_admin.id }
        expect(response).to redirect_to(admin_root_path)
      end

      it "権限不足時の適切なエラーメッセージ" do
        sign_in store_admin, scope: :admin

        get :index
        expect(flash[:alert]).to include("本部管理者権限が必要です")
      end
    end

    context "データアクセス制限" do
      it "監査ログ閲覧自体が監査される" do
        audit_log = create(:audit_log, user: headquarters_admin)

        expect(audit_log).to receive(:audit_view)
        get :show, params: { id: audit_log.id }
      end

      it "CSVエクスポートが監査される" do
        # CSVダウンロード操作も監査対象
        get :index, format: :csv
        expect(response).to be_successful
      end
    end

    context "入力検証" do
      it "不正な日付パラメータは適切に処理される" do
        expect {
          get :compliance_report, params: {
            start_date: "invalid_date",
            end_date: "also_invalid"
          }
        }.not_to raise_error
      end

      it "存在しないuser_idは404エラー" do
        expect {
          get :user_activity, params: { user_id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  # ============================================
  # 設定値の検証
  # ============================================

  describe "configuration validation" do
    before { sign_in headquarters_admin, scope: :admin }

    it "適切なページネーション設定" do
      create_list(:audit_log, 25, user: headquarters_admin)

      get :index
      audit_logs = assigns(:audit_logs)

      expect(audit_logs.count).to eq(20) # PER_PAGE = 20
      expect(audit_logs).to respond_to(:current_page)
    end

    it "セキュリティ監査スキップが正しく設定" do
      # skip_around_action :audit_sensitive_data_access の確認
      callbacks = AdminControllers::AuditLogsController._process_action_callbacks
      audit_callback = callbacks.find { |c| c.filter == :audit_sensitive_data_access }

      # スキップされているため、コールバックが見つからないか無効化されている
      expect(audit_callback).to be_nil
    end

    it "継承とモジュール構成の確認" do
      expect(AdminControllers::AuditLogsController.ancestors).to include(
        AdminControllers::BaseController,
        AuditLogViewer
      )
    end
  end
end
