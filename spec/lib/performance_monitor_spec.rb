# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PerformanceMonitor, type: :lib do
  let(:job_id) { 'test-job-123' }
  let(:monitor) { described_class.new(job_id) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:debug)
    allow(Rails.logger).to receive(:warn)
  end

  describe '#initialize' do
    it 'sets job_id and initializes metrics' do
      expect(monitor.job_id).to eq(job_id)
      expect(monitor.metrics).to be_a(Hash)
      expect(monitor.metrics[:processed_records]).to eq(0)
      expect(monitor.metrics[:batch_count]).to eq(0)
    end
  end

  describe '#start_monitoring' do
    it 'records start time and logs monitoring start' do
      freeze_time do
        monitor.start_monitoring

        expect(monitor.start_time).to eq(Time.current)
        expect(monitor.metrics[:started_at]).to eq(Time.current.iso8601)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            event: "performance_monitoring_started",
            job_id: job_id
          ).to_json
        )
      end
    end
  end

  describe '#stop_monitoring' do
    before { monitor.start_monitoring }

    it 'calculates total duration and logs monitoring stop' do
      travel_time(5.seconds) do
        monitor.stop_monitoring

        expect(monitor.metrics[:stopped_at]).to be_present
        expect(monitor.metrics[:total_duration]).to be_within(0.1).of(5.0)

        expect(Rails.logger).to have_received(:info).with(
          hash_including(
            event: "performance_monitoring_stopped",
            job_id: job_id,
            performance_stats: hash_including(:total_duration)
          ).to_json
        )
      end
    end

    it 'does nothing if monitoring was not started' do
      monitor_without_start = described_class.new('test-job-456')
      monitor_without_start.stop_monitoring

      expect(monitor_without_start.metrics[:stopped_at]).to be_nil
    end
  end

  describe '#record_batch_completion' do
    let(:batch_size) { 100 }

    before { monitor.start_monitoring }

    it 'updates metrics with batch information' do
      monitor.record_batch_completion(batch_size)

      expect(monitor.metrics[:processed_records]).to eq(batch_size)
      expect(monitor.metrics[:batch_count]).to eq(1)
      expect(monitor.metrics[:average_batch_time]).to be > 0
      expect(monitor.metrics[:peak_memory_usage]).to be >= 0
    end

    it 'logs batch completion' do
      monitor.record_batch_completion(batch_size)

      expect(Rails.logger).to have_received(:debug).with(
        hash_including(
          event: "batch_completion_recorded",
          job_id: job_id,
          batch_size: batch_size
        ).to_json
      )
    end

    it 'calculates correct averages across multiple batches' do
      monitor.record_batch_completion(50)
      monitor.record_batch_completion(100)
      monitor.record_batch_completion(150)

      expect(monitor.metrics[:processed_records]).to eq(300)
      expect(monitor.metrics[:batch_count]).to eq(3)
      expect(monitor.metrics[:average_batch_time]).to be > 0
    end
  end

  describe '#record_error' do
    let(:error) { StandardError.new('Test error') }

    it 'records error with metadata' do
      monitor.record_error(error)

      error_record = monitor.metrics[:errors].first
      expect(error_record[:error_class]).to eq('StandardError')
      expect(error_record[:error_message]).to eq('Test error')
      expect(error_record[:timestamp]).to be_present
      expect(error_record[:processed_records]).to eq(0)
    end

    it 'logs error recording' do
      monitor.record_error(error)

      expect(Rails.logger).to have_received(:warn).with(
        hash_including(
          event: "error_recorded_in_monitoring",
          job_id: job_id
        ).to_json
      )
    end
  end

  describe '#performance_stats' do
    before do
      monitor.start_monitoring
      monitor.record_batch_completion(100)
      monitor.record_batch_completion(200)
    end

    it 'returns comprehensive performance statistics' do
      travel_time(10.seconds) do
        stats = monitor.performance_stats

        expect(stats).to include(
          job_id: job_id,
          total_duration: be_within(0.1).of(10.0),
          records_per_second: be_within(1).of(30.0), # 300 records / 10 seconds
          average_batch_time: be > 0,
          peak_memory_mb: be >= 0,
          error_count: 0,
          efficiency_score: be_between(0, 100)
        )
      end
    end
  end

  describe '#calculate_efficiency_score' do
    before { monitor.start_monitoring }

    context 'with good performance and no errors' do
      it 'calculates high efficiency score' do
        # Simulate fast processing: 1000 records in 5 seconds = 200 records/sec
        travel_time(5.seconds) do
          10.times { monitor.record_batch_completion(100) }

          score = monitor.calculate_efficiency_score
          expect(score).to be > 50 # Should get high score for fast processing
        end
      end
    end

    context 'with slow performance' do
      it 'calculates lower efficiency score' do
        # Simulate slow processing: 100 records in 10 seconds = 10 records/sec
        travel_time(10.seconds) do
          monitor.record_batch_completion(100)

          score = monitor.calculate_efficiency_score
          expect(score).to be < 50 # Should get lower score for slow processing
        end
      end
    end

    context 'with errors' do
      it 'reduces efficiency score based on error rate' do
        travel_time(1.second) do
          monitor.record_batch_completion(100)
          monitor.record_error(StandardError.new('Test error'))

          score = monitor.calculate_efficiency_score
          expect(score).to be < 100 # Errors should reduce the score
        end
      end
    end

    context 'with no processed records' do
      it 'returns zero score' do
        score = monitor.calculate_efficiency_score
        expect(score).to eq(0)
      end
    end
  end

  describe 'memory usage tracking' do
    it 'tracks peak memory usage across batches' do
      monitor.start_monitoring

      # Record multiple batches to see memory tracking
      5.times { monitor.record_batch_completion(50) }

      expect(monitor.metrics[:peak_memory_usage]).to be >= 0
    end
  end

  describe 'edge cases' do
    it 'handles division by zero in calculations' do
      expect { monitor.performance_stats }.not_to raise_error
      expect { monitor.calculate_efficiency_score }.not_to raise_error
    end

    it 'handles very small time durations' do
      monitor.start_monitoring

      # Immediately record completion
      monitor.record_batch_completion(100)

      expect { monitor.performance_stats }.not_to raise_error
    end
  end

  private

  def travel_time(duration)
    travel(duration) { yield }
  end

  def freeze_time
    freeze_time_to = Time.current
    travel_to(freeze_time_to) { yield }
  end
end
