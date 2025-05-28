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
      get error_404_path
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("404")
      expect(response.body).to include("ページが見つかりません")
    end
  end

  describe "GET /403" do
    it "renders 403 error page" do
      get error_403_path
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("403")
      expect(response.body).to include("アクセスが拒否されました")
    end
  end

  describe "GET /429" do
    it "renders 429 error page" do
      get error_429_path
      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("429")
      expect(response.body).to include("リクエストが多すぎます")
    end
  end

  describe "GET /500" do
    it "renders 500 error page" do
      get error_500_path
      expect(response).to have_http_status(:internal_server_error)
      expect(response.body).to include("500")
      expect(response.body).to include("システムエラーが発生しました")
    end
  end

  describe "Wildcard route" do
    it "catches undefined routes and returns 404" do
      get "/this/path/does/not/exist"
      expect(response).to have_http_status(:not_found)
    end

    it "does not catch Rails internal routes" do
      # Rails internal routes should not be caught by our wildcard
      # In test environment, this might not raise an error but should not return 404 from our handler
      get "/rails/active_storage/blobs/redirect/test"
      expect(response).not_to have_http_status(:not_found)
    end
  end
end
