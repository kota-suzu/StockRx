# frozen_string_literal: true

RSpec.shared_examples "timestampable" do
  let(:model) { described_class }
  let(:instance) { create(model.name.underscore.to_sym) }

  describe "timestamps" do
    it "has created_at timestamp" do
      expect(instance).to respond_to(:created_at)
      expect(instance.created_at).to be_a(ActiveSupport::TimeWithZone)
    end

    it "has updated_at timestamp" do
      expect(instance).to respond_to(:updated_at)
      expect(instance.updated_at).to be_a(ActiveSupport::TimeWithZone)
    end

    it "sets created_at on create" do
      Timecop.freeze do
        new_instance = create(model.name.underscore.to_sym)
        expect(new_instance.created_at).to be_within(1.second).of(Time.current)
      end
    end

    it "updates updated_at on update" do
      original_updated_at = instance.updated_at
      
      Timecop.travel(1.hour.from_now) do
        instance.update!(updated_at: Time.current)
        expect(instance.updated_at).to be > original_updated_at
      end
    end

    it "does not change created_at on update" do
      original_created_at = instance.created_at
      
      Timecop.travel(1.hour.from_now) do
        instance.update!(updated_at: Time.current)
        expect(instance.created_at).to eq(original_created_at)
      end
    end
  end

  describe "scopes" do
    describe ".recent" do
      it "orders by created_at desc" do
        old_instance = create(model.name.underscore.to_sym, created_at: 2.days.ago)
        new_instance = create(model.name.underscore.to_sym, created_at: 1.hour.ago)
        
        if model.respond_to?(:recent)
          expect(model.recent.first).to eq(new_instance)
          expect(model.recent.last).to eq(old_instance)
        end
      end
    end

    describe ".created_between" do
      it "filters by created_at range" do
        old_instance = create(model.name.underscore.to_sym, created_at: 1.week.ago)
        recent_instance = create(model.name.underscore.to_sym, created_at: 1.day.ago)
        future_instance = create(model.name.underscore.to_sym, created_at: 1.day.from_now)
        
        if model.respond_to?(:created_between)
          results = model.created_between(2.days.ago, Time.current)
          expect(results).to include(recent_instance)
          expect(results).not_to include(old_instance, future_instance)
        end
      end
    end

    describe ".updated_after" do
      it "filters by updated_at" do
        old_instance = create(model.name.underscore.to_sym, updated_at: 1.week.ago)
        recent_instance = create(model.name.underscore.to_sym, updated_at: 1.hour.ago)
        
        if model.respond_to?(:updated_after)
          results = model.updated_after(1.day.ago)
          expect(results).to include(recent_instance)
          expect(results).not_to include(old_instance)
        end
      end
    end
  end

  describe "#touch" do
    it "updates updated_at without callbacks" do
      original_updated_at = instance.updated_at
      
      Timecop.travel(1.hour.from_now) do
        instance.touch
        expect(instance.updated_at).to be > original_updated_at
      end
    end

    it "can touch specific timestamp attribute" do
      if instance.respond_to?(:last_accessed_at)
        Timecop.freeze do
          instance.touch(:last_accessed_at)
          expect(instance.last_accessed_at).to be_within(1.second).of(Time.current)
        end
      end
    end
  end

  describe "time zone handling" do
    it "stores timestamps in UTC" do
      Time.use_zone("Tokyo") do
        new_instance = create(model.name.underscore.to_sym)
        expect(new_instance.created_at.zone).to eq("UTC")
        expect(new_instance.updated_at.zone).to eq("UTC")
      end
    end

    it "converts to application time zone on retrieval" do
      Time.use_zone("America/New_York") do
        expect(instance.created_at.zone).to eq("EST").or eq("EDT")
      end
    end
  end
end