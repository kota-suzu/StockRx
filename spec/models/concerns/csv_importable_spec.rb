# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvImportable, type: :model do
  # Test with Inventory model that includes CsvImportable
  let(:test_model) { Inventory }

  # Create a temporary CSV file for testing
  let(:csv_content) do
    <<~CSV
      name,quantity,price,status
      Test CSV Item 1,10,100.0,active
      Test CSV Item 2,20,200.0,active
      Test CSV Item 3,30,300.0,archived
    CSV
  end

  let(:temp_csv_file) do
    file = Tempfile.new([ 'test_csv_import', '.csv' ])
    file.write(csv_content)
    file.close
    file
  end

  before(:each) do
    # Clean up test data before each test
    Inventory.where(name: [ 'Test CSV Item 1', 'Test CSV Item 2', 'Test CSV Item 3' ]).destroy_all
    InventoryLog.where(note: 'CSVインポートによる登録').destroy_all
  end

  after do
    temp_csv_file.unlink if temp_csv_file
    # Clean up test data
    Inventory.where(name: [ 'Test CSV Item 1', 'Test CSV Item 2', 'Test CSV Item 3' ]).destroy_all
    InventoryLog.where(note: 'CSVインポートによる登録').destroy_all
  end

  describe '.import_from_csv' do
    it 'sets timestamps correctly with record_timestamps: true' do
      # Record start time
      start_time = Time.current

      # Perform CSV import
      result = test_model.import_from_csv(temp_csv_file.path)

      # Record end time
      end_time = Time.current

      # Verify import was successful
      expect(result[:valid_count]).to eq(3)
      expect(result[:invalid_records]).to be_empty

      # Get the imported records
      imported_records = test_model.where(name: [ 'Test CSV Item 1', 'Test CSV Item 2', 'Test CSV Item 3' ])

      # Verify all records have timestamps set
      imported_records.each do |record|
        expect(record.created_at).to be_present
        expect(record.updated_at).to be_present
        expect(record.created_at).to be_between(start_time, end_time)
        expect(record.updated_at).to be_between(start_time, end_time)
        expect(record.created_at).to eq(record.updated_at) # Should be the same for new records
      end
    end

    it 'creates inventory logs for bulk inserted records' do
      # Perform CSV import
      result = test_model.import_from_csv(temp_csv_file.path)

      # Verify import was successful
      expect(result[:valid_count]).to eq(3)

      # Verify inventory logs were created
      logs = InventoryLog.where(note: 'CSVインポートによる登録')
      expect(logs.count).to eq(3)

      # Verify log details
      imported_records = test_model.where(name: [ 'Test CSV Item 1', 'Test CSV Item 2', 'Test CSV Item 3' ]).order(:name)

      logs.joins(:inventory).order('inventories.name').each_with_index do |log, index|
        expected_record = imported_records[index]

        expect(log.inventory_id).to eq(expected_record.id)
        expect(log.operation_type).to eq('add')
        expect(log.delta).to eq(expected_record.quantity)
        expect(log.previous_quantity).to eq(0)
        expect(log.current_quantity).to eq(expected_record.quantity)
        expect(log.created_at).to be_present
        expect(log.updated_at).to be_present
      end
    end

    context 'when timestamps were manually set before the change' do
      it 'should have the same behavior as with record_timestamps: true' do
        # This test documents the change from manual timestamp setting to record_timestamps: true
        # The behavior should be identical - timestamps are automatically set during insert_all

        result = test_model.import_from_csv(temp_csv_file.path)

        expect(result[:valid_count]).to eq(3)

        # All records should have proper timestamps
        imported_records = test_model.where(name: [ 'Test CSV Item 1', 'Test CSV Item 2', 'Test CSV Item 3' ])
        imported_records.each do |record|
          expect(record.created_at).to be_present
          expect(record.updated_at).to be_present
          # The timestamps should be close to each other (within a few seconds)
          expect((record.updated_at - record.created_at).abs).to be < 1.second
        end
      end
    end
  end

  describe 'bulk operations with record_timestamps' do
    it 'handles large batches correctly' do
      # Create a larger CSV for batch testing
      large_csv_content = "name,quantity,price,status\n"
      50.times do |i|
        large_csv_content += "Batch Test Item #{i},#{i + 1},#{(i + 1) * 10},active\n"
      end

      large_temp_file = Tempfile.new([ 'large_test_csv', '.csv' ])
      large_temp_file.write(large_csv_content)
      large_temp_file.close

      begin
        result = test_model.import_from_csv(large_temp_file.path)

        expect(result[:valid_count]).to eq(50)

        # Verify all records have timestamps
        imported_records = test_model.where('name LIKE ?', 'Batch Test Item %')
        expect(imported_records.count).to eq(50)

        imported_records.each do |record|
          expect(record.created_at).to be_present
          expect(record.updated_at).to be_present
        end

        # Verify inventory logs were created for all records
        logs = InventoryLog.where(note: 'CSVインポートによる登録', inventory_id: imported_records.pluck(:id))
        expect(logs.count).to eq(50)

        # Clean up
        imported_records.destroy_all
        logs.destroy_all
      ensure
        large_temp_file.unlink
      end
    end
  end
end
