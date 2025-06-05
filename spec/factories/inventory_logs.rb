# frozen_string_literal: true

FactoryBot.define do
  factory :inventory_log do
    association :inventory
    association :admin
    delta { 10 }
    operation_type { :add }
    previous_quantity { 90 }
    current_quantity { 100 }
    note { "テスト操作" }

    trait :remove_operation do
      operation_type { :remove }
      delta { -10 }
      previous_quantity { 100 }
      current_quantity { 90 }
      note { "テスト削除操作" }
    end

    trait :ship_operation do
      operation_type { :ship }
      delta { -20 }
      previous_quantity { 100 }
      current_quantity { 80 }
      note { "テスト出荷操作" }
      destination { "東京都渋谷区" }
    end

    trait :receive_operation do
      operation_type { :receive }
      delta { 50 }
      previous_quantity { 50 }
      current_quantity { 100 }
      note { "テスト入荷操作" }
      source { "テスト仕入先" }
    end

    trait :adjust_operation do
      operation_type { :adjust }
      delta { 5 }
      previous_quantity { 95 }
      current_quantity { 100 }
      note { "在庫調整" }
    end
  end
end
