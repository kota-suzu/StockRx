# frozen_string_literal: true

# ===============================================
# パスワードバリデーター使用例
# ===============================================
#
# このファイルは、クラス分割されたPasswordStrengthValidatorV2の
# 実践的な使用例を示しています。
#
# 実行方法:
# $ rails runner examples/password_validator_usage_examples.rb

puts "🔐 パスワードバリデーター使用例デモ"
puts "=" * 50

# ===============================================
# 例1: 基本的な使用方法
# ===============================================
puts "\n📋 例1: 基本的な使用方法"

class User
  include ActiveModel::Validations

  attr_accessor :email, :password

  validates :password, password_strength_v2: true
end

user = User.new
test_passwords = [
  "weak",                           # 弱いパスワード
  "StrongPassword123!",            # 強いパスワード
  "OnlyLetters",                   # 文字のみ
  "Pass123!"                       # 短いが複雑
]

test_passwords.each do |password|
  user.password = password
  status = user.valid? ? "✅ 有効" : "❌ 無効"
  puts "  #{password.ljust(20)} -> #{status}"
  unless user.valid?
    user.errors[:password].each { |error| puts "    - #{error}" }
  end
end

# ===============================================
# 例2: ルールセット別の比較
# ===============================================
puts "\n📋 例2: ルールセット別の比較"

class BasicUser
  include ActiveModel::Validations
  attr_accessor :password
  validates :password, password_strength_v2: { rule_set: :basic }
end

class StandardUser
  include ActiveModel::Validations
  attr_accessor :password
  validates :password, password_strength_v2: { rule_set: :standard }
end

class EnterpriseUser
  include ActiveModel::Validations
  attr_accessor :password
  validates :password, password_strength_v2: { rule_set: :enterprise }
end

test_password = "Password123"  # 記号なし、12文字

[
  { name: "Basic", class: BasicUser },
  { name: "Standard", class: StandardUser },
  { name: "Enterprise", class: EnterpriseUser }
].each do |config|
  user = config[:class].new
  user.password = test_password
  status = user.valid? ? "✅ 有効" : "❌ 無効"
  puts "  #{config[:name].ljust(10)} -> #{status}"
end

# ===============================================
# 例3: カスタム設定の活用
# ===============================================
puts "\n📋 例3: カスタム設定の活用"

class CustomUser
  include ActiveModel::Validations
  attr_accessor :password

  validates :password, password_strength_v2: {
    min_length: 10,
    max_length: 50,
    require_digit: true,
    require_lowercase: true,
    require_uppercase: true,
    require_symbol: false,        # 記号は不要
    complexity_score: 3           # 低めの複雑度
  }
end

custom_passwords = [
  "SimplePass123",     # 記号なしでOK
  "Complex!@#456",     # 記号ありでもOK
  "short",             # 短すぎる
  "VeryLongPasswordThatExceedsTheMaximumLengthLimit123"  # 長すぎる
]

custom_user = CustomUser.new
custom_passwords.each do |password|
  custom_user.password = password
  status = custom_user.valid? ? "✅ 有効" : "❌ 無効"
  puts "  #{password[0..25].ljust(26)} -> #{status}"
  unless custom_user.valid?
    custom_user.errors[:password].each { |error| puts "    - #{error}" }
  end
end

# ===============================================
# 例4: カスタムルールの実装
# ===============================================
puts "\n📋 例4: カスタムルールの実装"

class SecureUser
  include ActiveModel::Validations
  attr_accessor :password, :username

  validates :password, password_strength_v2: {
    rule_set: :standard,
    custom_rules: [
      {
        type: :regex,
        pattern: /^[A-Za-z]/,  # 英字で始まる
        error_message: "パスワードは英字で始まる必要があります"
      },
      {
        type: :length_range,
        min_length: 15,
        max_length: 30,
        error_message: "パスワードは15-30文字である必要があります"
      },
      {
        type: :custom_lambda,
        lambda: ->(password) {
          # ユーザー名を含まない
          !password.downcase.include?('admin')
        },
        error_message: "パスワードに'admin'を含めることはできません"
      }
    ]
  }
end

secure_passwords = [
  "VerySecurePassword123!",      # 有効
  "1StartsWithNumber123!",       # 数字で始まる（無効）
  "AdminPassword123!",           # 'admin'を含む（無効）
  "ValidButTooLongPasswordThatExceedsLimit123!"  # 長すぎる（無効）
]

secure_user = SecureUser.new
secure_passwords.each do |password|
  secure_user.password = password
  status = secure_user.valid? ? "✅ 有効" : "❌ 無効"
  puts "  #{password[0..30].ljust(31)} -> #{status}"
  unless secure_user.valid?
    secure_user.errors[:password].each { |error| puts "    - #{error}" }
  end
end

# ===============================================
# 例5: 個別バリデーターの直接使用
# ===============================================
puts "\n📋 例5: 個別バリデーターの直接使用"

