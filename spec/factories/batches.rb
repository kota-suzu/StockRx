# frozen_string_literal: true

FactoryBot.define do
  factory :batch do
    association :inventory
    sequence(:lot_code) { |n| "LOT#{SecureRandom.hex(3).upcase}#{n}" }
    quantity { 50 }
    expires_on { 6.months.from_now }
    initial_quantity { quantity }

    trait :expired do
      expires_on { 1.day.ago }

      # Override factory to skip validation for expired batches
      after(:build) do |batch|
        def batch.new_record?
          false  # Pretend it's not a new record to skip validation
        end
      end
    end

    trait :expiring_soon do
      expires_on { 15.days.from_now }
    end

    trait :no_expiry do
      expires_on { nil }
    end
  end
end
