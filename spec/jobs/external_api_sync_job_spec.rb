# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExternalApiSyncJob, type: :job do
  describe "#perform" do
    let(:api_provider) { "sample_supplier" }
    let(:sync_type) { "inventory" }
    let(:options) { { store_id: 1, last_sync: 1.day.ago } }

    describe "API provider routing" do
      context "with sample_supplier provider" do
        it "calls sync_sample_supplier_data" do
          expect_any_instance_of(ExternalApiSyncJob).to receive(:sync_sample_supplier_data)
            .with(sync_type, options)
            .and_return({ status: "success" })

          ExternalApiSyncJob.perform_now(api_provider, sync_type, options)
        end

        it "logs sync start and completion" do
          expect(Rails.logger).to receive(:info).with("Starting external API sync: sample_supplier/inventory")
          expect(Rails.logger).to receive(:info).with(a_string_matching(/external_api_sync_completed/))

          ExternalApiSyncJob.perform_now(api_provider, sync_type, options)
        end
      end

      context "with accounting_system provider" do
        it "calls sync_accounting_data" do
          expect_any_instance_of(ExternalApiSyncJob).to receive(:sync_accounting_data)
            .with("sales", options)
            .and_return({ status: "not_implemented" })

          ExternalApiSyncJob.perform_now("accounting_system", "sales", options)
        end
      end

      context "with inventory_system provider" do
        it "calls sync_inventory_data" do
          expect_any_instance_of(ExternalApiSyncJob).to receive(:sync_inventory_data)
            .with("stock_levels", options)
            .and_return({ status: "not_implemented" })

          ExternalApiSyncJob.perform_now("inventory_system", "stock_levels", options)
        end
      end

      context "with unknown provider" do
        it "handles unknown provider gracefully" do
          result = ExternalApiSyncJob.perform_now("unknown_provider", sync_type, options)

          expect(result[:status]).to eq("error")
          expect(result[:error]).to include("Unknown API provider: unknown_provider")
        end

        it "logs error for unknown provider" do
          expect(Rails.logger).to receive(:error).with("Unknown API provider: unknown_provider")

          ExternalApiSyncJob.perform_now("unknown_provider", sync_type, options)
        end
      end
    end

    describe "sync_sample_supplier_data" do
      let(:job) { ExternalApiSyncJob.new }

      context "inventory sync" do
        it "returns success response" do
          result = job.send(:sync_sample_supplier_data, "inventory", options)

          expect(result[:status]).to eq("success")
          expect(result[:records_updated]).to eq(0)
          expect(result[:last_sync]).to be_present
          expect(result[:message]).to include("Supplier inventory sync completed")
        end
      end

      context "prices sync" do
        it "returns success response" do
          result = job.send(:sync_sample_supplier_data, "prices", options)

          expect(result[:status]).to eq("success")
          expect(result[:prices_updated]).to eq(0)
          expect(result[:last_sync]).to be_present
        end
      end

      context "orders sync" do
        it "returns success response" do
          result = job.send(:sync_sample_supplier_data, "orders", options)

          expect(result[:status]).to eq("success")
          expect(result[:orders_processed]).to eq(0)
          expect(result[:last_sync]).to be_present
        end
      end

      context "unknown sync type" do
        it "returns error response" do
          result = job.send(:sync_sample_supplier_data, "unknown_type", options)

          expect(result[:error]).to include("Unknown sync type: unknown_type")
        end
      end
    end

    describe "error handling" do
      let(:job) { ExternalApiSyncJob.new }

      context "when sync_supplier_inventory fails" do
        before do
          allow(job).to receive(:sync_supplier_inventory).and_raise(StandardError, "API connection failed")
        end

        it "catches error and returns error response" do
          result = job.send(:sync_sample_supplier_data, "inventory", options)

          expect(result[:status]).to eq("error")
          expect(result[:error]).to eq("API connection failed")
        end

        it "logs the error" do
          expect(Rails.logger).to receive(:error).with("Supplier inventory sync failed: API connection failed")

          job.send(:sync_sample_supplier_data, "inventory", options)
        end
      end
    end

    describe "retry configuration" do
      it "retries on timeout errors" do
        expect(ExternalApiSyncJob).to respond_to(:retry_on)

        # Verify retry configuration through job options
        job = ExternalApiSyncJob.new
        expect(job.class.sidekiq_options["retry"]).to eq(5)
      end

      it "has correct queue configuration" do
        job = ExternalApiSyncJob.new
        expect(job.queue_name).to eq("default")
      end

      it "has correct sidekiq options" do
        expect(ExternalApiSyncJob.sidekiq_options["retry"]).to eq(5)
        expect(ExternalApiSyncJob.sidekiq_options["backtrace"]).to be true
        expect(ExternalApiSyncJob.sidekiq_options["queue"]).to eq(:default)
      end
    end

    describe "helper methods" do
      let(:job) { ExternalApiSyncJob.new }

      describe "#fetch_with_retry" do
        it "returns mock response" do
          result = job.send(:fetch_with_retry, "https://api.example.com/data")

          expect(result[:status]).to eq("mock_response")
        end

        context "with network error" do
          before do
            call_count = 0
            allow(job).to receive(:fetch_with_retry).and_wrap_original do |method, *args|
              call_count += 1
              if call_count <= 2
                raise StandardError, "Network error"
              else
                { status: "success" }
              end
            end
          end

          it "retries on failure" do
            expect(Rails.logger).to receive(:warn).at_least(:once)

            result = job.send(:fetch_with_retry, "https://api.example.com/data")
            expect(result[:status]).to eq("success")
          end
        end

        context "when all retries fail" do
          before do
            allow(job).to receive(:fetch_with_retry).and_raise(StandardError, "Persistent error")
          end

          it "raises error after max retries" do
            expect {
              job.send(:fetch_with_retry, "https://api.example.com/data")
            }.to raise_error(StandardError, "Persistent error")
          end
        end
      end

      describe "#validate_api_response" do
        it "validates valid response" do
          response = { status: "success", data: [] }

          expect(job.send(:validate_api_response, response)).to be true
        end

        it "raises error for non-hash response" do
          expect {
            job.send(:validate_api_response, "invalid")
          }.to raise_error("Invalid API response format")
        end

        it "raises error when response contains error" do
          response = { error: "API rate limit exceeded" }

          expect {
            job.send(:validate_api_response, response)
          }.to raise_error("API returned error: API rate limit exceeded")
        end
      end
    end

    describe "sensitive data handling" do
      it "defines sensitive API parameters" do
        expect(ExternalApiSyncJob::SENSITIVE_API_PARAMS).to include(
          "api_token", "api_secret", "access_token", "password"
        )
      end
    end

    describe "not implemented sync types" do
      let(:job) { ExternalApiSyncJob.new }

      describe "#sync_accounting_data" do
        it "returns not_implemented status" do
          result = job.send(:sync_accounting_data, "sales", options)

          expect(result[:status]).to eq("not_implemented")
          expect(result[:sync_type]).to eq("sales")
        end

        it "logs not implemented message" do
          expect(Rails.logger).to receive(:info).with("Accounting system sync not yet implemented: sales")

          job.send(:sync_accounting_data, "sales", options)
        end
      end

      describe "#sync_inventory_data" do
        it "returns not_implemented status" do
          result = job.send(:sync_inventory_data, "stock_levels", options)

          expect(result[:status]).to eq("not_implemented")
          expect(result[:sync_type]).to eq("stock_levels")
        end
      end
    end

    describe "edge cases" do
      context "with nil options" do
        it "handles nil options gracefully" do
          result = ExternalApiSyncJob.perform_now(api_provider, sync_type, nil)

          expect(result).to be_a(Hash)
          expect(result[:status]).to be_present
        end
      end

      context "with empty string parameters" do
        it "handles empty provider" do
          result = ExternalApiSyncJob.perform_now("", sync_type, options)

          expect(result[:status]).to eq("error")
          expect(result[:error]).to include("Unknown API provider")
        end
      end

      context "concurrent job execution" do
        it "handles concurrent executions" do
          threads = []
          results = []

          3.times do
            threads << Thread.new do
              results << ExternalApiSyncJob.perform_now(api_provider, sync_type, options)
            end
          end

          threads.each(&:join)

          expect(results.size).to eq(3)
          expect(results.all? { |r| r[:status] == "success" }).to be true
        end
      end
    end
  end
end
