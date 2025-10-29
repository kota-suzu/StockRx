# frozen_string_literal: true

FactoryBot.define do
  factory :admin_notification_setting do
    association :admin

    notification_type { :stock_alert }
    delivery_method { :email }
    enabled { true }
    priority { :medium }
    frequency_minutes { nil }
    sent_count { 0 }
    last_sent_at { nil }
    active_from { nil }
    active_until { nil }

    trait :csv_import do
      notification_type { :csv_import }
    end

    trait :security_alert do
      notification_type { :security_alert }
      priority { :critical }
    end

    trait :disabled do
      enabled { false }
    end

    trait :with_frequency_limit do
      frequency_minutes { 30 }
    end

    trait :recently_sent do
      last_sent_at { 10.minutes.ago }
      sent_count { 5 }
    end

    trait :actioncable do
      delivery_method { :actioncable }
    end

    trait :slack do
      delivery_method { :slack }
    end

    trait :critical_priority do
      priority { :critical }
    end

    trait :with_active_period do
      active_from { 1.hour.ago }
      active_until { 1.hour.from_now }
    end

    trait :expired_period do
      active_from { 2.hours.ago }
      active_until { 1.hour.ago }
    end
  end
end
