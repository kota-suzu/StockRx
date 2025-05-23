# frozen_string_literal: true

FactoryBot.define do
  factory :receipt do
    association :inventory
    quantity { 100 }
    source { "株式会社サンプル" }
    receipt_date { Date.current }
    receipt_status { :completed }
    batch_number { "BN#{SecureRandom.hex(4).upcase}" }
    purchase_order { "PO#{SecureRandom.hex(4).upcase}" }
    cost_per_unit { 800.0 }
    notes { "テスト入荷" }

    trait :expected do
      receipt_status { :expected }
    end

    trait :partial do
      receipt_status { :partial }
    end

    trait :rejected do
      receipt_status { :rejected }
    end
  end
end
