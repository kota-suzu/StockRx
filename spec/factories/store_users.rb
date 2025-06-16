# frozen_string_literal: true

FactoryBot.define do
  factory :store_user do
    store
    sequence(:email) { |n| "store_user_#{n}@example.com" }
    name { "#{Faker::Name.first_name} #{Faker::Name.last_name}" }
    password { "SecureP@ssw0rd123!" }  # パスワードポリシー準拠
    password_confirmation { "SecureP@ssw0rd123!" }
    role { "staff" }
    active { true }
    sequence(:employee_code) { |n| "EMP#{n.to_s.rjust(5, '0')}" }

    # Deviseトラッキングフィールド
    sign_in_count { 0 }
    failed_attempts { 0 }

    # トレイト定義
    trait :manager do
      role { "manager" }
    end

    trait :inactive do
      active { false }
    end

    trait :locked do
      locked_at { 1.hour.ago }
      failed_attempts { 5 }
    end

    trait :password_expired do
      password_changed_at { 91.days.ago }
    end

    trait :must_change_password do
      must_change_password { true }
    end

    trait :with_login_history do
      sign_in_count { 10 }
      current_sign_in_at { 1.hour.ago }
      last_sign_in_at { 1.day.ago }
      current_sign_in_ip { "192.168.1.100" }
      last_sign_in_ip { "192.168.1.99" }
    end
  end
end
