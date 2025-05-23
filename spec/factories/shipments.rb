# frozen_string_literal: true

FactoryBot.define do
  factory :shipment do
    association :inventory
    quantity { 50 }
    destination { "東京都渋谷区" }
    scheduled_date { Date.current + 1.day }
    shipment_status { :pending }
    carrier { "ヤマト運輸" }
    tracking_number { "TN#{SecureRandom.hex(6).upcase}" }
    notes { "テスト出荷" }

    trait :shipped do
      shipment_status { :shipped }
    end

    trait :delivered do
      shipment_status { :delivered }
    end

    trait :cancelled do
      shipment_status { :cancelled }
    end
  end
end
