# frozen_string_literal: true

FactoryBot.define do
  factory :batch do
    association :inventory
    sequence(:lot_code) { |n| "LOT#{n.to_s.rjust(4, '0')}" }
    quantity { 50 }
    expires_on { 6.months.from_now }
  end
end
