# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::PasswordsController, type: :controller do
  # CLAUDE.md準拠: 店舗ユーザーパスワードリセット機能の包括的テスト
  # メタ認知: マルチテナント環境でのパスワードリセットの複雑性をテスト
  # 横展開: AdminControllers::PasswordsController と同様のセキュリティテスト適用

  let!(:store) { create(:store, slug: 'test-pharmacy') }
  let!(:store_user) { create(:store_user, store: store, email: 'user@example.com') }
  let!(:other_store) { create(:store, slug: 'other-pharmacy') }
  let!(:other_store_user) { create(:store_user, store: other_store, email: 'user@example.com') }

  before do
    @request.env["devise.mapping"] = Devise.mappings[:store_user]
  end

  describe "レイアウト設定" do
    it "store_authレイアウトを使用する" do
      get :new, params: { store_slug: store.slug }
      expect(response).to render_template(layout: "store_auth")
    end
  end

  describe "店舗情報の設定" do
    it "set_store_from_paramsが実行される" do
      expect(controller).to receive(:set_store_from_params)
      get :new, params: { store_slug: store.slug }
    end
  end

  describe "GET #new" do
    context "店舗が指定されている場合" do
      it "成功レスポンスを返す" do
        get :new, params: { store_slug: store.slug }
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:new)
      end

      it "店舗情報を設定する" do
        get :new, params: { store_slug: store.slug }
        expect(assigns(:store)).to eq(store)
      end
    end

    context "店舗が指定されていない場合" do
      it "店舗選択画面にリダイレクトする" do
        get :new
        expect(response).to redirect_to(store_selection_path)
      end
    end

    context "無効な店舗slugの場合" do
      it "店舗選択画面にリダイレクトする" do
        get :new, params: { store_slug: 'nonexistent-store' }
        expect(response).to redirect_to(store_selection_path)
      end
    end

    context "非アクティブな店舗の場合" do
      before { store.update!(active: false) }

      it "店舗選択画面にリダイレクトする" do
        get :new, params: { store_slug: store.slug }
        expect(response).to redirect_to(store_selection_path)
      end
    end
  end

  describe "POST #create" do
    context "有効なメールアドレスと店舗の組み合わせ" do
      it "パスワードリセットメールを送信する" do
        expect_any_instance_of(StoreUser).to receive(:send_reset_password_instructions)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email }
        }
      end

      it "ログイン画面にリダイレクトする" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email }
        }

        expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
      end

      it "成功メッセージを表示する" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email }
        }

        expect(flash[:notice]).to be_present
      end

      it "リセットトークンを生成する" do
        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: store_user.email }
          }
          store_user.reload
        }.to change { store_user.reset_password_token }.from(nil)
      end

      it "レート制限アクションを記録する" do
        expect(controller).to receive(:track_rate_limit_action!)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email }
        }
      end
    end

    context "存在しないメールアドレスの場合" do
      it "成功したように見せる（セキュリティのため）" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: 'nonexistent@example.com' }
        }

        expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
        expect(flash[:notice]).to be_present
      end

      it "パスワードリセットメールは送信しない" do
        expect_any_instance_of(StoreUser).not_to receive(:send_reset_password_instructions)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: 'nonexistent@example.com' }
        }
      end

      it "レート制限アクションを記録する" do
        expect(controller).to receive(:track_rate_limit_action!)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: 'nonexistent@example.com' }
        }
      end
    end

    context "他店舗のユーザーのメールアドレス" do
      it "成功したように見せる（店舗別分離のため）" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: other_store_user.email }
        }

        expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
        expect(flash[:notice]).to be_present
      end

      it "他店舗ユーザーにはメールを送信しない" do
        expect_any_instance_of(StoreUser).not_to receive(:send_reset_password_instructions)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: other_store_user.email }
        }
      end
    end

    context "大文字小文字を区別しないメール検索" do
      it "大文字のメールアドレスでも検索できる" do
        expect_any_instance_of(StoreUser).to receive(:send_reset_password_instructions)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email.upcase }
        }
      end
    end

    context "無効なメールフォーマット" do
      it "バリデーションエラーを表示する" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: 'invalid-email' }
        }

        expect(response).to render_template(:new)
      end
    end

    context "空のメールアドレス" do
      it "バリデーションエラーを表示する" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: '' }
        }

        expect(response).to render_template(:new)
      end
    end
  end

  describe "GET #edit" do
    let(:token) { store_user.send_reset_password_instructions }

    context "有効なトークンの場合" do
      it "成功レスポンスを返す" do
        get :edit, params: {
          store_slug: store.slug,
          reset_password_token: token
        }

        expect(response).to have_http_status(:success)
        expect(response).to render_template(:edit)
      end
    end

    context "無効なトークンの場合" do
      it "パスワードリセット申請画面にリダイレクトする" do
        get :edit, params: {
          store_slug: store.slug,
          reset_password_token: 'invalid-token'
        }

        expect(response).to redirect_to(new_store_user_password_path(store_slug: store.slug))
        expect(flash[:alert]).to be_present
      end
    end

    context "期限切れトークンの場合" do
      before do
        store_user.send_reset_password_instructions
        store_user.update!(reset_password_sent_at: 7.hours.ago)
      end

      it "パスワードリセット申請画面にリダイレクトする" do
        get :edit, params: {
          store_slug: store.slug,
          reset_password_token: token
        }

        expect(response).to redirect_to(new_store_user_password_path(store_slug: store.slug))
      end
    end
  end

  describe "PUT #update" do
    let(:token) { store_user.send_reset_password_instructions }
    let(:new_password) { 'NewPassword123!' }

    context "有効なパスワードの場合" do
      let(:valid_params) do
        {
          store_slug: store.slug,
          store_user: {
            reset_password_token: token,
            password: new_password,
            password_confirmation: new_password
          }
        }
      end

      it "パスワードを更新する" do
        put :update, params: valid_params

        store_user.reload
        expect(store_user.valid_password?(new_password)).to be true
      end

      it "password_changed_atを更新する" do
        freeze_time do
          put :update, params: valid_params

          store_user.reload
          expect(store_user.password_changed_at).to be_within(1.second).of(Time.current)
        end
      end

      it "must_change_passwordをfalseに設定する" do
        store_user.update!(must_change_password: true)

        put :update, params: valid_params

        store_user.reload
        expect(store_user.must_change_password).to be false
      end

      it "自動的にログインする" do
        put :update, params: valid_params

        expect(controller.current_store_user).to eq(store_user)
      end

      it "店舗ダッシュボードにリダイレクトする" do
        put :update, params: valid_params

        expect(response).to redirect_to(store_root_path)
      end

      it "成功メッセージを表示する" do
        put :update, params: valid_params

        expect(flash[:notice]).to be_present
      end
    end

    context "パスワードが一致しない場合" do
      let(:invalid_params) do
        {
          store_slug: store.slug,
          store_user: {
            reset_password_token: token,
            password: new_password,
            password_confirmation: 'DifferentPassword123!'
          }
        }
      end

      it "エラーを表示する" do
        put :update, params: invalid_params

        expect(response).to render_template(:edit)
        expect(assigns(:store_user).errors[:password_confirmation]).to be_present
      end

      it "パスワードを更新しない" do
        original_password = store_user.encrypted_password

        put :update, params: invalid_params

        store_user.reload
        expect(store_user.encrypted_password).to eq(original_password)
      end
    end

    context "弱いパスワードの場合" do
      let(:weak_params) do
        {
          store_slug: store.slug,
          store_user: {
            reset_password_token: token,
            password: 'weakpassword',
            password_confirmation: 'weakpassword'
          }
        }
      end

      it "パスワード強度エラーを表示する" do
        put :update, params: weak_params

        expect(response).to render_template(:edit)
        expect(assigns(:store_user).errors[:password]).to be_present
      end
    end

    context "無効なトークンの場合" do
      let(:invalid_token_params) do
        {
          store_slug: store.slug,
          store_user: {
            reset_password_token: 'invalid-token',
            password: new_password,
            password_confirmation: new_password
          }
        }
      end

      it "エラーを表示する" do
        put :update, params: invalid_token_params

        expect(response).to render_template(:edit)
      end
    end
  end

  describe "プロテクトメソッド" do
    describe "#resource_params" do
      let(:params_hash) do
        ActionController::Parameters.new({
          store_user: {
            email: 'test@example.com',
            password: 'password123',
            password_confirmation: 'password123',
            reset_password_token: 'token123',
            unauthorized_param: 'should_not_be_permitted'
          }
        })
      end

      before do
        allow(controller).to receive(:params).and_return(params_hash)
      end

      it "許可されたパラメータのみを返す" do
        permitted_params = controller.send(:resource_params)

        expect(permitted_params.keys).to include(
          'email', 'password', 'password_confirmation', 'reset_password_token'
        )
        expect(permitted_params.keys).not_to include('unauthorized_param')
      end
    end

    describe "#after_sending_reset_password_instructions_path_for" do
      context "店舗が設定されている場合" do
        before { controller.instance_variable_set(:@store, store) }

        it "店舗のログイン画面パスを返す" do
          path = controller.send(:after_sending_reset_password_instructions_path_for, :store_user)
          expect(path).to eq(new_store_user_session_path(store_slug: store.slug))
        end
      end

      context "店舗が設定されていない場合" do
        before { controller.instance_variable_set(:@store, nil) }

        it "店舗選択画面パスを返す" do
          path = controller.send(:after_sending_reset_password_instructions_path_for, :store_user)
          expect(path).to eq(store_selection_path)
        end
      end
    end

    describe "#after_resetting_password_path_for" do
      it "店舗ダッシュボードパスを返す" do
        path = controller.send(:after_resetting_password_path_for, store_user)
        expect(path).to eq(store_root_path)
      end
    end
  end

  describe "店舗管理メソッド" do
    describe "#set_store_from_params" do
      context "store_slugパラメータがある場合" do
        it "該当する店舗を設定する" do
          controller.params = { store_slug: store.slug }
          controller.send(:set_store_from_params)

          expect(controller.instance_variable_get(:@store)).to eq(store)
        end
      end

      context "store_userパラメータにstore_slugがある場合" do
        it "該当する店舗を設定する" do
          controller.params = {
            store_user: { store_slug: store.slug }
          }
          controller.send(:set_store_from_params)

          expect(controller.instance_variable_get(:@store)).to eq(store)
        end
      end

      context "リファラーから店舗slugを抽出する場合" do
        before do
          allow(controller.request).to receive(:referrer).and_return(
            "http://localhost:3000/store/#{store.slug}/login"
          )
        end

        it "リファラーから店舗を設定する" do
          controller.send(:set_store_from_params)

          expect(controller.instance_variable_get(:@store)).to eq(store)
        end
      end

      context "非アクティブな店舗の場合" do
        before { store.update!(active: false) }

        it "店舗を設定しない" do
          controller.params = { store_slug: store.slug }
          controller.send(:set_store_from_params)

          expect(controller.instance_variable_get(:@store)).to be_nil
        end
      end
    end

    describe "#extract_store_slug_from_referrer" do
      context "有効なリファラーがある場合" do
        before do
          allow(controller.request).to receive(:referrer).and_return(
            "http://localhost:3000/store/test-pharmacy/login"
          )
        end

        it "店舗slugを抽出する" do
          slug = controller.send(:extract_store_slug_from_referrer)
          expect(slug).to eq('test-pharmacy')
        end
      end

      context "店舗パスではないリファラーの場合" do
        before do
          allow(controller.request).to receive(:referrer).and_return(
            "http://localhost:3000/admin/dashboard"
          )
        end

        it "nilを返す" do
          slug = controller.send(:extract_store_slug_from_referrer)
          expect(slug).to be_nil
        end
      end

      context "リファラーがない場合" do
        before do
          allow(controller.request).to receive(:referrer).and_return(nil)
        end

        it "nilを返す" do
          slug = controller.send(:extract_store_slug_from_referrer)
          expect(slug).to be_nil
        end
      end
    end
  end

  describe "ヘルパーメソッド" do
    describe "#page_title" do
      context "店舗が設定されている場合" do
        before { controller.instance_variable_set(:@store, store) }

        it "店舗名を含むタイトルを返す" do
          title = controller.page_title
          expect(title).to eq("#{store.name} - パスワードリセット")
        end
      end

      context "店舗が設定されていない場合" do
        before { controller.instance_variable_set(:@store, nil) }

        it "基本タイトルを返す" do
          title = controller.page_title
          expect(title).to eq("パスワードリセット")
        end
      end
    end
  end

  describe "レート制限設定" do
    describe "#rate_limited_actions" do
      it "createアクションのみを制限する" do
        actions = controller.send(:rate_limited_actions)
        expect(actions).to eq([ :create ])
      end
    end

    describe "#rate_limit_key_type" do
      it "password_resetタイプを返す" do
        key_type = controller.send(:rate_limit_key_type)
        expect(key_type).to eq(:password_reset)
      end
    end

    describe "#rate_limit_identifier" do
      it "IPアドレスを返す" do
        allow(controller.request).to receive(:remote_ip).and_return('192.168.1.1')

        identifier = controller.send(:rate_limit_identifier)
        expect(identifier).to eq('192.168.1.1')
      end
    end
  end

  describe "セキュリティテスト" do
    context "SQLインジェクション防止" do
      it "悪意のあるメール入力を安全に処理する" do
        malicious_email = "user@example.com'; DROP TABLE store_users; --"

        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: malicious_email }
          }
        }.not_to raise_error

        expect(StoreUser.count).to be > 0
      end
    end

    context "XSS防止" do
      it "悪意のある入力をエスケープする" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: "<script>alert('XSS')</script>@example.com" }
        }

        expect(response.body).not_to include("<script>")
      end
    end

    context "タイミング攻撃防止" do
      it "存在するユーザーと存在しないユーザーで同じレスポンス時間" do
        # 存在するユーザー
        start_time1 = Time.current
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email }
        }
        time1 = Time.current - start_time1

        # 存在しないユーザー
        start_time2 = Time.current
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: 'nonexistent@example.com' }
        }
        time2 = Time.current - start_time2

        # タイミング差が大きくないことを確認（100ms以内）
        expect((time1 - time2).abs).to be < 0.1
      end
    end

    context "CSRF保護" do
      it "CSRFトークンが必要" do
        # CSRFトークンなしのリクエストは失敗する
        ActionController::Base.allow_forgery_protection = true

        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: store_user.email }
          }
        }.to raise_error(ActionController::InvalidAuthenticityToken)

        ActionController::Base.allow_forgery_protection = false
      end
    end
  end

  describe "エラーハンドリング" do
    context "メール送信エラー" do
      before do
        allow_any_instance_of(StoreUser).to receive(:send_reset_password_instructions).and_raise(Net::SMTPError)
      end

      it "エラーを適切に処理する" do
        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: store_user.email }
          }
        }.not_to raise_error
      end
    end

    context "データベース接続エラー" do
      before do
        allow(StoreUser).to receive(:find_by).and_raise(ActiveRecord::ConnectionTimeoutError)
      end

      it "データベースエラーを適切に処理する" do
        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: store_user.email }
          }
        }.to raise_error(ActiveRecord::ConnectionTimeoutError)
      end
    end
  end

  describe "国際化対応" do
    context "日本語環境" do
      before { I18n.locale = :ja }

      it "日本語メッセージを表示する" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email }
        }

        expect(flash[:notice]).to be_present
      end
    end

    context "英語環境" do
      before { I18n.locale = :en }

      it "英語環境でも正常に動作する" do
        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: store_user.email }
          }
        }.not_to raise_error
      end
    end
  end

  describe "パフォーマンステスト" do
    it "レスポンス時間が許容範囲内" do
      start_time = Time.current

      post :create, params: {
        store_slug: store.slug,
        store_user: { email: store_user.email }
      }

      elapsed_time = (Time.current - start_time) * 1000
      expect(elapsed_time).to be < 1000 # 1秒以内
    end
  end
end
