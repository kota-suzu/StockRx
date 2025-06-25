# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CleanupOldLogsJob, type: :job do
  describe "#perform" do
    let(:cutoff_date) { 90.days.ago }

    describe "InventoryLog cleanup" do
      let!(:old_log1) { create(:inventory_log, created_at: 100.days.ago) }
      let!(:old_log2) { create(:inventory_log, created_at: 91.days.ago) }
      let!(:recent_log) { create(:inventory_log, created_at: 89.days.ago) }
      let!(:new_log) { create(:inventory_log, created_at: 1.day.ago) }

      context "with default retention days" do
        it "deletes logs older than 90 days" do
          expect {
            CleanupOldLogsJob.perform_now
          }.to change(InventoryLog, :count).by(-2)

          expect(InventoryLog.exists?(old_log1.id)).to be false
          expect(InventoryLog.exists?(old_log2.id)).to be false
          expect(InventoryLog.exists?(recent_log.id)).to be true
          expect(InventoryLog.exists?(new_log.id)).to be true
        end

        it "returns summary of deleted logs" do
          result = CleanupOldLogsJob.perform_now

          expect(result[:total_deleted]).to eq(2)
          expect(result[:retention_days]).to eq(90)
          expect(result[:cutoff_date]).to be_within(1.day).of(cutoff_date)
        end

        it "logs the cleanup completion" do
          expect(Rails.logger).to receive(:info).with(/Starting cleanup of old logs/)
          expect(Rails.logger).to receive(:info).with(/Deleted 2 old InventoryLog records/)
          expect(Rails.logger).to receive(:info).with(a_string_matching(/log_cleanup_completed/))
          expect(Rails.logger).to receive(:info).with(/Redis cleanup completed/)

          CleanupOldLogsJob.perform_now
        end
      end

      context "with custom retention days" do
        it "deletes logs based on custom retention period" do
          expect {
            CleanupOldLogsJob.perform_now(30)
          }.to change(InventoryLog, :count).by(-3)

          expect(InventoryLog.exists?(recent_log.id)).to be false
        end
      end

      context "with custom batch size" do
        before do
          # Create many old logs
          20.times { create(:inventory_log, created_at: 100.days.ago) }
        end

        it "processes logs in batches" do
          expect(InventoryLog).to receive(:where).at_least(3).times.and_call_original

          CleanupOldLogsJob.perform_now(90, 10)
        end

        it "deletes all old logs regardless of batch size" do
          expect {
            CleanupOldLogsJob.perform_now(90, 5)
          }.to change(InventoryLog, :count).by(-22)
        end
      end
    end

    describe "Redis cleanup" do
      let(:redis) { double("Redis") }
      let(:redis_pool) { double("RedisPool") }

      before do
        allow(Sidekiq).to receive(:redis_pool).and_return(redis_pool)
        allow(redis_pool).to receive(:with).and_yield(redis)
      end

      describe "CSV import progress cleanup" do
        it "deletes old CSV import progress keys" do
          old_time = 8.days.ago.to_s
          recent_time = 6.days.ago.to_s

          expect(redis).to receive(:keys).with("csv_import:*").and_return([
            "csv_import:job1",
            "csv_import:job2"
          ])

          expect(redis).to receive(:hget).with("csv_import:job1", "started_at").and_return(old_time)
          expect(redis).to receive(:hget).with("csv_import:job2", "started_at").and_return(recent_time)

          expect(redis).to receive(:del).with("csv_import:job1")
          expect(redis).not_to receive(:del).with("csv_import:job2")

          CleanupOldLogsJob.perform_now
        end

        it "handles invalid date strings gracefully" do
          expect(redis).to receive(:keys).with("csv_import:*").and_return([ "csv_import:invalid" ])
          expect(redis).to receive(:hget).with("csv_import:invalid", "started_at").and_return("invalid_date")
          expect(redis).to receive(:del).with("csv_import:invalid")

          expect { CleanupOldLogsJob.perform_now }.not_to raise_error
        end

        it "skips keys without started_at" do
          expect(redis).to receive(:keys).with("csv_import:*").and_return([ "csv_import:no_date" ])
          expect(redis).to receive(:hget).with("csv_import:no_date", "started_at").and_return(nil)
          expect(redis).not_to receive(:del)

          CleanupOldLogsJob.perform_now
        end
      end

      describe "Sidekiq stats cleanup" do
        it "removes old statistics from sorted sets" do
          cutoff_timestamp = 30.days.ago.to_i

          %w[processed failed].each do |stat_type|
            expect(redis).to receive(:zremrangebyscore)
              .with("sidekiq:stat:#{stat_type}", 0, cutoff_timestamp)
          end

          CleanupOldLogsJob.perform_now
        end
      end
    end

    describe "error handling" do
      context "when InventoryLog deletion fails" do
        before do
          allow(InventoryLog).to receive(:where).and_raise(ActiveRecord::StatementInvalid, "Database error")
        end

        it "logs the error and re-raises" do
          expect(Rails.logger).to receive(:error).with(a_string_matching(/log_cleanup_failed/))

          expect {
            CleanupOldLogsJob.perform_now
          }.to raise_error(ActiveRecord::StatementInvalid)
        end
      end

      context "when Redis cleanup fails" do
        before do
          allow(Sidekiq).to receive(:redis_pool).and_raise(Redis::CannotConnectError, "Redis connection failed")
        end

        it "logs warning but continues execution" do
          create(:inventory_log, created_at: 100.days.ago)

          expect(Rails.logger).to receive(:warn).with(/Redis cleanup failed/)

          expect {
            CleanupOldLogsJob.perform_now
          }.to change(InventoryLog, :count).by(-1)
        end

        it "still returns successful result" do
          create(:inventory_log, created_at: 100.days.ago)

          result = CleanupOldLogsJob.perform_now
          expect(result[:total_deleted]).to eq(1)
        end
      end
    end

    describe "performance considerations" do
      it "includes sleep between batches to reduce database load" do
        # Create enough logs to trigger multiple batches
        5.times { create(:inventory_log, created_at: 100.days.ago) }

        expect_any_instance_of(CleanupOldLogsJob).to receive(:sleep).with(0.1).at_least(:once)

        CleanupOldLogsJob.perform_now(90, 2)
      end
    end

    describe "job configuration" do
      it "uses default queue" do
        expect(CleanupOldLogsJob.new.queue_name).to eq("default")
      end

      it "has correct sidekiq options" do
        expect(CleanupOldLogsJob.sidekiq_options["retry"]).to eq(1)
        expect(CleanupOldLogsJob.sidekiq_options["backtrace"]).to be true
        expect(CleanupOldLogsJob.sidekiq_options["queue"]).to eq(:default)
      end
    end

    describe "edge cases" do
      context "when no logs exist" do
        before { InventoryLog.destroy_all }

        it "completes successfully without deleting anything" do
          result = CleanupOldLogsJob.perform_now

          expect(result[:total_deleted]).to eq(0)
        end
      end

      context "when all logs are recent" do
        before do
          3.times { create(:inventory_log, created_at: 1.day.ago) }
        end

        it "does not delete any logs" do
          expect {
            CleanupOldLogsJob.perform_now
          }.not_to change(InventoryLog, :count)
        end
      end

      context "with extremely large batch size" do
        before do
          50.times { create(:inventory_log, created_at: 100.days.ago) }
        end

        it "handles large batches correctly" do
          expect {
            CleanupOldLogsJob.perform_now(90, 10000)
          }.to change(InventoryLog, :count).by(-50)
        end
      end
    end
  end
end
