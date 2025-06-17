# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "AdminControllers::Inventories", type: :request do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
  end

  describe "GET /admin/inventories" do
    it "returns a successful response" do
      get admin_inventories_path
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /admin/inventories/import_form" do
    it "returns a successful response" do
      get import_form_admin_inventories_path
      expect(response).to have_http_status(:success)
    end

    it "displays the CSV import form" do
      get import_form_admin_inventories_path
      expect(response.body).to include("在庫データCSVインポート")
      expect(response.body).to include("CSVファイル選択")
    end

    it "shows development notice" do
      get import_form_admin_inventories_path
      expect(response.body).to include("CSVインポート機能は現在Phase 3で実装予定です")
    end

    # TODO: Phase 3 - 追加テスト項目
    # - ファイルアップロード機能のテスト
    # - プレビュー機能のテスト
    # - バリデーションエラー表示のテスト
    # - ActionCable連携のテスト
    # - 進捗表示のテスト
  end

  describe "POST /admin/inventories/import" do
    it "redirects with development notice" do
      post import_admin_inventories_path
      expect(response).to redirect_to(admin_inventories_path)
      expect(flash[:alert]).to eq("CSVインポート機能は現在開発中です。Phase 3で実装予定です。")
    end

    # TODO: Phase 3 - CSVインポート機能実装時のテスト
    # context "with valid CSV file" do
    #   let(:csv_file) { fixture_file_upload('inventories.csv', 'text/csv') }
    #
    #   it "enqueues ImportInventoriesJob" do
    #     expect {
    #       post import_admin_inventories_path, params: { file: csv_file }
    #     }.to have_enqueued_job(ImportInventoriesJob)
    #   end
    # end
    #
    # context "with invalid file" do
    #   it "returns error for oversized file" do
    #     # ファイルサイズ制限のテスト
    #   end
    #
    #   it "returns error for non-CSV file" do
    #     # ファイル形式チェックのテスト
    #   end
    # end
  end
end
