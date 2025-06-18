# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::JobStatusesController, type: :controller do
  # CLAUDE.md準拠: API機能のテスト品質向上
  # メタ認知: ジョブステータスAPIの正確性とセキュリティ設定を確認
  # 横展開: 他のAPI系AdminControllersでも同様のテスト構造を適用

  let(:admin) { create(:admin) }
  let(:job_id) { "test_job_#{SecureRandom.hex(8)}" }

  before do
    sign_in admin, scope: :admin
  end

  describe "GET #show" do
    # TODO: 🟡 Phase 3（中）- Redis統合テスト強化
    # 優先度: 中（基本機能は動作中）
    # 実装内容: Redis接続エラー、タイムアウト、フォールバック処理
    # 理由: 本番環境での安定性確保
    # 期待効果: 障害時のユーザビリティ維持
    # 工数見積: 2-3日
    # 依存関係: Redis test環境設定

    context "with valid admin authentication" do
      context "when job exists in Redis" do
        before do
          # Redis モックデータ設定
          allow(controller).to receive(:get_job_status_from_redis)
            .with(job_id)
            .and_return({
              'status' => 'running',
              'progress' => 50,
              'total' => 100,
              'current_step' => 'processing_data'
            })
        end

        it "returns job status as JSON" do
          get :show, params: { id: job_id }, format: :json

          expect(response).to be_successful
          expect(response.content_type).to eq('application/json; charset=utf-8')

          json_response = JSON.parse(response.body)
          expect(json_response).to include(
            'status' => 'running',
            'progress' => 50,
            'total' => 100
          )
        end
      end

      context "when job does not exist" do
        before do
          allow(controller).to receive(:get_job_status_from_redis)
            .with(job_id)
            .and_return(nil)
        end

        it "returns not found status" do
          get :show, params: { id: job_id }, format: :json

          expect(response).to have_http_status(:not_found)

          json_response = JSON.parse(response.body)
          expect(json_response).to include('error' => 'Job not found')
        end
      end

      context "when Redis connection fails" do
        before do
          allow(controller).to receive(:get_job_status_from_redis)
            .with(job_id)
            .and_raise(Redis::CannotConnectError, "Connection refused")
        end

        it "returns internal server error with proper error handling" do
          get :show, params: { id: job_id }, format: :json

          expect(response).to have_http_status(:internal_server_error)

          json_response = JSON.parse(response.body)
          expect(json_response).to include('error')
        end
      end
    end

    context "without authentication" do
      before { sign_out admin }

      it "redirects to sign in page" do
        get :show, params: { id: job_id }
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "with HTML request" do
      it "returns not acceptable for non-JSON requests" do
        get :show, params: { id: job_id }
        # APIコントローラーはJSON専用
        expect(response).to have_http_status(:not_acceptable)
      end
    end
  end

  describe "security compliance" do
    it "skips audit_sensitive_data_access callback" do
      # メタ認知: ジョブステータス取得は機密データ操作ではない
      # コールバックがスキップされていることを確認
      callbacks = controller.class._process_action_callbacks
      audit_callbacks = callbacks.select { |cb| cb.filter == :audit_sensitive_data_access }

      # JobStatusesControllerではskip_around_actionが適用されているため
      # audit_sensitive_data_accessコールバックは実行されない
      expect(audit_callbacks).to be_empty
    end

    it "requires admin authentication" do
      # 認証が必要であることを確認
      callbacks = controller.class._process_action_callbacks
      auth_callbacks = callbacks.select { |cb| cb.filter == :authenticate_admin! }

      expect(auth_callbacks).not_to be_empty
    end
  end

  describe "performance and reliability" do
    # TODO: 🟢 Phase 4（推奨）- APIレスポンス時間監視
    # 優先度: 低（現在のレスポンス時間は良好）
    # 実装内容: レスポンス時間のベンチマーク、SLA監視
    # 理由: API品質の継続的改善
    # 期待効果: ユーザー体験向上
    # 工数見積: 1-2日
    # 依存関係: 監視ツール統合

    it "responds within acceptable time limits" do
      allow(controller).to receive(:get_job_status_from_redis)
        .with(job_id)
        .and_return({ 'status' => 'completed' })

      start_time = Time.current
      get :show, params: { id: job_id }, format: :json
      end_time = Time.current

      response_time = (end_time - start_time) * 1000 # ミリ秒
      expect(response_time).to be < 500 # 500ms未満
    end
  end
end
