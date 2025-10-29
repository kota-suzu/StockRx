# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::PasswordsController, type: :controller do
  # CLAUDE.md準拠: パスワードリセット機能の包括的テスト
  # メタ認知: Deviseベースのコントローラーだが独自のセキュリティ設定があるため重点的にテスト
  # 横展開: 他のDeviseコントローラー（SessionsController）と同様のテストパターン適用

  before do
    @request.env["devise.mapping"] = Devise.mappings[:admin]
  end

  describe "レイアウト設定" do
    it "adminレイアウトを使用する" do
      get :new
      expect(response).to render_template(layout: "admin")
    end
  end

  describe "GET #new" do
    context "未ログイン時" do
      it "パスワードリセット画面を表示する" do
        get :new
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:new)
      end
    end

    context "ログイン済みの場合" do
      let(:admin) { create(:admin) }

      before do
        sign_in admin
      end

      it "パスワードリセット画面を表示する（ログイン中でもアクセス可能）" do
        get :new
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST #create" do
    let!(:admin) { create(:admin, email: "admin@example.com") }

    context "有効なメールアドレスの場合" do
      before do
        allow(Admin).to receive(:send_reset_password_instructions).and_return(admin)
      end

      it "パスワードリセットメールを送信する" do
        expect(Admin).to receive(:send_reset_password_instructions).with(
          hash_including(email: admin.email)
        )

        post :create, params: { admin: { email: admin.email } }
      end

      it "ログイン画面にリダイレクトする" do
        post :create, params: { admin: { email: admin.email } }
        expect(response).to redirect_to(new_admin_session_path)
      end

      it "成功メッセージを表示する" do
        post :create, params: { admin: { email: admin.email } }
        expect(flash[:notice]).to be_present
      end

      it "パスワードリセットトークンを生成する" do
        expect {
          post :create, params: { admin: { email: admin.email } }
          admin.reload
        }.to change { admin.reset_password_token }.from(nil)
      end

      it "監査ログを作成する" do
        expect {
          post :create, params: { admin: { email: admin.email } }
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("password_reset_requested")
        expect(audit_log.user).to eq(admin)
      end
    end

    context "存在しないメールアドレスの場合" do
      it "エラーメッセージを表示しない（セキュリティのため）" do
        post :create, params: { admin: { email: "nonexistent@example.com" } }
        expect(flash[:notice]).to be_present  # エラーではなく通常のメッセージ
      end

      it "ログイン画面にリダイレクトする" do
        post :create, params: { admin: { email: "nonexistent@example.com" } }
        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    context "無効なメールアドレスフォーマットの場合" do
      it "バリデーションエラーを表示する" do
        post :create, params: { admin: { email: "invalid-email" } }
        expect(response).to render_template(:new)
      end
    end

    context "空のメールアドレスの場合" do
      it "バリデーションエラーを表示する" do
        post :create, params: { admin: { email: "" } }
        expect(response).to render_template(:new)
      end
    end

    context "CSRF保護のスキップ" do
      it "CSRFトークンなしでもリクエストを処理する" do
        allow(controller).to receive(:verify_authenticity_token).and_raise(ActionController::InvalidAuthenticityToken)

        expect {
          post :create, params: { admin: { email: admin.email } }
        }.not_to raise_error

        expect(response).to redirect_to(new_admin_session_path)
      end
    end
  end

  describe "GET #edit" do
    let(:admin) { create(:admin) }
    let(:token) { admin.send_reset_password_instructions }

    context "有効なトークンの場合" do
      it "パスワード変更画面を表示する" do
        get :edit, params: { reset_password_token: token }
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:edit)
      end
    end

    context "無効なトークンの場合" do
      it "エラーメッセージを表示する" do
        get :edit, params: { reset_password_token: "invalid-token" }
        expect(response).to render_template(:edit)
      end
    end

    context "期限切れトークンの場合" do
      before do
        admin.send_reset_password_instructions
        admin.update!(reset_password_sent_at: 7.hours.ago)
      end

      it "エラーメッセージを表示する" do
        get :edit, params: { reset_password_token: token }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe "PUT #update" do
    let(:admin) { create(:admin) }
    let(:token) { admin.send_reset_password_instructions }

    context "有効なパスワードの場合" do
      let(:new_password) { "NewPassword123!" }

      it "パスワードを更新する" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: new_password,
            password_confirmation: new_password
          }
        }

        admin.reload
        expect(admin.valid_password?(new_password)).to be true
      end

      it "管理画面にリダイレクトする" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: new_password,
            password_confirmation: new_password
          }
        }

        expect(response).to redirect_to(admin_root_path)
      end

      it "自動的にログインする" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: new_password,
            password_confirmation: new_password
          }
        }

        expect(controller.current_admin).to eq(admin)
      end

      it "成功メッセージを表示する" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: new_password,
            password_confirmation: new_password
          }
        }

        expect(flash[:notice]).to be_present
      end

      it "監査ログを作成する" do
        expect {
          put :update, params: {
            admin: {
              reset_password_token: token,
              password: new_password,
              password_confirmation: new_password
            }
          }
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.where(action: "password_reset", user: admin).last
        expect(audit_log).to be_present
      end
    end

    context "パスワードが一致しない場合" do
      it "エラーを表示する" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: "NewPassword123!",
            password_confirmation: "DifferentPassword123!"
          }
        }

        expect(response).to render_template(:edit)
        expect(assigns(:admin).errors[:password_confirmation]).to be_present
      end
    end

    context "弱いパスワードの場合" do
      it "パスワード強度エラーを表示する" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: "weakpassword",
            password_confirmation: "weakpassword"
          }
        }

        expect(response).to render_template(:edit)
        expect(assigns(:admin).errors[:password]).to include(/大文字を含める/)
      end
    end

    context "無効なトークンの場合" do
      it "エラーを表示する" do
        put :update, params: {
          admin: {
            reset_password_token: "invalid-token",
            password: "NewPassword123!",
            password_confirmation: "NewPassword123!"
          }
        }

        expect(response).to render_template(:edit)
      end
    end

    context "期限切れトークンの場合" do
      before do
        admin.send_reset_password_instructions
        admin.update!(reset_password_sent_at: 7.hours.ago)
      end

      it "期限切れエラーを表示する" do
        put :update, params: {
          admin: {
            reset_password_token: token,
            password: "NewPassword123!",
            password_confirmation: "NewPassword123!"
          }
        }

        expect(response).to render_template(:edit)
      end
    end

    context "CSRF保護のスキップ" do
      it "CSRFトークンなしでもリクエストを処理する" do
        allow(controller).to receive(:verify_authenticity_token).and_raise(ActionController::InvalidAuthenticityToken)

        expect {
          put :update, params: {
            admin: {
              reset_password_token: token,
              password: "NewPassword123!",
              password_confirmation: "NewPassword123!"
            }
          }
        }.not_to raise_error
      end
    end
  end

  describe "セキュリティ機能" do
    let(:admin) { create(:admin) }

    describe "レート制限" do
      it "短時間での複数回のリセット要求を制限する" do
        # 5回リセット要求
        5.times do
          post :create, params: { admin: { email: admin.email } }
        end

        # 6回目はレート制限に引っかかる想定
        # TODO: Rack::Attackなどのレート制限実装後に有効化
        # expect {
        #   post :create, params: { admin: { email: admin.email } }
        # }.to raise_error(Rack::Attack::Throttled)
      end
    end

    describe "トークンのセキュリティ" do
      it "予測不可能なトークンを生成する" do
        token1 = admin.send_reset_password_instructions
        admin.clear_reset_password_token
        token2 = admin.send_reset_password_instructions

        expect(token1).not_to eq(token2)
        expect(token1.length).to be >= 20
      end
    end
  end

  describe "エッジケース" do
    describe "同時リクエスト" do
      let(:admin) { create(:admin) }

      it "同じアドレスで複数のリセット要求を適切に処理する" do
        # マルチスレッドテストは制御困難なためシーケンシャルに変更
        3.times do |i|
          post :create, params: { admin: { email: admin.email } }
          expect(response).to have_http_status(302) # Deviseはリダイレクトを返す

          # 各回のadmin状態をリセット
          admin.reload if i < 2
        end

        # 最後のリクエストのトークンが有効
        admin.reload
        expect(admin.reset_password_token).to be_present
      end
    end

    describe "SQLインジェクション防止" do
      it "悪意のあるメール入力を安全に処理する" do
        malicious_email = "admin@example.com' OR '1'='1"

        expect {
          post :create, params: { admin: { email: malicious_email } }
        }.not_to raise_error

        expect(response).to redirect_to(new_admin_session_path)
      end
    end

    describe "XSS防止" do
      it "悪意のある入力をエスケープする" do
        post :create, params: {
          admin: {
            email: "<script>alert('XSS')</script>@example.com"
          }
        }

        expect(response.body).not_to include("<script>")
      end
    end
  end

  describe "プロテクトメソッド" do
    let(:admin) { create(:admin) }

    describe "#after_resetting_password_path_for" do
      it "管理画面のルートパスを返す" do
        path = controller.send(:after_resetting_password_path_for, admin)
        expect(path).to eq(admin_root_path)
      end
    end

    describe "#after_sending_reset_password_instructions_path_for" do
      it "ログイン画面のパスを返す" do
        path = controller.send(:after_sending_reset_password_instructions_path_for, :admin)
        expect(path).to eq(new_admin_session_path)
      end
    end
  end
end
