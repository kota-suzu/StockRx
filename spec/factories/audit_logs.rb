# frozen_string_literal: true

FactoryBot.define do
  factory :audit_log do
    association :auditable, factory: :inventory
    association :user, factory: :admin
    user_type { "Admin" }  # Fix: Add user_type for polymorphic association
    action { "create" }
    message { "リソースが作成されました" }
    details { { user: "admin@example.com", timestamp: Time.current }.to_json }
    ip_address { "127.0.0.1" }
    user_agent { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)" }

    # Action traits
    trait :create_action do
      action { "create" }
      message { "リソースが作成されました" }
    end

    trait :update_action do
      action { "update" }
      message { "リソースが更新されました" }
    end

    trait :delete_action do
      action { "delete" }
      message { "リソースが削除されました" }
    end

    trait :view_action do
      action { "view" }
      message { "リソースが閲覧されました" }
    end

    trait :export_action do
      action { "export" }
      message { "データがエクスポートされました" }
    end

    trait :import_action do
      action { "import" }
      message { "データがインポートされました" }
    end

    trait :login_action do
      action { "login" }
      message { "ユーザーがログインしました" }
    end

    trait :logout_action do
      action { "logout" }
      message { "ユーザーがログアウトしました" }
    end

    trait :security_event_action do
      action { "security_event" }
      message { "セキュリティイベントが発生しました" }
    end

    trait :permission_change_action do
      action { "permission_change" }
      message { "権限が変更されました" }
    end

    trait :password_change_action do
      action { "password_change" }
      message { "パスワードが変更されました" }
    end

    trait :failed_login_action do
      action { "failed_login" }
      message { "ログインに失敗しました" }
    end

    # Auditable traits
    trait :for_inventory do
      association :auditable, factory: :inventory
    end

    trait :for_admin do
      association :auditable, factory: :admin
    end

    trait :for_store do
      association :auditable, factory: :store
    end

    # System log (no user)
    trait :system do
      user { nil }
      user_type { nil }  # Fix: Clear user_type when no user
      message { "システムによる自動処理" }
    end

    # With detailed information
    trait :with_detailed_info do
      details do
        {
          before: { quantity: 100, price: 1000 },
          after: { quantity: 150, price: 1200 },
          changed_by: "admin@example.com",
          reason: "在庫調整",
          timestamp: Time.current.iso8601
        }.to_json
      end
    end

    # Old log for cleanup testing
    trait :old do
      created_at { 100.days.ago }
    end

    # Recent log
    trait :recent do
      created_at { 1.hour.ago }
    end
  end
end
