#!/usr/bin/env ruby
# Final CSV Import Test Script

puts 'Final CSV Import Test'
puts '===================='

# Check Sidekiq connection
require 'sidekiq/api'
begin
  stats = Sidekiq::Stats.new
  puts 'Sidekiq Connection: OK'
  puts "Initial stats - Processed: #{stats.processed}, Failed: #{stats.failed}"
rescue => e
  puts 'Sidekiq Connection: FAILED'
  puts "Error: #{e.message}"
  exit 1
end

# Use properly located CSV file
test_csv = '/tmp/test_inventory.csv'
puts "\nCSV File Check:"
puts "Path: #{test_csv}"
puts "Exists: #{File.exist?(test_csv)}"

if File.exist?(test_csv)
  puts "File size: #{File.size(test_csv)} bytes"
  puts "First 2 lines of CSV:"
  puts File.readlines(test_csv).first(2).join

  # Count inventories before
  before_count = Inventory.count
  puts "\nInventories before import: #{before_count}"

  # Get or create test admin
  admin = Admin.first
  if admin.nil?
    admin = Admin.create!(
      email: 'test@example.com',
      password: 'password123!',
      password_confirmation: 'password123!'
    )
    puts 'Created test admin'
  else
    puts "Using existing admin: #{admin.email}"
  end

  # Clear retry queue first
  retry_set = Sidekiq::RetrySet.new
  retry_set.clear
  puts "Cleared #{retry_set.size} jobs from retry queue"

  # Enqueue job
  job_id = SecureRandom.uuid
  puts "\nEnqueuing import job with ID: #{job_id}"

  begin
    ImportInventoriesJob.perform_later(test_csv, admin.id, job_id)
    puts 'Job enqueued successfully'

    # Wait for processing with multiple checks
    puts 'Waiting for job processing...'
    5.times do |i|
      sleep 2
      current_stats = Sidekiq::Stats.new
      queue_size = Sidekiq::Queue.new('imports').size
      retry_count = Sidekiq::RetrySet.new.size

      puts "  Check #{i+1}: Queue size: #{queue_size}, Retry queue: #{retry_count}, Processed: #{current_stats.processed}"

      if queue_size == 0 && retry_count == 0
        puts "  Job completed processing!"
        break
      end
    end

    # Check final results
    after_count = Inventory.count
    puts "\nFinal Results:"
    puts "Inventories before: #{before_count}"
    puts "Inventories after: #{after_count}"
    puts "New inventories: #{after_count - before_count}"

    # Check Sidekiq stats
    final_stats = Sidekiq::Stats.new
    puts "\nSidekiq final stats:"
    puts "Processed: #{final_stats.processed}"
    puts "Failed: #{final_stats.failed}"

    # Check for any errors
    retry_set = Sidekiq::RetrySet.new
    dead_set = Sidekiq::DeadSet.new

    puts "\nError check:"
    puts "Jobs in retry queue: #{retry_set.size}"
    puts "Jobs in dead queue: #{dead_set.size}"

    if retry_set.size > 0
      puts "\nRetry job errors:"
      retry_set.first&.tap do |job|
        puts "  Error: #{job['error_message']}"
      end
    end

    if dead_set.size > 0
      puts "\nDead job errors:"
      dead_set.first&.tap do |job|
        puts "  Error: #{job['error_message']}"
      end
    end

    # Success check
    if after_count > before_count
      puts "\n✅ CSV IMPORT SUCCESSFUL!"
      puts "Successfully imported #{after_count - before_count} new inventories"
    else
      puts "\n❌ CSV IMPORT FAILED"
      puts "No new inventories were created"
    end

  rescue => e
    puts "Job enqueue failed: #{e.message}"
    puts e.backtrace.first(3)
  end
else
  puts 'Test CSV file not found - cannot test import'
  exit 1
end

puts "\nTest completed"
