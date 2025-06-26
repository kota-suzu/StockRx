# frozen_string_literal: true

FactoryBot.define do
  factory :webhook_endpoint do
    sequence(:url) { |n| "https://customer#{n}.example.com/webhook" }
    events { [ "inventory.created" ] }
    active { true }

    # 関連付け（実際のモデルに合わせて調整が必要）
    # association :admin

    trait :inactive do
      active { false }
    end

    trait :all_events do
      events { [ "inventory.created", "inventory.updated", "inventory.deleted" ] }
    end

    trait :with_secret do
      after(:build) do |webhook|
        webhook.secret = SecureRandom.hex(32)
      end
    end
  end
end
