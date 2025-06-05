# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 管理者ユーザーのシード（開発環境のみ）
if Rails.env.development?
  if Admin.count.zero?
    puts 'Creating default admin user...'

    admin = Admin.new(
      email: 'admin@example.com',
      password: ENV.fetch('SEED_ADMIN_PASSWORD', 'Password1234!'),
      password_confirmation: ENV.fetch('SEED_ADMIN_PASSWORD', 'Password1234!')
    )

    # 保存に失敗した場合はエラーメッセージを表示
    if admin.save
      puts 'Default admin user created successfully!'
    else
      puts 'Failed to create default admin user:'
      puts admin.errors.full_messages.join(', ')
    end
  else
    puts 'Admin user already exists, skipping seed.'
  end
else
  puts 'Skipping admin user creation in production environment.'
  puts 'Please create admin users through Rails console or environment-specific seeds.'
end

# 検索機能テスト用の豊富なシードデータ
puts 'Creating inventory items with various conditions...'

# 開発環境でのみ追加の管理者ユーザーを作成
if Rails.env.development?
  admin2 = Admin.find_or_create_by!(email: 'admin2@example.com') do |a|
    a.password = ENV.fetch('SEED_ADMIN_PASSWORD', 'Password1234!')
    a.password_confirmation = ENV.fetch('SEED_ADMIN_PASSWORD', 'Password1234!')
  end

  admin3 = Admin.find_or_create_by!(email: 'admin3@example.com') do |a|
    a.password = ENV.fetch('SEED_ADMIN_PASSWORD', 'Password1234!')
    a.password_confirmation = ENV.fetch('SEED_ADMIN_PASSWORD', 'Password1234!')
  end
end

# Current.userを設定（ログ記録のため）
Current.user = Admin.first

# カテゴリごとの商品データ
categories = {
  "医薬品" => [
    { name: "アスピリン錠 100mg", price: 1200, quantity: 500, status: "active" },
    { name: "パラセタモール錠 500mg", price: 800, quantity: 0, status: "active" }, # 在庫切れ
    { name: "イブプロフェン錠 200mg", price: 1500, quantity: 8, status: "active" }, # 低在庫
    { name: "アモキシシリンカプセル 250mg", price: 2500, quantity: 200, status: "active" },
    { name: "セフジニルカプセル 100mg", price: 3200, quantity: 150, status: "archived" } # アーカイブ済み
  ],
  "医療機器" => [
    { name: "血圧計 デジタル式", price: 12000, quantity: 25, status: "active" },
    { name: "体温計 非接触式", price: 8500, quantity: 0, status: "active" }, # 在庫切れ
    { name: "パルスオキシメーター", price: 15000, quantity: 5, status: "active" }, # 低在庫
    { name: "聴診器 カーディオロジー", price: 25000, quantity: 12, status: "active" },
    { name: "血糖値測定器", price: 18000, quantity: 0, status: "archived" } # アーカイブ済み
  ],
  "消耗品" => [
    { name: "サージカルマスク 50枚入", price: 500, quantity: 1000, status: "active" },
    { name: "ニトリル手袋 Mサイズ 100枚", price: 1200, quantity: 2000, status: "active" },
    { name: "消毒用アルコール 500ml", price: 800, quantity: 3, status: "active" }, # 低在庫
    { name: "ガーゼ 滅菌済み 10cm×10cm", price: 300, quantity: 5000, status: "active" },
    { name: "注射針 23G 100本入", price: 2000, quantity: 0, status: "active" } # 在庫切れ
  ],
  "サプリメント" => [
    { name: "ビタミンC 1000mg 60錠", price: 2500, quantity: 100, status: "active" },
    { name: "マルチビタミン 90錠", price: 3500, quantity: 80, status: "active" },
    { name: "オメガ3 フィッシュオイル", price: 4200, quantity: 7, status: "active" }, # 低在庫
    { name: "プロバイオティクス 30カプセル", price: 3800, quantity: 0, status: "active" }, # 在庫切れ
    { name: "ビタミンD3 5000IU", price: 2800, quantity: 120, status: "archived" } # アーカイブ済み
  ]
}

inventories = []

categories.each do |category, items|
  items.each do |item_data|
    inventory = Inventory.create!(
      name: item_data[:name],
      price: item_data[:price],
      quantity: item_data[:quantity],
      status: item_data[:status],
      category: category,
      unit: "個",
      minimum_stock: 10,
      created_at: rand(90).days.ago,
      updated_at: rand(30).days.ago
    )
    inventories << inventory
  end
