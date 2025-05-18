FactoryBot.define do
  factory :inventory_log do
    inventory { nil }
    delta { 1 }
    operation_type { "MyString" }
    previous_quantity { 1 }
    current_quantity { 1 }
    note { "MyText" }
  end
end
