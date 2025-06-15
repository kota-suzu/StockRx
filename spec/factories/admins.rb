# frozen_string_literal: true

FactoryBot.define do
  factory :admin do
    sequence(:email) { |n| "admin-#{SecureRandom.hex(4)}-#{n}@example.com" }
    password { "Password1234!" }
    password_confirmation { "Password1234!" }
    role { 'store_user' }
    sequence(:name) { |n| "管理者#{n}" }
    active { true }
    association :store, factory: :store

    # 役割別のファクトリ
    trait :store_user do
      role { 'store_user' }
      association :store, :pharmacy, factory: :store
    end

    trait :pharmacist do
      role { 'pharmacist' }
      sequence(:name) { |n| "薬剤師#{n}" }
      association :store, :pharmacy, factory: :store
    end

    trait :store_manager do
      role { 'store_manager' }
      sequence(:name) { |n| "店舗管理者#{n}" }
      association :store, :pharmacy, factory: :store
    end

    trait :headquarters_admin do
      role { 'headquarters_admin' }
      sequence(:name) { |n| "本部管理者#{n}" }
      store { nil }
    end

    # 非アクティブユーザー
    trait :inactive do
      active { false }
    end

    # GitHubソーシャルログインユーザー
    trait :github_user do
      provider { 'github' }
      sequence(:uid) { |n| "github_#{n}" }
      password { nil }
      password_confirmation { nil }
    end

    # 特定の店舗に所属
    trait :with_specific_store do
      transient do
        target_store { nil }
      end

      after(:build) do |admin, evaluator|
        admin.store = evaluator.target_store if evaluator.target_store
      end
    end
  end
end
