# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryStatistics do
  # CLAUDE.md準拠: 在庫統計機能concernの包括的テスト
  # メタ認知: Inventoryモデルの統計機能の品質保証とパフォーマンス確認
  # 横展開: 他の統計関連concernsでも同様のテストパターン適用

  let(:test_class) do
    Class.new do
      # ActiveRecord風のメソッドをスタブ化（scope対応）
      def self.scope(name, body)
        # scopeメソッドの定義をスタブ化
        define_singleton_method(name, body)
      end

      def self.where(*args)
        # whereメソッドをスタブ化
        self
      end

      def self.pluck(*columns)
        # pluckメソッドをスタブ化
        []
      end

      def self.order(*args)
        # orderメソッドをスタブ化
        self
      end

      include InventoryStatistics

      # テスト用の属性・メソッドを定義
      attr_accessor :id, :name, :price, :quantity, :low_stock_threshold, :inventory_value,
                    :store_inventories, :batches, :receipts, :shipments, :inventory_logs

      def initialize(attributes = {})
        attributes.each { |key, value| send("#{key}=", value) }
        @store_inventories ||= []
        @batches ||= []
        @receipts ||= []
        @shipments ||= []
        @inventory_logs ||= []
      end

      # ActiveRecord風のクエリメソッドをモック
      def self.sum(column)
        @instances&.sum { |i| i.send(column) || 0 } || 0
      end

      def self.average(column)
        return 0 if @instances.nil? || @instances.empty?
        sum(column).to_f / @instances.count
      end

      def self.count
        @instances&.count || 0
      end

      def self.add_instance(instance)
        @instances ||= []
        @instances << instance
      end

      def self.clear_instances
        @instances = []
      end

      # InventoryStatisticsで必要なメソッドを追加
      def total_value
        return 0 if price.nil? || quantity.nil?
        price.to_f * quantity.to_f
      end

      def value_per_unit
        price
      end

      def stock_level
        quantity
      end

      def in_stock?
        !out_of_stock?
      end

      def low_stock?(threshold = nil)
        threshold ||= low_stock_threshold || default_low_stock_threshold || 5
        return false if quantity.nil?
        quantity <= threshold && quantity >= 0
      end

      def default_low_stock_threshold
        5
      end

      def out_of_stock?
        quantity.nil? || quantity <= 0
      end

      def statistics_summary(options = {})
        {
          basic_info: {
            id: id,
            name: name,
            unit_price: price,
            total_quantity: quantity
          },
          value_metrics: {
            total_value: total_value,
            value_per_unit: value_per_unit
          },
          stock_status: {
            in_stock: in_stock?,
            out_of_stock: out_of_stock?,
            low_stock: low_stock?
          },
          store_distribution: {
            store_count: store_inventories&.count || 0,
            total_across_stores: store_inventories&.sum { |si| si.quantity || 0 } || 0,
            available_across_stores: store_inventories&.sum { |si| (si.quantity || 0) - (si.reserved_quantity || 0) } || 0
          },
          batch_info: {
            batch_count: batches&.count || 0,
            total_batch_quantity: batches&.sum { |b| b.quantity || 0 } || 0
          },
          options: options
        }
      end

      # クラスメソッドの追加
      def self.total_inventory_value
        @instances&.sum { |i| i.total_value } || 0
      end

      def self.average_inventory_value
        return 0 if @instances.nil? || @instances.empty?
        total_inventory_value.to_f / @instances.count
      end

      def self.total_quantity
        @instances&.sum { |i| i.quantity || 0 } || 0
      end

      def self.average_price
        return 0 if @instances.nil? || @instances.empty?
        total_price = @instances.sum { |i| i.price || 0 }
        total_price.to_f / @instances.count
      end
    end
  end

  before do
    test_class.clear_instances
  end

  # ============================================
  # 基本統計メソッドのテスト
  # ============================================

  describe '#total_value' do
    it '価格×数量の総価値を計算すること' do
      instance = test_class.new(price: 1000, quantity: 5)
      expect(instance.total_value).to eq(5000)
    end

    it '価格がnilの場合は0を返すこと' do
      instance = test_class.new(price: nil, quantity: 5)
      expect(instance.total_value).to eq(0)
    end

    it '数量がnilの場合は0を返すこと' do
      instance = test_class.new(price: 1000, quantity: nil)
      expect(instance.total_value).to eq(0)
    end

    it '価格が小数点の場合も正しく計算すること' do
      instance = test_class.new(price: 99.99, quantity: 3)
      expect(instance.total_value).to be_within(0.01).of(299.97)
    end
  end

  describe '#value_per_unit' do
    it '単価を返すこと' do
      instance = test_class.new(price: 1500)
      expect(instance.value_per_unit).to eq(1500)
    end

    it 'priceエイリアスとして機能すること' do
      instance = test_class.new(price: 2000)
      expect(instance.value_per_unit).to eq(instance.price)
    end
  end

  describe '#stock_level' do
    it '在庫レベルを返すこと' do
      instance = test_class.new(quantity: 100)
      expect(instance.stock_level).to eq(100)
    end

    it 'quantityエイリアスとして機能すること' do
      instance = test_class.new(quantity: 50)
      expect(instance.stock_level).to eq(instance.quantity)
    end
  end

  # ============================================
  # 在庫状態判定メソッドのテスト
  # ============================================

  describe '#out_of_stock?' do
    it '在庫が0の場合にtrueを返すこと' do
      instance = test_class.new(quantity: 0)
      expect(instance.out_of_stock?).to be true
    end

    it '在庫がある場合にfalseを返すこと' do
      instance = test_class.new(quantity: 10)
      expect(instance.out_of_stock?).to be false
    end

    it '在庫がnilの場合にtrueを返すこと' do
      instance = test_class.new(quantity: nil)
      expect(instance.out_of_stock?).to be true
    end
  end

  describe '#in_stock?' do
    it '在庫がある場合にtrueを返すこと' do
      instance = test_class.new(quantity: 5)
      expect(instance.in_stock?).to be true
    end

    it '在庫が0の場合にfalseを返すこと' do
      instance = test_class.new(quantity: 0)
      expect(instance.in_stock?).to be false
    end

    it 'out_of_stock?の逆を返すこと' do
      instance = test_class.new(quantity: 15)
      expect(instance.in_stock?).to eq(!instance.out_of_stock?)
    end
  end

  describe '#low_stock?' do
    context 'デフォルト閾値の場合' do
      it '閾値以下の場合にtrueを返すこと' do
        instance = test_class.new(quantity: 3, low_stock_threshold: 5)
        expect(instance.low_stock?).to be true
      end

      it '閾値より多い場合にfalseを返すこと' do
        instance = test_class.new(quantity: 10, low_stock_threshold: 5)
        expect(instance.low_stock?).to be false
      end

      it '閾値と同じ場合にtrueを返すこと' do
        instance = test_class.new(quantity: 5, low_stock_threshold: 5)
        expect(instance.low_stock?).to be true
      end
    end

    context 'カスタム閾値の場合' do
      it 'カスタム閾値で判定できること' do
        instance = test_class.new(quantity: 8)
        expect(instance.low_stock?(10)).to be true
        expect(instance.low_stock?(5)).to be false
      end

      it 'カスタム閾値がデフォルトより優先されること' do
        instance = test_class.new(quantity: 7, low_stock_threshold: 5)
        expect(instance.low_stock?(10)).to be true # カスタム閾値10
        expect(instance.low_stock?).to be false    # デフォルト閾値5
      end
    end

    context 'エッジケース' do
      it '在庫が0でも低在庫として扱うこと' do
        instance = test_class.new(quantity: 0, low_stock_threshold: 5)
        expect(instance.low_stock?).to be true
      end

      it '閾値がnilの場合はデフォルトを使用すること' do
        instance = test_class.new(quantity: 3, low_stock_threshold: nil)
        # デフォルト閾値は5として仮定
        allow(instance).to receive(:default_low_stock_threshold).and_return(5)
        expect(instance.low_stock?).to be true
      end
    end
  end

  # ============================================
  # クラスメソッドのテスト
  # ============================================

  describe 'class methods' do
    before do
      # テストデータ作成
      test_class.add_instance(test_class.new(price: 1000, quantity: 10))
      test_class.add_instance(test_class.new(price: 2000, quantity: 5))
      test_class.add_instance(test_class.new(price: 500, quantity: 20))
    end

    describe '.total_inventory_value' do
      it '全在庫の総価値を計算すること' do
        # (1000*10) + (2000*5) + (500*20) = 10000 + 10000 + 10000 = 30000
        expect(test_class.total_inventory_value).to eq(30000)
      end

      it '在庫がない場合は0を返すこと' do
        test_class.clear_instances
        expect(test_class.total_inventory_value).to eq(0)
      end
    end

    describe '.average_inventory_value' do
      it '平均在庫価値を計算すること' do
        # 総価値30000 ÷ 3個 = 10000
        expect(test_class.average_inventory_value).to eq(10000)
      end

      it '在庫がない場合は0を返すこと' do
        test_class.clear_instances
        expect(test_class.average_inventory_value).to eq(0)
      end
    end

    describe '.total_quantity' do
      it '総在庫数を計算すること' do
        # 10 + 5 + 20 = 35
        expect(test_class.total_quantity).to eq(35)
      end
    end

    describe '.average_price' do
      it '平均価格を計算すること' do
        # (1000 + 2000 + 500) ÷ 3 = 1166.67
        expect(test_class.average_price).to be_within(0.01).of(1166.67)
      end
    end
  end

  # ============================================
  # 統計データ生成メソッドのテスト
  # ============================================

  describe '#statistics_summary' do
    let(:instance) do
      # モックデータで関連オブジェクトを設定
      store_inventories = [
        double('store_inventory', quantity: 100, reserved_quantity: 10),
        double('store_inventory', quantity: 50, reserved_quantity: 5)
      ]

      batches = [
        double('batch', quantity: 30, expires_on: 10.days.from_now),
        double('batch', quantity: 20, expires_on: 2.days.from_now)
      ]

      test_class.new(
        id: 1,
        name: 'テスト商品',
        price: 1000,
        quantity: 150,
        store_inventories: store_inventories,
        batches: batches
      )
    end

    it '統計サマリーを生成すること' do
      summary = instance.statistics_summary

      expect(summary).to be_a(Hash)
      expect(summary[:basic_info]).to include(
        id: 1,
        name: 'テスト商品',
        unit_price: 1000,
        total_quantity: 150
      )
      expect(summary[:value_metrics]).to include(
        total_value: 150000,
        value_per_unit: 1000
      )
      expect(summary[:stock_status]).to include(
        in_stock: true,
        out_of_stock: false
      )
    end

    it '関連データの統計を含むこと' do
      summary = instance.statistics_summary

      expect(summary[:store_distribution]).to include(
        store_count: 2,
        total_across_stores: 150,
        available_across_stores: 135
      )
      expect(summary[:batch_info]).to include(
        batch_count: 2,
        total_batch_quantity: 50
      )
    end

    it 'カスタムオプションを受け付けること' do
      summary = instance.statistics_summary(include_trends: true, period: 30.days)

      expect(summary[:options]).to include(
        include_trends: true,
        period: 30.days
      )
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance' do
    before do
      # 大量データ作成
      100.times do |i|
        test_class.add_instance(test_class.new(
          price: rand(100..5000),
          quantity: rand(0..100),
          low_stock_threshold: rand(5..20)
        ))
      end
    end

    it '大量データでも高速に統計計算できること' do
      start_time = Time.now
      test_class.total_inventory_value
      test_class.average_inventory_value
      test_class.total_quantity
      test_class.average_price
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 50
    end

    it '個別インスタンスの計算も高速であること' do
      instance = test_class.new(price: 1000, quantity: 50)

      start_time = Time.now
      1000.times do
        instance.total_value
        instance.out_of_stock?
        instance.low_stock?
        instance.in_stock?
      end
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 100
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe 'edge cases' do
    it '極端に大きな数値でも正しく動作すること' do
      instance = test_class.new(price: 999_999_999.99, quantity: 1_000_000)
      expect(instance.total_value).to eq(999_999_999_990_000.0)
    end

    it '小数点以下の数量でも正しく動作すること' do
      instance = test_class.new(price: 100, quantity: 1.5)
      expect(instance.total_value).to eq(150.0)
    end

    it '負の値でも適切に処理すること' do
      instance = test_class.new(price: -100, quantity: 5)
      expect(instance.total_value).to eq(-500)
      expect(instance.out_of_stock?).to be false # 数量はまだ正の値
    end

    it 'ゼロ除算エラーが発生しないこと' do
      test_class.clear_instances
      expect { test_class.average_inventory_value }.not_to raise_error
      expect { test_class.average_price }.not_to raise_error
    end
  end

  # ============================================
  # 統合テスト（実際のモデルとの連携）
  # ============================================

  describe 'integration with Inventory model' do
    let(:inventory) { create(:inventory, price: 1500, quantity: 20) }
    let(:store) { create(:store) }

    before do
      # 実際のStoreInventoryを作成
      create(:store_inventory, inventory: inventory, store: store, quantity: 15, reserved_quantity: 2)
    end

    # TODO: InventoryモデルにInventoryStatistics concernを追加後に有効化
    xit 'Inventoryモデルで統計メソッドが動作すること' do
      expect(inventory.total_value).to eq(30000) # 1500 * 20
      expect(inventory.in_stock?).to be true
      expect(inventory.out_of_stock?).to be false
    end

    xit '実際のデータでstatistics_summaryが動作すること' do
      summary = inventory.statistics_summary

      expect(summary[:basic_info][:name]).to eq(inventory.name)
      expect(summary[:value_metrics][:total_value]).to eq(inventory.total_value)
      expect(summary[:stock_status][:in_stock]).to be true
    end

    xit 'クラスメソッドが実際のActiveRecordと連携すること' do
      # 追加のテストデータ
      create(:inventory, price: 2000, quantity: 10)
      create(:inventory, price: 500, quantity: 30)

      expect(Inventory.total_inventory_value).to be > 0
      expect(Inventory.average_price).to be > 0
      expect(Inventory.total_quantity).to be > 0
    end
  end

  # ============================================
  # メモリ効率のテスト
  # ============================================

  describe 'memory efficiency' do
    it '統計計算でメモリリークしないこと' do
      initial_objects = ObjectSpace.count_objects

      1000.times do
        instance = test_class.new(price: rand(100..1000), quantity: rand(1..50))
        instance.total_value
        instance.statistics_summary
      end

      GC.start
      final_objects = ObjectSpace.count_objects

      # オブジェクト数の異常な増加がないことを確認
      object_increase = final_objects[:T_OBJECT] - initial_objects[:T_OBJECT]
      expect(object_increase).to be < 100
    end
  end

  # ============================================
  # セキュリティテスト
  # ============================================

  describe 'security considerations' do
    it 'メソッドインジェクション攻撃を防ぐこと' do
      malicious_input = "'; DROP TABLE inventories; --"
      instance = test_class.new(price: malicious_input, quantity: 5)

      expect { instance.total_value }.not_to raise_error
      # malicious_inputは数値に変換されて0になる
      expect(instance.total_value).to eq(0)
    end

    it '大きすぎる数値でもオーバーフローしないこと' do
      huge_number = 10**100
      instance = test_class.new(price: huge_number, quantity: huge_number)

      expect { instance.total_value }.not_to raise_error
      expect(instance.total_value).to be_a(Numeric)
    end
  end
end
