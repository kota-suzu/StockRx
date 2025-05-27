require "test_helper"

class InventoryTest < ActiveSupport::TestCase
  test "有効な在庫アイテムは保存できること" do
    inventory = Inventory.new(
      name: "テスト商品",
      quantity: 10,
      price: 100.50,
      status: :active
    )
    assert inventory.valid?
  end

  test "名前がなければ無効であること" do
    inventory = Inventory.new(name: nil)
    assert_not inventory.valid?
    assert_includes inventory.errors[:name], I18n.t("errors.messages.blank")
  end

  test "価格が負の値であれば無効であること" do
    inventory = Inventory.new(name: "テスト商品", price: -1.0)
    assert_not inventory.valid?
    assert_includes inventory.errors[:price], I18n.t("errors.messages.greater_than_or_equal_to", count: 0)
  end

  test "数量が負の値であれば無効であること" do
    inventory = Inventory.new(name: "テスト商品", quantity: -1)
    assert_not inventory.valid?
    assert_includes inventory.errors[:quantity], I18n.t("errors.messages.greater_than_or_equal_to", count: 0)
  end

  test "在庫削除時に関連するバッチも削除されること" do
    inventory = inventories(:one)
    batch_count = inventory.batches.count

    assert_difference("Batch.count", -batch_count) do
      inventory.destroy
    end
  end
end
