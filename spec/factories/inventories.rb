# frozen_string_literal: true

FactoryBot.define do
  factory :inventory do
    sequence(:name) { |n| "商品#{n}" }
    quantity { 100 }
    price { 1000 }
    status { 'active' }
  end
end
