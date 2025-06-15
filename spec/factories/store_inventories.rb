# frozen_string_literal: true

FactoryBot.define do
  factory :store_inventory do
    association :store
    association :inventory
    quantity { 100 }
    reserved_quantity { 0 }
    safety_stock_level { 10 }
    last_updated_at { Time.current }

    # 在庫状態別のファクトリ
    trait :out_of_stock do
      quantity { 0 }
      reserved_quantity { 0 }
    end

    trait :low_stock do
      quantity { 5 }
      safety_stock_level { 10 }
      reserved_quantity { 0 }
    end

    trait :critical_stock do
      quantity { 2 }
      safety_stock_level { 10 }
      reserved_quantity { 0 }
    end

    trait :optimal_stock do
      quantity { 20 }
      safety_stock_level { 10 }
      reserved_quantity { 0 }
    end

    trait :excess_stock do
      quantity { 100 }
      safety_stock_level { 10 }
      reserved_quantity { 0 }
    end

    # 予約在庫がある状態
    trait :with_reservation do
      quantity { 50 }
      reserved_quantity { 20 }
      safety_stock_level { 10 }
    end

    # 利用可能在庫なし（全て予約済み）
    trait :fully_reserved do
      quantity { 30 }
      reserved_quantity { 30 }
      safety_stock_level { 10 }
    end

    # 高額商品
    trait :high_value do
      association :inventory, :high_price
      quantity { 10 }
      safety_stock_level { 5 }
    end

    # 大量在庫
    trait :large_quantity do
      quantity { 1000 }
      reserved_quantity { 100 }
      safety_stock_level { 200 }
    end
  end
end
