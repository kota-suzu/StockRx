# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchCondition, type: :model do
  let(:condition) { described_class.new }
  
  describe 'attributes' do
    it 'has field attribute' do
      condition.field = 'name'
      expect(condition.field).to eq('name')
    end
    
    it 'has operator attribute' do
      condition.operator = 'equals'
      expect(condition.operator).to eq('equals')
    end
    
    it 'has value attribute' do
      condition.value = 'test'
      expect(condition.value).to eq('test')
    end
    
    it 'has logic_type attribute with default AND' do
      expect(condition.logic_type).to eq('AND')
    end
    
    it 'has data_type attribute with default string' do
      expect(condition.data_type).to eq('string')
    end
  end
  
  describe 'validations' do
    describe 'field' do
      it 'validates presence' do
        condition.field = nil
        expect(condition).not_to be_valid
        expect(condition.errors[:field]).to include('を入力してください')
      end
      
      it 'validates inclusion in ALLOWED_SEARCH_FIELDS' do
        condition.field = 'invalid_field'
        expect(condition).not_to be_valid
        expect(condition.errors[:field]).to include('は一覧にありません')
      end
      
      it 'accepts valid fields' do
        condition.field = 'name'
        condition.operator = 'equals'
        condition.value = 'test'
        expect(condition).to be_valid
      end
    end
    
    describe 'operator' do
      it 'validates inclusion in OPERATORS keys' do
        condition.field = 'name'
        condition.operator = 'invalid_operator'
        expect(condition).not_to be_valid
        expect(condition.errors[:operator]).to include('は一覧にありません')
      end
      
      it 'accepts valid operators' do
        condition.field = 'name'
        condition.operator = 'contains'
        condition.value = 'test'
        expect(condition).to be_valid
      end
    end
    
    describe 'logic_type' do
      it 'validates inclusion in LOGIC_TYPES' do
        condition.logic_type = 'INVALID'
        expect(condition).not_to be_valid
        expect(condition.errors[:logic_type]).to include('は一覧にありません')
      end
      
      it 'accepts AND and OR' do
        %w[AND OR].each do |logic_type|
          condition.logic_type = logic_type
          condition.field = 'name'
          condition.operator = 'equals'
          condition.value = 'test'
          expect(condition).to be_valid
        end
      end
    end
    
    describe 'data_type' do
      it 'validates inclusion in DATA_TYPES' do
        condition.data_type = 'invalid'
        expect(condition).not_to be_valid
        expect(condition.errors[:data_type]).to include('は一覧にありません')
      end
      
      it 'accepts valid data types' do
        %w[string integer decimal date boolean].each do |data_type|
          condition.data_type = data_type
          condition.field = 'name'
          condition.operator = 'equals'
          condition.value = 'test'
          expect(condition).to be_valid
        end
      end
    end
    
    describe 'value presence for operator' do
      it 'requires value for most operators' do
        condition.field = 'name'
        condition.operator = 'equals'
        condition.value = ''
        expect(condition).not_to be_valid
        expect(condition.errors[:value]).to include('を入力してください')
      end
      
      it 'does not require value for null operators' do
        condition.field = 'name'
        condition.operator = 'is_null'
        condition.value = ''
        expect(condition).to be_valid
      end
    end
    
    describe 'value type consistency' do
      context 'with integer data type' do
        before do
          condition.field = 'quantity'
          condition.operator = 'equals'
          condition.data_type = 'integer'
        end
        
        it 'accepts valid integer values' do
          condition.value = '123'
          expect(condition).to be_valid
        end
        
        it 'rejects non-integer values' do
          condition.value = 'abc'
          expect(condition).not_to be_valid
          expect(condition.errors[:value]).to include('数値を入力してください')
        end
      end
      
      context 'with decimal data type' do
        before do
          condition.field = 'price'
          condition.operator = 'equals'
          condition.data_type = 'decimal'
        end
        
        it 'accepts valid decimal values' do
          condition.value = '123.45'
          expect(condition).to be_valid
        end
        
        it 'accepts integer values' do
          condition.value = '123'
          expect(condition).to be_valid
        end
        
        it 'rejects non-numeric values' do
          condition.value = 'abc'
          expect(condition).not_to be_valid
          expect(condition.errors[:value]).to include('数値を入力してください')
        end
      end
      
      context 'with date data type' do
        before do
          condition.field = 'created_at'
          condition.operator = 'equals'
          condition.data_type = 'date'
        end
        
        it 'accepts valid date values' do
          condition.value = '2023-12-31'
          expect(condition).to be_valid
        end
        
        it 'rejects invalid date values' do
          condition.value = 'invalid-date'
          expect(condition).not_to be_valid
          expect(condition.errors[:value]).to include('有効な日付を入力してください')
        end
      end
      
      context 'with boolean data type' do
        before do
          condition.field = 'status'
          condition.operator = 'equals'
          condition.data_type = 'boolean'
        end
        
        it 'accepts valid boolean values' do
          %w[true false].each do |value|
            condition.value = value
            expect(condition).to be_valid
          end
        end
        
        it 'rejects invalid boolean values' do
          condition.value = 'maybe'
          expect(condition).not_to be_valid
          expect(condition.errors[:value]).to include('true/falseを入力してください')
        end
      end
    end
  end
  
  describe '#to_sql_condition' do
    before do
      condition.field = 'name'
      condition.data_type = 'string'
    end
    
    context 'with contains operator' do
      it 'generates LIKE condition' do
        condition.operator = 'contains'
        condition.value = 'test'
        
        result = condition.to_sql_condition
        expect(result).to eq(['inventories.name LIKE ?', '%test%'])
      end
    end
    
    context 'with equals operator' do
      it 'generates equals condition' do
        condition.operator = 'equals'
        condition.value = 'test'
        
        result = condition.to_sql_condition
        expect(result).to eq(['inventories.name = ?', 'test'])
      end
    end
    
    context 'with between operator' do
      it 'generates BETWEEN condition' do
        condition.operator = 'between'
        condition.value = '100, 200'
        condition.field = 'price'
        condition.data_type = 'decimal'
        
        result = condition.to_sql_condition
        expect(result).to eq(['inventories.price BETWEEN ? AND ?', 100.0, 200.0])
      end
    end
    
    context 'with in operator' do
      it 'generates IN condition' do
        condition.operator = 'in'
        condition.value = 'a, b, c'
        
        result = condition.to_sql_condition
        expect(result).to eq(['inventories.name IN (?,?,?)', 'a', 'b', 'c'])
      end
    end
    
    context 'with is_null operator' do
      it 'generates IS NULL condition' do
        condition.operator = 'is_null'
        condition.value = ''
        
        result = condition.to_sql_condition
        expect(result).to eq('inventories.name IS NULL')
      end
    end
    
    context 'with invalid condition' do
      it 'returns nil' do
        condition.field = 'invalid_field'
        
        result = condition.to_sql_condition
        expect(result).to be_nil
      end
    end
    
    context 'with related table fields' do
      it 'handles batches fields correctly' do
        condition.field = 'batches.lot_code'
        condition.operator = 'contains'
        condition.value = 'LOT'
        
        result = condition.to_sql_condition
        expect(result).to eq(['batches.lot_code LIKE ?', '%LOT%'])
      end
    end
  end
  
  describe '#description' do
    before do
      condition.field = 'name'
      condition.operator = 'contains'
      condition.value = 'test'
    end
    
    it 'generates human readable description' do
      result = condition.description
      expect(result).to include('name')
      expect(result).to include('test')
    end
    
    context 'with invalid condition' do
      it 'returns error message' do
        condition.field = 'invalid_field'
        
        result = condition.description
        expect(result).to eq('無効な条件')
      end
    end
  end
  
  describe '#field_display_name' do
    it 'returns localized field name' do
      condition.field = 'name'
      
      # I18n.t のスタブ化またはデフォルト値のテスト
      result = condition.field_display_name
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end
  
  describe '#operator_display_name' do
    it 'returns localized operator name' do
      condition.operator = 'contains'
      
      result = condition.operator_display_name
      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end
  end
  
  describe '#value_display_text' do
    context 'with null operators' do
      it 'returns empty string' do
        condition.operator = 'is_null'
        result = condition.value_display_text
        expect(result).to eq('')
      end
    end
    
    context 'with between operator' do
      it 'formats range display' do
        condition.operator = 'between'
        condition.value = '100, 200'
        
        result = condition.value_display_text
        expect(result).to eq('100 〜 200')
      end
    end
    
    context 'with in operator' do
      it 'formats list display' do
        condition.operator = 'in'
        condition.value = 'a, b, c'
        
        result = condition.value_display_text
        expect(result).to eq('a, b, c')
      end
    end
    
    context 'with regular value' do
      it 'returns the value as is' do
        condition.operator = 'equals'
        condition.value = 'test'
        
        result = condition.value_display_text
        expect(result).to eq('test')
      end
    end
  end
end