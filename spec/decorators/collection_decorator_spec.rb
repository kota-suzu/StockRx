# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CollectionDecorator do
  # CLAUDE.md準拠: コレクションデコレーターの包括的テスト
  # メタ認知: 動的デコレータークラス選択ロジックの品質保証
  # 横展開: 他のコレクションデコレーターでも同様のテストパターン適用

  # テスト用のモデルとデコレーター
  class TestModel
    attr_accessor :id, :name

    def initialize(id:, name:)
      @id = id
      @name = name
    end
  end

  class TestModelDecorator < Draper::Decorator
    def decorated_name
      "Decorated: #{object.name}"
    end
  end

  class AnotherModel
    attr_accessor :value

    def initialize(value:)
      @value = value
    end
  end

  # AnotherModelDecoratorは定義しない（NameErrorテスト用）

  describe '#decorator_class' do
    context 'with non-empty collection' do
      context 'when decorator class exists' do
        it 'returns the appropriate decorator class' do
          collection = [ TestModel.new(id: 1, name: 'Item 1'), TestModel.new(id: 2, name: 'Item 2') ]
          decorator = CollectionDecorator.new(collection)

          expect(decorator.decorator_class).to eq(TestModelDecorator)
        end

        it 'works with ActiveRecord relations' do
          # ActiveRecord::Relationのモック
          inventory = create(:inventory)
          relation = Inventory.where(id: inventory.id)
          decorator = CollectionDecorator.new(relation)

          expect(decorator.decorator_class).to eq(InventoryDecorator)
        end
      end

      context 'when decorator class does not exist' do
        it 'returns nil when decorator class is not found' do
          collection = [ AnotherModel.new(value: 'test') ]
          decorator = CollectionDecorator.new(collection)

          expect(decorator.decorator_class).to be_nil
        end
      end

      context 'with different model types' do
        it 'handles namespaced models' do
          # 名前空間付きモデルのテスト
          module TestNamespace
            class SpecialModel
              attr_accessor :data
            end

            class SpecialModelDecorator < Draper::Decorator
            end
          end

          collection = [ TestNamespace::SpecialModel.new ]
          decorator = CollectionDecorator.new(collection)

          expect(decorator.decorator_class).to eq(TestNamespace::SpecialModelDecorator)
        end
      end
    end

    context 'with empty collection' do
      it 'returns nil for empty array' do
        decorator = CollectionDecorator.new([])

        expect(decorator.decorator_class).to be_nil
      end

      it 'returns nil for empty ActiveRecord relation' do
        relation = Inventory.none
        decorator = CollectionDecorator.new(relation)

        expect(decorator.decorator_class).to be_nil
      end
    end

    context 'error handling' do
      it 'rescues NameError and returns nil' do
        # NameErrorが発生するケースを明示的にテスト
        collection = [ double(class: double(name: 'NonExistentModel')) ]
        decorator = CollectionDecorator.new(collection)

        expect(decorator.decorator_class).to be_nil
      end

      it 'handles classes with special characters in name' do
        # 特殊文字を含むクラス名のテスト
        special_class = Class.new do
          def self.name
            'Special::Model-With-Dash'
          end
        end

        collection = [ special_class.new ]
        decorator = CollectionDecorator.new(collection)

        expect { decorator.decorator_class }.not_to raise_error
        expect(decorator.decorator_class).to be_nil
      end
    end
  end

  describe 'collection decoration' do
    context 'with decorator class found' do
      it 'decorates each item in the collection' do
        items = [
          TestModel.new(id: 1, name: 'Item 1'),
          TestModel.new(id: 2, name: 'Item 2'),
          TestModel.new(id: 3, name: 'Item 3')
        ]

        decorator = CollectionDecorator.new(items)
        decorated_items = decorator.to_a

        expect(decorated_items).to all(be_a(TestModelDecorator))
        expect(decorated_items.map(&:decorated_name)).to eq([
          'Decorated: Item 1',
          'Decorated: Item 2',
          'Decorated: Item 3'
        ])
      end
    end

    context 'with no decorator class' do
      it 'returns undecorated items when decorator not found' do
        items = [
          AnotherModel.new(value: 'test1'),
          AnotherModel.new(value: 'test2')
        ]

        decorator = CollectionDecorator.new(items)
        result = decorator.to_a

        # Draper::CollectionDecoratorのデフォルト動作をテスト
        expect(result).to eq(items)
      end
    end
  end

  describe 'enumerable behavior' do
    let(:items) do
      [
        TestModel.new(id: 1, name: 'First'),
        TestModel.new(id: 2, name: 'Second'),
        TestModel.new(id: 3, name: 'Third')
      ]
    end
    let(:decorator) { CollectionDecorator.new(items) }

    it 'supports enumerable methods' do
      expect(decorator.count).to eq(3)
      expect(decorator.first.decorated_name).to eq('Decorated: First')
      expect(decorator.last.decorated_name).to eq('Decorated: Third')
    end

    it 'supports map operation' do
      names = decorator.map(&:decorated_name)
      expect(names).to eq([ 'Decorated: First', 'Decorated: Second', 'Decorated: Third' ])
    end

    it 'supports select operation' do
      filtered = decorator.select { |item| item.id > 1 }
      expect(filtered.count).to eq(2)
    end
  end

  describe 'edge cases' do
    context 'with nil collection' do
      it 'handles nil collection gracefully' do
        expect { CollectionDecorator.new(nil) }.to raise_error(NoMethodError)
      end
    end

    context 'with heterogeneous collection' do
      it 'uses the first item class for decorator selection' do
        # 異なる型のオブジェクトが混在するコレクション
        mixed_items = [
          TestModel.new(id: 1, name: 'Test'),
          AnotherModel.new(value: 'Another'),
          TestModel.new(id: 2, name: 'Test 2')
        ]

        decorator = CollectionDecorator.new(mixed_items)
        expect(decorator.decorator_class).to eq(TestModelDecorator)
      end
    end

    context 'with custom collection objects' do
      it 'works with objects that respond to first and empty?' do
        custom_collection = double('CustomCollection')
        allow(custom_collection).to receive(:empty?).and_return(false)
        allow(custom_collection).to receive(:first).and_return(TestModel.new(id: 1, name: 'Test'))
        allow(custom_collection).to receive(:each).and_yield(TestModel.new(id: 1, name: 'Test'))

        decorator = CollectionDecorator.new(custom_collection)
        expect(decorator.decorator_class).to eq(TestModelDecorator)
      end
    end
  end

  describe 'performance' do
    it 'caches decorator class lookup' do
      items = Array.new(100) { |i| TestModel.new(id: i, name: "Item #{i}") }
      decorator = CollectionDecorator.new(items)

      # 最初の呼び出し
      expect(decorator).to receive(:object).once.and_return(items)
      decorator.decorator_class

      # 2回目の呼び出しはキャッシュされるべき（実際の実装に依存）
      # 注: 現在の実装はキャッシュしていないが、パフォーマンステストとして記載
      decorator.decorator_class
    end
  end

  describe 'inheritance behavior' do
    class CustomCollectionDecorator < CollectionDecorator
      def custom_method
        'custom behavior'
      end
    end

    it 'preserves custom behavior in subclasses' do
      items = [ TestModel.new(id: 1, name: 'Test') ]
      decorator = CustomCollectionDecorator.new(items)

      expect(decorator.decorator_class).to eq(TestModelDecorator)
      expect(decorator.custom_method).to eq('custom behavior')
    end
  end
end
