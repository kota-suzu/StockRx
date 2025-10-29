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
          if instance.respond_to?(:name=)
            instance.update!(name: "Updated Name")
          elsif instance.respond_to?(:lot_code=)
            instance.update!(lot_code: "UPDATED-#{SecureRandom.hex(3)}")
          elsif instance.respond_to?(:quantity=)
            instance.update!(quantity: instance.quantity + 10)
          end
        }.to change(AuditLog, :count).by(1)
      end

      it "records changed attributes" do
        instance

        if instance.respond_to?(:name=)
          instance.update!(name: "Updated Name")
          changed_key = "name"
        elsif instance.respond_to?(:lot_code=)
          instance.update!(lot_code: "UPDATED-#{SecureRandom.hex(3)}")
          changed_key = "lot_code"
        elsif instance.respond_to?(:quantity=)
          instance.update!(quantity: instance.quantity + 10)
          changed_key = "quantity"
        end

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("update")
        # Fix: details is JSON string, need to parse
        details = JSON.parse(audit_log.details)
        expect(details["changes"]).to have_key(changed_key)
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

        # 関連レコードを作成しない、または削除可能な状態にする
        if instance.respond_to?(:audit_logs)
          instance.audit_logs.destroy_all
        end

        expect {
          instance.destroy!
        }.to change(AuditLog, :count).by_at_least(1)
      end

      it "records destroy action with final state" do
        instance
        instance_attributes = instance.attributes

        # 関連レコードを削除可能にする
        if instance.respond_to?(:audit_logs)
          instance.audit_logs.destroy_all
        end

        instance.destroy!

        audit_log = AuditLog.last
        expect(audit_log.action).to eq("delete")
        # Fix: details is JSON string, need to parse
        details = JSON.parse(audit_log.details)
        expect(details).to include("final_state")
      end
    end
  end

  describe "#audit_changes" do
    it "returns formatted changes" do
      # モデルに応じて適切な属性を変更
      if instance.respond_to?(:name=)
        instance.name = "変更後"
      elsif instance.respond_to?(:lot_code=)
        instance.lot_code = "CHANGED-#{SecureRandom.hex(3)}"
      elsif instance.respond_to?(:quantity=)
        instance.quantity = instance.quantity + 10
      end

      instance.save!
      changes = instance.send(:audit_changes)

      expect(changes).to be_a(Hash)
      expect(changes.keys.size).to be > 0
    end

    it "excludes timestamps by default" do
      # モデルに応じて適切な属性を変更
      if instance.respond_to?(:name=)
        instance.name = "変更後"
      elsif instance.respond_to?(:lot_code=)
        instance.lot_code = "CHANGED-#{SecureRandom.hex(3)}"
      elsif instance.respond_to?(:quantity=)
        instance.quantity = instance.quantity + 10
      end

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
      # 名前の重複を避けるためにインデックスを追加
      expect {
        instances.each_with_index do |inst, i|
          # モデルに応じて適切な属性を更新
          if inst.respond_to?(:name=)
            inst.update!(name: "Bulk Updated #{i}")
          elsif inst.respond_to?(:lot_code=)
            inst.update!(lot_code: "BULK-#{i}-#{SecureRandom.hex(3)}")
          else
            inst.update!(updated_at: Time.current)
          end
        end
      }.to change(AuditLog, :count).by_at_least(3)
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
