# frozen_string_literal: true

RSpec.shared_examples "auditable" do
  let(:model) { described_class }
  let(:instance) { create(model.name.underscore.to_sym) }
  let(:admin) { create(:admin) }
  let(:store_user) { create(:store_user) }

  describe "associations" do
    it { is_expected.to have_many(:audit_logs).dependent(:destroy) }
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
          instance.update!(updated_at: Time.current)
        }.to change(AuditLog, :count).by(1)
      end

      it "records changed attributes" do
        instance
        original_value = instance.updated_at
        instance.update!(updated_at: Time.current + 1.hour)
        
        audit_log = AuditLog.last
        expect(audit_log.action).to eq("update")
        expect(audit_log.details).to include("updated_at")
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
      instance.updated_at = Time.current + 1.hour
      changes = instance.send(:audit_changes)
      
      expect(changes).to be_a(Hash)
      expect(changes).to have_key("updated_at")
    end

    it "excludes timestamps by default" do
      instance.created_at = Time.current
      instance.updated_at = Time.current
      changes = instance.send(:audit_changes, exclude_timestamps: true)
      
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
      
      expect {
        model.where(id: instances.map(&:id)).update_all(updated_at: Time.current)
      }.to change(AuditLog, :count).by_at_least(1)
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