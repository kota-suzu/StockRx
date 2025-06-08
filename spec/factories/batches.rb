# frozen_string_literal: true

FactoryBot.define do
  factory :batch do
    association :inventory
    sequence(:lot_code) { |n| "LOT#{SecureRandom.hex(3).upcase}#{n}" }
    quantity { 50 }
    expires_on { 6.months.from_now }
  end
end
