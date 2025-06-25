# frozen_string_literal: true

RSpec.shared_examples "auditable" do
  let(:model) { described_class }
  let(:instance) { create(model.name.underscore.to_sym) }
  let(:admin) { create(:admin) }
  let(:store_user) { create(:store_user) }

  describe "associations" do
    it "has many audit_logs with restrict_with_error" do
      # モジュールのテストなので、実際のモデルインスタンスで確認
      expect(instance.class.reflect_on_association(:audit_logs)).not_to be_nil
      expect(instance.class.reflect_on_association(:audit_logs).options[:dependent]).to eq(:restrict_with_error)
    end
  end

  describe "callbacks" do
    describe "after_create" do
      it "creates an audit log entry" do
        Current.user = admin
        expect {
          create(model.name.underscore.to_sym)
        }.to change(AuditLog, :count).by(1)
      end

      it "records create action" do
        Current.user = admin
        new_instance = create(model.name.underscore.to_sym)
        audit_log = AuditLog.last

        expect(audit_log.action).to eq("create")
        expect(audit_log.auditable).to eq(new_instance)
        expect(audit_log.user).to eq(admin)
      end

      it "handles nil user gracefully" do
        Current.user = nil
        expect {
          create(model.name.underscore.to_sym)
        }.to change(AuditLog, :count).by(1)

        expect(AuditLog.last.user).to be_nil
      end
    end

    describe "after_update" do
      before { Current.user = admin }

      it "creates an audit log entry" do
        instance
        expect {
          instance.update!(name: "Updated Name")
        }.to change(AuditLog, :count).by(1)
      end

      it "records changed attributes" do
        instance
        instance.update!(name: "Updated Name")

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("update")
        expect(audit_log.details["changes"]).to have_key("name")
      end

      it "skips audit for no actual changes" do
        instance
        expect {
          instance.touch
        }.not_to change(AuditLog, :count)
      end
    end

    describe "before_destroy" do
      before { Current.user = admin }

      it "creates an audit log entry" do
        instance
        expect {
          instance.destroy!
        }.to change(AuditLog, :count).by(1)
      end

      it "records destroy action with final state" do
        instance
        instance_attributes = instance.attributes
        instance.destroy!

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("destroy")
        expect(audit_log.details).to include("final_state")
      end
    end
  end

  describe "#audit_changes" do
    it "returns formatted changes" do
      instance.name = "変更後"
      instance.save!
      changes = instance.send(:audit_changes)

      expect(changes).to be_a(Hash)
      expect(changes).to have_key("name")
    end

    it "excludes timestamps by default" do
      instance.name = "変更後"
      instance.save!
      changes = instance.send(:audit_changes)

      expect(changes).not_to have_key("created_at")
      expect(changes).not_to have_key("updated_at")
    end
  end

  describe "#audit_user" do
    it "returns Current.user" do
      Current.user = admin
      expect(instance.send(:audit_user)).to eq(admin)
    end

    it "returns nil when no user set" do
      Current.user = nil
      expect(instance.send(:audit_user)).to be_nil
    end
  end

  describe "#auditable_name" do
    it "returns a human-readable identifier" do
      expect(instance.auditable_name).to be_present
      expect(instance.auditable_name).to be_a(String)
    end
  end

  describe "bulk operations" do
    it "creates audit logs for bulk updates" do
      instances = create_list(model.name.underscore.to_sym, 3)
      Current.user = admin

      # update_allはコールバックを発火しないため、個別更新に変更
      expect {
        instances.each { |inst| inst.update!(name: "Bulk Updated") }
      }.to change(AuditLog, :count).by(3)
    end
  end

  describe "error handling" do
    it "does not prevent save on audit failure" do
      allow_any_instance_of(AuditLog).to receive(:save!).and_raise(StandardError)

      expect {
        instance.update!(updated_at: Time.current)
      }.not_to raise_error
    end
  end
end
