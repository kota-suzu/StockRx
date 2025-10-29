# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MemoryMonitor, type: :lib do
  let(:memory_limit_mb) { 100 }
  let(:monitoring_interval) { 5 }
  let(:monitor) { described_class.new(memory_limit_mb, monitoring_interval) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe '#initialize' do
    it 'sets memory limit and monitoring interval' do
      expect(monitor.memory_limit_mb).to eq(memory_limit_mb)
      expect(monitor.monitoring_interval).to eq(monitoring_interval)
    end
  end

  describe '#current_memory_usage' do
    it 'returns current memory usage in MB' do
      usage = monitor.current_memory_usage
      expect(usage).to be >= 0
      expect(usage).to be_a(Float)
    end

    context 'when ObjectSpace is not available' do
      before do
        hide_const('ObjectSpace')
      end

      it 'falls back gracefully' do
        usage = monitor.current_memory_usage
        expect(usage).to eq(0)
      end
    end
  end

  describe '#available_memory_mb' do
    it 'calculates available memory correctly' do
      allow(monitor).to receive(:current_memory_usage).and_return(30.0)

      available = monitor.available_memory_mb
      expect(available).to eq(70.0) # 100 - 30
    end

    it 'returns zero when usage exceeds limit' do
      allow(monitor).to receive(:current_memory_usage).and_return(150.0)

      available = monitor.available_memory_mb
      expect(available).to eq(0)
    end
  end

  describe '#memory_usage_high?' do
    it 'returns true when usage exceeds high threshold' do
      # 90MB usage with 100MB limit = 90% > 80% threshold
      allow(monitor).to receive(:current_memory_usage).and_return(90.0)

      expect(monitor.memory_usage_high?).to be true
    end

    it 'returns false when usage is below high threshold' do
      # 50MB usage with 100MB limit = 50% < 80% threshold
      allow(monitor).to receive(:current_memory_usage).and_return(50.0)

      expect(monitor.memory_usage_high?).to be false
    end
  end

  describe '#memory_usage_critical?' do
    it 'returns true when usage exceeds critical threshold' do
      # 98MB usage with 100MB limit = 98% > 95% threshold
      allow(monitor).to receive(:current_memory_usage).and_return(98.0)

      expect(monitor.memory_usage_critical?).to be true
    end

    it 'returns false when usage is below critical threshold' do
      # 80MB usage with 100MB limit = 80% < 95% threshold
      allow(monitor).to receive(:current_memory_usage).and_return(80.0)

      expect(monitor.memory_usage_critical?).to be false
    end
  end

  describe '#memory_usage_ratio' do
    it 'calculates correct usage ratio' do
      allow(monitor).to receive(:current_memory_usage).and_return(25.0)

      ratio = monitor.memory_usage_ratio
      expect(ratio).to eq(0.25) # 25MB / 100MB
    end
  end

  describe '#check_memory_periodically' do
    context 'when enough time has passed' do
      before do
        # Simulate time passage
        monitor.instance_variable_set(:@last_check_time, 10.seconds.ago)
      end

      it 'checks memory and records usage' do
        allow(monitor).to receive(:current_memory_usage).and_return(50.0)

        monitor.check_memory_periodically

        history = monitor.instance_variable_get(:@memory_history)
        expect(history).not_to be_empty
        expect(history.last[:usage_mb]).to eq(50.0)
      end

      context 'when memory usage is high' do
        it 'handles high memory usage' do
          allow(monitor).to receive(:current_memory_usage).and_return(90.0)

          monitor.check_memory_periodically

          expect(Rails.logger).to have_received(:warn).with(
            hash_including(
              event: "high_memory_usage_detected",
              current_usage_mb: 90.0
            ).to_json
          )
        end
      end

      context 'when memory usage is critical' do
        it 'handles critical memory usage' do
          allow(monitor).to receive(:current_memory_usage).and_return(98.0)
          allow(monitor).to receive(:perform_emergency_memory_cleanup)

          monitor.check_memory_periodically

          expect(Rails.logger).to have_received(:error).with(
            hash_including(
              event: "critical_memory_usage_detected",
              current_usage_mb: 98.0
            ).to_json
          )
        end
      end
    end

    context 'when not enough time has passed' do
      it 'skips the check' do
        # Recent check
        monitor.instance_variable_set(:@last_check_time, 1.second.ago)

        expect(monitor).not_to receive(:current_memory_usage)
        monitor.check_memory_periodically
      end
    end
  end

  describe '#memory_stats' do
    before do
      # Set up some memory history
      history = [
        { timestamp: 5.minutes.ago, usage_mb: 20.0 },
        { timestamp: 4.minutes.ago, usage_mb: 30.0 },
        { timestamp: 3.minutes.ago, usage_mb: 40.0 },
        { timestamp: 2.minutes.ago, usage_mb: 35.0 },
        { timestamp: 1.minute.ago, usage_mb: 45.0 }
      ]
      monitor.instance_variable_set(:@memory_history, history)

      allow(monitor).to receive(:current_memory_usage).and_return(50.0)
    end

    it 'returns comprehensive memory statistics' do
      stats = monitor.memory_stats

      expect(stats).to include(
        current_usage_mb: 50.0,
        limit_mb: 100,
        usage_ratio: 0.5,
        available_mb: 50.0,
        peak_usage_mb: 45.0,
        average_usage_mb: 34.0, # (20+30+40+35+45)/5
        memory_trend: be_a(String)
      )
    end
  end

  describe '#memory_leak_detected?' do
    context 'with insufficient data' do
      it 'returns false when history is too small' do
        expect(monitor.memory_leak_detected?).to be false
      end
    end

    context 'with increasing memory trend' do
      it 'detects potential memory leak' do
        # Create monotonically increasing usage pattern
        history = (1..10).map do |i|
          { timestamp: i.minutes.ago, usage_mb: i * 10.0 }
        end.reverse

        monitor.instance_variable_set(:@memory_history, history)

        expect(monitor.memory_leak_detected?).to be true
      end
    end

    context 'with stable memory usage' do
      it 'does not detect memory leak' do
        # Create stable usage pattern
        history = (1..10).map do |i|
          { timestamp: i.minutes.ago, usage_mb: 50.0 + rand(-5..5) }
        end

        monitor.instance_variable_set(:@memory_history, history)

        expect(monitor.memory_leak_detected?).to be false
      end
    end
  end

  describe 'memory trend analysis' do
    it 'identifies decreasing trend' do
      history = [
        { timestamp: 3.minutes.ago, usage_mb: 60.0 },
        { timestamp: 2.minutes.ago, usage_mb: 50.0 },
        { timestamp: 1.minute.ago, usage_mb: 40.0 },
        { timestamp: 30.seconds.ago, usage_mb: 30.0 },
        { timestamp: Time.current, usage_mb: 20.0 }
      ]
      monitor.instance_variable_set(:@memory_history, history)

      trend = monitor.send(:memory_trend_analysis)
      expect(trend).to eq('decreasing')
    end

    it 'identifies increasing trend' do
      history = [
        { timestamp: 3.minutes.ago, usage_mb: 20.0 },
        { timestamp: 2.minutes.ago, usage_mb: 30.0 },
        { timestamp: 1.minute.ago, usage_mb: 40.0 },
        { timestamp: 30.seconds.ago, usage_mb: 50.0 },
        { timestamp: Time.current, usage_mb: 60.0 }
      ]
      monitor.instance_variable_set(:@memory_history, history)

      trend = monitor.send(:memory_trend_analysis)
      expect(trend).to eq('increasing')
    end

    it 'identifies stable trend' do
      history = [
        { timestamp: 3.minutes.ago, usage_mb: 50.0 },
        { timestamp: 2.minutes.ago, usage_mb: 51.0 },
        { timestamp: 1.minute.ago, usage_mb: 49.0 },
        { timestamp: 30.seconds.ago, usage_mb: 50.5 },
        { timestamp: Time.current, usage_mb: 50.2 }
      ]
      monitor.instance_variable_set(:@memory_history, history)

      trend = monitor.send(:memory_trend_analysis)
      expect(trend).to eq('stable')
    end
  end

  describe 'emergency memory cleanup' do
    it 'performs garbage collection and connection cleanup' do
      expect(GC).to receive(:start)
      expect(ActiveRecord::Base).to receive(:clear_active_connections!)

      monitor.send(:perform_emergency_memory_cleanup)

      expect(Rails.logger).to have_received(:warn)
        .with("Performing emergency memory cleanup")
    end
  end

  describe 'memory history management' do
    it 'limits history size to 100 entries' do
      # Add more than 100 entries
      105.times do |i|
        monitor.send(:record_memory_usage, i.to_f)
      end

      history = monitor.instance_variable_get(:@memory_history)
      expect(history.size).to eq(100)
    end
  end

  describe 'platform-specific memory detection' do
    context 'on Linux' do
      before do
        stub_const('RUBY_PLATFORM', 'x86_64-linux')
        allow(File).to receive(:read).with('/proc/self/status')
                                    .and_return("VmRSS:\t50000 kB\n")
      end

      it 'uses proc filesystem for memory detection' do
        usage = monitor.send(:get_process_memory_usage)
        expect(usage).to eq(50000 * 1024) # 50MB in bytes
      end
    end

    context 'on macOS' do
      before do
        stub_const('RUBY_PLATFORM', 'x86_64-darwin')
        allow(monitor).to receive(:`).with(/ps -o rss/).and_return("50000\n")
      end

      it 'uses ps command for memory detection' do
        usage = monitor.send(:get_process_memory_usage)
        expect(usage).to eq(50000 * 1024) # 50MB in bytes
      end
    end
  end
end
