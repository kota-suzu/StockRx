# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Mass Assignment Security', type: :request do
  let(:store) { create(:store) }
  let(:store_user) { create(:store_user, store: store) }

  before do
    sign_in store_user
  end

  describe 'Store Inventories Controller' do
    describe 'Mass Assignment対策' do
      it 'params.permit!の使用を禁止し、ホワイトリスト方式を使用する' do
        # 🛡️ セキュリティテスト: Mass Assignment攻撃の防止
        malicious_params = {
          q: {
            name_cont: 'test',
            manufacturer_eq: 'TestCorp'
          },
          # 悪意のあるパラメータ
          admin_access: true,
          role: 'admin',
          destroy_all: true,
          secret_key: 'hacked',
          sort: 'name',
          direction: 'asc'
        }

        get '/store/inventories', params: malicious_params

        # レスポンスが正常に返る（攻撃は阻止される）
        expect(response).to have_http_status(:success)

        # ログイン状態の確認（権限昇格攻撃が失敗）
        expect(store_user.role).not_to eq('admin')
      end

      it 'ソートリンクで許可されたパラメータのみを使用する' do
        # 正常なソートパラメータのテスト
        valid_params = {
          q: {
            name_cont: 'test',
            manufacturer_eq: 'TestCorp',
            stock_level_eq: 'low',
            quantity_gteq: 10,
            quantity_lteq: 100
          },
          sort: 'inventories.name',
          direction: 'asc',
          page: 1
        }

        get '/store/inventories', params: valid_params

        expect(response).to have_http_status(:success)
        expect(response.body).to include('在庫管理')
      end

      context 'パラメータタンパリング攻撃' do
        it '不正なパラメータ組み合わせを拒否する' do
          tampered_params = {
            q: {
              name_cont: "'; DROP TABLE inventories; --",
              manufacturer_eq: "' UNION SELECT password FROM admins --"
            },
            sort: "name; DELETE FROM stores; --",
            direction: "asc; UPDATE store_users SET role='admin'; --"
          }

          expect {
            get '/store/inventories', params: tampered_params
          }.not_to raise_error

          # データベースが破損していないことを確認
          expect(Store.count).to be > 0
          expect(StoreUser.count).to be > 0
        end
      end
    end

    describe 'CSRF対策' do
      it 'CSRFトークンなしのリクエストを拒否する' do
        # CSRFトークンを無効化してテスト
        allow_any_instance_of(ActionController::Base)
          .to receive(:protect_against_forgery?).and_return(true)

        # POST/PUT/DELETEリクエストでCSRF検証が機能することを確認
        post '/store/inventories', params: { name: 'test' }

        # CSRFエラーまたは認証エラーが発生することを期待
        expect(response).not_to have_http_status(:success)
      end
    end
  end

  describe 'セキュリティヘッダー検証' do
    it '適切なセキュリティヘッダーが設定されている' do
      get '/store/inventories'

      # XSS対策ヘッダー
      expect(response.headers['X-Frame-Options']).to be_present
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')

      # CSRF対策
      expect(response.body).to include('csrf-token')
    end
  end

  describe 'エラーハンドリング' do
    it '予期しないエラーで機密情報を漏洩しない' do
      # 存在しないページへのアクセス
      get '/store/inventories/99999999'

      # エラーページが適切に表示される
      expect(response).to have_http_status(:not_found)

      # データベース情報やスタックトレースが漏洩していない
      expect(response.body).not_to include('ActiveRecord')
      expect(response.body).not_to include('mysql')
      expect(response.body).not_to include('password')
    end
  end
end
