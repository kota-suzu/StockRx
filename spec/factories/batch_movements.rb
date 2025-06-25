# frozen_string_literal: true

FactoryBot.define do
  factory :batch_movement do
    batch
    store
    store_inventory { nil }
    quantity { 10 }
    movement_date { Date.today }

    trait :yesterday do
      movement_date { Date.yesterday }
    end

    trait :last_week do
      movement_date { 1.week.ago }
    end

    trait :future do
      movement_date { 1.week.from_now }
    end

    trait :small_quantity do
      quantity { 1 }
    end

    trait :large_quantity do
      quantity { 1000 }
    end

    trait :with_store_inventory do
      after(:build) do |movement|
        movement.store_inventory = create(:store_inventory,
          store: movement.store,
          inventory: movement.batch.inventory
        )
      end
    end
  end
end
