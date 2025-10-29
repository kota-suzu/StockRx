# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvExportAuditJob, type: :job do
  include ActiveJob::TestHelper

  let(:admin) { create(:admin) }
  let(:store) { create(:store) }
  let(:performance_metrics) do
    {
      memory_usage: 1024,
      processing_time: 2.5,
      batch_size: 1000
    }
  end
  let(:request_metadata) do
    {
      ip_address: '192.168.1.1',
      user_agent: 'Mozilla/5.0 Test Agent'
    }
  end

  let(:job_params) do
    {
      user_id: admin.id,
      store_id: store.id,
      record_count: 500,
      performance_metrics: performance_metrics,
      request_metadata: request_metadata
    }
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe 'job configuration' do
    it 'is queued on critical queue' do
      expect(described_class.queue_name).to eq('critical')
    end

    it 'retries on StandardError with exponential backoff' do
      # This tests the retry configuration is set up correctly
      expect(described_class.retry_on_exceptions).to include(StandardError)
    end

    it 'discards on ActiveRecord::RecordNotFound' do
      # This tests that certain errors are not retried
      expect(described_class.discard_on_exceptions).to include(ActiveRecord::RecordNotFound)
    end
  end

  describe '#perform' do
    context 'with valid parameters' do
      it 'creates audit log successfully' do
        expect {
          described_class.perform_now(**job_params)
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.user).to eq(admin)
        expect(audit_log.action).to eq('csv_export')
        expect(audit_log.details['store_id']).to eq(store.id)
        expect(audit_log.details['record_count']).to eq(500)
        expect(audit_log.details['performance_metrics']).to be_present
      end

      it 'logs job completion' do
        described_class.perform_now(**job_params)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            event: "csv_export_audit_completed",
            user_id: be_a(String), # filtered
            store_id: store.id,
            record_count: 500
          ).to_json
        )
      end

      it 'sanitizes performance metrics' do
        invalid_metrics = {
          memory_usage: Float::INFINITY,
          processing_time: Float::NAN,
          batch_size: 'invalid'
        }

        job_params[:performance_metrics] = invalid_metrics

        expect {
          described_class.perform_now(**job_params)
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        sanitized_metrics = audit_log.details['performance_metrics']

        expect(sanitized_metrics['memory_usage']).to be_nil
        expect(sanitized_metrics['processing_time']).to be_nil
        expect(sanitized_metrics['batch_size']).to be_nil
      end

      it 'sanitizes request metadata' do
        invalid_metadata = {
          ip_address: 'not-an-ip',
          user_agent: 'a' * 600 # Too long
        }

        job_params[:request_metadata] = invalid_metadata

        expect {
          described_class.perform_now(**job_params)
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.ip_address).to be_nil
        expect(audit_log.user_agent).to have_attributes(length: 500)
      end
    end

    context 'with missing user' do
      it 'raises ActiveRecord::RecordNotFound and gets discarded' do
        job_params[:user_id] = 99999 # Non-existent user

        expect {
          described_class.perform_now(**job_params)
        }.to raise_error(ActiveRecord::RecordNotFound)

        expect(Rails.logger).to have_received(:error).with(
          include("User not found for CSV export audit: 99999")
        )
      end
    end

    context 'with missing store' do
      it 'continues processing with nil store' do
        job_params[:store_id] = 99999 # Non-existent store

        expect {
          described_class.perform_now(**job_params)
        }.to change(AuditLog, :count).by(1)

        audit_log = AuditLog.last
        expect(audit_log.details['store_id']).to be_nil
        expect(audit_log.details['store_name']).to be_nil
      end
    end

    context 'with invalid parameters' do
      it 'raises ArgumentError for missing user_id' do
        job_params.delete(:user_id)

        expect {
          described_class.perform_now(**job_params)
        }.to raise_error(ArgumentError, "user_id is required")
      end

      it 'raises ArgumentError for negative record_count' do
        job_params[:record_count] = -1

        expect {
          described_class.perform_now(**job_params)
        }.to raise_error(ArgumentError, "record_count must be non-negative")
      end

      it 'raises ArgumentError for invalid store_id' do
        job_params[:store_id] = 0

        expect {
          described_class.perform_now(**job_params)
        }.to raise_error(ArgumentError, "store_id must be positive")
      end
    end

    context 'when AuditLog creation fails' do
      before do
        allow(AuditLog).to receive(:create!).and_raise(ActiveRecord::StatementInvalid.new('DB Error'))
      end

      it 'logs error and re-raises for retry' do
        expect {
          described_class.perform_now(**job_params)
        }.to raise_error(ActiveRecord::StatementInvalid)

        expect(Rails.logger).to have_received(:error).with(
          hash_including(
            event: "csv_export_audit_failed",
            error_class: "ActiveRecord::StatementInvalid"
          ).to_json
        )
      end
    end
  end

  describe 'parameter sanitization' do
    describe '#sanitize_performance_metrics' do
      let(:job) { described_class.new }

      it 'sanitizes numeric values correctly' do
        metrics = {
          memory_usage: 1024.567,
          processing_time: Float::INFINITY,
          batch_size: Float::NAN,
          valid_number: 42.123456789
        }

        result = job.send(:sanitize_performance_metrics, metrics)

        expect(result[:memory_usage]).to eq(1024.57)
        expect(result[:processing_time]).to be_nil
        expect(result[:batch_size]).to be_nil
        expect(result[:valid_number]).to be_nil # Not in expected keys
      end

      it 'handles non-hash input gracefully' do
        result = job.send(:sanitize_performance_metrics, 'not a hash')
        expect(result).to eq({})
      end
    end

    describe '#sanitize_request_metadata' do
      let(:job) { described_class.new }

      it 'sanitizes IP addresses' do
        metadata = {
          ip_address: '192.168.1.1',
          invalid_ip: 'not-an-ip',
          user_agent: 'Valid Agent'
        }

        result = job.send(:sanitize_request_metadata, metadata)

        expect(result[:ip_address]).to eq('192.168.1.1')
        expect(result[:invalid_ip]).to be_nil # Not sanitized key
        expect(result[:user_agent]).to eq('Valid Agent')
      end

      it 'truncates long user agents' do
        long_agent = 'a' * 600
        metadata = { user_agent: long_agent }

        result = job.send(:sanitize_request_metadata, metadata)

        expect(result[:user_agent]).to eq('a' * 500)
      end

      it 'handles non-hash input gracefully' do
        result = job.send(:sanitize_request_metadata, 'not a hash')
        expect(result).to eq({})
      end
    end

    describe '#sanitize_ip_address' do
      let(:job) { described_class.new }

      it 'validates correct IP addresses' do
        expect(job.send(:sanitize_ip_address, '192.168.1.1')).to eq('192.168.1.1')
        expect(job.send(:sanitize_ip_address, '10.0.0.1')).to eq('10.0.0.1')
        expect(job.send(:sanitize_ip_address, '255.255.255.255')).to eq('255.255.255.255')
      end

      it 'rejects invalid IP addresses' do
        expect(job.send(:sanitize_ip_address, 'not-an-ip')).to be_nil
        expect(job.send(:sanitize_ip_address, '999.999.999.999')).to be_nil
        expect(job.send(:sanitize_ip_address, '192.168.1')).to be_nil
        expect(job.send(:sanitize_ip_address, 123)).to be_nil
      end
    end

    describe '#sanitize_user_agent' do
      let(:job) { described_class.new }

      it 'truncates long user agents' do
        long_agent = 'a' * 600
        result = job.send(:sanitize_user_agent, long_agent)
        expect(result).to eq('a' * 500)
      end

      it 'handles normal user agents' do
        agent = 'Mozilla/5.0 (compatible; Test)'
        result = job.send(:sanitize_user_agent, agent)
        expect(result).to eq(agent)
      end

      it 'handles non-string input' do
        expect(job.send(:sanitize_user_agent, 123)).to be_nil
        expect(job.send(:sanitize_user_agent, nil)).to be_nil
      end
    end
  end

  describe 'job metadata inclusion' do
    it 'includes job metadata in audit log details' do
      described_class.perform_now(**job_params)

      audit_log = AuditLog.last
      job_metadata = audit_log.details['job_metadata']

      expect(job_metadata).to include(
        'job_id',
        'queue_name',
        'created_at'
      )
      expect(job_metadata['queue_name']).to eq('critical')
    end
  end

  describe 'error handling and logging' do
    it 'includes job_id in all log messages' do
      # This will generate a job_id when the job is created
      job = described_class.new(**job_params)

      expect {
        job.perform(**job_params)
      }.to change(AuditLog, :count).by(1)

      # Check that logs include job_id
      expect(Rails.logger).to have_received(:info).with(
        include('"job_id":')
      )
    end
  end

  describe 'SecureLogging integration' do
    it 'filters sensitive data in error messages' do
      # Mock a failure with sensitive data in error message
      sensitive_error = StandardError.new('Error with password123 in message')
      allow(AuditLog).to receive(:create!).and_raise(sensitive_error)

      expect {
        described_class.perform_now(**job_params)
      }.to raise_error(StandardError)

      # Verify that error message is filtered
      expect(Rails.logger).to have_received(:error).with(
        include('"error_message":"Error with **** in message"')
      )
    end
  end
end
