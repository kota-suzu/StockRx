# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::SessionsController, type: :controller do
  before do
    @request.env["devise.mapping"] = Devise.mappings[:admin]
  end

  describe "GET #new" do
    context "when not logged in" do
      it "renders the login page" do
        get :new
        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:new)
      end
    end

    context "when already logged in" do
      let(:admin) { create(:admin) }

      before do
        sign_in admin
      end

      it "redirects to dashboard" do
        get :new
        expect(response).to redirect_to(admin_root_path)
      end
    end
  end

  describe "POST #create" do
    let(:admin) { create(:admin) }

    context "with valid credentials" do
      it "logs in the admin" do
        post :create, params: {
          admin: {
            email: admin.email,
            password: "Password123!"
          }
        }

        expect(controller.current_admin).to eq(admin)
        expect(response).to redirect_to(admin_root_path)
      end
    end

    context "with invalid credentials" do
      it "renders the login page with error" do
        post :create, params: {
          admin: {
            email: admin.email,
            password: "wrong_password"
          }
        }

        expect(controller.current_admin).to be_nil
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "XSS prevention" do
      it "escapes malicious input in flash messages" do
        post :create, params: {
          admin: {
            email: "<script>alert('XSS')</script>",
            password: "password"
          }
        }

        expect(flash[:alert]).not_to include("<script>")
      end
    end
  end
end
