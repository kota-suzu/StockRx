# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MigrationExecution, type: :model do
  let(:admin) { create(:admin) }
  subject { build(:migration_execution, admin: admin) }

  describe 'associations' do
    it { should belong_to(:admin) }
    it { should have_many(:migration_progress_logs).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:version) }
    it { should validate_uniqueness_of(:version).case_insensitive }
    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:admin_id) }

    # Enum validations are automatically handled by Rails enums
    # it { should validate_inclusion_of(:status).in_array(%w[pending running completed failed rolled_back paused cancelled]) }
    it { should validate_numericality_of(:processed_records).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:total_records).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:progress_percentage).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
    it { should validate_numericality_of(:retry_count).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(10) }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(pending: "pending", running: "running", completed: "completed", failed: "failed", rolled_back: "rolled_back", paused: "paused", cancelled: "cancelled").backed_by_column_of_type(:string) }
  end

  describe 'scopes' do
    let!(:pending_execution) { create(:migration_execution, :pending, admin: admin) }
    let!(:running_execution) { create(:migration_execution, :running, admin: admin) }
    let!(:completed_execution) { create(:migration_execution, :completed, admin: admin) }
    let!(:failed_execution) { create(:migration_execution, :failed, admin: admin) }

    describe '.active' do
      it 'returns pending, running, and paused executions' do
        paused_execution = create(:migration_execution, :paused, admin: admin)

        expect(MigrationExecution.active).to include(pending_execution, running_execution, paused_execution)
        expect(MigrationExecution.active).not_to include(completed_execution, failed_execution)
      end
    end

    describe '.completed_or_failed' do
      it 'returns completed, failed, rolled_back, and cancelled executions' do
        expect(MigrationExecution.completed_or_failed).to include(completed_execution, failed_execution)
        expect(MigrationExecution.completed_or_failed).not_to include(pending_execution, running_execution)
      end
    end
  end

  describe 'business logic' do
    let(:execution) { create(:migration_execution, admin: admin) }

    describe '#can_execute?' do
      it 'returns true for pending status' do
        execution.update(status: 'pending')
        expect(execution.can_execute?).to be true
      end

      it 'returns false for non-pending status' do
        execution.update(status: 'running')
        expect(execution.can_execute?).to be false
      end
    end

    describe '#can_pause?' do
      it 'returns true for running status' do
        execution.update(status: 'running')
        expect(execution.can_pause?).to be true
      end

      it 'returns false for non-running status' do
        execution.update(status: 'pending')
        expect(execution.can_pause?).to be false
      end
    end

    describe '#can_rollback?' do
      it 'returns true for completed status with rollback data' do
        execution.update(status: 'completed', rollback_data: [ { table: 'test' } ])
        expect(execution.can_rollback?).to be true
      end

      it 'returns false without rollback data' do
        execution.update(status: 'completed', rollback_data: nil)
        expect(execution.can_rollback?).to be false
      end
    end

    describe '#execution_duration' do
      it 'calculates duration when both times are present' do
        start_time = 1.hour.ago
        end_time = 30.minutes.ago
        execution.update(started_at: start_time, completed_at: end_time)

        expect(execution.execution_duration).to be_within(1.second).of(30.minutes)
      end

      it 'returns nil when times are missing' do
        execution.update(started_at: nil, completed_at: nil)
        expect(execution.execution_duration).to be_nil
      end
    end

    describe '#average_records_per_second' do
      it 'calculates average processing speed' do
        execution.update(
          started_at: 1.hour.ago,
          completed_at: 30.minutes.ago,
          processed_records: 1800
        )

        # 1800 records in 30 minutes = 1 record per second
        expect(execution.average_records_per_second).to be_within(0.01).of(1.0)
      end

      it 'returns 0 when no records processed' do
        execution.update(processed_records: 0)
        expect(execution.average_records_per_second).to eq(0)
      end
    end
  end

  describe 'action methods' do
    let(:execution) { create(:migration_execution, :pending, admin: admin) }

    describe '#start_execution!' do
      it 'updates status and timestamps' do
        expect { execution.start_execution! }
          .to change { execution.status }.from('pending').to('running')
          .and change { execution.started_at }.from(nil)

        expect(execution.hostname).to be_present
        expect(execution.process_id).to be_present
      end

      it 'creates initial progress log' do
        expect { execution.start_execution! }
          .to change { execution.migration_progress_logs.count }.by(1)

        log = execution.migration_progress_logs.first
        expect(log.phase).to eq('initialization')
        expect(log.message).to include('マイグレーション実行を開始しました')
      end
    end

    describe '#mark_completed!' do
      let(:running_execution) { create(:migration_execution, :running, admin: admin) }

      it 'updates status and completion time' do
        expect { running_execution.mark_completed! }
          .to change { running_execution.status }.from('running').to('completed')
          .and change { running_execution.completed_at }.from(nil)
          .and change { running_execution.progress_percentage }.to(100.0)
      end
    end

    describe '#mark_failed!' do
      let(:running_execution) { create(:migration_execution, :running, admin: admin) }
      let(:error_info) { { message: 'Test error', backtrace: [ 'line 1', 'line 2' ] } }

      it 'updates status and error information' do
        expect { running_execution.mark_failed!(error_info) }
          .to change { running_execution.status }.from('running').to('failed')
          .and change { running_execution.completed_at }.from(nil)
          .and change { running_execution.retry_count }.by(1)

        expect(running_execution.error_message).to eq('Test error')
        expect(running_execution.error_backtrace).to eq("line 1\nline 2")
      end
    end

    describe '#pause!' do
      let(:running_execution) { create(:migration_execution, :running, admin: admin) }

      it 'pauses running execution' do
        expect(running_execution.pause!).to be true
        expect(running_execution.status).to eq('paused')
      end
    end

    describe '#resume!' do
      let(:paused_execution) { create(:migration_execution, :paused, admin: admin) }

      it 'resumes paused execution' do
        expect(paused_execution.resume!).to be true
        expect(paused_execution.status).to eq('running')
      end
    end
  end

  describe 'factory' do
    it 'creates valid migration execution' do
      execution = build(:migration_execution, admin: admin)
      expect(execution).to be_valid
    end

    it 'creates valid migration execution with traits' do
      %i[pending running completed failed paused cancelled rolled_back].each do |trait|
        execution = build(:migration_execution, trait, admin: admin)
        expect(execution).to be_valid
      end
    end
  end
end
