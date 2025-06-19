# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::EmailAuthController, type: :controller do
  let(:store) { create(:store, :active) }
  let(:store_user) { create(:store_user, store: store) }
  let(:email_auth_service) { instance_double(EmailAuthService) }

  before do
    allow(EmailAuthService).to receive(:new).and_return(email_auth_service)
  end

  # ============================================
  # 一時パスワードリクエストフォーム表示テスト
  # ============================================

  describe 'GET #new' do
    context 'when store is specified' do
      before { get :new, params: { store_slug: store.slug } }

      it 'returns http success' do
        expect(response).to have_http_status(:success)
      end

      it 'assigns store' do
        expect(assigns(:store)).to eq(store)
      end

      it 'assigns email auth request' do
        expect(assigns(:email_auth_request)).to be_a(EmailAuthRequest)
        expect(assigns(:email_auth_request).store_id).to eq(store.id)
      end

      it 'uses store_auth layout' do
        expect(response).to render_template(layout: 'store_auth')
      end
    end

    context 'when store is not specified' do
      before { get :new }

      it 'redirects to store selection' do
        expect(response).to redirect_to(store_selection_path)
      end
    end

    context 'when store is inactive' do
      let(:inactive_store) { create(:store, :inactive) }

      before { get :new, params: { store_slug: inactive_store.slug } }

      it 'redirects to store selection with error' do
        expect(response).to redirect_to(store_selection_path)
        expect(flash[:alert]).to be_present
      end
    end
  end

  # ============================================
  # 一時パスワードリクエスト処理テスト
  # ============================================

  describe 'POST #request_temp_password' do
    let(:valid_params) do
      {
        store_slug: store.slug,
        email_auth_request: {
          email: store_user.email
        }
      }
    end

    context 'with valid parameters and successful service call' do
      before do
        allow(email_auth_service).to receive(:generate_and_send_temp_password)
          .and_return({ success: true })
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(true)
        allow(email_auth_service).to receive(:record_authentication_attempt).and_return(true)
      end

      it 'calls EmailAuthService' do
        post :request_temp_password, params: valid_params

        expect(email_auth_service).to have_received(:generate_and_send_temp_password)
          .with(
            store_user,
            admin_id: nil,
            request_metadata: hash_including(
              :ip_address,
              :user_agent,
              :requested_at
            )
          )
      end

      it 'redirects to verification form with success message' do
        post :request_temp_password, params: valid_params

        expect(response).to redirect_to(verify_form_store_email_auth_path(store_slug: store.slug))
        expect(flash[:notice]).to include('一時パスワード')
      end

      it 'increments rate limit counter' do
        post :request_temp_password, params: valid_params

        expect(email_auth_service).to have_received(:record_authentication_attempt)
          .with(store_user.email, request.remote_ip)
      end
    end

    context 'with valid parameters but service failure' do
      before do
        allow(email_auth_service).to receive(:generate_and_send_temp_password)
          .and_return({ success: false, error: 'Service error' })
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(true)
      end

      it 'renders new template with error' do
        post :request_temp_password, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to be_present
      end
    end

    context 'when user does not exist' do
      let(:invalid_params) do
        {
          store_slug: store.slug,
          email_auth_request: {
            email: 'nonexistent@example.com'
          }
        }
      end

      before do
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(true)
      end

      it 'still returns success message (security: enumeration attack prevention)' do
        post :request_temp_password, params: invalid_params

        expect(response).to redirect_to(verify_form_store_email_auth_path(store_slug: store.slug))
        expect(flash[:notice]).to include('一時パスワード')
      end

      it 'does not call EmailAuthService' do
        post :request_temp_password, params: invalid_params

        expect(email_auth_service).not_to have_received(:generate_and_send_temp_password)
      end
    end

    context 'when rate limit is exceeded' do
      before do
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(false)
      end

      it 'renders error without calling service' do
        post :request_temp_password, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to include('制限')
        expect(email_auth_service).not_to have_received(:generate_and_send_temp_password)
      end
    end

    context 'without email parameter' do
      let(:invalid_params) do
        {
          store_slug: store.slug,
          email_auth_request: {
            email: ''
          }
        }
      end

      it 'renders error for missing email' do
        post :request_temp_password, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to be_present
      end
    end

    context 'without store' do
      let(:invalid_params) do
        {
          email_auth_request: {
            email: store_user.email
          }
        }
      end

      it 'renders error for missing store' do
        post :request_temp_password, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash.now[:alert]).to include('店舗')
      end
    end

    # JSON format tests
    context 'with JSON format' do
      before do
        allow(email_auth_service).to receive(:generate_and_send_temp_password)
          .and_return({ success: true })
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(true)
        allow(email_auth_service).to receive(:record_authentication_attempt).and_return(true)
      end

      it 'returns JSON success response' do
        post :request_temp_password, params: valid_params, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['next_step']).to eq('verify_temp_password')
      end
    end
  end

  # ============================================
  # 一時パスワード検証フォーム表示テスト
  # ============================================

  describe 'GET #verify_form' do
    context 'when store is specified' do
      before { get :verify_form, params: { store_slug: store.slug } }

      it 'returns http success' do
        expect(response).to have_http_status(:success)
      end

      it 'assigns store' do
        expect(assigns(:store)).to eq(store)
      end

      it 'assigns temp password verification' do
        expect(assigns(:temp_password_verification)).to be_a(TempPasswordVerification)
        expect(assigns(:temp_password_verification).store_id).to eq(store.id)
      end
    end

    context 'when store is not specified' do
      before { get :verify_form }

      it 'redirects to store selection' do
        expect(response).to redirect_to(store_selection_path)
      end
    end
  end

  # ============================================
  # 一時パスワード検証・ログイン処理テスト
  # ============================================

  describe 'POST #verify_temp_password' do
    let(:temp_password) { create(:temp_password, store_user: store_user) }
    let(:valid_params) do
      {
        store_slug: store.slug,
        temp_password_verification: {
          email: store_user.email,
          temp_password: 'TempPass123!'
        }
      }
    end

    context 'with valid parameters and successful authentication' do
      before do
        allow(email_auth_service).to receive(:authenticate_with_temp_password)
          .and_return({ success: true, temp_password: temp_password })
        allow(controller).to receive(:sign_in)
        allow(AuditLog).to receive(:log_action)
      end

      it 'calls EmailAuthService for authentication' do
        post :verify_temp_password, params: valid_params

        expect(email_auth_service).to have_received(:authenticate_with_temp_password)
          .with(
            store_user,
            'TempPass123!',
            request_metadata: hash_including(
              :ip_address,
              :user_agent,
              :verified_at
            )
          )
      end

      it 'signs in the user' do
        post :verify_temp_password, params: valid_params

        expect(controller).to have_received(:sign_in)
          .with(store_user, scope: :store_user)
      end

      it 'sets session information' do
        post :verify_temp_password, params: valid_params

        expect(session[:current_store_id]).to eq(store_user.store_id)
        expect(session[:login_method]).to eq('temp_password')
        expect(session[:temp_password_id]).to eq(temp_password.id)
        expect(session[:signed_in_at]).to be_within(1.second).of(Time.current)
      end

      it 'logs the authentication event' do
        post :verify_temp_password, params: valid_params

        expect(AuditLog).to have_received(:log_action)
          .with(
            store_user,
            'temp_password_login',
            a_string_including(store_user.name),
            hash_including(
              store_id: store_user.store_id,
              login_method: 'temp_password',
              temp_password_id: temp_password.id
            )
          )
      end

      it 'redirects to store root with success message' do
        post :verify_temp_password, params: valid_params

        expect(response).to redirect_to(store_root_path)
        expect(flash[:notice]).to include('ログイン')
      end
    end

    context 'with valid parameters but authentication failure' do
      before do
        allow(email_auth_service).to receive(:authenticate_with_temp_password)
          .and_return({ success: false, error: 'Invalid password' })
        allow(email_auth_service).to receive(:record_authentication_attempt).and_return(true)
      end

      it 'renders verification form with error' do
        post :verify_temp_password, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:verify_form)
        expect(flash.now[:alert]).to be_present
      end

      it 'increments rate limit counter' do
        post :verify_temp_password, params: valid_params

        expect(email_auth_service).to have_received(:record_authentication_attempt)
          .with(store_user.email, request.remote_ip)
      end

      it 'does not sign in the user' do
        allow(controller).to receive(:sign_in)
        post :verify_temp_password, params: valid_params

        expect(controller).not_to have_received(:sign_in)
      end
    end

    context 'when user does not exist' do
      let(:invalid_params) do
        {
          store_slug: store.slug,
          temp_password_verification: {
            email: 'nonexistent@example.com',
            temp_password: 'TempPass123!'
          }
        }
      end

      before do
        allow(email_auth_service).to receive(:record_authentication_attempt).and_return(true)
      end

      it 'renders error without calling authentication service' do
        post :verify_temp_password, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:verify_form)
        expect(flash.now[:alert]).to be_present
        expect(email_auth_service).not_to have_received(:authenticate_with_temp_password)
      end

      it 'increments rate limit counter' do
        post :verify_temp_password, params: invalid_params

        expect(email_auth_service).to have_received(:record_authentication_attempt)
          .with('nonexistent@example.com', request.remote_ip)
      end
    end

    context 'without required parameters' do
      let(:invalid_params) do
        {
          store_slug: store.slug,
          temp_password_verification: {
            email: '',
            temp_password: ''
          }
        }
      end

      it 'renders error for missing parameters' do
        post :verify_temp_password, params: invalid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:verify_form)
        expect(flash.now[:alert]).to be_present
      end
    end

    # JSON format tests
    context 'with JSON format' do
      before do
        allow(email_auth_service).to receive(:authenticate_with_temp_password)
          .and_return({ success: true, temp_password: temp_password })
        allow(controller).to receive(:sign_in)
        allow(AuditLog).to receive(:log_action)
      end

      it 'returns JSON success response' do
        post :verify_temp_password, params: valid_params, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be true
        expect(json_response['redirect_url']).to eq(store_root_path)
      end
    end
  end

  # ============================================
  # レート制限テスト
  # ============================================

  describe 'rate limiting' do
    let(:valid_params) do
      {
        store_slug: store.slug,
        email_auth_request: {
          email: store_user.email
        }
      }
    end

    context 'when rate limit is exceeded' do
      before do
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(false)
      end

      it 'blocks request_temp_password action' do
        post :request_temp_password, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash.now[:alert]).to include('制限')
      end

      it 'blocks verify_temp_password action' do
        verification_params = {
          store_slug: store.slug,
          temp_password_verification: {
            email: store_user.email,
            temp_password: 'TempPass123!'
          }
        }

        post :verify_temp_password, params: verification_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(flash.now[:alert]).to include('制限')
      end

      context 'with JSON format' do
        it 'returns rate limit error in JSON' do
          post :request_temp_password, params: valid_params, format: :json

          expect(response).to have_http_status(:too_many_requests)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be false
          expect(json_response['error_code']).to eq('rate_limit_exceeded')
        end
      end
    end
  end

  # ============================================
  # エラーハンドリングテスト
  # ============================================

  describe 'error handling' do
    let(:valid_params) do
      {
        store_slug: store.slug,
        email_auth_request: {
          email: store_user.email
        }
      }
    end

    context 'when EmailAuthService raises an exception' do
      before do
        allow(email_auth_service).to receive(:rate_limit_check)
          .and_return(true)
        allow(email_auth_service).to receive(:generate_and_send_temp_password)
          .and_raise(StandardError, 'Service unavailable')
      end

      it 'handles the exception gracefully' do
        post :request_temp_password, params: valid_params

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:new)
        expect(flash.now[:alert]).to include('システム')
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error)
          .with(a_string_including('一時パスワード生成エラー'))

        post :request_temp_password, params: valid_params
      end
    end
  end

  # ============================================
  # プライベートメソッドテスト
  # ============================================

  describe 'private methods' do
    describe '#mask_email' do
      let(:controller_instance) { described_class.new }

      it 'masks single character email' do
        expect(controller_instance.send(:mask_email, 'a@example.com')).to eq('a***@example.com')
      end

      it 'masks two character email' do
        expect(controller_instance.send(:mask_email, 'ab@example.com')).to eq('a*@example.com')
      end

      it 'masks longer email' do
        expect(controller_instance.send(:mask_email, 'test@example.com')).to eq('t***t@example.com')
      end

      it 'handles empty email' do
        expect(controller_instance.send(:mask_email, '')).to eq('[NO_EMAIL]')
      end

      it 'handles invalid email' do
        expect(controller_instance.send(:mask_email, 'invalid')).to eq('[INVALID_EMAIL]')
      end
    end

    describe '#extract_email_from_params' do
      let(:controller_instance) { described_class.new }

      before do
        controller_instance.params = ActionController::Parameters.new(params)
      end

      context 'with email_auth_request params' do
        let(:params) { { email_auth_request: { email: 'test@example.com' } } }

        it 'extracts email correctly' do
          expect(controller_instance.send(:extract_email_from_params)).to eq('test@example.com')
        end
      end

      context 'with temp_password_verification params' do
        let(:params) { { temp_password_verification: { email: 'verify@example.com' } } }

        it 'extracts email correctly' do
          expect(controller_instance.send(:extract_email_from_params)).to eq('verify@example.com')
        end
      end

      context 'with direct email param' do
        let(:params) { { email: 'direct@example.com' } }

        it 'extracts email correctly' do
          expect(controller_instance.send(:extract_email_from_params)).to eq('direct@example.com')
        end
      end
    end
  end

  # ============================================
  # 統合テスト（将来のフォームオブジェクト用）
  # ============================================

  describe 'form objects' do
    describe 'EmailAuthRequest' do
      let(:form) { EmailAuthRequest.new(email: 'test@example.com', store_id: store.id) }

      it 'is valid with valid attributes' do
        expect(form).to be_valid
      end

      it 'is invalid without email' do
        form.email = nil
        expect(form).not_to be_valid
        expect(form.errors[:email]).to include("can't be blank")
      end

      it 'is invalid with invalid email format' do
        form.email = 'invalid-email'
        expect(form).not_to be_valid
        expect(form.errors[:email]).to include('is invalid')
      end

      it 'is invalid without store_id' do
        form.store_id = nil
        expect(form).not_to be_valid
        expect(form.errors[:store_id]).to include("can't be blank")
      end

      it 'returns the correct store' do
        expect(form.store).to eq(store)
      end
    end

    describe 'TempPasswordVerification' do
      let(:form) do
        TempPasswordVerification.new(
          email: 'test@example.com',
          temp_password: 'TempPass123!',
          store_id: store.id
        )
      end

      it 'is valid with valid attributes' do
        expect(form).to be_valid
      end

      it 'is invalid without temp_password' do
        form.temp_password = nil
        expect(form).not_to be_valid
        expect(form.errors[:temp_password]).to include("can't be blank")
      end

      it 'returns the correct store' do
        expect(form.store).to eq(store)
      end
    end
  end
end
