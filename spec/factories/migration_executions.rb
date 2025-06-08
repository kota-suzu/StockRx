# frozen_string_literal: true

FactoryBot.define do
  factory :migration_execution do
    association :admin

    version { "20250608#{rand(100000..999999)}" }
    name { "create_test_migration_#{rand(1000..9999)}" }
    status { "pending" }

    configuration do
      {
        "batch_size" => 1000,
        "cpu_threshold" => 75,
        "memory_threshold" => 80,
        "max_retries" => 3,
        "timeout" => 3600
      }
    end

    processed_records { 0 }
    total_records { 10000 }
    progress_percentage { 0.0 }
    retry_count { 0 }
    environment { Rails.env }
    hostname { Socket.gethostname }
    process_id { Process.pid }

    trait :pending do
      status { "pending" }
    end

    trait :running do
      status { "running" }
      started_at { 10.minutes.ago }
      processed_records { 2500 }
      progress_percentage { 25.0 }
    end

    trait :completed do
      status { "completed" }
      started_at { 1.hour.ago }
      completed_at { 30.minutes.ago }
      processed_records { 10000 }
      total_records { 10000 }
      progress_percentage { 100.0 }

      rollback_data do
        [
          {
            "table" => "test_table",
            "action" => "create",
            "rollback_sql" => "DROP TABLE test_table"
          }
        ]
      end
    end

    trait :failed do
      status { "failed" }
      started_at { 2.hours.ago }
      completed_at { 1.hour.ago }
      processed_records { 5000 }
      progress_percentage { 50.0 }
      retry_count { 3 }
      error_message { "Migration failed due to foreign key constraint violation" }
      error_backtrace do
        [
          "/app/db/migrate/20250608123456_create_test_migration.rb:15:in `up'",
          "/app/app/jobs/migration_executor_job.rb:120:in `execute_schema_change_phase'",
          "/app/app/jobs/migration_executor_job.rb:75:in `execute_migration_with_monitoring'"
        ].join("\n")
      end
    end

    trait :paused do
      status { "paused" }
      started_at { 20.minutes.ago }
      processed_records { 3000 }
      progress_percentage { 30.0 }
    end

    trait :cancelled do
      status { "cancelled" }
      started_at { 30.minutes.ago }
      completed_at { 15.minutes.ago }
      processed_records { 1500 }
      progress_percentage { 15.0 }
    end

    trait :rolled_back do
      status { "rolled_back" }
      started_at { 3.hours.ago }
      completed_at { 2.hours.ago }
      processed_records { 10000 }
      total_records { 10000 }
      progress_percentage { 100.0 }

      rollback_data do
        [
          {
            "table" => "test_table",
            "action" => "rollback_completed",
            "original_action" => "create"
          }
        ]
      end
    end

    trait :with_large_dataset do
      total_records { 1_000_000 }
      configuration do
        {
          "batch_size" => 5000,
          "cpu_threshold" => 70,
          "memory_threshold" => 75,
          "max_retries" => 5,
          "timeout" => 7200
        }
      end
    end

    trait :with_high_performance do
      metrics do
        {
          "average_rps" => 2500.0,
          "peak_cpu" => 45.2,
          "peak_memory" => 62.8,
          "total_execution_time" => 1800
        }
      end
    end

    trait :with_performance_issues do
      metrics do
        {
          "average_rps" => 150.0,
          "peak_cpu" => 95.5,
          "peak_memory" => 89.2,
          "total_execution_time" => 7200
        }
      end
    end
  end
end
