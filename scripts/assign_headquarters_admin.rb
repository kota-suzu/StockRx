# GitHub認証で作成された管理者に本部管理者権限を付与するスクリプト

puts "=== GitHub認証の管理者アカウント一覧 ==="
github_admins = Admin.where(provider: 'github')

if github_admins.any?
  github_admins.each do |admin|
    puts "ID: #{admin.id}, Email: #{admin.email}, Role: #{admin.role}, Store: #{admin.store&.name || 'なし'}"
  end
  admin = github_admins.last
else
  puts "GitHub認証の管理者が見つかりません。"
  puts "\n=== 全管理者アカウント ==="
  Admin.all.each do |a|
    puts "ID: #{a.id}, Email: #{a.email}, Role: #{a.role}, Provider: #{a.provider || 'email'}"
  end
  exit
end

puts "\n=== 選択された管理者 ==="
admin = github_admins.last

if admin
  puts "ID: #{admin.id}"
  puts "Email: #{admin.email}"
  puts "Role: #{admin.role}"
  puts "Store: #{admin.store&.name || 'なし'}"
  puts "Provider: #{admin.provider || 'email'}"

  # 本部管理者権限を付与
  puts "\n=== 本部管理者権限を付与 ==="
  admin.role = 'headquarters_admin'
  admin.store = nil

  if admin.save(validate: false)  # バリデーションをスキップして保存
    puts "✅ 権限更新成功!"
    puts "新しいRole: #{admin.role}"
    puts "Store: #{admin.store&.name || 'なし（本部管理者）'}"
    puts "\n📝 ブラウザでログアウト後、再度GitHubでログインしてください。"
  else
    puts "❌ エラー: #{admin.errors.full_messages.join(', ')}"
  end
else
  puts "管理者アカウントが見つかりません"
end
