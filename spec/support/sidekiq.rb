# frozen_string_literal: true

# Sidekiq test configuration for Redis-free testing

RSpec.configure do |config|
  # テスト実行前のSidekiq設定初期化
  config.before(:suite) do
    # テスト環境ではSidekiqをfakeモードで動作（デフォルト）
    Sidekiq::Testing.fake!

    # ActiveJobのテストアダプターを設定（環境設定でinlineが設定されている場合は上書きしない）
    ActiveJob::Base.queue_adapter = :test unless Rails.application.config.active_job.queue_adapter == :inline

    # TODO: Phase 2実装予定 - より高度なジョブテスト機能
    # - ジョブ実行順序の検証
    # - ジョブチェーンの統合テスト
    # - パフォーマンステストの追加
  end

  config.after(:suite) do
    Sidekiq::Testing.disable!
  end

  # 各テスト実行前の設定
  config.before(:each) do
    # ジョブキューのクリア
    Sidekiq::Worker.clear_all
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear if ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)

    # Sidekiqをfakeモードに設定（デフォルト）
    Sidekiq::Testing.fake!
  end

  # ActionCableテストが必要な場合の設定
  config.before(:each, :action_cable) do
    # ActionCableのテストアダプターを有効化
    # Rails.application.config.action_cable.adapter = :test
  end

  # 実際にジョブを実行する必要がある場合
  config.before(:each, :perform_jobs) do
    Sidekiq::Testing.inline!
    ActiveJob::Base.queue_adapter = :inline
  end

  config.after(:each, :perform_jobs) do
    Sidekiq::Testing.fake!
    ActiveJob::Base.queue_adapter = :test
  end

  # feature specでジョブ実行が必要な場合の設定
  config.before(:each, type: :feature) do |example|
    if example.metadata[:js] || example.metadata[:perform_jobs] ||
       example.full_description.include?('CSV Import')
      Sidekiq::Testing.inline!
      ActiveJob::Base.queue_adapter = :inline
    end
  end

  # 特定のジョブテスト用ヘルパーメソッド
  config.include Module.new {
    # キューに入っているジョブの確認
    def jobs_for(job_class)
      job_class.jobs
    end

    # 特定のジョブが実行されたかチェック
    def expect_job_to_be_enqueued(job_class, *args)
      expect(job_class).to have_enqueued_sidekiq_job(*args)
    end

    # ジョブを実際に実行
    def perform_all_jobs
      Sidekiq::Worker.drain_all
    end

    # ActionCableのブロードキャストをモック
    def mock_action_cable_broadcast
      allow(ActionCable.server).to receive(:broadcast)
    end

    # Redis接続エラーをシミュレート
    def simulate_redis_connection_error
      return unless defined?(Redis)
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError.new("Connection refused"))
    end

    # Redis接続チェック
    def redis_available?
      # TODO: docs/TODO.md - Redis接続エラー対策 (優先度: 高)
      # 再接続ロジックや詳細なエラーハンドリングを追加する
      return false unless defined?(RedisClient)
      @redis_available ||= begin
        RedisClient.new(host: 'localhost', port: 6379, timeout: 1).ping
        true
      rescue StandardError
        false
      end
    end

    # Sidekiq UIテストのスキップ判定
    def skip_if_redis_unavailable
      skip 'Redisが利用できないため、Sidekiq UIテストをスキップします' unless redis_available?
    end

    # ジョブの強制実行（テスト環境で確実にジョブを実行したい場合）
    def ensure_job_execution
      # Sidekiqのペンディングジョブを実行
      Sidekiq::Worker.drain_all if Sidekiq::Testing.fake?

      # ActiveJobのペンディングジョブも実行
      if ActiveJob::Base.queue_adapter.respond_to?(:enqueued_jobs)
        ActiveJob::Base.queue_adapter.enqueued_jobs.each do |job|
          job[:job].perform_now
        end
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      end
    end
  }
end

# Custom RSpec matchers for Sidekiq
RSpec::Matchers.define :have_enqueued_sidekiq_job do |*expected_args|
  match do |job_class|
    job_class.jobs.any? do |job|
      if expected_args.any?
        job['args'] == expected_args
      else
        true
      end
    end
  end

  failure_message do |job_class|
    "expected #{job_class} to have enqueued job with args #{expected_args}, but got #{job_class.jobs.map { |j| j['args'] }}"
  end

  failure_message_when_negated do |job_class|
    "expected #{job_class} not to have enqueued job with args #{expected_args}"
  end
end

# ActionCableのテスト用マッチャー
RSpec::Matchers.define :have_broadcasted_to do |stream|
  match do |_actual, &block|
    @broadcasted_messages = []

    # ActionCableのブロードキャストをキャプチャ
    allow(ActionCable.server).to receive(:broadcast) do |stream_name, message|
      @broadcasted_messages << { stream: stream_name, message: message }
    end

    # ブロックが与えられた場合のみ実行
    block.call if block

    @broadcasted_messages.any? { |broadcast| broadcast[:stream] == stream }
  end

  failure_message do |_actual|
    "expected to broadcast to #{stream}, but broadcasts were: #{@broadcasted_messages.map { |b| b[:stream] }}"
  end
end
