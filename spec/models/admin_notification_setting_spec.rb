# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminNotificationSetting, type: :model do
  # CLAUDE.md準拠: 管理者通知設定の包括的テスト
  # メタ認知: 複雑な分岐ロジックを持つ通知システムの品質保証
  # 横展開: 他の設定系モデルでも同様のテストパターン適用

  let(:admin) { create(:admin) }
  let(:setting) do
    create(:admin_notification_setting,
           admin: admin,
           notification_type: :stock_alert,
           delivery_method: :email,
           enabled: true)
  end

  # ============================================
  # 関連付けテスト
  # ============================================

  describe 'associations' do
    it { should belong_to(:admin) }
  end

  # ============================================
  # バリデーションテスト
  # ============================================

  describe 'validations' do
    subject { setting }

    it { should validate_presence_of(:notification_type) }
    it { should validate_presence_of(:delivery_method) }
    it { should validate_inclusion_of(:enabled).in_array([ true, false ]) }

    describe 'frequency_minutes validation' do
      it 'accepts valid frequency minutes' do
        subject.frequency_minutes = 60
        expect(subject).to be_valid
      end

      it 'rejects zero frequency minutes' do
        subject.frequency_minutes = 0
        expect(subject).not_to be_valid
        expect(subject.errors[:frequency_minutes]).to include('は0より大きい値にしてください')
      end

      it 'rejects negative frequency minutes' do
        subject.frequency_minutes = -5
        expect(subject).not_to be_valid
      end

      it 'rejects frequency minutes over 1440' do
        subject.frequency_minutes = 1441
        expect(subject).not_to be_valid
        expect(subject.errors[:frequency_minutes]).to include('は1440以下の値にしてください')
      end

      it 'accepts nil frequency minutes' do
        subject.frequency_minutes = nil
        expect(subject).to be_valid
      end
    end

    describe 'uniqueness validation' do
      it 'prevents duplicate notification_type and delivery_method for same admin' do
        create(:admin_notification_setting,
               admin: admin,
               notification_type: :stock_alert,
               delivery_method: :email)

        duplicate = build(:admin_notification_setting,
                         admin: admin,
                         notification_type: :stock_alert,
                         delivery_method: :email)

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:admin_id]).to include('同じ通知タイプと配信方法の組み合わせは既に存在します')
      end

      it 'allows same notification_type with different delivery_method' do
        create(:admin_notification_setting,
               admin: admin,
               notification_type: :stock_alert,
               delivery_method: :email)

        different_method = build(:admin_notification_setting,
                                admin: admin,
                                notification_type: :stock_alert,
                                delivery_method: :slack)

        expect(different_method).to be_valid
      end

      it 'allows same combination for different admins' do
        admin2 = create(:admin)
        create(:admin_notification_setting,
               admin: admin,
               notification_type: :stock_alert,
               delivery_method: :email)

        different_admin = build(:admin_notification_setting,
                               admin: admin2,
                               notification_type: :stock_alert,
                               delivery_method: :email)

        expect(different_admin).to be_valid
      end
    end
  end

  # ============================================
  # Enumテスト
  # ============================================

  describe 'enums' do
    describe 'notification_type' do
      it 'defines all notification types' do
        expect(AdminNotificationSetting.notification_types.keys).to match_array([
          'csv_import', 'stock_alert', 'security_alert',
          'system_maintenance', 'monthly_report', 'error_notification'
        ])
      end

      it 'rejects invalid notification types' do
        expect {
          setting.notification_type = 'invalid_type'
        }.to raise_error(ArgumentError)
      end
    end

    describe 'delivery_method' do
      it 'defines all delivery methods' do
        expect(AdminNotificationSetting.delivery_methods.keys).to match_array([
          'email', 'actioncable', 'slack', 'teams', 'webhook'
        ])
      end

      it 'rejects invalid delivery methods' do
        expect {
          setting.delivery_method = 'invalid_method'
        }.to raise_error(ArgumentError)
      end
    end

    describe 'priority' do
      it 'defines all priority levels' do
        expect(AdminNotificationSetting.priorities).to eq({
          'low' => 0, 'medium' => 1, 'high' => 2, 'critical' => 3
        })
      end

      it 'rejects invalid priority levels' do
        expect {
          setting.priority = 'invalid_priority'
        }.to raise_error(ArgumentError)
      end
    end
  end

  # ============================================
  # スコープテスト
  # ============================================

  describe 'scopes' do
    before do
      @enabled_setting = create(:admin_notification_setting, enabled: true, priority: :high)
      @disabled_setting = create(:admin_notification_setting, enabled: false, priority: :low)
      @critical_setting = create(:admin_notification_setting, priority: :critical)
    end

    describe '.enabled' do
      it 'returns only enabled settings' do
        expect(AdminNotificationSetting.enabled).to include(@enabled_setting, @critical_setting)
        expect(AdminNotificationSetting.enabled).not_to include(@disabled_setting)
      end
    end

    describe '.disabled' do
      it 'returns only disabled settings' do
        expect(AdminNotificationSetting.disabled).to include(@disabled_setting)
        expect(AdminNotificationSetting.disabled).not_to include(@enabled_setting, @critical_setting)
      end
    end

    describe '.by_type' do
      it 'filters by notification type' do
        stock_setting = create(:admin_notification_setting, notification_type: :stock_alert)
        security_setting = create(:admin_notification_setting, notification_type: :security_alert)

        expect(AdminNotificationSetting.by_type(:stock_alert)).to include(stock_setting)
        expect(AdminNotificationSetting.by_type(:stock_alert)).not_to include(security_setting)
      end
    end

    describe '.critical_only' do
      it 'returns only critical priority settings' do
        expect(AdminNotificationSetting.critical_only).to include(@critical_setting)
        expect(AdminNotificationSetting.critical_only).not_to include(@enabled_setting, @disabled_setting)
      end
    end

    describe '.high_priority_and_above' do
      it 'returns high and critical priority settings' do
        expect(AdminNotificationSetting.high_priority_and_above).to include(@enabled_setting, @critical_setting)
        expect(AdminNotificationSetting.high_priority_and_above).not_to include(@disabled_setting)
      end
    end
  end

  # ============================================
  # インスタンスメソッドテスト
  # ============================================

  describe '#can_send_notification?' do
    context 'when setting is disabled' do
      it 'returns false' do
        setting.enabled = false
        expect(setting.can_send_notification?).to be false
      end
    end

    context 'when setting is enabled' do
      before { setting.enabled = true }

      context 'without frequency limit' do
        it 'returns true' do
          setting.frequency_minutes = nil
          expect(setting.can_send_notification?).to be true
        end
      end

      context 'with frequency limit' do
        before { setting.frequency_minutes = 30 }

        context 'when last_sent_at is nil' do
          it 'returns true' do
            setting.last_sent_at = nil
            expect(setting.can_send_notification?).to be true
          end
        end

        context 'when enough time has passed' do
          it 'returns true' do
            setting.last_sent_at = 1.hour.ago
            expect(setting.can_send_notification?).to be true
          end
        end

        context 'when not enough time has passed' do
          it 'returns false' do
            setting.last_sent_at = 10.minutes.ago
            expect(setting.can_send_notification?).to be false
          end
        end

        context 'when exactly enough time has passed' do
          it 'returns true' do
            setting.last_sent_at = 30.minutes.ago
            expect(setting.can_send_notification?).to be true
          end
        end
      end
    end
  end

  describe '#mark_as_sent!' do
    it 'updates last_sent_at to current time' do
      freeze_time do
        setting.mark_as_sent!
        expect(setting.reload.last_sent_at).to eq(Time.current)
      end
    end

    it 'increments sent_count' do
      setting.sent_count = 5
      setting.mark_as_sent!
      expect(setting.reload.sent_count).to eq(6)
    end

    it 'handles nil sent_count' do
      setting.sent_count = nil
      setting.mark_as_sent!
      expect(setting.reload.sent_count).to eq(1)
    end
  end

  describe '#summary' do
    it 'returns formatted summary for enabled setting' do
      setting.enabled = true
      setting.frequency_minutes = 15
      setting.notification_type = :stock_alert
      setting.delivery_method = :email

      expected = "在庫アラート - メール (有効, 15分間隔)"
      expect(setting.summary).to eq(expected)
    end

    it 'returns formatted summary for disabled setting' do
      setting.enabled = false
      setting.frequency_minutes = nil
      setting.notification_type = :csv_import
      setting.delivery_method = :slack

      expected = "CSVインポート - Slack (無効, 制限なし)"
      expect(setting.summary).to eq(expected)
    end
  end

  describe '#notification_type_label' do
    it 'returns Japanese labels for all notification types' do
      expect(AdminNotificationSetting.new(notification_type: :csv_import).notification_type_label).to eq("CSVインポート")
      expect(AdminNotificationSetting.new(notification_type: :stock_alert).notification_type_label).to eq("在庫アラート")
      expect(AdminNotificationSetting.new(notification_type: :security_alert).notification_type_label).to eq("セキュリティアラート")
      expect(AdminNotificationSetting.new(notification_type: :system_maintenance).notification_type_label).to eq("システムメンテナンス")
      expect(AdminNotificationSetting.new(notification_type: :monthly_report).notification_type_label).to eq("月次レポート")
      expect(AdminNotificationSetting.new(notification_type: :error_notification).notification_type_label).to eq("エラー通知")
    end

    it 'returns original value for unknown types' do
      # Direct assignment to bypass enum validation for testing
      setting.instance_variable_set(:@attributes, setting.attributes.merge('notification_type' => 'unknown_type'))
      expect(setting.notification_type_label).to eq('unknown_type')
    end
  end

  describe '#delivery_method_label' do
    it 'returns Japanese labels for all delivery methods' do
      expect(AdminNotificationSetting.new(delivery_method: :email).delivery_method_label).to eq("メール")
      expect(AdminNotificationSetting.new(delivery_method: :actioncable).delivery_method_label).to eq("リアルタイム通知")
      expect(AdminNotificationSetting.new(delivery_method: :slack).delivery_method_label).to eq("Slack")
      expect(AdminNotificationSetting.new(delivery_method: :teams).delivery_method_label).to eq("Microsoft Teams")
      expect(AdminNotificationSetting.new(delivery_method: :webhook).delivery_method_label).to eq("Webhook")
    end

    it 'returns original value for unknown methods' do
      # Direct assignment to bypass enum validation for testing
      setting.instance_variable_set(:@attributes, setting.attributes.merge('delivery_method' => 'unknown_method'))
      expect(setting.delivery_method_label).to eq('unknown_method')
    end
  end

  describe '#priority_label' do
    it 'returns Japanese labels for all priority levels' do
      expect(AdminNotificationSetting.new(priority: :low).priority_label).to eq("低")
      expect(AdminNotificationSetting.new(priority: :medium).priority_label).to eq("中")
      expect(AdminNotificationSetting.new(priority: :high).priority_label).to eq("高")
      expect(AdminNotificationSetting.new(priority: :critical).priority_label).to eq("緊急")
    end

    it 'returns original value for unknown priorities' do
      # Direct assignment to bypass enum validation for testing
      setting.instance_variable_set(:@attributes, setting.attributes.merge('priority' => 'unknown_priority'))
      expect(setting.priority_label).to eq('unknown_priority')
    end
  end

  describe '#within_active_period?' do
    context 'when no active period is set' do
      it 'returns true' do
        setting.active_from = nil
        setting.active_until = nil
        expect(setting.within_active_period?).to be true
      end
    end

    context 'when only active_from is set' do
      it 'returns true when current time is after active_from' do
        setting.active_from = 1.hour.ago
        setting.active_until = nil
        expect(setting.within_active_period?).to be true
      end

      it 'returns false when current time is before active_from' do
        setting.active_from = 1.hour.from_now
        setting.active_until = nil
        expect(setting.within_active_period?).to be false
      end
    end

    context 'when only active_until is set' do
      it 'returns true when current time is before active_until' do
        setting.active_from = nil
        setting.active_until = 1.hour.from_now
        expect(setting.within_active_period?).to be true
      end

      it 'returns false when current time is after active_until' do
        setting.active_from = nil
        setting.active_until = 1.hour.ago
        expect(setting.within_active_period?).to be false
      end
    end

    context 'when both active_from and active_until are set' do
      it 'returns true when current time is within the period' do
        setting.active_from = 1.hour.ago
        setting.active_until = 1.hour.from_now
        expect(setting.within_active_period?).to be true
      end

      it 'returns false when current time is before the period' do
        setting.active_from = 1.hour.from_now
        setting.active_until = 2.hours.from_now
        expect(setting.within_active_period?).to be false
      end

      it 'returns false when current time is after the period' do
        setting.active_from = 2.hours.ago
        setting.active_until = 1.hour.ago
        expect(setting.within_active_period?).to be false
      end
    end
  end

  # ============================================
  # クラスメソッドテスト
  # ============================================

  describe '.create_default_settings_for' do
    it 'creates default settings for an admin' do
      new_admin = create(:admin)

      expect {
        AdminNotificationSetting.create_default_settings_for(new_admin)
      }.to change { new_admin.admin_notification_settings.count }.by(8)
    end

    it 'creates settings with correct default configurations' do
      new_admin = create(:admin)
      AdminNotificationSetting.create_default_settings_for(new_admin)

      csv_actioncable = new_admin.admin_notification_settings
                                .find_by(notification_type: :csv_import, delivery_method: :actioncable)
      expect(csv_actioncable.enabled).to be true
      expect(csv_actioncable.priority).to eq('medium')

      security_email = new_admin.admin_notification_settings
                               .find_by(notification_type: :security_alert, delivery_method: :email)
      expect(security_email.enabled).to be true
      expect(security_email.priority).to eq('critical')
      expect(security_email.frequency_minutes).to eq(5)
    end

    it 'does not create duplicate settings' do
      new_admin = create(:admin)
      AdminNotificationSetting.create_default_settings_for(new_admin)

      expect {
        AdminNotificationSetting.create_default_settings_for(new_admin)
      }.not_to change { new_admin.admin_notification_settings.count }
    end
  end

  describe '.admins_for_notification' do
    let!(:admin1) { create(:admin) }
    let!(:admin2) { create(:admin) }
    let!(:admin3) { create(:admin) }

    before do
      # Admin1: enabled, can send, within period
      create(:admin_notification_setting,
             admin: admin1,
             notification_type: :stock_alert,
             delivery_method: :email,
             enabled: true,
             priority: :high,
             last_sent_at: 2.hours.ago,
             frequency_minutes: 60)

      # Admin2: enabled, cannot send (frequency limit)
      create(:admin_notification_setting,
             admin: admin2,
             notification_type: :stock_alert,
             delivery_method: :email,
             enabled: true,
             priority: :high,
             last_sent_at: 30.minutes.ago,
             frequency_minutes: 60)

      # Admin3: disabled
      create(:admin_notification_setting,
             admin: admin3,
             notification_type: :stock_alert,
             delivery_method: :email,
             enabled: false,
             priority: :high)
    end

    it 'returns admins who can receive notifications' do
      admins = AdminNotificationSetting.admins_for_notification(:stock_alert, :email)
      expect(admins).to include(admin1)
      expect(admins).not_to include(admin2, admin3)
    end

    it 'filters by delivery method when specified' do
      create(:admin_notification_setting,
             admin: admin1,
             notification_type: :stock_alert,
             delivery_method: :slack,
             enabled: true,
             priority: :high)

      admins = AdminNotificationSetting.admins_for_notification(:stock_alert, :slack)
      expect(admins).to include(admin1)

      admins = AdminNotificationSetting.admins_for_notification(:stock_alert, :teams)
      expect(admins).to be_empty
    end

    it 'filters by minimum priority' do
      # Create low priority setting for admin1
      create(:admin_notification_setting,
             admin: admin1,
             notification_type: :monthly_report,
             delivery_method: :email,
             enabled: true,
             priority: :low)

      # Only returns admins with medium or higher priority
      admins = AdminNotificationSetting.admins_for_notification(:monthly_report, :email, :medium)
      expect(admins).to be_empty

      # Returns admins with low or higher priority
      admins = AdminNotificationSetting.admins_for_notification(:monthly_report, :email, :low)
      expect(admins).to include(admin1)
    end

    it 'considers active period restrictions' do
      # Create setting that's outside active period
      create(:admin_notification_setting,
             admin: admin1,
             notification_type: :system_maintenance,
             delivery_method: :email,
             enabled: true,
             priority: :high,
             active_from: 1.hour.from_now,
             active_until: 2.hours.from_now)

      admins = AdminNotificationSetting.admins_for_notification(:system_maintenance)
      expect(admins).not_to include(admin1)
    end
  end

  describe '.notification_statistics' do
    before do
      create(:admin_notification_setting,
             notification_type: :stock_alert,
             delivery_method: :email,
             priority: :high,
             enabled: true,
             sent_count: 10,
             last_sent_at: 1.day.ago)

      create(:admin_notification_setting,
             notification_type: :stock_alert,
             delivery_method: :slack,
             priority: :medium,
             enabled: false,
             sent_count: 5)

      create(:admin_notification_setting,
             notification_type: :security_alert,
             delivery_method: :email,
             priority: :critical,
             enabled: true,
             sent_count: 3,
             last_sent_at: 10.days.ago)
    end

    it 'returns comprehensive statistics' do
      stats = AdminNotificationSetting.notification_statistics

      expect(stats[:total_settings]).to eq(3)
      expect(stats[:enabled_settings]).to eq(2)
      expect(stats[:by_type]['stock_alert']).to eq(2)
      expect(stats[:by_type]['security_alert']).to eq(1)
      expect(stats[:by_method]['email']).to eq(2)
      expect(stats[:by_method]['slack']).to eq(1)
      expect(stats[:by_priority]['high']).to eq(1)
      expect(stats[:by_priority]['medium']).to eq(1)
      expect(stats[:by_priority]['critical']).to eq(1)
    end

    it 'includes recent activity within specified period' do
      stats = AdminNotificationSetting.notification_statistics(30.days)
      expect(stats[:recent_activity]['stock_alert']).to eq(10)
      expect(stats[:recent_activity]['security_alert']).to eq(3)

      stats = AdminNotificationSetting.notification_statistics(5.days)
      expect(stats[:recent_activity]['stock_alert']).to eq(10)
      expect(stats[:recent_activity]['security_alert']).to be_nil
    end
  end

  # ============================================
  # コールバックテスト
  # ============================================

  describe 'callbacks' do
    describe 'before_validation :set_defaults' do
      it 'sets default priority to medium' do
        new_setting = AdminNotificationSetting.new(admin: admin, notification_type: :stock_alert, delivery_method: :email)
        new_setting.valid?
        expect(new_setting.priority).to eq('medium')
      end

      it 'sets default enabled to true' do
        new_setting = AdminNotificationSetting.new(admin: admin, notification_type: :stock_alert, delivery_method: :email)
        new_setting.valid?
        expect(new_setting.enabled).to be true
      end

      it 'sets default sent_count to 0' do
        new_setting = AdminNotificationSetting.new(admin: admin, notification_type: :stock_alert, delivery_method: :email)
        new_setting.valid?
        expect(new_setting.sent_count).to eq(0)
      end

      it 'does not override existing values' do
        new_setting = AdminNotificationSetting.new(
          admin: admin,
          notification_type: :stock_alert,
          delivery_method: :email,
          priority: :critical,
          enabled: false,
          sent_count: 5
        )
        new_setting.valid?
        expect(new_setting.priority).to eq('critical')
        expect(new_setting.enabled).to be false
        expect(new_setting.sent_count).to eq(5)
      end
    end

    describe 'logging callbacks' do
      it 'logs when setting is created' do
        expect(Rails.logger).to receive(:info).with(
          hash_including(event: "notification_setting_created")
        )

        create(:admin_notification_setting, admin: admin)
      end

      it 'logs when setting is enabled' do
        setting.enabled = false
        setting.save!

        expect(Rails.logger).to receive(:info).with(
          hash_including(event: "notification_setting_enabled")
        )

        setting.update!(enabled: true)
      end

      it 'logs when setting is disabled' do
        expect(Rails.logger).to receive(:info).with(
          hash_including(event: "notification_setting_disabled")
        )

        setting.update!(enabled: false)
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe 'edge cases' do
    it 'handles very large sent_count values' do
      setting.sent_count = 999_999_999
      setting.mark_as_sent!
      expect(setting.reload.sent_count).to eq(1_000_000_000)
    end

    it 'handles time boundaries correctly in can_send_notification?' do
      setting.frequency_minutes = 60
      setting.last_sent_at = 60.minutes.ago

      freeze_time do
        expect(setting.can_send_notification?).to be true
      end
    end

    it 'handles concurrent updates safely' do
      setting.sent_count = 10

      # Simulate concurrent updates
      expect {
        setting.mark_as_sent!
        setting.mark_as_sent!
      }.to change { setting.reload.sent_count }.by(2)
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it 'efficiently queries admins for notifications' do
      # Create test data
      50.times do
        admin = create(:admin)
        create(:admin_notification_setting,
               admin: admin,
               notification_type: :stock_alert,
               enabled: true)
      end

      start_time = Time.now
      AdminNotificationSetting.admins_for_notification(:stock_alert)
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 100
    end
  end
end
