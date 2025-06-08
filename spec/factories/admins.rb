# frozen_string_literal: true

FactoryBot.define do
  factory :admin do
    sequence(:email) { |n| "admin-#{SecureRandom.hex(4)}-#{n}@example.com" }
    password { "Password1234!" }
    password_confirmation { "Password1234!" }
  end
end