end

puts "Created #{inventories.count} inventory items"

# バッチ（ロット）情報の追加
puts 'Creating batches with various expiry dates...'

inventories.each do |inventory|
  # アクティブな商品にはバッチを作成
  if inventory.status == "active" && inventory.quantity > 0
    # 複数バッチを持つ商品
    if rand(100) < 50
      # バッチ1: 期限切れ間近
      Batch.create!(
        inventory: inventory,
        lot_code: "LOT#{inventory.id}A#{rand(1000..9999)}",
        quantity: inventory.quantity / 2,
        expires_on: rand(1..30).days.from_now,
        created_at: 2.months.ago
      )

      # バッチ2: 余裕のある期限
      Batch.create!(
        inventory: inventory,
        lot_code: "LOT#{inventory.id}B#{rand(1000..9999)}",
        quantity: inventory.quantity / 2,
        expires_on: rand(60..180).days.from_now,
        created_at: 1.month.ago
      )
    else
      # 単一バッチ
      expiry_date = case rand(100)
      when 0..20 then rand(1..14).days.from_now # 期限切れ間近
      when 21..40 then rand(15..30).days.from_now # やや期限が近い
      when 41..60 then rand(31..90).days.from_now # 通常
      else rand(91..365).days.from_now # 期限に余裕
      end

      Batch.create!(
        inventory: inventory,
        lot_code: "LOT#{inventory.id}#{rand(10000..99999)}",
        quantity: inventory.quantity,
        expires_on: expiry_date,
        created_at: rand(60).days.ago
      )
    end
  end

  # 期限切れバッチも一部作成
  if rand(100) < 20
    Batch.create!(
      inventory: inventory,
      lot_code: "EXPIRED#{inventory.id}#{rand(1000..9999)}",
      quantity: rand(1..10),
      expires_on: rand(1..30).days.ago,
      created_at: 3.months.ago
    )
  end
end

puts "Created batches for inventory items"

# 在庫ログの作成
puts 'Creating inventory logs with various actions...'

inventories.each do |inventory|
  # 各商品に対して複数のログを作成
  rand(3..8).times do
    user = [ Admin.first, admin2, admin3 ].sample
    action = [ "increment", "decrement", "update", "adjustment" ].sample
    quantity_change = case action
    when "increment" then rand(10..100)
    when "decrement" then -rand(1..50)
    when "adjustment" then [ -5, -10, 5, 10, 15 ].sample
    else 0
    end

    InventoryLog.create!(
      inventory: inventory,
      user: user,
      action: action,
      quantity_change: quantity_change,
      quantity_before: inventory.quantity - quantity_change,
      quantity_after: inventory.quantity,
      reason: [ "在庫調整", "入荷", "出荷", "返品", "廃棄", "棚卸し" ].sample,
      notes: [ "定期補充", "緊急対応", "顧客要求", "品質問題", nil ].sample,
      created_at: rand(60).days.ago
    )
  end
end

puts "Created inventory logs"

# 出荷情報の作成
puts 'Creating shipment records...'

# アクティブな商品から出荷を作成
active_inventories = inventories.select { |i| i.status == "active" }
active_inventories.sample(10).each do |inventory|
  rand(1..3).times do
    status = [ "preparing", "pending", "shipped", "delivered", "cancelled" ].sample

    shipment = Shipment.create!(
      inventory: inventory,
      quantity: rand(1..20),
      destination: [ "東京都千代田区", "大阪府大阪市", "愛知県名古屋市", "北海道札幌市",
                   "福岡県福岡市", "宮城県仙台市", "広島県広島市", "京都府京都市" ].sample,
      status: status,
      scheduled_date: case status
                      when "preparing", "pending" then rand(1..14).days.from_now
                      when "shipped" then rand(1..7).days.ago
                      when "delivered" then rand(7..30).days.ago
                      else Date.current
                      end,
      tracking_number: status == "shipped" || status == "delivered" ? "TRACK#{rand(100000..999999)}" : nil,
      notes: [ "特急配送", "通常配送", "冷蔵配送", nil ].sample,
      created_at: rand(30).days.ago
    )

    # 出荷済み・配達済みの場合は実際の出荷日を設定
    if [ "shipped", "delivered" ].include?(status)
      shipment.update!(shipped_date: shipment.scheduled_date)
    end
  end
