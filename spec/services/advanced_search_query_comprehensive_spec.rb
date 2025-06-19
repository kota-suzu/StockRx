# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdvancedSearchQuery do
  # CLAUDE.md準拠: 高度検索クエリサービスの包括的テスト
  # メタ認知: 5つのビルダークラスと複雑なOR/AND条件構築の品質保証
  # 横展開: 他の検索サービスでも同様のテストパターン適用

  # テストデータの準備
  let(:test_prefix) { "ASQ_#{SecureRandom.hex(4)}" }
  
  let!(:inventory1) { create(:inventory, name: "#{test_prefix}_Medicine A", quantity: 100, price: 500, status: 'active') }
  let!(:inventory2) { create(:inventory, name: "#{test_prefix}_Equipment B", quantity: 5, price: 10000, status: 'active') }
  let!(:inventory3) { create(:inventory, name: "#{test_prefix}_Supply C", quantity: 0, price: 100, status: 'discontinued') }
  
  let!(:batch1) { create(:batch, inventory: inventory1, lot_code: 'LOT001', expiration_date: 30.days.from_now) }
  let!(:batch2) { create(:batch, inventory: inventory1, lot_code: 'LOT002', expiration_date: 5.days.from_now) }
  let!(:batch3) { create(:batch, inventory: inventory2, lot_code: 'LOT003', expiration_date: 1.year.from_now) }

  describe '.build' do
    it 'creates new instance with default scope' do
      query = described_class.build
      expect(query).to be_a(described_class)
      expect(query.scope).to eq(Inventory.all)
    end

    it 'creates instance with custom scope' do
      custom_scope = Inventory.where("name LIKE ?", "#{test_prefix}%")
      query = described_class.build(custom_scope)
      expect(query.scope).to eq(custom_scope)
    end
  end

  describe '#filter' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    context 'simple filters' do
      it 'filters by name' do
        result = query.filter(name: 'Medicine').execute
        expect(result).to include(inventory1)
        expect(result).not_to include(inventory2, inventory3)
      end

      it 'filters by quantity range' do
        result = query.filter(min_quantity: 10, max_quantity: 200).execute
        expect(result).to include(inventory1)
        expect(result).not_to include(inventory2, inventory3)
      end

      it 'filters by price range' do
        result = query.filter(min_price: 1000, max_price: 20000).execute
        expect(result).to include(inventory2)
        expect(result).not_to include(inventory1, inventory3)
      end

      it 'filters by status' do
        result = query.filter(status: 'active').execute
        expect(result).to include(inventory1, inventory2)
        expect(result).not_to include(inventory3)
      end

      it 'filters by multiple statuses' do
        result = query.filter(status: ['active', 'discontinued']).execute
        expect(result).to include(inventory1, inventory2, inventory3)
      end
    end

    context 'association filters' do
      it 'filters by batch existence' do
        no_batch_inventory = create(:inventory, name: "#{test_prefix}_No Batch")
        
        result = query.filter(has_batches: true).execute
        expect(result).to include(inventory1, inventory2)
        expect(result).not_to include(inventory3, no_batch_inventory)
      end

      it 'filters by expiry status' do
        result = query.filter(expiring_soon: true).execute
        expect(result).to include(inventory1) # has batch expiring in 5 days
        expect(result).not_to include(inventory2, inventory3)
      end

      it 'filters by specific batch lot code' do
        result = query.filter(lot_code: 'LOT001').execute
        expect(result).to include(inventory1)
        expect(result).not_to include(inventory2, inventory3)
      end
    end

    context 'complex filters' do
      it 'combines multiple filters with AND logic' do
        result = query.filter(
          status: 'active',
          min_quantity: 50,
          max_price: 1000
        ).execute
        
        expect(result).to include(inventory1)
        expect(result).not_to include(inventory2, inventory3)
      end

      it 'filters by stock level categories' do
        result = query.filter(stock_level: 'out_of_stock').execute
        expect(result).to include(inventory3)
        expect(result).not_to include(inventory1, inventory2)
      end
    end
  end

  describe '#or' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'creates OR condition between filters' do
      result = query
        .filter(name: 'Medicine')
        .or
        .filter(quantity: 0)
        .execute
      
      expect(result).to include(inventory1, inventory3)
      expect(result).not_to include(inventory2)
    end

    it 'chains multiple OR conditions' do
      result = query
        .filter(name: 'Medicine')
        .or
        .filter(price: 10000)
        .or
        .filter(status: 'discontinued')
        .execute
      
      expect(result).to include(inventory1, inventory2, inventory3)
    end

    it 'combines OR groups with AND' do
      # (name LIKE 'Medicine' OR quantity = 0) AND status = 'active'
      result = query
        .filter(status: 'active')
        .and_group do |g|
          g.filter(name: 'Medicine').or.filter(quantity: 0)
        end
        .execute
      
      expect(result).to include(inventory1)
      expect(result).not_to include(inventory2, inventory3)
    end
  end

  describe 'condition builders' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    describe 'BasicConditionBuilder' do
      it 'handles equals conditions' do
        builder = AdvancedSearchQuery::BasicConditionBuilder.new(query.scope)
        result = builder.add_condition(:status, 'active').build
        
        expect(result.to_sql).to include("status = 'active'")
      end

      it 'handles IN conditions for arrays' do
        builder = AdvancedSearchQuery::BasicConditionBuilder.new(query.scope)
        result = builder.add_condition(:status, ['active', 'pending']).build
        
        expect(result.to_sql).to include("status IN")
      end

      it 'handles nil values' do
        builder = AdvancedSearchQuery::BasicConditionBuilder.new(query.scope)
        result = builder.add_condition(:deleted_at, nil).build
        
        expect(result.to_sql).to include("deleted_at IS NULL")
      end
    end

    describe 'RangeConditionBuilder' do
      it 'handles minimum value' do
        builder = AdvancedSearchQuery::RangeConditionBuilder.new(query.scope)
        result = builder.add_range(:quantity, min: 10).build
        
        expect(result.to_sql).to include("quantity >= 10")
      end

      it 'handles maximum value' do
        builder = AdvancedSearchQuery::RangeConditionBuilder.new(query.scope)
        result = builder.add_range(:price, max: 1000).build
        
        expect(result.to_sql).to include("price <= 1000")
      end

      it 'handles both min and max' do
        builder = AdvancedSearchQuery::RangeConditionBuilder.new(query.scope)
        result = builder.add_range(:quantity, min: 10, max: 100).build
        
        sql = result.to_sql
        expect(sql).to include("quantity >= 10")
        expect(sql).to include("quantity <= 100")
      end
    end

    describe 'TextSearchBuilder' do
      it 'performs case-insensitive search' do
        builder = AdvancedSearchQuery::TextSearchBuilder.new(query.scope)
        result = builder.search(:name, 'medicine').build
        
        expect(result.to_sql).to include("LOWER(inventories.name) LIKE")
      end

      it 'handles multiple search terms' do
        builder = AdvancedSearchQuery::TextSearchBuilder.new(query.scope)
        result = builder
          .search(:name, 'medicine')
          .search(:description, 'emergency')
          .build
        
        sql = result.to_sql
        expect(sql).to include("LOWER(inventories.name)")
        expect(sql).to include("LOWER(inventories.description)")
      end

      it 'escapes special characters' do
        builder = AdvancedSearchQuery::TextSearchBuilder.new(query.scope)
        result = builder.search(:name, 'test%_').build
        
        expect(result.to_sql).to include("\\%")
        expect(result.to_sql).to include("\\_")
      end
    end

    describe 'DateRangeBuilder' do
      it 'handles date range with start date' do
        builder = AdvancedSearchQuery::DateRangeBuilder.new(query.scope)
        result = builder.add_date_range(:created_at, from: 1.week.ago).build
        
        expect(result.to_sql).to include("created_at >=")
      end

      it 'handles date range with end date' do
        builder = AdvancedSearchQuery::DateRangeBuilder.new(query.scope)
        result = builder.add_date_range(:updated_at, to: Date.today).build
        
        expect(result.to_sql).to include("updated_at <=")
      end

      it 'converts strings to dates' do
        builder = AdvancedSearchQuery::DateRangeBuilder.new(query.scope)
        result = builder.add_date_range(:created_at, 
          from: '2024-01-01',
          to: '2024-12-31'
        ).build
        
        sql = result.to_sql
        expect(sql).to include("created_at >= '2024-01-01")
        expect(sql).to include("created_at <= '2024-12-31")
      end
    end

    describe 'AssociationBuilder' do
      it 'joins associated tables' do
        builder = AdvancedSearchQuery::AssociationBuilder.new(query.scope)
        result = builder.join(:batches).build
        
        expect(result.joins_values).to include(:batches)
      end

      it 'filters through associations' do
        builder = AdvancedSearchQuery::AssociationBuilder.new(query.scope)
        result = builder
          .join(:batches)
          .where_assoc(:batches, lot_code: 'LOT001')
          .build
        
        expect(result.to_sql).to include("batches")
        expect(result.to_sql).to include("lot_code")
      end

      it 'handles nested associations' do
        builder = AdvancedSearchQuery::AssociationBuilder.new(query.scope)
        result = builder
          .join(inventory_logs: :user)
          .where_assoc(:inventory_logs, operation_type: 'receive')
          .build
        
        expect(result.joins_values.first).to eq(inventory_logs: :user)
      end
    end
  end

  describe '#apply_sorting' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'sorts by single column' do
      result = query.apply_sorting(sort_by: 'name', direction: 'asc').execute
      names = result.pluck(:name)
      expect(names).to eq(names.sort)
    end

    it 'sorts by multiple columns' do
      result = query.apply_sorting(
        sort_by: ['status', 'name'],
        direction: ['desc', 'asc']
      ).execute
      
      expect(result.first.status).not_to be_nil
    end

    it 'handles association sorting' do
      result = query.apply_sorting(
        sort_by: 'batches.expiration_date',
        direction: 'asc'
      ).execute
      
      expect(result.to_sql).to include('batches')
    end

    it 'defaults to descending order' do
      result = query.apply_sorting(sort_by: 'created_at').execute
      dates = result.pluck(:created_at)
      expect(dates).to eq(dates.sort.reverse)
    end
  end

  describe '#paginate' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    before do
      # ページネーションテスト用の追加データ
      10.times do |i|
        create(:inventory, name: "#{test_prefix}_Item #{i}")
      end
    end

    it 'limits results per page' do
      result = query.paginate(page: 1, per_page: 5).execute
      expect(result.count).to eq(5)
    end

    it 'offsets for different pages' do
      page1 = query.paginate(page: 1, per_page: 5).execute
      page2 = query.paginate(page: 2, per_page: 5).execute
      
      expect(page1.pluck(:id) & page2.pluck(:id)).to be_empty
    end

    it 'handles last page correctly' do
      total_count = Inventory.where("name LIKE ?", "#{test_prefix}%").count
      last_page = (total_count / 5.0).ceil
      
      result = query.paginate(page: last_page, per_page: 5).execute
      expect(result.count).to be <= 5
    end
  end

  describe '#select_fields' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'selects specific fields' do
      result = query.select_fields([:id, :name, :quantity]).execute
      
      first_item = result.first
      expect(first_item.attributes.keys).to include('id', 'name', 'quantity')
      expect { first_item.price }.to raise_error(ActiveModel::MissingAttributeError)
    end

    it 'includes calculated fields' do
      result = query.select_fields([
        :id,
        :name,
        'quantity * price AS total_value'
      ]).execute
      
      first_item = result.first
      expect(first_item.attributes).to have_key('total_value')
    end
  end

  describe '#include_associations' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'eager loads associations' do
      result = query.include_associations([:batches]).execute
      
      # N+1クエリを避けるためのeager loading確認
      expect(result.first.association(:batches).loaded?).to be true
    end

    it 'includes nested associations' do
      result = query.include_associations([
        :batches,
        { inventory_logs: :user }
      ]).execute
      
      expect(result.includes_values).to include(:batches)
      expect(result.includes_values).to include(inventory_logs: :user)
    end
  end

  describe 'complex queries' do
    it 'builds complex query with multiple conditions' do
      result = described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%"))
        .filter(status: 'active')
        .filter(min_quantity: 1)
        .or
        .filter(expiring_soon: true)
        .apply_sorting(sort_by: 'quantity', direction: 'desc')
        .paginate(page: 1, per_page: 10)
        .include_associations([:batches])
        .execute
      
      expect(result).to be_present
      expect(result).to be_a(ActiveRecord::Relation)
    end

    it 'handles search conditions with custom operators' do
      conditions = [
        { field: 'name', operator: 'contains', value: 'Medicine' },
        { field: 'quantity', operator: 'greater_than', value: 50 },
        { field: 'status', operator: 'in', value: ['active', 'pending'] }
      ]
      
      result = described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%"))
        .apply_search_conditions(conditions)
        .execute
      
      expect(result).to include(inventory1)
      expect(result).not_to include(inventory2, inventory3)
    end
  end

  describe 'performance optimization' do
    it 'uses distinct when necessary' do
      query = described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%"))
        .filter(has_batches: true)
        .distinct
      
      expect(query.scope.distinct_value).to be true
    end

    it 'optimizes joins to avoid duplicates' do
      result = described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%"))
        .filter(lot_code: 'LOT001')
        .execute
      
      # 重複なしで結果が返される
      expect(result.count).to eq(result.distinct.count)
    end
  end

  describe 'error handling' do
    let(:query) { described_class.build }

    it 'handles invalid column names gracefully' do
      expect {
        query.filter(invalid_column: 'value').execute
      }.not_to raise_error
    end

    it 'validates sort columns' do
      result = query.apply_sorting(sort_by: 'invalid_column').execute
      expect(result).to be_a(ActiveRecord::Relation)
    end

    it 'handles nil parameters' do
      result = query.filter(nil).execute
      expect(result).to be_a(ActiveRecord::Relation)
    end
  end

  describe '#to_sql' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'returns SQL string' do
      sql = query
        .filter(status: 'active')
        .filter(min_quantity: 10)
        .to_sql
      
      expect(sql).to be_a(String)
      expect(sql).to include('WHERE')
      expect(sql).to include('status')
      expect(sql).to include('quantity')
    end
  end

  describe '#count' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'returns total count without pagination' do
      paginated_query = query.paginate(page: 1, per_page: 1)
      
      expect(paginated_query.count).to be > 1
      expect(paginated_query.execute.count).to eq(1)
    end
  end

  describe '#pluck' do
    let(:query) { described_class.build(Inventory.where("name LIKE ?", "#{test_prefix}%")) }

    it 'plucks single column' do
      names = query.pluck(:name)
      expect(names).to include(inventory1.name, inventory2.name, inventory3.name)
    end

    it 'plucks multiple columns' do
      data = query.pluck(:id, :name, :quantity)
      expect(data.first).to be_an(Array)
      expect(data.first.length).to eq(3)
    end
  end
end