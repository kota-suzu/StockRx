# frozen_string_literal: true

FactoryBot.define do
  factory :inventory do
    sequence(:name) { |n| "商品#{n}" }
    quantity { 100 }
    price { 1000 }
    status { 'active' }

    # 価格別のファクトリ
    trait :low_price do
      price { 500 }
    end

    trait :high_price do
      price { 5000 }
    end

    trait :premium_price do
      price { 10000 }
    end

    # ステータス別のファクトリ
    trait :archived do
      status { 'archived' }
    end

    # 特定の商品カテゴリ
    trait :medicine do
      sequence(:name) { |n| "薬品#{n}" }
      price { 2000 }
    end

    trait :supplement do
      sequence(:name) { |n| "サプリメント#{n}" }
      price { 1500 }
    end

    trait :medical_device do
      sequence(:name) { |n| "医療機器#{n}" }
      price { 8000 }
    end

    # バッチ付きの商品
    trait :with_batches do
      transient do
        batches_count { 2 }
      end

      after(:create) do |inventory, evaluator|
        create_list(:batch, evaluator.batches_count, inventory: inventory)
      end
    end

    # 店舗在庫付きの商品
    trait :with_store_inventories do
      transient do
        stores_count { 3 }
      end

      after(:create) do |inventory, evaluator|
        stores = create_list(:store, evaluator.stores_count)
        stores.each do |store|
          create(:store_inventory, store: store, inventory: inventory)
        end
      end
    end
  end
end
