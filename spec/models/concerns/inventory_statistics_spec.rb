require 'rails_helper'

RSpec.describe InventoryStatistics do
  # Inventoryクラスはすでにモジュールをincludeしているので直接使用
  let(:inventory_class) { Inventory }

  describe 'scopes' do
    before do
      Inventory.delete_all
      # BatchManageable の sync_total_quantity コールバックを避けるため、
      # create後にupdate_columnでquantityを設定する
      # Inventory::LOW_STOCK_THRESHOLD が 5 の場合
      @out_of_stock_item = create(:inventory, price: 500)
      @out_of_stock_item.update_column(:quantity, 0)

      @low_stock_item = create(:inventory, price: 800)
      @low_stock_item.update_column(:quantity, Inventory::LOW_STOCK_THRESHOLD) # 0 < quantity <= 5

      @normal_stock_item = create(:inventory, price: 1200)
      @normal_stock_item.update_column(:quantity, Inventory::LOW_STOCK_THRESHOLD + 3) # quantity > 5
    end

    it 'low_stockは閾値以下の在庫を返す' do
      expect(inventory_class.low_stock).to contain_exactly(@low_stock_item)
    end

    it 'out_of_stockは在庫切れの商品を返す' do
      expect(inventory_class.out_of_stock).to contain_exactly(@out_of_stock_item)
    end

    it 'normal_stockは閾値より多い在庫を返す' do
      expect(inventory_class.normal_stock).to contain_exactly(@normal_stock_item)
    end
  end

  describe 'instance methods' do
    # buildだとコールバックは実行されないが、DBに依存するテストではないためこのままで良い
    # ただし、永続化されたオブジェクトの振る舞いをテストする場合はcreateとupdate_columnを検討
    let(:out_of_stock) { build_stubbed(:inventory, quantity: 0, price: 500) }
    let(:low_stock_item) { build_stubbed(:inventory, quantity: Inventory::LOW_STOCK_THRESHOLD, price: 800) }
    let(:normal_stock) { build_stubbed(:inventory, quantity: Inventory::LOW_STOCK_THRESHOLD + 3, price: 1200) }
    # Inventory::LOW_STOCK_THRESHOLD が 0 の場合、low_stock_item.low_stock? が false になるため、
    # LOW_STOCK_THRESHOLD は 1以上であるという前提でテストデータを作成する。
    # FactoryBotで Inventory::LOW_STOCK_THRESHOLD を 5 と仮定して値を設定。

    it 'low_stock?は閾値以下かを判定する' do
      expect(out_of_stock.low_stock?).to be false
      expect(low_stock_item.low_stock?).to be true # 変数名変更
      expect(normal_stock.low_stock?).to be false
    end

    it 'out_of_stock?は在庫切れかを判定する' do
      expect(out_of_stock.out_of_stock?).to be true
      expect(low_stock_item.out_of_stock?).to be false # 変数名を修正
    end

    it 'stock_statusは適切なステータスを返す' do
      expect(out_of_stock.stock_status).to eq(:out_of_stock)
      expect(low_stock_item.stock_status).to eq(:low_stock) # 変数名変更
      expect(normal_stock.stock_status).to eq(:normal)
    end
  end

  describe 'class methods' do
    before do
      Inventory.delete_all
      # BatchManageable の sync_total_quantity コールバックを避けるため、
      # create後にupdate_columnでquantityを設定する
      # ユーザー指示「3-4. テストデータの最小修正」を参考に、より具体的な値で設定
      @no_stock     = create(:inventory, price: 500)
      @no_stock.update_column(:quantity, 0)
      @few_stock    = create(:inventory, price: 800)
      @few_stock.update_column(:quantity, Inventory::LOW_STOCK_THRESHOLD)
      @enough_stock = create(:inventory, price: 1200)
      @enough_stock.update_column(:quantity, Inventory::LOW_STOCK_THRESHOLD + 3)
    end

    it 'stock_summaryは在庫の統計情報を返す' do
      summary = inventory_class.stock_summary

      expect(summary[:total_items]).to eq(3) # キー名変更
      expect(summary[:total_value]).to eq(@few_stock.price * @few_stock.quantity + @enough_stock.price * @enough_stock.quantity)
      expect(summary[:low_stock_count]).to eq(1)
      expect(summary[:out_of_stock_count]).to eq(1)
      expect(summary[:normal_stock_count]).to eq(1)
    end
  end
end
