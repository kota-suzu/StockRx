# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# 管理者ユーザーのシード
if Admin.count.zero?
  puts 'Creating default admin user...'

  admin = Admin.new(
    email: 'admin@example.com',
    password: 'Password1234!',  # 本番環境では変更すること
    password_confirmation: 'Password1234!'
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

# TODO: 在庫アイテムのシードデータ
# TODO: 商品カテゴリのシードデータ
# TODO: テスト用サンプルデータ