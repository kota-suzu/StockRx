#!/usr/bin/env ruby
# CSV Import Test Script

puts 'Testing CSV Import Functionality'
puts '================================='

# Check Sidekiq connection
require 'sidekiq/api'
begin
  stats = Sidekiq::Stats.new
  puts 'Sidekiq Connection: OK'
  puts "Processed: #{stats.processed}"
  puts "Failed: #{stats.failed}"
  puts "Queues: #{Sidekiq::Queue.all.map(&:name).join(', ')}"
rescue => e
  puts 'Sidekiq Connection: FAILED'
  puts "Error: #{e.message}"
end

# Check CSV file availability
test_csv = Rails.root.join('test_data', 'inventory_sample_basic.csv')
puts "\nCSV File Check:"
puts "Path: #{test_csv}"
puts "Exists: #{File.exist?(test_csv)}"

if File.exist?(test_csv)
  puts "File size: #{File.size(test_csv)} bytes"

  # Count inventories before
  before_count = Inventory.count
  puts "\nInventories before import: #{before_count}"

  # Create test admin if needed
  admin = Admin.first
  if admin.nil?
    admin = Admin.create!(
      email: 'test@example.com',
      password: 'password123!',
      password_confirmation: 'password123!'
    )
    puts 'Created test admin'
  end

  # Enqueue job
  job_id = SecureRandom.uuid
  puts "\nEnqueuing import job with ID: #{job_id}"

  begin
    ImportInventoriesJob.perform_later(test_csv.to_s, admin.id, job_id)
    puts 'Job enqueued successfully'

    # Wait for processing
    puts 'Waiting 5 seconds for job processing...'
    sleep 5

    # Check results
    after_count = Inventory.count
    puts "\nInventories after import: #{after_count}"
    puts "New inventories: #{after_count - before_count}"

    # Check Sidekiq stats again
    new_stats = Sidekiq::Stats.new
    puts "\nSidekiq stats after job:"
    puts "Processed: #{new_stats.processed}"
    puts "Failed: #{new_stats.failed}"

  rescue => e
    puts "Job enqueue failed: #{e.message}"
    puts e.backtrace.first(5)
  end
else
  puts 'Test CSV file not found - cannot test import'
end

puts "\nTest completed"
