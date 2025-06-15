#!/usr/bin/env ruby
# Test CSV Import with New Items

puts 'Testing CSV Import with New Items:'
puts '=================================='

# Use new test CSV file
test_csv = '/tmp/new_test_inventory.csv'
puts "CSV File: #{test_csv}"
puts "File exists: #{File.exist?(test_csv)}"

if File.exist?(test_csv)
  puts "CSV content:"
  puts File.read(test_csv)

  # Count inventories before
  before_count = Inventory.count
  puts "\nInventories before import: #{before_count}"

  # Get admin
  admin = Admin.first
  puts "Using admin: #{admin.email}"

  # Clear queues
  Sidekiq::RetrySet.new.clear
  Sidekiq::DeadSet.new.clear

  # Enqueue job
  job_id = SecureRandom.uuid
  puts "\nEnqueuing import job with ID: #{job_id}"

  begin
    ImportInventoriesJob.perform_later(test_csv, admin.id, job_id)
    puts 'Job enqueued successfully'

    # Wait for processing
    puts 'Waiting for job processing...'
    10.times do |i|
      sleep 1
      current_stats = Sidekiq::Stats.new
      queue_size = Sidekiq::Queue.new('imports').size
      retry_count = Sidekiq::RetrySet.new.size
      dead_count = Sidekiq::DeadSet.new.size

      puts "  Check #{i+1}: Queue: #{queue_size}, Retry: #{retry_count}, Dead: #{dead_count}, Processed: #{current_stats.processed}"

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

    # Show new inventories
    if after_count > before_count
      new_inventories = Inventory.last(after_count - before_count)
      puts "\nNewly created inventories:"
      new_inventories.each do |inv|
        puts "  - #{inv.name} (ID: #{inv.id}, Qty: #{inv.quantity}, Price: #{inv.price})"
      end
    end

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
  puts 'Test CSV file not found'
  exit 1
end

puts "\nTest completed"
