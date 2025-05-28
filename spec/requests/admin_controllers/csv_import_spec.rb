# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin CSV Import', type: :request do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
    # ActiveJobマッチャーを使用するためのキューアダプター設定
    ActiveJob::Base.queue_adapter = :test
  end

  describe 'GET /admin/inventories/import_form' do
    it 'displays import form' do
      get import_form_admin_inventories_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('CSVインポート')
    end
  end

  describe 'POST /admin/inventories/import' do
    context 'with valid CSV file' do
      let(:csv_file) do
        file = Tempfile.new([ 'inventories', '.csv' ])
        file.write("name,quantity,price\nテスト商品,100,1000")
        file.rewind
        file
      end

      after do
        csv_file.close
        csv_file.unlink
      end

      it 'enqueues import job' do
        expect {
          post import_admin_inventories_path, params: {
            file: Rack::Test::UploadedFile.new(csv_file.path, 'text/csv')
          }
        }.to have_enqueued_job(ImportInventoriesJob)

        # ジョブID付きのリダイレクトを期待
        expect(response).to redirect_to(/\/admin\/inventories\?import_started=true&job_id=.+/)
        follow_redirect!
        expect(response.body).to include('CSVインポートを開始しました')
      end
    end

    context 'without file' do
      it 'returns error' do
        post import_admin_inventories_path

        expect(response).to redirect_to(import_form_admin_inventories_path)
        follow_redirect!
        expect(response.body).to include('ファイルを選択してください')
      end
    end

    context 'with invalid file type' do
      let(:text_file) do
        file = Tempfile.new([ 'test', '.txt' ])
        file.write('invalid content')
        file.rewind
        file
      end

      after do
        text_file.close
        text_file.unlink
      end

      it 'returns error' do
        post import_admin_inventories_path, params: {
          file: Rack::Test::UploadedFile.new(text_file.path, 'text/plain')
        }

        # セキュリティエラーによりフォームにリダイレクト
        expect(response).to redirect_to(import_form_admin_inventories_path)
        follow_redirect!
        expect(response.body).to include('Invalid file type: .txt. Allowed types: .csv')
      end
    end
  end
end
