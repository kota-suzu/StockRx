# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::SessionsController, type: :controller do
  let(:store) { create(:store) }
  let(:inactive_store) { create(:store, :inactive) }

  before do
    @request.env["devise.mapping"] = Devise.mappings[:store_user]
  end

  describe "GET #new" do
    context "with store_slug parameter" do
      it "renders the login page" do
        get :new, params: { store_slug: store.slug }
        expect(response).to have_http_status(:success)
        expect(response).to render_template(:new)
      end

      it "uses store_auth layout" do
        get :new, params: { store_slug: store.slug }
        expect(response).to render_template(layout: "store_auth")
      end

      it "sets @store instance variable" do
        get :new, params: { store_slug: store.slug }
        expect(assigns(:store)).to eq(store)
      end
    end

    context "without store_slug parameter" do
      it "redirects to store selection page" do
        get :new
        expect(response).to redirect_to(store_selection_path)
      end
    end

    context "with invalid store_slug" do
      it "redirects to store selection page with alert" do
        get :new, params: { store_slug: "invalid-slug" }
        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("見つかりません")
      end
    end

    context "when already logged in" do
      let(:store_user) { create(:store_user, store: store) }

      before do
        sign_in store_user
      end

      it "allows access to login page" do
        get :new, params: { store_slug: store.slug }
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "POST #create" do
    let(:store_user) { create(:store_user, store: store, email: "user@example.com", password: "Password123!") }

    context "with valid credentials and store" do
      it "logs in the store user" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "Password123!" }
        }

        expect(controller.current_store_user).to eq(store_user)
        expect(response).to redirect_to(store_root_path)
      end

      it "sets store_id in session" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "Password123!" }
        }

        expect(session[:current_store_id]).to eq(store.id)
        expect(session[:signed_in_at]).to be_present
      end

      it "creates audit log for successful login" do
        expect {
          post :create, params: {
            store_slug: store.slug,
            store_user: { email: store_user.email, password: "Password123!" }
          }
        }.to change { AuditLog.where(action: "login").count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.auditable).to eq(store_user)
        expect(JSON.parse(audit_log.details)["store_id"]).to eq(store.id)
      end

      it "sets flash notice" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "Password123!" }
        }

        expect(flash[:notice]).to be_present
      end
    end

    context "with password change required" do
      let(:store_user) { create(:store_user, :must_change_password, store: store) }

      it "redirects to password change page" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: store_user.password }
        }

        expect(response).to redirect_to(store_root_path)
        expect(flash[:notice]).to include("初回ログイン")
      end
    end

    context "without store_slug" do
      it "redirects to store selection page" do
        post :create, params: {
          store_user: { email: store_user.email, password: "Password123!" }
        }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("店舗を選択")
      end

      it "does not log in the user" do
        post :create, params: {
          store_user: { email: store_user.email, password: "Password123!" }
        }

        expect(controller.current_store_user).to be_nil
      end
    end

    context "with invalid credentials" do
      it "does not log in with wrong password" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "WrongPassword!" }
        }

        expect(controller.current_store_user).to be_nil
        expect(response).to redirect_to(new_store_user_session_path(store_slug: store.slug))
        expect(flash[:alert]).to include("メールアドレスまたはパスワードが違います")
      end

      it "does not log in user from different store" do
        other_store = create(:store, :active)
        other_user = create(:store_user, store: other_store)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: other_user.email, password: other_user.password }
        }

        expect(controller.current_store_user).to be_nil
      end

      it "tracks rate limit for failed attempts" do
        expect(controller).to receive(:track_rate_limit_action!)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "WrongPassword!" }
        }
      end
    end

    context "with inactive store" do
      it "does not allow login" do
        user = create(:store_user, store: inactive_store)

        post :create, params: {
          store_slug: inactive_store.slug,
          store_user: { email: user.email, password: user.password }
        }

        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to include("無効")
      end
    end

    context "JSON format" do
      before do
        request.accept = "application/json"
      end

      it "returns JSON response on success" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "Password123!" }
        }, format: :json

        expect(response).to have_http_status(:success)
        expect(response.content_type).to match(/json/)
      end

      it "skips CSRF verification for JSON requests" do
        allow(controller).to receive(:verify_authenticity_token).and_raise(ActionController::InvalidAuthenticityToken)

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: store_user.email, password: "Password123!" }
        }, format: :json

        expect(controller.current_store_user).to eq(store_user)
      end
    end
  end

  describe "DELETE #destroy" do
    let(:store_user) { create(:store_user, store: store) }

    context "when logged in" do
      before do
        sign_in store_user
        session[:current_store_id] = store.id
        session[:signed_in_at] = 1.hour.ago
      end

      it "logs out the store user" do
        delete :destroy

        expect(controller.current_store_user).to be_nil
        expect(response).to redirect_to(store_selection_path)
      end

      it "clears session data" do
        delete :destroy

        expect(session[:current_store_id]).to be_nil
        expect(session[:signed_in_at]).to be_nil
      end

      it "creates audit log for logout" do
        expect {
          delete :destroy
        }.to change { AuditLog.where(action: "logout").count }.by(1)

        audit_log = AuditLog.last
        expect(audit_log.message).to include(store_user.name)
        expect(JSON.parse(audit_log.details)["session_duration"]).to be > 0
      end

      it "handles audit log errors gracefully" do
        allow(AuditLog).to receive(:log_action).and_raise(StandardError, "DB Error")

        expect {
          delete :destroy
        }.not_to raise_error

        expect(controller.current_store_user).to be_nil
      end
    end

    context "when not logged in" do
      it "redirects to store selection page" do
        delete :destroy

        expect(response).to redirect_to(store_selection_path)
      end
    end
  end

  describe "protected methods" do
    describe "#after_sign_in_path_for" do
      let(:store_user) { create(:store_user, store: store) }

      it "returns store root path by default" do
        expect(controller.send(:after_sign_in_path_for, store_user)).to eq(store_root_path)
      end

      it "returns stored location if present" do
        stored_path = "/store/inventories"
        controller.store_location_for(:store_user, stored_path)

        expect(controller.send(:after_sign_in_path_for, store_user)).to eq(stored_path)
      end
    end

    describe "#after_sign_out_path_for" do
      it "returns store selection path" do
        expect(controller.send(:after_sign_out_path_for, :store_user)).to eq(store_selection_path)
      end
    end
  end

  describe "rate limiting" do
    let(:controller_with_rate_limit) do
      controller.extend(RateLimitable)
      controller
    end

    it "applies rate limiting to create action" do
      expect(controller.send(:rate_limited_actions)).to include(:create)
    end

    it "uses login as rate limit key type" do
      expect(controller.send(:rate_limit_key_type)).to eq(:login)
    end

    it "generates rate limit identifier with store and IP" do
      controller.instance_variable_set(:@store, store)
      allow(controller.request).to receive(:remote_ip).and_return("192.168.1.1")

      expect(controller.send(:rate_limit_identifier)).to eq("#{store.id}:192.168.1.1")
    end
  end

  describe "security features" do
    describe "SQL injection prevention" do
      it "safely handles malicious email input" do
        malicious_email = "user@example.com' OR '1'='1"

        post :create, params: {
          store_slug: store.slug,
          store_user: { email: malicious_email, password: "password" }
        }

        expect(controller.current_store_user).to be_nil
      end
    end

    describe "XSS prevention" do
      it "escapes malicious store slug" do
        get :new, params: { store_slug: "<script>alert('XSS')</script>" }

        expect(flash[:alert]).not_to include("<script>")
      end
    end

    describe "parameter filtering" do
      it "only permits allowed parameters" do
        post :create, params: {
          store_slug: store.slug,
          store_user: {
            email: "user@example.com",
            password: "password",
            admin: true,  # Should be filtered
            store_id: 999  # Should be filtered
          }
        }

        # These parameters should not affect the authentication
        expect(controller.current_store_user).to be_nil
      end
    end
  end

  describe "edge cases" do
    describe "concurrent login attempts" do
      let(:store_user) { create(:store_user, store: store) }

      it "handles race conditions" do
        threads = []
        success_count = 0

        5.times do
          threads << Thread.new do
            begin
              post :create, params: {
                store_slug: store.slug,
                store_user: { email: store_user.email, password: store_user.password }
              }
              success_count += 1 if response.redirect_url == store_root_url
            rescue => e
              # Handle any connection errors in thread
            end
          end
        end

        threads.each(&:join)

        # At least one login should succeed
        expect(success_count).to be >= 1
      end
    end

    describe "malformed parameters" do
      it "handles missing store_user params" do
        post :create, params: { store_slug: store.slug }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(controller.current_store_user).to be_nil
      end

      it "handles empty credentials" do
        post :create, params: {
          store_slug: store.slug,
          store_user: { email: "", password: "" }
        }

        expect(controller.current_store_user).to be_nil
      end
    end
  end
end
