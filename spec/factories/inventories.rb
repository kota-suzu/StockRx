# frozen_string_literal: true

FactoryBot.define do
  factory :inventory do
    sequence(:name) { |n| "商品#{n}" }
    quantity { 100 }
    price { 1000 }
    status { 'active' }
    category { '処方薬' }
    unit { '錠' }
    minimum_stock { 10 }
  end
end
