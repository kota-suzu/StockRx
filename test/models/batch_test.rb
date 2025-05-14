require "test_helper"

class BatchTest < ActiveSupport::TestCase
  setup do
    @inventory = inventories(:one)
  end

  test "有効なバッチは保存できること" do
    batch = Batch.new(
      inventory: @inventory,
      lot_code: "TEST-LOT-001",
      expires_on: Date.current + 30.days,
      quantity: 5
    )
    assert batch.valid?
  end

  test "ロットコードがなければ無効であること" do
    batch = Batch.new(inventory: @inventory, lot_code: nil)
    assert_not batch.valid?
    assert_includes batch.errors[:lot_code], I18n.t("errors.messages.blank")
  end

  test "数量が負の値であれば無効であること" do
    batch = Batch.new(inventory: @inventory, lot_code: "TEST-LOT-001", quantity: -1)
    assert_not batch.valid?
    assert_includes batch.errors[:quantity], I18n.t("errors.messages.greater_than_or_equal_to", count: 0)
  end

  test "同じ在庫に同じロットコードの重複は許可されないこと" do
    Batch.create!(inventory: @inventory, lot_code: "DUPLICATE", quantity: 1)
    batch = Batch.new(inventory: @inventory, lot_code: "DUPLICATE", quantity: 2)
    assert_not batch.valid?
    assert_includes batch.errors[:lot_code], I18n.t("errors.messages.taken")
  end

  test "期限切れ判定が正しく行われること" do
    # 期限切れ
    expired_batch = Batch.new(
      inventory: @inventory,
      lot_code: "EXPIRED",
      expires_on: Date.current - 1.day,
      quantity: 5
    )
    assert expired_batch.expired?
    assert_not expired_batch.expiring_soon?

    # 期限切れではないが期限が近い
    expiring_soon_batch = Batch.new(
      inventory: @inventory,
      lot_code: "SOON",
      expires_on: Date.current + 15.days,
      quantity: 5
    )
    assert_not expiring_soon_batch.expired?
    assert expiring_soon_batch.expiring_soon?

    # 期限切れでも期限が近くもない
    valid_batch = Batch.new(
      inventory: @inventory,
      lot_code: "VALID",
      expires_on: Date.current + 60.days,
      quantity: 5
    )
    assert_not valid_batch.expired?
    assert_not valid_batch.expiring_soon?
  end
end
