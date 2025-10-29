# frozen_string_literal: true

# カスタムRSpecマッチャー: パフォーマンステスト用
# CLAUDE.md準拠: テスト駆動のパフォーマンス最適化

RSpec::Matchers.define :exceed_query_limit do |expected|
  match do |actual|
    @query_count = count_queries(&actual)
    @query_count > expected
  end

  failure_message do |actual|
    "expected block to exceed #{expected} queries, but executed #{@query_count} queries"
  end

  failure_message_when_negated do |actual|
    "expected block not to exceed #{expected} queries, but executed #{@query_count} queries"
  end

  def count_queries(&block)
    count = 0
    counter = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      # SCHEMA関連とCACHEクエリは除外
      unless event.payload[:name]&.match?(/SCHEMA|CACHE/)
        count += 1
      end
    end

    yield

    ActiveSupport::Notifications.unsubscribe(counter)
    count
  end

  supports_block_expectations
end

RSpec::Matchers.define :perform_under do |expected|
  match do |actual|
    @execution_time = measure_time(&actual)
    @execution_time < expected
  end

  failure_message do |actual|
    "expected block to complete within #{expected}ms, but took #{@execution_time.round(2)}ms"
  end

  def measure_time(&block)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    (end_time - start_time) * 1000  # ミリ秒に変換
  end

  supports_block_expectations

  # .ms チェーンメソッドを追加
  chain :ms do
    # expected値はすでにミリ秒単位
  end
end

RSpec::Matchers.define :perform_constant_number_of_queries do
  match do |actual|
    # 最初の実行でクエリ数をカウント
    @first_count = count_queries(&actual)

    # 2回目の実行でクエリ数が変わらないことを確認
    @second_count = count_queries(&actual)

    @first_count == @second_count
  end

  failure_message do |actual|
    "expected block to perform constant number of queries, but first execution: #{@first_count} queries, second execution: #{@second_count} queries"
  end

  def count_queries(&block)
    count = 0
    counter = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      event = ActiveSupport::Notifications::Event.new(*args)
      unless event.payload[:name]&.match?(/SCHEMA|CACHE/)
        count += 1
      end
    end

    yield

    ActiveSupport::Notifications.unsubscribe(counter)
    count
  end

  supports_block_expectations
end
