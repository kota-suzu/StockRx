# frozen_string_literal: true

RSpec.shared_examples 'a CRUD controller' do |model_class|
  let(:model_name) { model_class.name.underscore }
  let(:model_symbol) { model_name.to_sym }
  let(:admin) { create(:admin, :headquarters_admin) }

  before do
    sign_in admin
  end

  describe 'GET #index' do
    let!(:records) { create_list(model_symbol, 3) }

    it 'returns successful response' do
      get :index
      expect(response).to have_http_status(:success)
    end

    it 'assigns records' do
      get :index
      expect(assigns(model_name.pluralize.to_sym)).to match_array(records)
    end

    context 'with search parameters' do
      it 'filters records' do
        get :index, params: { q: records.first.name }
        expect(assigns(model_name.pluralize.to_sym)).to include(records.first)
      end
    end

    context 'with pagination' do
      let!(:many_records) { create_list(model_symbol, 30) }

      it 'paginates results' do
        get :index, params: { page: 2 }
        expect(assigns(model_name.pluralize.to_sym).size).to be <= 25
      end
    end
  end

  describe 'GET #show' do
    let(:record) { create(model_symbol) }

    it 'returns successful response' do
      get :show, params: { id: record.id }
      expect(response).to have_http_status(:success)
    end

    it 'assigns the record' do
      get :show, params: { id: record.id }
      expect(assigns(model_symbol)).to eq(record)
    end

    context 'with non-existent record' do
      it 'raises RecordNotFound' do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'GET #new' do
    it 'returns successful response' do
      get :new
      expect(response).to have_http_status(:success)
    end

    it 'assigns new record' do
      get :new
      expect(assigns(model_symbol)).to be_a_new(model_class)
    end
  end

  describe 'POST #create' do
    let(:valid_attributes) { attributes_for(model_symbol) }
    let(:invalid_attributes) { attributes_for(model_symbol, name: '') }

    context 'with valid parameters' do
      it 'creates new record' do
        expect {
          post :create, params: { model_symbol => valid_attributes }
        }.to change(model_class, :count).by(1)
      end

      it 'redirects to show page' do
        post :create, params: { model_symbol => valid_attributes }
        expect(response).to redirect_to(action: :show, id: model_class.last.id)
      end

      it 'sets success flash' do
        post :create, params: { model_symbol => valid_attributes }
        expect(flash[:notice]).to match(/作成しました/)
      end
    end

    context 'with invalid parameters' do
      it 'does not create record' do
        expect {
          post :create, params: { model_symbol => invalid_attributes }
        }.not_to change(model_class, :count)
      end

      it 'renders new template' do
        post :create, params: { model_symbol => invalid_attributes }
        expect(response).to render_template(:new)
      end
    end
  end

  describe 'GET #edit' do
    let(:record) { create(model_symbol) }

    it 'returns successful response' do
      get :edit, params: { id: record.id }
      expect(response).to have_http_status(:success)
    end

    it 'assigns the record' do
      get :edit, params: { id: record.id }
      expect(assigns(model_symbol)).to eq(record)
    end
  end

  describe 'PATCH #update' do
    let(:record) { create(model_symbol) }
    let(:new_attributes) { { name: 'Updated Name' } }

    context 'with valid parameters' do
      it 'updates the record' do
        patch :update, params: { id: record.id, model_symbol => new_attributes }
        record.reload
        expect(record.name).to eq('Updated Name')
      end

      it 'redirects to show page' do
        patch :update, params: { id: record.id, model_symbol => new_attributes }
        expect(response).to redirect_to(action: :show, id: record.id)
      end

      it 'sets success flash' do
        patch :update, params: { id: record.id, model_symbol => new_attributes }
        expect(flash[:notice]).to match(/更新しました/)
      end
    end

    context 'with invalid parameters' do
      let(:invalid_attributes) { { name: '' } }

      it 'does not update record' do
        original_name = record.name
        patch :update, params: { id: record.id, model_symbol => invalid_attributes }
        record.reload
        expect(record.name).to eq(original_name)
      end

      it 'renders edit template' do
        patch :update, params: { id: record.id, model_symbol => invalid_attributes }
        expect(response).to render_template(:edit)
      end
    end
  end

  describe 'DELETE #destroy' do
    let!(:record) { create(model_symbol) }

    it 'destroys the record' do
      expect {
        delete :destroy, params: { id: record.id }
      }.to change(model_class, :count).by(-1)
    end

    it 'redirects to index' do
      delete :destroy, params: { id: record.id }
      expect(response).to redirect_to(action: :index)
    end

    it 'sets success flash' do
      delete :destroy, params: { id: record.id }
      expect(flash[:notice]).to match(/削除しました/)
    end
  end
end

RSpec.shared_examples 'has search functionality' do
  let(:admin) { create(:admin, :headquarters_admin) }
  let!(:searchable_records) { create_list(described_class.controller_name.singularize.to_sym, 5) }

  before do
    sign_in admin
  end

  it 'responds to search parameters' do
    get :index, params: { q: searchable_records.first.name }
    expect(response).to have_http_status(:success)
  end

  it 'filters results based on search query' do
    get :index, params: { q: searchable_records.first.name }
    expect(assigns(:q)).to be_present
  end
end
