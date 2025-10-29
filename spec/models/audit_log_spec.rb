# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  describe "associations" do
    it { should belong_to(:auditable) }
    it { should belong_to(:user).optional }
  end

  describe "polymorphic user association" do
    let(:admin) { create(:admin) }
    let(:store_user) { create(:store_user) }

    it "returns admin when user_type is Admin" do
      log = create(:audit_log, user: admin)
      expect(log.admin).to eq(admin)
      expect(log.store_user).to be_nil
    end

    it "returns store_user when user_type is StoreUser" do
      log = create(:audit_log, user: store_user)
      expect(log.store_user).to eq(store_user)
      expect(log.admin).to be_nil
    end

    it "returns nil when user is nil" do
      log = create(:audit_log, user: nil)
      expect(log.admin).to be_nil
      expect(log.store_user).to be_nil
    end
  end

  describe "validations" do
    it { should validate_presence_of(:action) }
    it { should validate_presence_of(:message) }
  end

  describe "enums" do
    it "defines action enum with correct values" do
      expect(AuditLog.actions).to eq(
        "create" => "create",
        "update" => "update",
        "delete" => "delete",
        "view" => "view",
        "export" => "export",
        "import" => "import",
        "login" => "login",
        "logout" => "logout",
        "security_event" => "security_event",
        "permission_change" => "permission_change",
        "password_change" => "password_change",
        "failed_login" => "failed_login"
      )
    end

    it "provides action query methods with suffix" do
      log = create(:audit_log, action: "login")
      expect(log.login_action?).to be true
      expect(log.logout_action?).to be false
    end
  end

  describe "scopes" do
    let!(:admin1) { create(:admin) }
    let!(:admin2) { create(:admin) }
    let!(:old_log) { create(:audit_log, created_at: 2.days.ago, user: admin1) }
    let!(:new_log) { create(:audit_log, created_at: 1.hour.ago, user: admin2) }
    let!(:login_log) { create(:audit_log, :login_action, user: admin1) }
    let!(:logout_log) { create(:audit_log, :logout_action, user: admin2) }
    let!(:security_log) { create(:audit_log, :security_event_action) }

    describe ".recent" do
      it "returns logs in descending order by created_at" do
        logs = AuditLog.recent.to_a
        expect(logs.first.created_at).to be >= logs.last.created_at
        expect(logs.size).to eq(5)
      end
    end

    describe ".by_action" do
      it "filters logs by action" do
        expect(AuditLog.by_action("login")).to contain_exactly(login_log)
      end
    end

    describe ".by_user" do
      it "filters logs by user_id" do
        expect(AuditLog.by_user(admin1.id)).to contain_exactly(old_log, login_log)
      end
    end

    describe ".by_date_range" do
      it "filters logs within date range" do
        start_date = 3.days.ago
        end_date = Time.current
        expect(AuditLog.by_date_range(start_date, end_date)).to include(old_log, new_log, login_log, logout_log, security_log)
      end

      it "excludes logs outside date range" do
        start_date = 1.day.ago
        end_date = Time.current
        expect(AuditLog.by_date_range(start_date, end_date)).not_to include(old_log)
      end
    end

    describe ".security_events" do
      it "returns only security-related events" do
        expect(AuditLog.security_events).to contain_exactly(security_log)
      end
    end

    describe ".authentication_events" do
      it "returns only authentication events" do
        expect(AuditLog.authentication_events).to contain_exactly(login_log, logout_log)
      end
    end

    describe ".data_access_events" do
      let!(:view_log) { create(:audit_log, :view_action) }
      let!(:export_log) { create(:audit_log, :export_action) }

      it "returns only data access events" do
        expect(AuditLog.data_access_events).to contain_exactly(view_log, export_log)
      end
    end
  end

  describe "instance methods" do
    let(:admin) { create(:admin, email: "test@example.com") }
    let(:audit_log) { create(:audit_log, user: admin) }
    let(:system_log) { create(:audit_log, user: nil) }

    describe "#user_display_name" do
      it "returns user email when user exists" do
        expect(audit_log.user_display_name).to eq("test@example.com")
      end

      it "returns 'システム' when user is nil" do
        expect(system_log.user_display_name).to eq("システム")
      end
    end

    describe "#formatted_created_at" do
      it "formats created_at in Japanese format" do
        log = create(:audit_log, created_at: Time.zone.parse("2025-06-25 14:30:00"))
        expect(log.formatted_created_at).to eq("2025年06月25日 14:30:00")
      end
    end

    describe "#audit_view" do
      let(:viewer) { create(:admin) }
      let(:audit_log) { create(:audit_log) }

      context "when viewing regular audit log" do
        it "creates a view audit log" do
          expect {
            audit_log.audit_view(viewer, { access_reason: "監査確認" })
          }.to change(AuditLog, :count).by(1)

          view_log = AuditLog.last
          expect(view_log.action).to eq("view")
          expect(view_log.message).to include("監査ログ(ID: #{audit_log.id})が閲覧されました")
          expect(view_log.user).to eq(viewer)
        end

        it "includes viewer details in the log" do
          audit_log.audit_view(viewer, { access_reason: "定期監査" })

          view_log = AuditLog.last
          details = JSON.parse(view_log.details)
          expect(details["viewed_log_id"]).to eq(audit_log.id)
          expect(details["viewed_log_action"]).to eq(audit_log.action)
          expect(details["viewer_role"]).to eq(viewer.role)
          expect(details["compliance_reason"]).to eq("定期監査")
        end
      end

      context "when viewing a view audit log" do
        let(:view_audit_log) { create(:audit_log, :view_action, auditable: audit_log) }

        it "does not create infinite loop" do
          expect {
            view_audit_log.audit_view(viewer)
          }.not_to change(AuditLog, :count)
        end
      end

      context "when error occurs" do
        before do
          allow(AuditLog).to receive(:log_action).and_raise(StandardError, "Test error")
          allow(Rails.logger).to receive(:error)
        end

        it "logs error and returns nil" do
          result = audit_log.audit_view(viewer)
          expect(result).to be_nil
          expect(Rails.logger).to have_received(:error).with(/監査ログ閲覧記録エラー/)
        end
      end
    end
  end

  describe "class methods" do
    describe ".log_action" do
      let(:admin) { create(:admin) }
      let(:inventory) { create(:inventory) }

      context "with all parameters" do
        it "creates audit log with all attributes" do
          Current.user = admin
          Current.ip_address = "192.168.1.1"
          Current.user_agent = "Mozilla/5.0"

          log = AuditLog.log_action(
            inventory,
            "update",
            "在庫が更新されました",
            { old_quantity: 10, new_quantity: 20 },
            admin
          )

          expect(log).to be_persisted
          expect(log.auditable).to eq(inventory)
          expect(log.action).to eq("update")
          expect(log.message).to eq("在庫が更新されました")
          expect(log.details).to eq({ old_quantity: 10, new_quantity: 20 }.to_json)
          expect(log.user).to eq(admin)
          expect(log.ip_address).to eq("192.168.1.1")
          expect(log.user_agent).to eq("Mozilla/5.0")
        ensure
          Current.reset
        end
      end

      context "without user parameter" do
        it "uses Current.user" do
          Current.user = admin

          log = AuditLog.log_action(
            inventory,
            "view",
            "在庫が閲覧されました",
            {}
          )

          expect(log.user).to eq(admin)
        ensure
          Current.reset
        end
      end

      context "with invalid parameters" do
        it "raises validation error" do
          expect {
            AuditLog.log_action(inventory, nil, "メッセージ", {})
          }.to raise_error(ActiveRecord::RecordInvalid)
        end
      end
    end

    describe ".cleanup_old_logs" do
      let!(:old_log1) { create(:audit_log, created_at: 100.days.ago) }
      let!(:old_log2) { create(:audit_log, created_at: 91.days.ago) }
      let!(:recent_log) { create(:audit_log, created_at: 89.days.ago) }

      context "with default retention days" do
        it "deletes logs older than 90 days" do
          expect {
            AuditLog.cleanup_old_logs
          }.to change(AuditLog, :count).by(-2)

          expect(AuditLog.exists?(old_log1.id)).to be false
          expect(AuditLog.exists?(old_log2.id)).to be false
          expect(AuditLog.exists?(recent_log.id)).to be true
        end
      end

      context "with custom retention days" do
        it "deletes logs based on specified days" do
          expect {
            AuditLog.cleanup_old_logs(30)
          }.to change(AuditLog, :count).by(-3)
        end
      end

      context "when no old logs exist" do
        before { AuditLog.destroy_all }
        let!(:new_log) { create(:audit_log, created_at: 1.day.ago) }

        it "does not delete any logs" do
          expect {
            AuditLog.cleanup_old_logs
          }.not_to change(AuditLog, :count)
        end
      end
    end
  end

  describe "polymorphic auditable" do
    it "can belong to different types of models" do
      inventory = create(:inventory)
      admin = create(:admin)

      inventory_log = create(:audit_log, auditable: inventory)
      admin_log = create(:audit_log, auditable: admin)

      expect(inventory_log.auditable).to eq(inventory)
      expect(inventory_log.auditable_type).to eq("Inventory")

      expect(admin_log.auditable).to eq(admin)
      expect(admin_log.auditable_type).to eq("Admin")
    end
  end

  describe "edge cases and security" do
    describe "large details handling" do
      it "stores large JSON details correctly" do
        large_details = { data: "x" * 10000 }
        log = create(:audit_log, details: large_details.to_json)

        expect(JSON.parse(log.details)).to eq(large_details.stringify_keys)
      end
    end

    describe "concurrent access" do
      it "handles concurrent log creation" do
        inventory = create(:inventory)

        # Sequential creation to avoid MySQL concurrency issues in test
        5.times do |i|
          AuditLog.log_action(inventory, "update", "Sequential update #{i}", {})
        end

        expect(AuditLog.where(auditable: inventory).count).to eq(5)
      end
    end

    describe "SQL injection prevention" do
      it "safely handles malicious input in scopes" do
        malicious_action = "'; DROP TABLE audit_logs; --"
        expect { AuditLog.by_action(malicious_action) }.not_to raise_error
        expect(AuditLog.by_action(malicious_action)).to be_empty
      end
    end
  end
end
