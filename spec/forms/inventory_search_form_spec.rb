# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventorySearchForm, type: :model do
  let(:form) { described_class.new }

  # テスト用のInventoryデータを作成
  let!(:inventory1) { create(:inventory, name: 'テスト商品A', price: 100, quantity: 10, status: 'active') }
  let!(:inventory2) { create(:inventory, name: 'テスト商品B', price: 200, quantity: 5, status: 'active') }
  let!(:inventory3) { create(:inventory, name: '別商品C', price: 150, quantity: 0, status: 'archived') }

  describe 'attributes' do
    it 'has basic search fields' do
      form.name = 'test'
      form.status = 'active'
      form.min_price = 100
      form.max_price = 200

      expect(form.name).to eq('test')
      expect(form.status).to eq('active')
      expect(form.min_price).to eq(100)
      expect(form.max_price).to eq(200)
    end

    it 'has date fields' do
      form.created_from = Date.current
      form.created_to = Date.current + 1.day

      expect(form.created_from).to eq(Date.current)
      expect(form.created_to).to eq(Date.current + 1.day)
    end

    it 'has batch fields' do
      form.lot_code = 'LOT001'
      form.expires_before = Date.current + 30.days

      expect(form.lot_code).to eq('LOT001')
      expect(form.expires_before).to eq(Date.current + 30.days)
    end

    it 'has default values' do
      expect(form.search_type).to eq('basic')
      expect(form.include_archived).to be_falsy
      expect(form.low_stock_threshold).to eq(10)
      expect(form.low_stock).to be_falsy
      expect(form.advanced_search).to be_falsy
    end
  end

  describe 'validations' do
    describe 'basic field validations' do
      it 'validates name length' do
        form.name = 'a' * 256
        expect(form).not_to be_valid
        expect(form.errors[:name]).to include(I18n.t('errors.messages.too_long', count: 255))
      end

      it 'validates price numericality' do
        form.min_price = -1
        expect(form).not_to be_valid
        expect(form.errors[:min_price]).to include(I18n.t('errors.messages.greater_than_or_equal_to', count: 0))
      end

      it 'validates quantity numericality' do
        form.min_quantity = -1
        expect(form).not_to be_valid
        expect(form.errors[:min_quantity]).to include(I18n.t('errors.messages.greater_than_or_equal_to', count: 0))
      end

      it 'validates search_type inclusion' do
        form.search_type = 'invalid'
        expect(form).not_to be_valid
        expect(form.errors[:search_type]).to include(I18n.t('errors.messages.inclusion'))
      end

      it 'validates stock_filter inclusion' do
        form.stock_filter = 'invalid'
        expect(form).not_to be_valid
        expect(form.errors[:stock_filter]).to include(I18n.t('errors.messages.inclusion'))
      end
    end

    describe 'range consistency validations' do
      it 'validates price range consistency' do
        form.min_price = 200
        form.max_price = 100
        expect(form).not_to be_valid
        expect(form.errors[:max_price]).to include(I18n.t('form_validation.price_range_error'))
      end

      it 'validates quantity range consistency' do
        form.min_quantity = 10
        form.max_quantity = 5
        expect(form).not_to be_valid
        expect(form.errors[:max_quantity]).to include(I18n.t('form_validation.quantity_range_error'))
      end

      it 'validates date range consistency' do
        form.created_from = Date.current + 1.day
        form.created_to = Date.current
        expect(form).not_to be_valid
        expect(form.errors[:created_to]).to include(I18n.t('form_validation.date_range_error'))
      end
    end
  end

  describe '#effective_name' do
    it 'returns name when present' do
      form.name = 'test name'
      form.q = 'test q'
      expect(form.effective_name).to eq('test name')
    end

    it 'returns q when name is blank' do
      form.name = ''
      form.q = 'test q'
      expect(form.effective_name).to eq('test q')
    end

    it 'returns nil when both are blank' do
      form.name = ''
      form.q = ''
      expect(form.effective_name).to be_nil
    end
  end

  describe '#has_search_conditions?' do
    it 'returns false when no conditions are set' do
      expect(form.has_search_conditions?).to be_falsy
    end

    it 'returns true when basic conditions are set' do
      form.name = 'test'
      expect(form.has_search_conditions?).to be_truthy
    end

    it 'returns true when status is set' do
      form.status = 'active'
      expect(form.has_search_conditions?).to be_truthy
    end

    it 'returns true when price range is set' do
      form.min_price = 100
      expect(form.has_search_conditions?).to be_truthy
    end

    it 'returns true when advanced conditions are set' do
      form.created_from = Date.current
      expect(form.has_search_conditions?).to be_truthy
    end

    it 'returns true when low_stock is true' do
      form.low_stock = true
      expect(form.has_search_conditions?).to be_truthy
    end
  end

  describe '#conditions_summary' do
    it 'returns すべて when no conditions' do
      expect(form.conditions_summary).to eq('すべて')
    end

    it 'includes name condition' do
      form.name = 'テスト'
      summary = form.conditions_summary
      expect(summary).to include('名前: テスト')
    end

    it 'includes status condition' do
      form.status = 'active'
      summary = form.conditions_summary
      expect(summary).to include('ステータス: active')
    end

    it 'includes price range condition' do
      form.min_price = 100
      form.max_price = 200
      summary = form.conditions_summary
      expect(summary).to include('価格: 100円〜200円')
    end

    it 'includes low stock condition' do
      form.low_stock = true
      summary = form.conditions_summary
      expect(summary).to include('在庫切れのみ')
    end

    it 'includes multiple conditions' do
      form.name = 'テスト'
      form.status = 'active'
      summary = form.conditions_summary
      expect(summary).to include('名前: テスト')
      expect(summary).to include('ステータス: active')
    end
  end

  describe '#search' do
    context 'with invalid form' do
      it 'returns empty scope' do
        form.min_price = 200
        form.max_price = 100  # Invalid range

        result = form.search
        expect(result).to eq(Inventory.none)
      end
    end

    context 'with basic search' do
      it 'searches by name' do
        form.name = 'テスト'
        form.search_type = 'basic'

        result = form.search
        expect(result).to include(inventory1, inventory2)
        expect(result).not_to include(inventory3)
      end

      it 'searches by status' do
        form.status = 'active'
        form.search_type = 'basic'

        result = form.search
        expect(result).to include(inventory1, inventory2)
        expect(result).not_to include(inventory3)
      end

      it 'searches by price range' do
        form.min_price = 150
        form.max_price = 250
        form.search_type = 'basic'
        form.include_archived = true  # archivedアイテム(inventory3)を含める

        result = form.search
        expect(result).to include(inventory2, inventory3)
        expect(result).not_to include(inventory1)
      end

      it 'searches by low stock' do
        form.low_stock = true
        form.search_type = 'basic'
        form.include_archived = true  # archivedアイテム(inventory3)を含める

        result = form.search
        expect(result).to include(inventory3)
        expect(result).not_to include(inventory1, inventory2)
      end

      it 'searches by stock filter out_of_stock' do
        form.stock_filter = 'out_of_stock'
        form.search_type = 'basic'
        form.include_archived = true  # archivedアイテム(inventory3)を含める

        result = form.search
        expect(result).to include(inventory3)
        expect(result).not_to include(inventory1, inventory2)
      end

      it 'searches by stock filter low_stock' do
        form.stock_filter = 'low_stock'
        form.low_stock_threshold = 7
        form.search_type = 'basic'

        result = form.search
        expect(result).to include(inventory2)  # quantity: 5
        expect(result).not_to include(inventory1, inventory3)  # quantity: 10, 0
      end

      it 'searches by stock filter in_stock' do
        form.stock_filter = 'in_stock'
        form.low_stock_threshold = 7
        form.search_type = 'basic'

        result = form.search
        expect(result).to include(inventory1)  # quantity: 10
        expect(result).not_to include(inventory2, inventory3)  # quantity: 5, 0
      end

      it 'combines multiple conditions with AND logic' do
        form.name = 'テスト'
        form.status = 'active'
        form.min_price = 150
        form.search_type = 'basic'

        result = form.search
        expect(result).to include(inventory2)
        expect(result).not_to include(inventory1, inventory3)
      end
    end

    context 'with auto-determined search type' do
      it 'uses basic search for simple conditions' do
        form.name = 'テスト'

        result = form.search
        expect(result).to include(inventory1, inventory2)
        expect(result).not_to include(inventory3)
      end

      it 'uses advanced search when complex conditions are present' do
        form.name = 'テスト'
        form.created_from = Date.current - 1.day

        # This should trigger advanced search due to date condition
        result = form.search
        expect(result).to include(inventory1, inventory2)
      end
    end
  end

  describe '#to_search_params' do
    it 'converts form attributes to search params hash' do
      form.name = 'テスト'
      form.status = 'active'
      form.min_price = 100
      form.low_stock = true

      params = form.to_search_params
      expect(params[:q]).to eq('テスト')
      expect(params[:status]).to eq('active')
      expect(params[:min_price]).to eq(100)
      expect(params[:low_stock]).to eq('true')
    end

    it 'excludes blank values' do
      form.name = 'テスト'
      form.status = ''
      form.min_price = nil

      params = form.to_search_params
      expect(params).to have_key(:q)
      expect(params).not_to have_key(:status)
      expect(params).not_to have_key(:min_price)
    end

    it 'includes pagination and sorting params' do
      form.page = 2
      form.per_page = 50
      form.sort_field = 'name'
      form.sort_direction = 'asc'

      params = form.to_search_params
      expect(params[:page]).to eq(2)
      expect(params[:per_page]).to eq(50)
      expect(params[:sort]).to eq('name')
      expect(params[:direction]).to eq('asc')
    end
  end

  describe '#complex_search_required?' do
    it 'returns false for basic conditions only' do
      form.name = 'テスト'
      form.status = 'active'

      expect(form.complex_search_required?).to be_falsy
    end

    it 'returns true for price range conditions' do
      form.min_price = 100
      expect(form.complex_search_required?).to be_truthy
    end

    it 'returns true for date conditions' do
      form.created_from = Date.current
      expect(form.complex_search_required?).to be_truthy
    end

    it 'returns true for batch conditions' do
      form.lot_code = 'LOT001'
      expect(form.complex_search_required?).to be_truthy
    end

    it 'returns true for advanced flags' do
      form.expiring_soon = true
      expect(form.complex_search_required?).to be_truthy
    end

    it 'returns true for stock filter' do
      form.stock_filter = 'low_stock'
      expect(form.complex_search_required?).to be_truthy
    end
  end

  describe 'display helper methods' do
    describe '#price_range_display' do
      it 'displays min and max price' do
        form.min_price = 100
        form.max_price = 200
        expect(form.price_range_display).to eq('100円〜200円')
      end

      it 'displays min price only' do
        form.min_price = 100
        expect(form.price_range_display).to eq('100円以上')
      end

      it 'displays max price only' do
        form.max_price = 200
        expect(form.price_range_display).to eq('200円以下')
      end
    end

    describe '#quantity_range_display' do
      it 'displays quantity range' do
        form.min_quantity = 10
        form.max_quantity = 100
        expect(form.quantity_range_display).to eq('10〜100')
      end
    end

    describe '#stock_filter_display' do
      it 'displays stock filter with threshold' do
        form.stock_filter = 'low_stock'
        form.low_stock_threshold = 5
        expect(form.stock_filter_display).to eq('在庫少 (5以下)')
      end

      it 'displays out of stock' do
        form.stock_filter = 'out_of_stock'
        expect(form.stock_filter_display).to eq('在庫切れ')
      end

      it 'displays in stock with threshold' do
        form.stock_filter = 'in_stock'
        form.low_stock_threshold = 10
        expect(form.stock_filter_display).to eq('在庫あり (10超)')
      end
    end
  end

  describe 'condition check helpers' do
    describe '#basic_conditions?' do
      it 'returns true when basic conditions are present' do
        form.name = 'test'
        expect(form.basic_conditions?).to be_truthy
      end

      it 'returns false when no basic conditions' do
        expect(form.basic_conditions?).to be_falsy
      end
    end

    describe '#advanced_conditions?' do
      it 'returns true when advanced conditions are present' do
        form.created_from = Date.current
        expect(form.advanced_conditions?).to be_truthy
      end

      it 'returns false when no advanced conditions' do
        expect(form.advanced_conditions?).to be_falsy
      end
    end

    describe '#custom_conditions?' do
      it 'returns true when custom conditions are present' do
        form.custom_conditions = [ {} ]
        expect(form.custom_conditions?).to be_truthy
      end

      it 'returns false when no custom conditions' do
        expect(form.custom_conditions?).to be_falsy
      end
    end
  end
end
