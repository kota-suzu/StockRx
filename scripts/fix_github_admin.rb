# GitHub認証問題を解決するスクリプト
# 既存の管理者に本部管理者権限を付与、またはGitHub認証管理者を修正

puts "=== 管理者アカウント診断 ==="
puts ""

# 方法1: 既存の管理者（admin@example.com）に本部管理者権限があるか確認
default_admin = Admin.find_by(email: 'admin@example.com')
if default_admin
  puts "デフォルト管理者情報:"
  puts "  Email: #{default_admin.email}"
  puts "  Role: #{default_admin.role}"
  puts "  Store: #{default_admin.store&.name || 'なし'}"
  puts "  Provider: #{default_admin.provider || 'email'}"

  if default_admin.headquarters_admin?
    puts "  ✅ すでに本部管理者権限があります"
    puts "\n👉 ブラウザでこのアカウントでログインしてください:"
    puts "   Email: admin@example.com"
    puts "   Password: Password1234!"
  else
    puts "\n本部管理者権限を付与しますか？ (y/n)"
    # スクリプト実行なので自動でyesとする
    puts "  → 自動的に権限を付与します..."
    default_admin.role = 'headquarters_admin'
    default_admin.store = nil
    if default_admin.save(validate: false)
      puts "  ✅ 権限付与成功!"
    else
      puts "  ❌ エラー: #{default_admin.errors.full_messages.join(', ')}"
    end
  end
else
  puts "デフォルト管理者が見つかりません"
end

puts "\n=== GitHub認証で使用したメールアドレスの管理者を確認 ==="
puts "GitHubアカウントのメールアドレスを確認してください。"
puts "もし既存の管理者と同じメールアドレスの場合、そのアカウントが更新されています。"

# 方法2: 最新の管理者アカウントを確認
puts "\n=== 最新5件の管理者アカウント ==="
Admin.order(updated_at: :desc).limit(5).each do |admin|
  puts "ID: #{admin.id}"
  puts "  Email: #{admin.email}"
  puts "  Role: #{admin.role}"
  puts "  Store: #{admin.store&.name || 'なし'}"
  puts "  Provider: #{admin.provider || 'email'}"
  puts "  Updated: #{admin.updated_at}"
  puts ""
end

# 方法3: store_userロールで店舗未割当の管理者を検索（GitHub認証の可能性）
puts "=== 店舗未割当のstore_userを検索 ==="
unassigned_users = Admin.where(role: 'store_user', store_id: nil)
if unassigned_users.any?
  puts "店舗未割当のstore_userが見つかりました:"
  unassigned_users.each do |admin|
    puts "ID: #{admin.id}, Email: #{admin.email}"
    puts "  → 本部管理者権限を付与します..."
    admin.role = 'headquarters_admin'
    if admin.save(validate: false)
      puts "  ✅ 権限付与成功!"
    else
      puts "  ❌ エラー: #{admin.errors.full_messages.join(', ')}"
    end
  end
else
  puts "該当なし"
end
