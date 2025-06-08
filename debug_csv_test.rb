#!/usr/bin/env ruby
# CSVインポート機能デバッグ用スクリプト

require 'csv'
require 'tempfile'

# ログレベルをdebugに設定
Rails.logger.level = Logger::DEBUG

# テスト用CSVファイルを作成
csv_content = <<~CSV
  name,quantity,price,status
  Debug Test Item 1,10,100.0,active
  Debug Test Item 2,20,200.0,active
  Debug Test Item 3,30,300.0,archived
CSV

temp_csv_file = Tempfile.new([ 'debug_csv_import', '.csv' ])
temp_csv_file.write(csv_content)
temp_csv_file.close

begin
  puts "=== CSVインポートデバッグ開始 ==="
  puts "CSV内容:"
  puts csv_content

  # クリーンアップ
  Inventory.where(name: [ 'Debug Test Item 1', 'Debug Test Item 2', 'Debug Test Item 3' ]).destroy_all
  InventoryLog.where(note: 'CSVインポートによる登録').destroy_all

  puts "\n=== インポート前状態 ==="
  puts "在庫数: #{Inventory.count}"
  puts "在庫ログ数: #{InventoryLog.count}"

  # CSVインポート実行
  puts "\n=== CSVインポート実行 ==="
  result = Inventory.import_from_csv(temp_csv_file.path)

  puts "インポート結果:"
  puts "  valid_count: #{result[:valid_count]}"
  puts "  update_count: #{result[:update_count]}"
  puts "  invalid_records: #{result[:invalid_records].size}"

  puts "\n=== インポート後状態 ==="
  imported_inventories = Inventory.where(name: [ 'Debug Test Item 1', 'Debug Test Item 2', 'Debug Test Item 3' ])
  puts "インポートされた在庫数: #{imported_inventories.count}"

  imported_inventories.each do |inventory|
    puts "  - #{inventory.name}: quantity=#{inventory.quantity}, price=#{inventory.price}, id=#{inventory.id}"
  end

  inventory_logs = InventoryLog.where(note: 'CSVインポートによる登録')
  puts "作成された在庫ログ数: #{inventory_logs.count}"

  inventory_logs.each do |log|
    puts "  - inventory_id=#{log.inventory_id}, delta=#{log.delta}, operation_type=#{log.operation_type}"
  end

  # insert_allの戻り値を直接確認
  puts "\n=== insert_allの戻り値確認 ==="
  test_records = [
    Inventory.new(name: "Test Insert All 1", quantity: 5, price: 50.0, status: "active"),
    Inventory.new(name: "Test Insert All 2", quantity: 15, price: 150.0, status: "active")
  ]

  attributes = test_records.map do |record|
    record.attributes.except("id", "created_at", "updated_at")
  end

  insert_result = Inventory.insert_all(attributes, record_timestamps: true)
  puts "insert_result class: #{insert_result.class}"
  puts "insert_result methods: #{insert_result.methods.sort - Object.methods}"

  if insert_result.respond_to?(:rows)
    puts "insert_result.rows: #{insert_result.rows}"
    puts "insert_result.rows present?: #{insert_result.rows.present?}"
  end

  # クリーンアップ
  Inventory.where(name: [ 'Test Insert All 1', 'Test Insert All 2' ]).destroy_all

ensure
  temp_csv_file.unlink if temp_csv_file
end
