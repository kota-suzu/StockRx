# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Errors", type: :request do
  describe "GET /error" do
    context "with code parameter" do
      %w[403 404 429 500].each do |code|
        it "renders error page for code #{code}" do
          get error_path(code: code)
          expect(response).to have_http_status(code.to_i)
          expect(response.body).to include(code)
        end
      end
    end

    context "with unsupported code" do
      it "defaults to 500 error" do
        get error_path(code: "999")
        expect(response).to have_http_status(:internal_server_error)
      end
    end

    context "without code parameter" do
      it "defaults to 500 error" do
        get error_path
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe "GET /404" do
    it "renders 404 error page" do
      get "/404"
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("404")
      expect(response.body).to include("ページが見つかりません")
    end
  end

  describe "GET /403" do
    it "renders 403 error page" do
      get "/403"
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("403")
      expect(response.body).to include("アクセスが禁止されています")
    end
  end

  describe "GET /429" do
    it "renders 429 error page" do
      get "/429"
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("429")
      expect(response.body).to include("リクエスト頻度が制限を超えています")
    end
  end

  describe "GET /500" do
    it "renders 500 error page" do
      get "/500"
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("500")
      expect(response.body).to include("サーバーエラーが発生しました")
    end
  end

  describe "Wildcard route" do
    it "catches undefined routes and returns 404" do
      get "/this/path/does/not/exist"
      expect(response).to have_http_status(:not_found)
    end

    it "does not catch Rails internal routes" do
      # Rails internal routes should not be caught by our wildcard
      # This test ensures that our constraint properly excludes Rails internal paths
      # Rails returns 404 for non-existent internal paths, which is expected behavior
      get "/rails/info/properties"
      # Rails handles this internally and returns 404, not our custom error page
      expect(response).to have_http_status(:not_found)
      # Verify it's not our custom error page by checking it doesn't have our error template structure
      expect(response.body).not_to include("error-container")
      expect(response.body).not_to include("error-code")
    end
  end
end
