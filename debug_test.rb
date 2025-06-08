#!/usr/bin/env ruby
# デバッグ用テスト
require_relative 'config/environment'

# テストデータ作成
test_prefix = "DEBUG_#{SecureRandom.hex(4)}"
inventory1 = FactoryBot.create(:inventory, name: "#{test_prefix}_Product_A", quantity: 100, price: 50.0, status: "active")
admin = FactoryBot.create(:admin, email: "debug@example.com")

# シンボルと文字列の両方でshipmentを作成
shipment1 = FactoryBot.create(:shipment, inventory: inventory1, shipment_status: :shipped, destination: "Tokyo")
log1 = FactoryBot.create(:inventory_log, inventory: inventory1, user: admin, operation_type: "add", delta: 10)

puts "=== デバッグ情報 ==="
puts "inventory1 ID: #{inventory1.id}"
puts "shipment1 ID: #{shipment1.id}, status: #{shipment1.shipment_status}, raw value: #{shipment1.shipment_status_before_type_cast}"
puts "log1 ID: #{log1.id}, operation_type: #{log1.operation_type}"

# クエリテスト
test_scope = Inventory.where("name LIKE ?", "#{test_prefix}%")
puts "\n=== 基本スコープテスト ==="
puts "Basic scope count: #{test_scope.count}"

# ShipmentConditionBuilderのテスト
puts "\n=== ShipmentConditionBuilder単体テスト ==="
builder = AdvancedSearchQuery::ShipmentConditionBuilder.new
builder.status("shipped")
basic_joined_scope = test_scope.joins(:shipments)
shipment_results = builder.apply_to(basic_joined_scope)
puts "Shipment query SQL: #{shipment_results.to_sql}"
puts "Shipment results count: #{shipment_results.count}"

# AdvancedSearchQueryでのテスト
puts "\n=== AdvancedSearchQuery統合テスト ==="
query = AdvancedSearchQuery.build(test_scope)
  .with_shipment_conditions do
    status("shipped")
  end
puts "AdvancedSearchQuery SQL: #{query.to_sql}"
puts "AdvancedSearchQuery results count: #{query.count}"
puts "AdvancedSearchQuery results: #{query.results.to_a}"

# InventoryLogConditionBuilderのテスト
puts "\n=== InventoryLogConditionBuilder単体テスト ==="
log_builder = AdvancedSearchQuery::InventoryLogConditionBuilder.new
log_builder.action_type("add")
log_joined_scope = test_scope.joins(:inventory_logs)
log_results = log_builder.apply_to(log_joined_scope)
puts "InventoryLog query SQL: #{log_results.to_sql}"
puts "InventoryLog results count: #{log_results.count}"

# AdvancedSearchQueryでのログテスト
puts "\n=== AdvancedSearchQuery ログ統合テスト ==="
log_query = AdvancedSearchQuery.build(test_scope)
  .with_inventory_log_conditions do
    action_type("add")
  end
puts "AdvancedSearchQuery log SQL: #{log_query.to_sql}"
puts "AdvancedSearchQuery log results count: #{log_query.count}"
puts "AdvancedSearchQuery log results: #{log_query.results.to_a}"

# クリーンアップ
shipment1.destroy!
log1.destroy!
inventory1.destroy!
admin.destroy!

puts "\n=== デバッグ完了 ==="
