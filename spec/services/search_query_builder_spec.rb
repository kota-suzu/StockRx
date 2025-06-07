# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SearchQueryBuilder, type: :service do
  let(:builder) { described_class.new }

  # テスト用のInventoryデータを作成
  let!(:inventory1) { create(:inventory, name: 'テスト商品A', price: 100, quantity: 10, status: 'active') }
  let!(:inventory2) { create(:inventory, name: 'テスト商品B', price: 200, quantity: 5, status: 'active') }
  let!(:inventory3) { create(:inventory, name: '別商品C', price: 150, quantity: 0, status: 'archived') }

  describe '#initialize' do
    it 'initializes with default Inventory scope' do
      expect(builder.scope).to eq(Inventory.all)
    end

    it 'initializes with custom scope' do
      custom_scope = Inventory.where(status: 'active')
      custom_builder = described_class.new(custom_scope)
      expect(custom_builder.scope).to eq(custom_scope)
    end

    it 'initializes empty joins and conditions' do
      expect(builder.joins_applied).to be_empty
      expect(builder.conditions).to be_empty
      expect(builder.distinct_applied).to be_falsy
    end
  end

  describe '.build' do
    it 'creates new instance with factory method' do
      result = described_class.build
      expect(result).to be_a(described_class)
    end
  end

  describe '#filter_by_name' do
    it 'filters by name with LIKE query' do
      result = builder.filter_by_name('テスト').results
      expect(result).to include(inventory1, inventory2)
      expect(result).not_to include(inventory3)
    end

    it 'returns self for method chaining' do
      result = builder.filter_by_name('テスト')
      expect(result).to eq(builder)
    end

    it 'ignores blank names' do
      result = builder.filter_by_name('').results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'adds condition to summary' do
      builder.filter_by_name('テスト')
      expect(builder.conditions).to include('名前: テスト')
    end

    it 'handles SQL injection safely' do
      # SQLインジェクション攻撃のテスト
      malicious_input = "'; DROP TABLE inventories; --"
      expect { builder.filter_by_name(malicious_input).results.to_a }.not_to raise_error
    end
  end

  describe '#filter_by_status' do
    it 'filters by valid status' do
      result = builder.filter_by_status('active').results
      expect(result).to include(inventory1, inventory2)
      expect(result).not_to include(inventory3)
    end

    it 'ignores invalid status' do
      result = builder.filter_by_status('invalid_status').results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'ignores blank status' do
      result = builder.filter_by_status('').results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'adds condition to summary' do
      builder.filter_by_status('active')
      expect(builder.conditions).to include('ステータス: active')
    end
  end

  describe '#filter_by_price_range' do
    it 'filters by min and max price' do
      result = builder.filter_by_price_range(120, 180).results
      expect(result).to include(inventory3)
      expect(result).not_to include(inventory1, inventory2)
    end

    it 'filters by min price only' do
      result = builder.filter_by_price_range(150, nil).results
      expect(result).to include(inventory2, inventory3)
      expect(result).not_to include(inventory1)
    end

    it 'filters by max price only' do
      result = builder.filter_by_price_range(nil, 150).results
      expect(result).to include(inventory1, inventory3)
      expect(result).not_to include(inventory2)
    end

    it 'ignores when both prices are blank' do
      result = builder.filter_by_price_range(nil, nil).results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'adds appropriate condition to summary' do
      builder.filter_by_price_range(100, 200)
      expect(builder.conditions).to include('価格: 100円〜200円')

      builder.conditions.clear
      builder.filter_by_price_range(100, nil)
      expect(builder.conditions).to include('価格: 100円以上')

      builder.conditions.clear
      builder.filter_by_price_range(nil, 200)
      expect(builder.conditions).to include('価格: 200円以下')
    end
  end

  describe '#filter_by_quantity_range' do
    it 'filters by quantity range' do
      result = builder.filter_by_quantity_range(5, 10).results
      expect(result).to include(inventory1, inventory2)
      expect(result).not_to include(inventory3)
    end

    it 'filters by min quantity only' do
      result = builder.filter_by_quantity_range(6, nil).results
      expect(result).to include(inventory1)
      expect(result).not_to include(inventory2, inventory3)
    end

    it 'adds condition to summary' do
      builder.filter_by_quantity_range(5, 10)
      expect(builder.conditions).to include('数量: 5〜10')
    end
  end

  describe '#filter_by_stock_status' do
    it 'filters out of stock items' do
      result = builder.filter_by_stock_status('out_of_stock').results
      expect(result).to include(inventory3)
      expect(result).not_to include(inventory1, inventory2)
    end

    it 'filters low stock items' do
      result = builder.filter_by_stock_status('low_stock', 7).results
      expect(result).to include(inventory2)  # quantity: 5
      expect(result).not_to include(inventory1, inventory3)
    end

    it 'filters in stock items' do
      result = builder.filter_by_stock_status('in_stock', 7).results
      expect(result).to include(inventory1)  # quantity: 10
      expect(result).not_to include(inventory2, inventory3)
    end

    it 'ignores invalid stock filter' do
      result = builder.filter_by_stock_status('invalid').results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'adds condition to summary' do
      builder.filter_by_stock_status('out_of_stock')
      expect(builder.conditions).to include('在庫切れ')

      builder.conditions.clear
      builder.filter_by_stock_status('low_stock', 5)
      expect(builder.conditions).to include('在庫少 (5以下)')
    end
  end

  describe '#filter_by_date_range' do
    let(:yesterday) { Date.current - 1.day }
    let(:tomorrow) { Date.current + 1.day }

    it 'filters by date range' do
      result = builder.filter_by_date_range('created_at', yesterday, tomorrow).results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'filters by from date only' do
      result = builder.filter_by_date_range('created_at', yesterday, nil).results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'filters by to date only' do
      result = builder.filter_by_date_range('created_at', nil, tomorrow).results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'ignores when both dates are blank' do
      result = builder.filter_by_date_range('created_at', nil, nil).results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'adds condition to summary' do
      builder.filter_by_date_range('created_at', yesterday, tomorrow)
      expect(builder.conditions).to include('Created at')
    end
  end

  describe '#apply_search_condition' do
    let(:condition) do
      SearchCondition.new(
        field: 'name',
        operator: 'contains',
        value: 'テスト',
        data_type: 'string'
      )
    end

    it 'applies valid search condition' do
      result = builder.apply_search_condition(condition).results
      expect(result).to include(inventory1, inventory2)
      expect(result).not_to include(inventory3)
    end

    it 'ignores invalid search condition' do
      invalid_condition = SearchCondition.new(field: 'invalid_field')
      result = builder.apply_search_condition(invalid_condition).results
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'adds condition description to summary' do
      builder.apply_search_condition(condition)
      expect(builder.conditions).not_to be_empty
    end
  end

  describe '#order_by' do
    it 'orders by field and direction' do
      result = builder.order_by('name', :asc).results
      expect(result.first).to eq(inventory3)  # '別商品C'
    end

    it 'defaults to desc direction' do
      result = builder.order_by('price').results
      expect(result.first).to eq(inventory2)  # price: 200
    end

    it 'ignores blank field' do
      expect { builder.order_by('').results }.not_to raise_error
    end

    it 'sanitizes field name' do
      # SQLインジェクション攻撃のテスト
      malicious_field = "name; DROP TABLE inventories; --"
      expect { builder.order_by(malicious_field).results.to_a }.not_to raise_error
    end
  end

  describe '#conditions_summary' do
    it 'returns すべて when no conditions' do
      expect(builder.conditions_summary).to eq('すべて')
    end

    it 'joins multiple conditions' do
      builder.filter_by_name('テスト')
      builder.filter_by_status('active')

      summary = builder.conditions_summary
      expect(summary).to include('名前: テスト')
      expect(summary).to include('ステータス: active')
    end
  end

  describe '#count' do
    it 'returns count of matching records' do
      count = builder.filter_by_name('テスト').count
      expect(count).to eq(2)
    end
  end

  describe '#to_sql' do
    it 'returns SQL string' do
      sql = builder.filter_by_name('テスト').to_sql
      expect(sql).to be_a(String)
      expect(sql).to include('SELECT')
      expect(sql).to include('inventories')
    end
  end

  describe 'method chaining' do
    it 'allows chaining multiple filters' do
      result = builder
        .filter_by_name('テスト')
        .filter_by_status('active')
        .filter_by_price_range(150, 250)
        .order_by('price', :asc)
        .results

      expect(result).to include(inventory2)
      expect(result).not_to include(inventory1, inventory3)
    end

    it 'maintains builder state through chaining' do
      builder
        .filter_by_name('テスト')
        .filter_by_status('active')

      expect(builder.conditions).to include('名前: テスト')
      expect(builder.conditions).to include('ステータス: active')
    end
  end

  describe 'security' do
    it 'sanitizes LIKE parameters' do
      # SQLインジェクション攻撃のテスト
      malicious_input = "%'; DROP TABLE inventories; --"
      expect { builder.filter_by_name(malicious_input).results.to_a }.not_to raise_error
    end

    it 'validates field names against whitelist' do
      # 許可されていないフィールド名でのテスト
      builder.send(:sanitize_field_name, 'malicious_field')
      # エラーなく処理されることを確認
    end
  end
end