end

puts "Created shipment records"

# 入荷情報の作成
puts 'Creating receipt records...'

inventories.sample(12).each do |inventory|
  rand(1..2).times do
    status = [ "pending", "received", "inspecting", "rejected" ].sample
    receipt_date = case status
    when "pending" then rand(1..14).days.from_now
    when "received", "inspecting" then rand(1..30).days.ago
    when "rejected" then rand(7..60).days.ago
    else Date.current
    end

    Receipt.create!(
      inventory: inventory,
      quantity: rand(50..500),
      source: [ "Supplier A - 東京", "Supplier B - 大阪", "Supplier C - 名古屋",
               "海外サプライヤー X", "海外サプライヤー Y", "製薬会社直送" ].sample,
      status: status,
      receipt_date: receipt_date,
      cost: inventory.price * rand(0.5..0.8) * rand(50..500),
      invoice_number: "INV#{Date.current.strftime('%Y%m')}#{rand(1000..9999)}",
      notes: [ "定期発注", "緊急補充", "新規取引", "品質検査要", nil ].sample,
      created_at: receipt_date || Date.current
    )
  end
end

puts "Created receipt records"

# 監査ログの作成（ポリモーフィック）
puts 'Creating audit logs...'

inventories.each do |inventory|
  # 在庫の監査ログ
  rand(2..5).times do
    AuditLog.create!(
      auditable: inventory,
      user: [ Admin.first, admin2, admin3 ].sample,
      action: [ "create", "update", "delete" ].sample,
      changed_fields: [ "quantity", "price", "status", "name" ].sample(rand(1..2)).to_json,
      ip_address: [ "192.168.1.#{rand(1..255)}", "10.0.0.#{rand(1..255)}" ].sample,
      user_agent: [ "Mozilla/5.0", "Chrome/91.0", "Safari/14.0" ].sample,
      created_at: rand(90).days.ago
    )
  end
end

# 管理者の監査ログも作成
[ Admin.first, admin2, admin3 ].each do |admin|
  rand(3..6).times do
    AuditLog.create!(
      auditable: admin,
      user: [ Admin.first, admin2, admin3 ].sample,
      action: [ "login", "logout", "update", "password_change" ].sample,
      changed_fields: [ "last_sign_in_at", "password", "email" ].sample(1).to_json,
      ip_address: [ "192.168.1.#{rand(1..255)}", "10.0.0.#{rand(1..255)}" ].sample,
      user_agent: [ "Mozilla/5.0", "Chrome/91.0", "Safari/14.0" ].sample,
      created_at: rand(30).days.ago
    )
  end
end

puts "Created audit logs"

# 統計情報の表示
puts "\n=== Seed Data Summary ==="
puts "Total Inventories: #{Inventory.count}"
puts "- Active: #{Inventory.active.count}"
puts "- Archived: #{Inventory.archived.count}"
puts "- Out of Stock: #{Inventory.where(quantity: 0).count}"
puts "- Low Stock (≤10): #{Inventory.where('quantity > 0 AND quantity <= 10').count}"
puts "\nTotal Batches: #{Batch.count}"
puts "- Expiring Soon (≤30 days): #{Batch.where('expires_on <= ?', 30.days.from_now).count}"
puts "- Expired: #{Batch.where('expires_on < ?', Date.current).count}"
puts "\nTotal Logs: #{InventoryLog.count}"
puts "Total Shipments: #{Shipment.count}"
puts "Total Receipts: #{Receipt.count}"
puts "Total Audit Logs: #{AuditLog.count}"
puts "\nAdmins: #{Admin.count}"
puts "===================="

puts "\nSeed data created successfully!"
puts "\nYou can now test the advanced search features with:"
puts "- Various inventory statuses (active/archived)"
puts "- Stock levels (out of stock, low stock, in stock)"
puts "- Price ranges (¥300 - ¥25,000)"
puts "- Expiring items (some expire within 14 days)"
puts "- Batch/Lot searches (LOT prefixed codes)"
puts "- Shipment destinations (various Japanese cities)"
puts "- Receipt sources (multiple suppliers)"
puts "- User activity logs (3 different admin users)"
puts "- Date range searches (items created over last 90 days)"

# 最後にCurrent.userをクリア
Current.user = nil
