# GitHub認証用の管理者アカウントを作成・修正するスクリプト

email = 'kota.weeds1204@gmail.com'
uid = '119728455'

puts "=== GitHub認証管理者アカウントの作成・修正 ==="

# 既存のアカウントを確認
existing_admin = Admin.find_by(email: email)

if existing_admin
  puts "既存のアカウントが見つかりました："
  puts "  Email: #{existing_admin.email}"
  puts "  Role: #{existing_admin.role}"
  puts "  Provider: #{existing_admin.provider}"

  # GitHub認証情報を追加
  puts "\nGitHub認証情報を追加します..."
  existing_admin.provider = 'github'
  existing_admin.uid = uid
  existing_admin.role = 'headquarters_admin'
  existing_admin.store = nil

  if existing_admin.save(validate: false)
    puts "✅ 更新成功！"
    puts "  新しいRole: #{existing_admin.role}"
    puts "  Provider: #{existing_admin.provider}"
    puts "  UID: #{existing_admin.uid}"
  else
    puts "❌ エラー: #{existing_admin.errors.full_messages.join(', ')}"
  end
else
  puts "新規アカウントを作成します..."

  # パスワードは自動生成（GitHub認証では使用しない）
  password = Devise.friendly_token[0, 20]

  admin = Admin.new(
    email: email,
    password: password,
    password_confirmation: password,
    provider: 'github',
    uid: uid,
    role: 'headquarters_admin', # 本部管理者として作成
    store: nil, # 本部管理者は店舗不要
    sign_in_count: 0,
    failed_attempts: 0
  )

  if admin.save(validate: false)
    puts "✅ アカウント作成成功！"
    puts "  Email: #{admin.email}"
    puts "  Role: #{admin.role}"
    puts "  Provider: #{admin.provider}"
  else
    puts "❌ エラー: #{admin.errors.full_messages.join(', ')}"

    # エラーの詳細を表示
    admin.errors.details.each do |attr, details|
      puts "  #{attr}: #{details}"
    end
  end
end

puts "\n📝 次の手順："
puts "1. ブラウザでログアウト（既にログイン中の場合）"
puts "2. http://localhost:3000/admin/sign_in にアクセス"
puts "3. 「GitHubでログイン」ボタンをクリック"
puts "4. GitHub認証完了後、管理者ダッシュボードにアクセスできます"
