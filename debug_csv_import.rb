#!/usr/bin/env ruby
# Debug CSV Import Process

puts 'Debugging CSV Import Process:'
puts '============================='

# Load the CSV and check first row
require 'csv'
CSV.foreach('/tmp/test_inventory.csv', headers: true) do |row|
  puts "First CSV row: #{row.to_h}"

  # Test row_to_attributes method
  attributes = {}
  row.to_h.each do |key, value|
    if key.present? && Inventory.column_names.include?(key.to_s)
      attributes[key] = value
      puts "  Adding: #{key} = #{value}"
    else
      puts "  Skipping: #{key} (not in column_names: #{Inventory.column_names})"
    end
  end

  puts "Final attributes: #{attributes}"

  # Test creating inventory with these attributes
  inventory = Inventory.new(attributes)
  puts "Valid: #{inventory.valid?}"
  if !inventory.valid?
    puts "Errors: #{inventory.errors.full_messages}"
  end

  break # Only check first row
end

puts "\nInventory column names: #{Inventory.column_names}"
