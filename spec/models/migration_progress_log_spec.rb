# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MigrationProgressLog, type: :model do
  let(:admin) { create(:admin) }
  let(:migration_execution) { create(:migration_execution, admin: admin) }

  describe 'associations' do
    it { should belong_to(:migration_execution) }
  end

  describe 'validations' do
    it { should validate_presence_of(:migration_execution_id) }
    it { should validate_presence_of(:phase) }
    # Length validation not needed for enum fields
    # it { should validate_length_of(:phase).is_at_most(100) }
    it { should validate_presence_of(:progress_percentage) }
    it { should validate_presence_of(:log_level) }

    it { should validate_numericality_of(:progress_percentage).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { should validate_numericality_of(:processed_records).is_greater_than_or_equal_to(0) }

    # Enum validations are automatically handled by Rails enums
    # it { should validate_inclusion_of(:log_level).in_array(%w[debug info warn error fatal]) }
    # it { should validate_inclusion_of(:phase).in_array(%w[initialization schema_change data_migration index_creation validation cleanup rollback]) }
  end

  describe 'enums' do
    it { should define_enum_for(:log_level).with_values(debug: "debug", info: "info", warn: "warn", error: "error", fatal: "fatal").backed_by_column_of_type(:string) }
    it { should define_enum_for(:phase).with_values(
      initialization: "initialization",
      schema_change: "schema_change",
      data_migration: "data_migration",
      index_creation: "index_creation",
      validation: "validation",
      cleanup: "cleanup",
      rollback: "rollback"
    ).backed_by_column_of_type(:string) }
  end

  describe 'scopes' do
    let!(:old_log) { create(:migration_progress_log, migration_execution: migration_execution, created_at: 1.day.ago) }
    let!(:recent_log) { create(:migration_progress_log, migration_execution: migration_execution, created_at: 5.minutes.ago) }
    let!(:warn_log) { create(:migration_progress_log, :warn_level, migration_execution: migration_execution, created_at: 2.minutes.ago) }
    let!(:error_log) { create(:migration_progress_log, :error_level, migration_execution: migration_execution, created_at: 1.minute.ago) }

    describe '.chronological' do
      it 'orders by created_at ascending' do
        expect(MigrationProgressLog.chronological.first).to eq(old_log)
        expect(MigrationProgressLog.chronological.last).to eq(error_log)
      end
    end

    describe '.reverse_chronological' do
      it 'orders by created_at descending' do
        expect(MigrationProgressLog.reverse_chronological.first).to eq(error_log)
      end
    end

    describe '.errors_and_fatals' do
      it 'returns error and fatal level logs' do
        fatal_log = create(:migration_progress_log, log_level: 'fatal', migration_execution: migration_execution)

        expect(MigrationProgressLog.errors_and_fatals).to include(error_log, fatal_log)
        expect(MigrationProgressLog.errors_and_fatals).not_to include(warn_log)
      end
    end

    describe '.warnings_and_above' do
      it 'returns warn, error, and fatal level logs' do
        expect(MigrationProgressLog.warnings_and_above).to include(error_log, warn_log)
        expect(MigrationProgressLog.warnings_and_above).not_to include(recent_log)
      end
    end

    describe '.recent' do
      it 'returns logs from specified minutes ago' do
        expect(MigrationProgressLog.recent(10)).to include(recent_log)
        expect(MigrationProgressLog.recent(10)).not_to include(old_log)
      end
    end
  end

  describe 'business logic' do
    let(:progress_log) { create(:migration_progress_log, migration_execution: migration_execution) }

    describe '#formatted_message' do
      it 'returns formatted message with timestamp and indicators' do
        progress_log.update(
          log_level: 'info',
          phase: 'data_migration',
          message: 'Processing batch'
        )

        formatted = progress_log.formatted_message
        expect(formatted).to include('ℹ️')
        expect(formatted).to include('[Data migration]')
        expect(formatted).to include('Processing batch')
      end
    end

    describe '#log_level_indicator' do
      it 'returns correct emoji for each log level' do
        expect(create(:migration_progress_log, log_level: 'debug', migration_execution: migration_execution).log_level_indicator).to eq('🔍')
        expect(create(:migration_progress_log, log_level: 'info', migration_execution: migration_execution).log_level_indicator).to eq('ℹ️')
        expect(create(:migration_progress_log, log_level: 'warn', migration_execution: migration_execution).log_level_indicator).to eq('⚠️')
        expect(create(:migration_progress_log, log_level: 'error', migration_execution: migration_execution).log_level_indicator).to eq('❌')
        expect(create(:migration_progress_log, log_level: 'fatal', migration_execution: migration_execution).log_level_indicator).to eq('💀')
      end
    end

    describe '#performance_summary' do
      it 'returns performance metrics hash' do
        progress_log.update(
          records_per_second: 1500.5,
          current_batch_size: 1000,
          metrics: { 'cpu_usage' => 45.2, 'memory_usage' => 62.8 }
        )

        summary = progress_log.performance_summary
        expect(summary[:records_per_second]).to eq(1500.5)
        expect(summary[:batch_size]).to eq(1000)
        expect(summary[:cpu_usage]).to eq(45.2)
        expect(summary[:memory_usage]).to eq(62.8)
      end
    end

    describe '#calculate_efficiency_score' do
      it 'calculates efficiency score based on metrics' do
        progress_log.update(
          records_per_second: 2000.0,
          metrics: { 'cpu_usage' => 40.0, 'memory_usage' => 60.0 }
        )

        score = progress_log.calculate_efficiency_score
        expect(score).to be > 0
        expect(score).to be <= 100
      end

      it 'returns nil when required metrics are missing' do
        progress_log.update(records_per_second: nil)
        expect(progress_log.calculate_efficiency_score).to be_nil
      end
    end

    describe '#requires_alert?' do
      it 'returns true for error/fatal log levels' do
        error_log = create(:migration_progress_log, :error_level, migration_execution: migration_execution)
        expect(error_log.requires_alert?).to be true
      end

      it 'returns true for high resource usage' do
        progress_log.update(metrics: { 'cpu_usage' => 95.0 })
        expect(progress_log.requires_alert?).to be true
      end

      it 'returns false for normal conditions' do
        progress_log.update(
          log_level: 'info',
          metrics: { 'cpu_usage' => 50.0, 'memory_usage' => 60.0 },
          records_per_second: 1000.0
        )
        expect(progress_log.requires_alert?).to be false
      end
    end

    describe '#broadcast_data' do
      it 'returns properly formatted data for ActionCable' do
        progress_log.update(
          phase: 'data_migration',
          progress_percentage: 45.5,
          processed_records: 4550,
          message: 'Processing batch 10',
          log_level: 'info',
          metrics: { 'cpu_usage' => 45.2 }
        )

        data = progress_log.broadcast_data
        expect(data[:phase]).to eq('data_migration')
        expect(data[:progress_percentage]).to eq(45.5)
        expect(data[:processed_records]).to eq(4550)
        expect(data[:message]).to eq('Processing batch 10')
        expect(data[:log_level]).to eq('info')
        expect(data[:system_metrics]).to include('cpu_usage' => 45.2)
      end
    end
  end

  describe 'class methods' do
    describe '.create_log_entry' do
      it 'creates log entry with specified parameters' do
        log = MigrationProgressLog.create_log_entry(
          migration_execution,
          'data_migration',
          50.0,
          'Processing batch 5',
          level: 'info',
          processed_records: 5000,
          batch_size: 1000
        )

        expect(log.migration_execution).to eq(migration_execution)
        expect(log.phase).to eq('data_migration')
        expect(log.progress_percentage).to eq(50.0)
        expect(log.message).to eq('Processing batch 5')
        expect(log.log_level).to eq('info')
        expect(log.processed_records).to eq(5000)
        expect(log.current_batch_size).to eq(1000)
      end
    end

    describe '.progress_summary_for' do
      let!(:logs) do
        [
          create(:migration_progress_log, :info_level, migration_execution: migration_execution, records_per_second: 1500.0),
          create(:migration_progress_log, :warn_level, migration_execution: migration_execution, records_per_second: 800.0),
          create(:migration_progress_log, :error_level, migration_execution: migration_execution)
        ]
      end

      it 'returns summary statistics for migration execution' do
        summary = MigrationProgressLog.progress_summary_for(migration_execution)

        expect(summary[:total_logs]).to eq(3)
        expect(summary[:error_count]).to eq(1)
        expect(summary[:warning_count]).to eq(1)
        expect(summary[:average_rps]).to be_present
      end
    end
  end

  describe 'callbacks' do
    it 'updates parent execution progress on create' do
      expect(migration_execution).to receive(:update_columns)

      create(:migration_progress_log,
        migration_execution: migration_execution,
        progress_percentage: 25.0,
        processed_records: 2500
      )
    end
  end

  describe 'factory' do
    it 'creates valid migration progress log' do
      log = build(:migration_progress_log, migration_execution: migration_execution)
      expect(log).to be_valid
    end

    it 'creates valid logs with different traits' do
      traits = %i[initialization schema_change data_migration index_creation validation cleanup rollback]
      traits.each do |trait|
        log = build(:migration_progress_log, trait, migration_execution: migration_execution)
        expect(log).to be_valid
      end
    end

    it 'creates valid logs with different log levels' do
      levels = %i[info_level warn_level error_level debug_level]
      levels.each do |level|
        log = build(:migration_progress_log, level, migration_execution: migration_execution)
        expect(log).to be_valid
      end
    end
  end
end
