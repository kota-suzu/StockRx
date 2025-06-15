#!/usr/bin/env ruby
# Sidekiq Status Check Script

require 'sidekiq/api'

puts 'Sidekiq Queue Status:'
puts '===================='

# Check imports queue
imports_queue = Sidekiq::Queue.new('imports')
puts "Imports queue size: #{imports_queue.size}"

# Check failed jobs
begin
  failed_jobs = Sidekiq::DeadSet.new
  puts "Dead jobs count: #{failed_jobs.size}"

  if failed_jobs.size > 0
    puts "\nRecent dead jobs:"
    failed_jobs.take(3).each_with_index do |job, index|
      puts "\n--- Dead Job #{index + 1} ---"
      puts "Class: #{job['class']}"
      puts "Queue: #{job['queue']}"
      puts "Failed at: #{job['failed_at']}"
      puts "Error: #{job['error_message']}"
      puts "Backtrace: #{job['error_backtrace']&.first(3)&.join("\n")}" if job['error_backtrace']
    end
  end
rescue => e
  puts "Error checking dead jobs: #{e.message}"
end

# Check retry set
begin
  retry_set = Sidekiq::RetrySet.new
  puts "\nRetry jobs count: #{retry_set.size}"

  if retry_set.size > 0
    puts "\nJobs in retry queue:"
    retry_set.take(3).each_with_index do |job, index|
      puts "\n--- Retry Job #{index + 1} ---"
      puts "Class: #{job['class']}"
      puts "Queue: #{job['queue']}"
      puts "Retry count: #{job['retry_count']}"
      puts "Error: #{job['error_message']}"
    end
  end
rescue => e
  puts "Error checking retry jobs: #{e.message}"
end

# Check processed jobs stats
stats = Sidekiq::Stats.new
puts "\nOverall stats:"
puts "Processed: #{stats.processed}"
puts "Failed: #{stats.failed}"
puts "Enqueued: #{stats.enqueued}"
puts "Scheduled: #{stats.scheduled}"

# Check specific queue details
puts "\nAll queues:"
Sidekiq::Queue.all.each do |queue|
  puts "  #{queue.name}: #{queue.size} jobs"
end