# 長さバリデーター
length_validator = PasswordRules::LengthRangeValidator.secure
puts "長さバリデーター (推奨セキュア設定):"
puts "  範囲: #{length_validator.range_description}"
puts "  'Password123!' -> #{length_validator.valid?('Password123!') ? '✅' : '❌'}"

# 正規表現バリデーター
digit_validator = PasswordRules::RegexRuleValidator.digit
puts "\n数字バリデーター:"
puts "  'OnlyLetters' -> #{digit_validator.valid?('OnlyLetters') ? '✅' : '❌'}"
puts "  'WithNumber1' -> #{digit_validator.valid?('WithNumber1') ? '✅' : '❌'}"

# 複雑度バリデーター
complexity_validator = PasswordRules::ComplexityScoreValidator.strong
puts "\n複雑度バリデーター (強レベル):"
test_password = "ComplexPassword123!"
breakdown = complexity_validator.complexity_breakdown(test_password)
puts "  パスワード: #{test_password}"
puts "  スコア: #{breakdown[:total_score]}"
puts "  セキュリティレベル: #{breakdown[:security_level]}"
puts "  有効: #{breakdown[:meets_requirement] ? '✅' : '❌'}"

# ===============================================
# 例6: パフォーマンス測定
# ===============================================
puts "\n📋 例6: パフォーマンス測定"

class PerformanceUser
  include ActiveModel::Validations
  attr_accessor :password
  validates :password, password_strength_v2: { rule_set: :enterprise }
end

performance_user = PerformanceUser.new
test_password = "PerformanceTestPassword123!"

# 大量バリデーション実行
iterations = 10000
puts "#{iterations}回のバリデーション実行..."

start_time = Time.current
iterations.times do |i|
  performance_user.password = "#{test_password}#{i}"
  performance_user.valid?
end
end_time = Time.current

duration = end_time - start_time
avg_time = (duration / iterations * 1000000).round(2)  # マイクロ秒

puts "  実行時間: #{(duration * 1000).round(2)}ms"
puts "  平均時間: #{avg_time}μs/回"
puts "  スループット: #{(iterations / duration).round(0)}回/秒"

# ===============================================
# 例7: メモリ使用量測定
# ===============================================
puts "\n📋 例7: メモリ使用量測定"

GC.start
before_objects = ObjectSpace.count_objects

memory_user = PerformanceUser.new
5000.times do |i|
  memory_user.password = "MemoryTest#{i}Password123!"
  memory_user.valid?
end

GC.start
after_objects = ObjectSpace.count_objects

object_diff = after_objects[:T_OBJECT] - before_objects[:T_OBJECT]
puts "  オブジェクト増加数: #{object_diff}"
puts "  メモリ効率: #{object_diff < 100 ? '✅ 良好' : '⚠️ 要確認'}"

# ===============================================
# 例8: エラーハンドリングと国際化
# ===============================================
puts "\n📋 例8: エラーハンドリングと国際化"

class InternationalUser
  include ActiveModel::Validations
  attr_accessor :password
  validates :password, password_strength_v2: { rule_set: :standard }
end

international_passwords = [
  "パスワード123!",        # 日本語
  "Contraseña123!",       # スペイン語
  "Пароль123!",           # ロシア語
  "密码123!",             # 中国語
  "🔐SecurePass123!"     # 絵文字
]

international_user = InternationalUser.new
puts "国際化文字対応テスト:"
international_passwords.each do |password|
  international_user.password = password
  status = international_user.valid? ? "✅ 有効" : "❌ 無効"
  puts "  #{password.ljust(20)} -> #{status}"
end

# ===============================================
# 例9: 複数バリデーターの組み合わせ
# ===============================================
puts "\n📋 例9: 複数バリデーターの組み合わせ"

class MultiValidationUser
  include ActiveModel::Validations

  attr_accessor :password, :password_confirmation

  validates :password, password_strength_v2: { rule_set: :enterprise }
  validates :password, confirmation: true
  validates :password_confirmation, presence: true
end

multi_user = MultiValidationUser.new
multi_user.password = "StrongEnterprisePassword123!"
multi_user.password_confirmation = "StrongEnterprisePassword123!"

puts "パスワード強度 + 確認チェック:"
puts "  パスワード: #{multi_user.password}"
puts "  確認: #{multi_user.password_confirmation}"
puts "  バリデーション結果: #{multi_user.valid? ? '✅ 有効' : '❌ 無効'}"

# 確認パスワードが異なる場合
multi_user.password_confirmation = "DifferentPassword123!"
puts "\n確認パスワードが異なる場合:"
puts "  バリデーション結果: #{multi_user.valid? ? '✅ 有効' : '❌ 無効'}"
unless multi_user.valid?
  multi_user.errors.full_messages.each { |error| puts "    - #{error}" }
end

puts "\n" + "=" * 50
puts "🎉 デモ完了！分割されたバリデーターの柔軟性と性能をご確認ください。"
