# frozen_string_literal: true

require 'rails_helper'

# ErrorHandlers concernのテスト
# CLAUDE.md準拠: 包括的エラーハンドリングのテスト
# メタ認知: 各条件分岐を完全にカバーしてブランチカバレッジを向上
# 横展開: AdminControllers/API/Store全てで共通使用
RSpec.describe ErrorHandlers, type: :controller do
  # テスト用コントローラーを作成
  controller(ApplicationController) do
    include ErrorHandlers

    def test_json_error
      raise ActiveRecord::RecordNotFound, "テストレコードが見つかりません"
    end

    def test_html_error
      raise ActiveRecord::RecordInvalid.new(build(:admin))
    end

    def test_parameter_missing
      raise ActionController::ParameterMissing, :required_param
    end

    def test_custom_error
      raise CustomError::ValidationError.new("カスタムバリデーションエラー")
    end

    def test_422_error
      raise ActiveRecord::RecordInvalid.new(build(:admin))
    end

    def test_500_error
      raise StandardError, "内部サーバーエラー"
    end

    def test_turbo_stream_error
      raise ActiveRecord::RecordNotFound, "Turbo Streamエラー"
    end

    def test_custom_turbo_error
      raise CustomError::BaseError.new("カスタムTurboエラー", 422)
    end
  end

  let(:admin_user) { create(:admin) }

  before do
    # Current.userの設定をモック
    allow(Current).to receive(:respond_to?).with(:user).and_return(true)
    allow(Current).to receive(:user).and_return(admin_user)
  end

  # ============================================
  # JSON レスポンステスト（API用）
  # ============================================

  describe "JSON error handling" do
    context "ActiveRecord::RecordNotFound" do
      it "returns 404 status with proper JSON structure" do
        get :test_json_error, format: :json

        expect(response).to have_http_status(404)
        json_response = JSON.parse(response.body)

        expect(json_response).to include(
          "success" => false,
          "status_code" => 404,
          "error_code" => "resource_not_found"
        )
        expect(json_response["message"]).to include("テストレコードが見つかりません")
        expect(json_response["meta"]["request_id"]).to be_present
        expect(json_response["meta"]["timestamp"]).to be_present
      end
    end

    context "ActiveRecord::RecordInvalid" do
      it "returns 422 status with validation errors" do
        get :test_html_error, format: :json

        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)

        expect(json_response).to include(
          "success" => false,
          "status_code" => 422,
          "error_code" => "validation_error"
        )
      end
    end

    context "ActionController::ParameterMissing" do
      it "returns 400 status for missing parameters" do
        get :test_parameter_missing, format: :json

        expect(response).to have_http_status(400)
        json_response = JSON.parse(response.body)

        expect(json_response).to include(
          "success" => false,
          "status_code" => 400,
          "error_code" => "parameter_missing"
        )
      end
    end

    context "CustomError::BaseError" do
      it "handles custom errors with ApiResponse integration" do
        get :test_custom_error, format: :json

        expect(response).to have_http_status(422)
        json_response = JSON.parse(response.body)

        expect(json_response).to include(
          "success" => false,
          "error_code" => "validation_error"
        )
        expect(json_response["message"]).to include("カスタムバリデーションエラー")
      end
    end
  end

  # ============================================
  # HTML レスポンステスト（ブラウザ用）
  # ============================================

  describe "HTML error handling" do
    context "in test environment" do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test")) }

      it "returns plain text response for non-422 errors" do
        get :test_html_error, format: :html

        expect(response.body).to include("Validation failed")
        expect(response.content_type).to include("text/plain")
      end

      it "handles 500 errors with plain text" do
        get :test_500_error, format: :html

        expect(response).to have_http_status(500)
        expect(response.body).to include("内部サーバーエラー")
      end
    end

    context "in production environment" do
      before { allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production")) }

      it "redirects to error page for non-422 errors" do
        routes.draw { get "error/:code", to: "errors#show", as: :error }

        get :test_html_error, format: :html

        expect(response).to redirect_to(error_path(code: 422))
      end
    end

    context "422 validation errors" do
      it "sets flash alert and does not redirect" do
        get :test_422_error, format: :html

        expect(flash.now[:alert]).to be_present
        expect(response).not_to be_redirect
      end
    end
  end

  # ============================================
  # Turbo Stream レスポンステスト
  # ============================================

  describe "Turbo Stream error handling" do
    context "standard errors" do
      it "renders error partial with proper locals" do
        expect(controller).to receive(:render).with(
          partial: "shared/error",
          status: 404,
          locals: {
            message: "Turbo Streamエラー",
            details: nil
          }
        )

        get :test_turbo_stream_error, format: :turbo_stream
      end
    end

    context "custom errors" do
      it "renders error partial with custom error details" do
        expect(controller).to receive(:render).with(
          partial: "shared/error",
          status: 422,
          locals: {
            message: "カスタムTurboエラー",
            details: kind_of(Hash)
          }
        )

        get :test_custom_turbo_error, format: :turbo_stream
      end
    end

    context "validation errors with details" do
      it "extracts validation error details" do
        invalid_admin = build(:admin)
        invalid_admin.valid? # トリガーバリデーションエラー

        allow(controller).to receive(:test_turbo_stream_error) do
          raise ActiveRecord::RecordInvalid.new(invalid_admin)
        end

        expect(controller).to receive(:render).with(
          partial: "shared/error",
          status: 422,
          locals: {
            message: kind_of(String),
            details: kind_of(Array)
          }
        )

        get :test_turbo_stream_error, format: :turbo_stream
      end
    end
  end

  # ============================================
  # ログ機能テスト
  # ============================================

  describe "error logging" do
    context "500+ errors" do
      it "logs with error severity and includes backtrace" do
        expect(Rails.logger).to receive(:error) do |&block|
          log_data = JSON.parse(block.call)
          expect(log_data["status"]).to eq(500)
          expect(log_data["error"]).to eq("StandardError")
          expect(log_data["backtrace"]).to be_present
          expect(log_data["request_id"]).to be_present
          expect(log_data["user_id"]).to eq(admin_user.id)
        end

        get :test_500_error, format: :json
      end
    end

    context "400-499 errors" do
      it "logs with info severity without backtrace" do
        expect(Rails.logger).to receive(:info) do |&block|
          log_data = JSON.parse(block.call)
          expect(log_data["status"]).to eq(404)
          expect(log_data["error"]).to eq("ActiveRecord::RecordNotFound")
          expect(log_data["backtrace"]).to be_nil
          expect(log_data["user_id"]).to eq(admin_user.id)
        end

        get :test_json_error, format: :json
      end
    end

    context "parameter filtering" do
      it "excludes controller, action, and format from logged parameters" do
        expect(Rails.logger).to receive(:info) do |&block|
          log_data = JSON.parse(block.call)
          expect(log_data["params"]).not_to include("controller", "action", "format")
        end

        get :test_json_error, params: { test_param: "value", sensitive: "data" }, format: :json
      end
    end
  end

  # ============================================
  # ユーザーID取得テスト
  # ============================================

  describe "#get_current_user_id" do
    context "with admin authentication" do
      before { sign_in admin_user }

      it "returns admin ID" do
        expect(controller.send(:get_current_user_id)).to eq(admin_user.id)
      end
    end

    context "with store user authentication" do
      let(:store_user) { create(:store_user) }

      before do
        allow(controller).to receive(:respond_to?).with(:current_store_user).and_return(true)
        allow(controller).to receive(:current_store_user).and_return(store_user)
      end

      it "returns store user ID" do
        expect(controller.send(:get_current_user_id)).to eq(store_user.id)
      end
    end

    context "without authentication" do
      it "returns nil" do
        expect(controller.send(:get_current_user_id)).to be_nil
      end
    end
  end

  # ============================================
  # エラーコード生成テスト
  # ============================================

  describe "#error_code_for_status" do
    it "generates correct error codes for different exceptions" do
      not_found = ActiveRecord::RecordNotFound.new
      expect(controller.send(:error_code_for_status, 404, not_found)).to eq("resource_not_found")

      invalid = ActiveRecord::RecordInvalid.new(build(:admin))
      expect(controller.send(:error_code_for_status, 422, invalid)).to eq("validation_error")

      missing_param = ActionController::ParameterMissing.new(:param)
      expect(controller.send(:error_code_for_status, 400, missing_param)).to eq("parameter_missing")

      generic_error = StandardError.new
      expect(controller.send(:error_code_for_status, 500, generic_error)).to eq("internal_server_error")
    end
  end

  # ============================================
  # エラー詳細抽出テスト
  # ============================================

  describe "#extract_error_details" do
    context "ActiveRecord::RecordInvalid" do
      it "extracts validation error messages" do
        admin = build(:admin, email: "invalid")
        admin.valid? # トリガーバリデーション
        exception = ActiveRecord::RecordInvalid.new(admin)

        details = controller.send(:extract_error_details, exception)
        expect(details).to be_an(Array)
        expect(details).not_to be_empty
      end
    end

    context "ActiveModel::ValidationError" do
      it "extracts model validation errors" do
        form = double("form")
        errors = double("errors")
        allow(errors).to receive(:full_messages).and_return([ "フィールドは必須です" ])
        allow(form).to receive(:errors).and_return(errors)

        exception = ActiveModel::ValidationError.new(form)
        details = controller.send(:extract_error_details, exception)

        expect(details).to eq([ "フィールドは必須です" ])
      end
    end

    context "other exceptions" do
      it "returns nil for non-validation errors" do
        exception = StandardError.new("generic error")
        details = controller.send(:extract_error_details, exception)

        expect(details).to be_nil
      end
    end
  end

  # ============================================
  # Edge Cases & Security Tests
  # ============================================

  describe "edge cases and security" do
    context "request context" do
      it "handles missing request gracefully" do
        allow(controller).to receive(:request).and_return(nil)

        expect { get :test_json_error, format: :json }.not_to raise_error
      end
    end

    context "malformed requests" do
      it "handles requests without proper format" do
        expect { get :test_json_error }.not_to raise_error
      end
    end

    context "large error messages" do
      it "handles very long error messages" do
        long_message = "A" * 1000
        allow_any_instance_of(ActiveRecord::RecordNotFound).to receive(:message).and_return(long_message)

        get :test_json_error, format: :json

        expect(response).to have_http_status(404)
        json_response = JSON.parse(response.body)
        expect(json_response["message"].length).to be <= 1000
      end
    end

    context "concurrent error handling" do
      it "handles multiple simultaneous errors" do
        threads = []

        5.times do
          threads << Thread.new do
            get :test_json_error, format: :json
          end
        end

        threads.each(&:join)

        # スレッドが完了し、例外が発生しないことを確認
        expect(threads.all?(&:stop?)).to be true
      end
    end
  end

  # ============================================
  # Integration with other modules
  # ============================================

  describe "integration with other modules" do
    context "with SecurityCompliance" do
      before do
        allow(controller.class).to receive(:ancestors).and_return([ SecurityCompliance, ErrorHandlers ])
      end

      it "works alongside security compliance features" do
        expect { get :test_json_error, format: :json }.not_to raise_error
      end
    end

    context "with ApiResponse" do
      it "integrates properly with ApiResponse class" do
        expect(ApiResponse).to receive(:from_exception).and_call_original

        get :test_json_error, format: :json
      end
    end
  end
end
