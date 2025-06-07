# frozen_string_literal: true

require 'rails_helper'

# テスト用の具象クラス
class TestSearchForm < BaseSearchForm
  def search
    'test search result'
  end
  
  def has_search_conditions?
    true
  end
  
  def conditions_summary
    'test conditions'
  end
end

RSpec.describe BaseSearchForm, type: :model do
  let(:form) { TestSearchForm.new }
  
  describe 'attributes' do
    it 'has page attribute with default value 1' do
      expect(form.page).to eq(1)
    end
    
    it 'has per_page attribute with default value 20' do
      expect(form.per_page).to eq(20)
    end
    
    it 'has sort_field attribute with default value updated_at' do
      expect(form.sort_field).to eq('updated_at')
    end
    
    it 'has sort_direction attribute with default value desc' do
      expect(form.sort_direction).to eq('desc')
    end
  end
  
  describe 'validations' do
    describe 'page' do
      it 'validates numericality greater than 0' do
        form.page = 0
        expect(form).not_to be_valid
        expect(form.errors[:page]).to include('must be greater than 0')
      end
      
      it 'accepts positive numbers' do
        form.page = 5
        expect(form).to be_valid
      end
    end
    
    describe 'per_page' do
      it 'validates inclusion in [10, 20, 50, 100]' do
        form.per_page = 15
        expect(form).not_to be_valid
        expect(form.errors[:per_page]).to include('is not included in the list')
      end
      
      it 'accepts valid values' do
        [10, 20, 50, 100].each do |value|
          form.per_page = value
          expect(form).to be_valid
        end
      end
    end
    
    describe 'sort_direction' do
      it 'validates inclusion in [asc, desc]' do
        form.sort_direction = 'invalid'
        expect(form).not_to be_valid
        expect(form.errors[:sort_direction]).to include('is not included in the list')
      end
      
      it 'accepts valid values' do
        %w[asc desc].each do |direction|
          form.sort_direction = direction
          expect(form).to be_valid
        end
      end
    end
  end
  
  describe '#cache_key' do
    it 'generates MD5 hash of serializable attributes' do
      form.page = 2
      form.per_page = 50
      
      expected_hash = Digest::MD5.hexdigest(form.serializable_hash.to_json)
      expect(form.cache_key).to eq(expected_hash)
    end
    
    it 'returns different keys for different attributes' do
      form1 = TestSearchForm.new(page: 1)
      form2 = TestSearchForm.new(page: 2)
      
      expect(form1.cache_key).not_to eq(form2.cache_key)
    end
  end
  
  describe '#to_params' do
    it 'returns attributes rejecting blank values' do
      form.page = 1
      form.per_page = nil
      form.sort_field = ''
      form.sort_direction = 'asc'
      
      result = form.to_params
      expect(result).to include('page' => 1, 'sort_direction' => 'asc')
      expect(result).not_to have_key('per_page')
      expect(result).not_to have_key('sort_field')
    end
  end
  
  describe '#to_query_params' do
    it 'returns URL query string from to_params' do
      form.page = 2
      form.sort_direction = 'asc'
      
      expected = form.to_params.to_query
      expect(form.to_query_params).to eq(expected)
    end
  end
  
  describe 'abstract methods' do
    let(:base_form) { BaseSearchForm.new }
    
    it 'raises NotImplementedError for search method' do
      expect { base_form.search }.to raise_error(NotImplementedError, /search must be implemented/)
    end
    
    it 'raises NotImplementedError for has_search_conditions? method' do
      expect { base_form.has_search_conditions? }.to raise_error(NotImplementedError, /has_search_conditions\? must be implemented/)
    end
    
    it 'raises NotImplementedError for conditions_summary method' do
      expect { base_form.conditions_summary }.to raise_error(NotImplementedError, /conditions_summary must be implemented/)
    end
  end
end