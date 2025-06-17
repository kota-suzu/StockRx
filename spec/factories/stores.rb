# frozen_string_literal: true

FactoryBot.define do
  factory :store do
    sequence(:name) { |n| "薬局#{n}" }
    sequence(:code) { |n| "ST#{(Time.current.to_i + n).to_s[-6, 6]}" }
    sequence(:slug) { |n| "st#{(Time.current.to_i + n).to_s[-6, 6]}".downcase }
    store_type { 'pharmacy' }
    region { '東京都' }
    address { '東京都港区赤坂1-1-1' }
    phone { '03-1234-5678' }
    sequence(:email) { |n| "store#{n}@example.com" }
    manager_name { '店舗責任者' }
    active { true }

    # 特定の店舗タイプのファクトリ
    trait :pharmacy do
      store_type { 'pharmacy' }
      sequence(:name) { |n| "#{n}番薬局" }
    end

    trait :warehouse do
      store_type { 'warehouse' }
      sequence(:name) { |n| "倉庫#{n}" }
      manager_name { '倉庫管理者' }
    end

    trait :headquarters do
      store_type { 'headquarters' }
      name { '本部' }
      sequence(:code) { |n| "HQ#{(Time.current.to_i + n).to_s[-6, 6]}" }
      manager_name { '本部長' }
    end

    # 非アクティブ店舗
    trait :inactive do
      active { false }
    end

    # 在庫付きの店舗
    trait :with_inventories do
      transient do
        inventories_count { 3 }
      end

      after(:create) do |store, evaluator|
        inventories = create_list(:inventory, evaluator.inventories_count)
        inventories.each do |inventory|
          create(:store_inventory, store: store, inventory: inventory)
        end
      end
    end

    # Phase 3: パフォーマンステスト用 - 在庫・管理者付きの店舗
    trait :with_inventories_and_admins do
      transient do
        inventories_count { 5 }
        admins_count { 2 }
      end

      after(:create) do |store, evaluator|
        # 在庫データ作成
        inventories = create_list(:inventory, evaluator.inventories_count)
        inventories.each do |inventory|
          create(:store_inventory, store: store, inventory: inventory,
                 quantity: rand(10..100), safety_stock_level: rand(5..20))
        end

        # 管理者作成
        create_list(:admin, evaluator.admins_count, :with_specific_store, 
                   target_store: store)

        # Counter Cacheの更新（必要に応じて）
        store.reload
      end
    end

    # 東京地域の店舗
    trait :tokyo do
      region { '東京都' }
      address { '東京都港区赤坂1-1-1' }
    end

    # 大阪地域の店舗
    trait :osaka do
      region { '大阪府' }
      address { '大阪府大阪市中央区1-1-1' }
    end
  end
end
