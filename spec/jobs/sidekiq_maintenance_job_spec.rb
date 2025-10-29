# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/api'

RSpec.describe SidekiqMaintenanceJob, type: :job do
  # CLAUDE.md準拠: Sidekiqメンテナンスジョブの包括的テスト
  # メタ認知: 複数の分析メソッドとクリーンアップロジックの品質保証
  # 横展開: 他のメンテナンス系ジョブでも同様のテストパターン適用

  include ActiveJob::TestHelper

  before do
    # Sidekiqのテストモードを設定
    Sidekiq::Testing.fake!
    # 既存のジョブをクリア
    Sidekiq::Worker.clear_all
  end

  after do
    Sidekiq::Worker.clear_all
  end

  describe '#perform' do
    context 'with default options' do
      it 'runs all maintenance tasks' do
        job = SidekiqMaintenanceJob.new

        expect(job).to receive(:analyze_queue_health).and_return({})
        expect(job).to receive(:clean_old_jobs).and_return(0)
        expect(job).to receive(:analyze_job_performance).and_return({})
        expect(job).to receive(:check_redis_memory).and_return({})
        expect(job).to receive(:generate_recommendations).and_return([])

        job.perform
      end

      it 'creates maintenance report' do
        expect {
          SidekiqMaintenanceJob.perform_now
        }.to change { MaintenanceReport.count }.by(1)
      end

      it 'sends notification on completion' do
        expect {
          SidekiqMaintenanceJob.perform_now
        }.to have_enqueued_mail(AdminMailer, :maintenance_report)
      end
    end

    context 'with specific tasks' do
      it 'runs only specified tasks' do
        job = SidekiqMaintenanceJob.new

        expect(job).to receive(:analyze_queue_health).and_return({})
        expect(job).not_to receive(:clean_old_jobs)
        expect(job).not_to receive(:analyze_job_performance)

        job.perform(tasks: [ 'analyze_queue_health' ])
      end

      it 'handles invalid task names gracefully' do
        expect {
          SidekiqMaintenanceJob.perform_now(tasks: [ 'invalid_task' ])
        }.not_to raise_error
      end
    end

    context 'with cleanup disabled' do
      it 'skips cleanup tasks' do
        job = SidekiqMaintenanceJob.new

        expect(job).not_to receive(:clean_old_jobs)
        expect(job).to receive(:analyze_queue_health).and_return({})

        job.perform(skip_cleanup: true)
      end
    end
  end

  describe '#analyze_queue_health' do
    let(:job) { SidekiqMaintenanceJob.new }

    before do
      # テスト用のジョブをエンキュー
      5.times { TestWorker.perform_async }
      3.times { TestWorker.perform_in(1.hour) }
    end

    it 'analyzes queue sizes' do
      result = job.send(:analyze_queue_health)

      expect(result).to have_key(:queues)
      expect(result[:queues]).to be_a(Hash)
      expect(result[:total_enqueued]).to be >= 0
    end

    it 'identifies queue backlogs' do
      # 大量のジョブをエンキュー
      100.times { TestWorker.perform_async }

      result = job.send(:analyze_queue_health)

      expect(result[:warnings]).to be_present
      expect(result[:warnings]).to include(/backlog detected/)
    end

    it 'calculates queue latency' do
      result = job.send(:analyze_queue_health)

      expect(result).to have_key(:latency)
      expect(result[:latency]).to be_a(Hash)
    end

    it 'detects stale queues' do
      # 古いジョブを作成
      allow_any_instance_of(Sidekiq::Queue).to receive(:first) do
        double(enqueued_at: 2.days.ago.to_f)
      end

      result = job.send(:analyze_queue_health)

      expect(result[:stale_queues]).to be_present
    end
  end

  describe '#clean_old_jobs' do
    let(:job) { SidekiqMaintenanceJob.new }

    before do
      # RetrySetとDeadSetのモック
      @retry_set = Sidekiq::RetrySet.new
      @dead_set = Sidekiq::DeadSet.new

      # 古いジョブのモック
      allow(@retry_set).to receive(:each).and_yield(
        double(enqueued_at: 35.days.ago.to_f, delete: true)
      )
      allow(@dead_set).to receive(:each).and_yield(
        double(enqueued_at: 35.days.ago.to_f, delete: true)
      )
    end

    it 'removes old retry jobs' do
      expect(@retry_set).to receive(:each)

      count = job.send(:clean_old_jobs)
      expect(count).to be > 0
    end

    it 'removes old dead jobs' do
      expect(@dead_set).to receive(:each)

      job.send(:clean_old_jobs)
    end

    it 'respects retention period' do
      recent_job = double(enqueued_at: 5.days.ago.to_f)
      allow(@retry_set).to receive(:each).and_yield(recent_job)

      expect(recent_job).not_to receive(:delete)

      job.send(:clean_old_jobs, retention_days: 30)
    end

    it 'logs cleanup activity' do
      expect(Rails.logger).to receive(:info).with(/Cleaned/)

      job.send(:clean_old_jobs)
    end
  end

  describe '#analyze_job_performance' do
    let(:job) { SidekiqMaintenanceJob.new }

    before do
      # パフォーマンスデータのセットアップ
      allow(Redis.new).to receive(:hgetall).with('job_performance').and_return({
        'TestWorker' => '{"count":100,"total_time":500.0,"errors":5}',
        'SlowWorker' => '{"count":10,"total_time":1000.0,"errors":0}'
      })
    end

    it 'calculates average execution time' do
      result = job.send(:analyze_job_performance)

      expect(result[:by_class]).to be_present
      expect(result[:by_class]['TestWorker'][:avg_time]).to eq(5.0)
      expect(result[:by_class]['SlowWorker'][:avg_time]).to eq(100.0)
    end

    it 'identifies slow jobs' do
      result = job.send(:analyze_job_performance)

      expect(result[:slow_jobs]).to include('SlowWorker')
      expect(result[:slow_jobs]).not_to include('TestWorker')
    end

    it 'calculates error rates' do
      result = job.send(:analyze_job_performance)

      expect(result[:by_class]['TestWorker'][:error_rate]).to eq(5.0)
      expect(result[:by_class]['SlowWorker'][:error_rate]).to eq(0.0)
    end

    it 'identifies high error rate jobs' do
      result = job.send(:analyze_job_performance)

      expect(result[:high_error_jobs]).to be_present
      expect(result[:high_error_jobs]).to include(
        hash_including(class: 'TestWorker', error_rate: 5.0)
      )
    end

    it 'handles missing performance data' do
      allow(Redis.new).to receive(:hgetall).and_return({})

      result = job.send(:analyze_job_performance)

      expect(result[:by_class]).to be_empty
      expect(result[:slow_jobs]).to be_empty
    end
  end

  describe '#check_redis_memory' do
    let(:job) { SidekiqMaintenanceJob.new }

    before do
      @redis_info = {
        'used_memory' => '100000000',
        'used_memory_human' => '95.37M',
        'used_memory_peak' => '150000000',
        'used_memory_peak_human' => '143.05M',
        'maxmemory' => '500000000',
        'maxmemory_human' => '476.84M'
      }

      allow(Redis.new).to receive(:info).with('memory').and_return(@redis_info)
    end

    it 'reports memory usage' do
      result = job.send(:check_redis_memory)

      expect(result[:current_usage]).to eq('95.37M')
      expect(result[:peak_usage]).to eq('143.05M')
      expect(result[:max_memory]).to eq('476.84M')
    end

    it 'calculates usage percentage' do
      result = job.send(:check_redis_memory)

      expect(result[:usage_percent]).to eq(20.0)
    end

    it 'warns on high memory usage' do
      @redis_info['used_memory'] = '400000000'
      @redis_info['used_memory_human'] = '381.47M'

      result = job.send(:check_redis_memory)

      expect(result[:warnings]).to include(/High memory usage/)
    end

    it 'handles unlimited memory configuration' do
      @redis_info['maxmemory'] = '0'

      result = job.send(:check_redis_memory)

      expect(result[:usage_percent]).to be_nil
      expect(result[:max_memory]).to eq('unlimited')
    end
  end

  describe '#generate_recommendations' do
    let(:job) { SidekiqMaintenanceJob.new }

    context 'with queue issues' do
      let(:queue_analysis) do
        {
          queues: { default: 1000, critical: 50 },
          warnings: [ 'High backlog detected in default queue' ],
          latency: { default: 300 }
        }
      end

      it 'recommends scaling workers' do
        recommendations = job.send(:generate_recommendations,
          queue_health: queue_analysis
        )

        expect(recommendations).to include(
          hash_including(
            type: 'scale_workers',
            priority: 'high'
          )
        )
      end

      it 'suggests queue optimization' do
        recommendations = job.send(:generate_recommendations,
          queue_health: queue_analysis
        )

        expect(recommendations).to include(
          hash_including(
            type: 'optimize_queue',
            details: /Split high-volume jobs/
          )
        )
      end
    end

    context 'with performance issues' do
      let(:performance_analysis) do
        {
          slow_jobs: [ 'SlowWorker', 'HeavyWorker' ],
          high_error_jobs: [
            { class: 'ErrorProneWorker', error_rate: 15.0 }
          ]
        }
      end

      it 'recommends job optimization' do
        recommendations = job.send(:generate_recommendations,
          job_performance: performance_analysis
        )

        expect(recommendations).to include(
          hash_including(
            type: 'optimize_job',
            target: 'SlowWorker'
          )
        )
      end

      it 'recommends error investigation' do
        recommendations = job.send(:generate_recommendations,
          job_performance: performance_analysis
        )

        expect(recommendations).to include(
          hash_including(
            type: 'investigate_errors',
            target: 'ErrorProneWorker'
          )
        )
      end
    end

    context 'with memory pressure' do
      let(:memory_analysis) do
        {
          usage_percent: 85.0,
          warnings: [ 'High memory usage: 85.0%' ]
        }
      end

      it 'recommends memory optimization' do
        recommendations = job.send(:generate_recommendations,
          redis_memory: memory_analysis
        )

        expect(recommendations).to include(
          hash_including(
            type: 'memory_optimization',
            priority: 'critical'
          )
        )
      end

      it 'suggests specific memory reduction strategies' do
        recommendations = job.send(:generate_recommendations,
          redis_memory: memory_analysis
        )

        memory_rec = recommendations.find { |r| r[:type] == 'memory_optimization' }
        expect(memory_rec[:actions]).to include(
          'Reduce job retention period',
          'Clear unused keys',
          'Optimize data structures'
        )
      end
    end

    context 'with no issues' do
      it 'returns empty recommendations' do
        recommendations = job.send(:generate_recommendations,
          queue_health: { queues: { default: 5 }, warnings: [] },
          job_performance: { slow_jobs: [], high_error_jobs: [] },
          redis_memory: { usage_percent: 30.0 }
        )

        expect(recommendations).to be_empty
      end
    end
  end

  describe '#create_maintenance_report' do
    let(:job) { SidekiqMaintenanceJob.new }
    let(:analysis_results) do
      {
        queue_health: { queues: { default: 10 } },
        job_performance: { slow_jobs: [] },
        redis_memory: { usage_percent: 50.0 },
        cleaned_jobs: 25,
        recommendations: []
      }
    end

    it 'creates report record' do
      expect {
        job.send(:create_maintenance_report, analysis_results)
      }.to change { MaintenanceReport.count }.by(1)
    end

    it 'stores analysis data' do
      report = job.send(:create_maintenance_report, analysis_results)

      expect(report.report_type).to eq('sidekiq_maintenance')
      expect(report.data['queue_health']).to be_present
      expect(report.data['job_performance']).to be_present
      expect(report.data['redis_memory']).to be_present
    end

    it 'includes summary metrics' do
      report = job.send(:create_maintenance_report, analysis_results)

      expect(report.summary).to include(
        'total_queued' => 10,
        'cleaned_jobs' => 25,
        'redis_usage' => 50.0
      )
    end
  end

  describe 'error handling' do
    let(:job) { SidekiqMaintenanceJob.new }

    it 'handles Redis connection errors' do
      allow(Redis.new).to receive(:info).and_raise(Redis::ConnectionError)

      expect {
        job.perform
      }.not_to raise_error
    end

    it 'logs errors and continues' do
      allow(job).to receive(:analyze_queue_health).and_raise(StandardError, 'Test error')
      expect(Rails.logger).to receive(:error).with(/Failed to analyze queue health/)

      job.perform
    end

    it 'creates partial report on errors' do
      allow(job).to receive(:analyze_job_performance).and_raise(StandardError)

      expect {
        job.perform
      }.to change { MaintenanceReport.count }.by(1)

      report = MaintenanceReport.last
      expect(report.data['errors']).to be_present
    end
  end

  describe 'performance' do
    let(:job) { SidekiqMaintenanceJob.new }

    it 'completes within reasonable time' do
      # 大量のジョブデータを作成
      100.times { TestWorker.perform_async }

      start_time = Time.current
      job.perform
      duration = Time.current - start_time

      expect(duration).to be < 30.seconds
    end

    it 'uses batch processing for large datasets' do
      # 大量のリトライジョブ
      retry_set = Sidekiq::RetrySet.new
      allow(retry_set).to receive(:size).and_return(10000)

      expect(retry_set).to receive(:each).with(limit: 1000)

      job.send(:clean_old_jobs)
    end
  end

  # テスト用のワーカークラス
  class TestWorker
    include Sidekiq::Worker

    def perform
      # テスト用の空実装
    end
  end
end
