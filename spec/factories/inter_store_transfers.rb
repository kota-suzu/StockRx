# frozen_string_literal: true

FactoryBot.define do
  factory :inter_store_transfer do
    association :source_store, factory: :store
    association :destination_store, factory: :store
    association :inventory
    # ポリモーフィック関連付け：デフォルトはAdmin、traitでStoreUserも対応
    # メタ認知: テスト時にAdminとStoreUserの両方のケースをカバー
    association :requested_by, factory: :admin
    quantity { 10 }
    status { 'pending' }
    priority { 'normal' }
    reason { '在庫不足のため移動が必要です' }
    requested_at { Time.current }

    # 移動元に十分な在庫を事前に作成
    before(:create) do |transfer|
      # 移動元店舗に在庫を作成または更新
      store_inventory = StoreInventory.find_or_initialize_by(
        store: transfer.source_store,
        inventory: transfer.inventory
      )

      # 新規作成の場合のみデフォルト値を設定
      if store_inventory.new_record?
        store_inventory.assign_attributes(
          quantity: transfer.quantity + 20,
          reserved_quantity: 0,
          safety_stock_level: 5
        )
      else
        # 既存レコードの場合は在庫量のみ確保
        if store_inventory.quantity < transfer.quantity
          store_inventory.quantity = transfer.quantity + 20
        end
      end

      store_inventory.save!
    end

    # ステータス別のファクトリ
    trait :pending do
      status { 'pending' }
      approved_by { nil }
      approved_at { nil }
      completed_at { nil }
    end

    trait :approved do
      status { 'approved' }
      association :approved_by, factory: :admin
      approved_at { 1.hour.ago }
      completed_at { nil }
    end

    trait :rejected do
      status { 'rejected' }
      association :approved_by, factory: :admin
      approved_at { 1.hour.ago }
      reason { "在庫不足のため移動が必要です\n\n【却下理由】\n他の手段で対応済み" }
      completed_at { nil }
    end

    trait :in_transit do
      status { 'in_transit' }
      association :approved_by, factory: :admin
      approved_at { 2.hours.ago }
      completed_at { nil }
    end

    trait :completed do
      status { 'completed' }
      association :approved_by, factory: :admin
      approved_at { 3.hours.ago }
      completed_at { 1.hour.ago }
    end

    trait :cancelled do
      status { 'cancelled' }
      completed_at { 1.hour.ago }
    end

    # 優先度別のファクトリ
    trait :urgent do
      priority { 'urgent' }
      reason { '緊急：患者からの要求により即座の移動が必要' }
    end

    trait :emergency do
      priority { 'emergency' }
      reason { '非常時：災害対応のため緊急移動' }
    end

    # 数量別のファクトリ
    trait :small_quantity do
      quantity { 5 }
    end

    trait :large_quantity do
      quantity { 100 }
    end

    # 完全なワークフローを持つファクトリ
    trait :full_workflow do
      association :source_store, :with_inventories, factory: :store
      association :destination_store, factory: :store
      association :requested_by, :store_manager, factory: :admin
      association :approved_by, :headquarters_admin, factory: :admin

      transient do
        workflow_status { 'completed' }
      end

      after(:create) do |transfer, evaluator|
        # 移動元に十分な在庫を設定
        create(:store_inventory,
               store: transfer.source_store,
               inventory: transfer.inventory,
               quantity: transfer.quantity + 50,
               reserved_quantity: transfer.quantity)

        # ワークフローのステータスに応じて日時を設定
        case evaluator.workflow_status
        when 'approved'
          transfer.update!(
            status: 'approved',
            approved_at: 1.hour.ago
          )
        when 'completed'
          transfer.update!(
            status: 'completed',
            approved_at: 2.hours.ago,
            completed_at: 1.hour.ago
          )
        end
      end
    end

    # 薬局間の移動（一般的なケース）
    trait :pharmacy_to_pharmacy do
      association :source_store, :pharmacy, factory: :store
      association :destination_store, :pharmacy, factory: :store
    end

    # 倉庫から薬局への移動
    trait :warehouse_to_pharmacy do
      association :source_store, :warehouse, factory: :store
      association :destination_store, :pharmacy, factory: :store
      quantity { 50 }
      reason { '倉庫から薬局への定期補充' }
    end

    # 地域間の移動
    trait :cross_region do
      association :source_store, :tokyo, factory: :store
      association :destination_store, :osaka, factory: :store
      reason { '地域間での在庫調整' }
    end

    # ポリモーフィック関連付けのテスト用trait
    # TODO: 🟡 Phase 5（重要）- StoreUserとAdminの権限テスト拡張
    #   - StoreUserによる申請・承認テストケース
    #   - 権限ベースのアクセス制御テスト
    #   - 横展開: 他のポリモーフィック関連付けでも同様のパターン適用
    trait :requested_by_store_user do
      association :requested_by, factory: :store_user
    end

    trait :approved_by_store_user do
      association :approved_by, factory: :store_user
    end

    trait :full_store_user_workflow do
      association :source_store, factory: :store
      association :destination_store, factory: :store
      association :requested_by, factory: :store_user
      association :approved_by, factory: :store_user

      after(:create) do |transfer|
        # StoreUserの店舗に在庫を確保
        create(:store_inventory,
               store: transfer.requested_by.store,
               inventory: transfer.inventory,
               quantity: transfer.quantity + 30,
               reserved_quantity: 0)
      end
    end
  end
end
