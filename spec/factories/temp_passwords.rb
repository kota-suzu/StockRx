# frozen_string_literal: true

FactoryBot.define do
  factory :temp_password do
    # 関連付け
    store_user

    # 基本フィールド
    password_hash { BCrypt::Password.create("123456") }
    expires_at { 15.minutes.from_now }
    active { true }
    usage_attempts { 0 }

    # 監査・セキュリティ情報
    ip_address { "192.168.1.100" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }

    # ============================================
    # トレイト定義（状態別テストケース）
    # ============================================

    # 期限切れ
    trait :expired do
      after(:create) do |temp_password|
        temp_password.update_column(:expires_at, 1.hour.ago)
      end
    end

    # 使用済み
    trait :used do
      used_at { 5.minutes.ago }
    end

    # ロック状態（試行回数上限）
    trait :locked do
      usage_attempts { TempPassword::MAX_ATTEMPTS }
      last_attempt_at { 1.minute.ago }
    end

    # 非アクティブ（管理者により無効化）
    trait :inactive do
      active { false }
    end

    # 管理者により生成
    trait :admin_generated do
      generated_by_admin_id { "admin_#{rand(1000)}" }
    end

    # 長期有効（テスト用）
    trait :long_term do
      expires_at { 1.hour.from_now }
    end

    # 即期限切れ（テスト用）
    trait :about_to_expire do
      expires_at { 30.seconds.from_now }
    end

    # IPv6アドレス
    trait :ipv6 do
      ip_address { "2001:db8::1" }
    end

    # 複数回試行済み
    trait :multiple_attempts do
      usage_attempts { 3 }
      last_attempt_at { 2.minutes.ago }
    end

    # セキュリティ監査用（完全なメタデータ付き）
    trait :audit_complete do
      ip_address { "203.0.113.195" }
      user_agent { "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)" }
      generated_by_admin_id { "security_admin_001" }
    end

    # ============================================
    # 複合トレイト（実際のユースケース）
    # ============================================

    # 期限切れ + 使用済み
    trait :expired_and_used do
      used
      after(:create) do |temp_password|
        temp_password.update_column(:expires_at, 1.hour.ago)
      end
    end

    # ロック + 期限切れ
    trait :locked_and_expired do
      locked
      after(:create) do |temp_password|
        temp_password.update_column(:expires_at, 1.hour.ago)
      end
    end

    # 管理者生成 + 長期有効
    trait :admin_long_term do
      admin_generated
      long_term
    end

    # ============================================
    # 動的ファクトリ（実際のパスワード生成）
    # ============================================

    # 実際の平文パスワード付き（暗号化前）
    trait :with_plain_password do
      transient do
        plain_password { "12345678" }
      end

      after(:build) do |temp_password, evaluator|
        temp_password.plain_password = evaluator.plain_password
        temp_password.encrypt_password_if_changed
      end
    end

    # セキュアなランダムパスワード
    trait :secure_random do
      transient do
        plain_password { TempPassword.generate_secure_password }
      end

      after(:build) do |temp_password, evaluator|
        temp_password.plain_password = evaluator.plain_password
        temp_password.encrypt_password_if_changed
      end
    end

    # ============================================
    # データベース作成後のコールバック
    # ============================================

    # 作成後に関連データを設定
    after(:create) do |temp_password, evaluator|
      # 必要に応じて追加のセットアップ
    end
  end
end

# ============================================
# 使用例とベストプラクティス
# ============================================
#
# # 基本的な使用
# create(:temp_password)
#
# # 状態別テスト
# create(:temp_password, :expired)
# create(:temp_password, :used)
# create(:temp_password, :locked)
#
# # 複合状態
# create(:temp_password, :expired_and_used)
#
# # 実際のパスワード付き
# temp_pass = create(:temp_password, :with_plain_password, plain_password: "test123")
#
# # セキュアランダム
# create(:temp_password, :secure_random)
#
# # 完全な監査情報付き
# create(:temp_password, :audit_complete, :admin_generated)
# ============================================
