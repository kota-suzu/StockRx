# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationRecord, type: :model do
  describe 'inheritance' do
    it 'is an abstract class' do
      expect(described_class.abstract_class?).to be true
    end

    it 'inherits from ActiveRecord::Base' do
      expect(described_class.superclass).to eq(ActiveRecord::Base)
    end
  end

  describe 'included modules' do
    it 'includes DataPortable module' do
      expect(described_class.included_modules).to include(DataPortable)
    end
  end

  describe 'primary_abstract_class' do
    it 'is defined as primary abstract class' do
      expect(described_class.abstract_class?).to be true
    end

    it 'prevents direct instantiation' do
      expect { described_class.new }.to raise_error(NotImplementedError)
    end
  end

  describe 'DataPortable integration' do
    # Test a concrete model that inherits from ApplicationRecord
    let(:test_model_class) do
      Class.new(ApplicationRecord) do
        self.table_name = 'inventories'
      end
    end

    it 'provides DataPortable methods to inheriting models' do
      # DataPortableモジュールの主要メソッドをテスト
      expect(test_model_class).to respond_to(:export_to_csv)
      expect(test_model_class).to respond_to(:export_system_data)
      expect(test_model_class).to respond_to(:import_system_data)
    end

    it 'allows models to access DataPortable class methods' do
      expect(test_model_class.included_modules).to include(DataPortable)
    end
  end

  describe 'ActiveRecord functionality' do
    # テスト用の具象モデル
    let(:concrete_model) do
      Class.new(ApplicationRecord) do
        self.table_name = 'inventories'

        def self.name
          'TestModel'
        end
      end
    end

    it 'provides ActiveRecord query methods' do
      expect(concrete_model).to respond_to(:all)
      expect(concrete_model).to respond_to(:where)
      expect(concrete_model).to respond_to(:find_by)
    end

    it 'provides ActiveRecord connection' do
      expect(concrete_model.connection).to eq(ActiveRecord::Base.connection)
    end
  end

  describe 'Rails configuration' do
    it 'uses the application timezone' do
      # ActiveRecordの設定を確認
      expect(ActiveRecord.default_timezone).to eq(:utc)
    end
  end

  describe 'subclass behavior' do
    # 実際のモデルクラスでの動作確認
    it 'allows all application models to inherit common behavior' do
      # すべてのモデルがApplicationRecordを継承していることを確認
      expect(Admin.superclass).to eq(ApplicationRecord)
      expect(Inventory.superclass).to eq(ApplicationRecord)
      expect(Store.superclass).to eq(ApplicationRecord)
    end

    it 'provides DataPortable to all models' do
      [ Admin, Inventory, Store ].each do |model_class|
        expect(model_class.included_modules).to include(DataPortable)
      end
    end
  end
end
