# frozen_string_literal: true

FactoryBot.define do
  factory :migration_progress_log do
    association :migration_execution

    phase { "data_migration" }
    progress_percentage { rand(0.0..100.0).round(2) }
    processed_records { rand(0..10000) }
    message { "バッチ処理中..." }
    log_level { "info" }

    current_batch_size { 1000 }
    current_batch_number { rand(1..100) }
    records_per_second { rand(500.0..2000.0).round(2) }
    estimated_remaining_seconds { rand(60..3600) }

    metrics do
      {
        "cpu_usage" => rand(20.0..80.0).round(1),
        "memory_usage" => rand(30.0..90.0).round(1),
        "db_connections" => rand(5..20),
        "query_time" => rand(0.1..1.0).round(3),
        "records_per_second" => rand(500..2000)
      }
    end

    broadcasted { false }

    trait :initialization do
      phase { "initialization" }
      progress_percentage { 0.0 }
      processed_records { 0 }
      message { "マイグレーション実行の初期化を開始" }
    end

    trait :schema_change do
      phase { "schema_change" }
      progress_percentage { rand(10.0..40.0).round(2) }
      message { "スキーマ変更を実行中" }
    end

    trait :data_migration do
      phase { "data_migration" }
      progress_percentage { rand(40.0..80.0).round(2) }
      message { "データ移行を実行中" }
      current_batch_size { 1000 }
      current_batch_number { rand(1..50) }
    end

    trait :index_creation do
      phase { "index_creation" }
      progress_percentage { rand(80.0..90.0).round(2) }
      message { "インデックスを作成中" }
    end

    trait :validation do
      phase { "validation" }
      progress_percentage { rand(90.0..95.0).round(2) }
      message { "データ整合性を検証中" }
    end

    trait :cleanup do
      phase { "cleanup" }
      progress_percentage { rand(95.0..100.0).round(2) }
      message { "クリーンアップを実行中" }
    end

    trait :rollback do
      phase { "rollback" }
      progress_percentage { rand(0.0..100.0).round(2) }
      message { "ロールバックを実行中" }
    end

    trait :info_level do
      log_level { "info" }
      message { "正常に処理中です" }
    end

    trait :warn_level do
      log_level { "warn" }
      message { "システムリソースが高負荷状態です" }
      metrics do
        {
          "cpu_usage" => rand(80.0..95.0).round(1),
          "memory_usage" => rand(85.0..95.0).round(1),
          "db_connections" => rand(15..25),
          "query_time" => rand(1.0..3.0).round(3)
        }
      end
    end

    trait :error_level do
      log_level { "error" }
      message { "バッチ処理中にエラーが発生しました" }
      metrics do
        {
          "cpu_usage" => rand(90.0..100.0).round(1),
          "memory_usage" => rand(95.0..100.0).round(1),
          "db_connections" => rand(20..30),
          "query_time" => rand(5.0..10.0).round(3)
        }
      end
    end

    trait :debug_level do
      log_level { "debug" }
      message { "デバッグ情報: バッチ#{rand(1..100)}を処理中" }
    end

    trait :high_performance do
      records_per_second { rand(2000.0..5000.0).round(2) }
      metrics do
        {
          "cpu_usage" => rand(20.0..50.0).round(1),
          "memory_usage" => rand(30.0..60.0).round(1),
          "db_connections" => rand(5..10),
          "query_time" => rand(0.05..0.2).round(3),
          "records_per_second" => rand(2000..5000)
        }
      end
    end

    trait :low_performance do
      records_per_second { rand(10.0..100.0).round(2) }
      estimated_remaining_seconds { rand(3600..7200) }
      metrics do
        {
          "cpu_usage" => rand(80.0..95.0).round(1),
          "memory_usage" => rand(85.0..95.0).round(1),
          "db_connections" => rand(20..30),
          "query_time" => rand(2.0..5.0).round(3),
          "records_per_second" => rand(10..100)
        }
      end
    end

    trait :broadcasted do
      broadcasted { true }
      broadcasted_at { Time.current }
    end

    trait :not_broadcasted do
      broadcasted { false }
      broadcasted_at { nil }
    end

    trait :recent do
      created_at { rand(1.minute.ago..Time.current) }
    end

    trait :old do
      created_at { rand(1.week.ago..1.day.ago) }
    end

    trait :with_detailed_metrics do
      metrics do
        {
          "cpu_usage" => rand(20.0..80.0).round(1),
          "memory_usage" => rand(30.0..90.0).round(1),
          "db_connections" => rand(5..20),
          "query_time" => rand(0.1..1.0).round(3),
          "records_per_second" => rand(500..2000),
          "disk_io" => rand(10.0..100.0).round(1),
          "network_io" => rand(5.0..50.0).round(1),
          "active_threads" => rand(1..10),
          "heap_usage" => rand(40.0..80.0).round(1),
          "gc_count" => rand(0..5)
        }
      end
    end
  end
end
