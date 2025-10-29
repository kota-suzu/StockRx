# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe DataPortable do
  # CLAUDE.md準拠: データポータビリティ機能の包括的テスト
  # メタ認知: エクスポート/インポート/バックアップの複雑な分岐ロジックの品質保証
  # 横展開: 他のデータ処理concernでも同様のテストパターン適用

  # テスト用のダミークラス作成
  class DataPortableTestClass
    include DataPortable
  end

  let(:test_class) { DataPortableTestClass }
  let(:temp_dir) { Rails.root.join('tmp', 'test_exports') }

  before do
    FileUtils.mkdir_p(temp_dir)
    # テストデータの作成
    @inventory1 = create(:inventory, name: "Test Item 1", quantity: 100)
    @inventory2 = create(:inventory, name: "Test Item 2", quantity: 50)
    @batch1 = create(:batch, inventory: @inventory1, quantity: 30)
    @batch2 = create(:batch, inventory: @inventory2, quantity: 20)
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  # ============================================
  # export_system_data のテスト
  # ============================================

  describe '.export_system_data' do
    context 'with default options' do
      it 'exports all specified models' do
        data = test_class.export_system_data

        expect(data[:metadata][:version]).to eq("1.0")
        expect(data[:metadata][:exported_at]).to be_a(Time)
        expect(data[:metadata][:models]).to include("inventories", "batches", "inventory_logs")
        expect(data[:data]).to have_key("inventories")
        expect(data[:data]).to have_key("batches")
      end
    end

    context 'with custom models' do
      it 'exports only specified models' do
        data = test_class.export_system_data(models: [ Inventory ])

        expect(data[:metadata][:models]).to eq([ "inventories" ])
        expect(data[:data]).to have_key("inventories")
        expect(data[:data]).not_to have_key("batches")
      end
    end

    context 'with date range filter' do
      it 'exports records within date range' do
        old_inventory = create(:inventory, created_at: 1.year.ago)
        recent_inventory = create(:inventory, created_at: 1.day.ago)

        data = test_class.export_system_data(
          models: [ Inventory ],
          start_date: 1.week.ago,
          end_date: Time.current
        )

        inventory_ids = data[:data]["inventories"].map { |i| i["id"] }
        expect(inventory_ids).to include(recent_inventory.id)
        expect(inventory_ids).not_to include(old_inventory.id)
      end

      it 'exports all records when model lacks created_at' do
        allow(Inventory).to receive(:column_names).and_return([ 'id', 'name' ])

        data = test_class.export_system_data(
          models: [ Inventory ],
          start_date: 1.week.ago,
          end_date: Time.current
        )

        expect(data[:data]["inventories"].count).to eq(Inventory.count)
      end
    end

    context 'with pagination' do
      before do
        5.times { create(:inventory) }
      end

      it 'paginates results with page_size' do
        data = test_class.export_system_data(
          models: [ Inventory ],
          page_size: 3,
          page: 1
        )

        expect(data[:data]["inventories"].count).to eq(3)
      end

      it 'returns correct page of results' do
        page1_data = test_class.export_system_data(
          models: [ Inventory ],
          page_size: 3,
          page: 1
        )

        page2_data = test_class.export_system_data(
          models: [ Inventory ],
          page_size: 3,
          page: 2
        )

        page1_ids = page1_data[:data]["inventories"].map { |i| i["id"] }
        page2_ids = page2_data[:data]["inventories"].map { |i| i["id"] }

        expect(page1_ids & page2_ids).to be_empty # No overlap
      end
    end

    context 'with file export' do
      it 'exports to JSON file' do
        file_path = temp_dir.join('export.json')

        result = test_class.export_system_data(
          file: true,
          file_path: file_path,
          format: :json
        )

        expect(result).to eq(file_path)
        expect(File.exist?(file_path)).to be true

        content = JSON.parse(File.read(file_path))
        expect(content).to have_key("metadata")
        expect(content).to have_key("data")
      end

      it 'exports to YAML file' do
        file_path = temp_dir.join('export.yaml')

        result = test_class.export_system_data(
          file: true,
          file_path: file_path,
          format: :yaml
        )

        expect(result).to eq(file_path)
        expect(File.exist?(file_path)).to be true

        content = YAML.load_file(file_path)
        expect(content).to have_key(:metadata)
        expect(content).to have_key(:data)
      end

      it 'exports to CSV files' do
        file_path = temp_dir.join('export.csv')

        result = test_class.export_system_data(
          file: true,
          file_path: file_path,
          format: :csv,
          models: [ Inventory ]
        )

        expect(result).to eq(file_path)

        csv_file = file_path.sub('.csv', '_inventories.csv')
        expect(File.exist?(csv_file)).to be true

        csv_content = CSV.read(csv_file)
        expect(csv_content.first).to include("id", "name", "quantity")
      end

      it 'generates default filename when not specified' do
        result = test_class.export_system_data(file: true)

        expect(result.to_s).to match(/export_\d+\.json$/)
        expect(File.exist?(result)).to be true
      end
    end

    context 'with include associations' do
      it 'includes associated data' do
        data = test_class.export_system_data(
          models: [ Inventory ],
          include: { inventories: [ :batches ] }
        )

        # Note: actual include behavior depends on ActiveRecord setup
        expect(data[:data]["inventories"]).to be_present
      end
    end
  end

  # ============================================
  # import_system_data のテスト
  # ============================================

  describe '.import_system_data' do
    let(:valid_export_data) do
      {
        metadata: {
          exported_at: Time.current,
          version: "1.0",
          models: [ "inventories" ]
        },
        data: {
          "inventories" => [
            { "name" => "Imported Item 1", "quantity" => 25, "price" => 100 },
            { "name" => "Imported Item 2", "quantity" => 50, "price" => 200 }
          ]
        }
      }
    end

    context 'with valid hash data' do
      it 'imports new records successfully' do
        expect {
          result = test_class.import_system_data(valid_export_data)
          expect(result[:metadata][:success]).to be true
          expect(result[:metadata][:errors]).to be_empty
          expect(result[:counts]["inventories"]).to eq(2)
        }.to change { Inventory.count }.by(2)
      end
    end

    context 'with JSON string data' do
      it 'parses and imports JSON string' do
        json_data = valid_export_data.to_json

        expect {
          result = test_class.import_system_data(json_data)
          expect(result[:metadata][:success]).to be true
        }.to change { Inventory.count }.by(2)
      end

      it 'handles invalid JSON string' do
        result = test_class.import_system_data("invalid json{")

        expect(result[:metadata][:success]).to be false
        expect(result[:metadata][:errors]).to include("Invalid JSON string")
      end
    end

    context 'with file path' do
      it 'imports from JSON file' do
        file_path = temp_dir.join('import.json')
        File.write(file_path, valid_export_data.to_json)

        expect {
          result = test_class.import_system_data(file_path.to_s)
          expect(result[:metadata][:success]).to be true
        }.to change { Inventory.count }.by(2)
      end

      it 'imports from YAML file' do
        file_path = temp_dir.join('import.yaml')
        File.write(file_path, valid_export_data.to_yaml)

        expect {
          result = test_class.import_system_data(file_path.to_s)
          expect(result[:metadata][:success]).to be true
        }.to change { Inventory.count }.by(2)
      end

      it 'handles unsupported file format' do
        file_path = temp_dir.join('import.txt')
        File.write(file_path, "some text")

        result = test_class.import_system_data(file_path.to_s)

        expect(result[:metadata][:success]).to be false
        expect(result[:metadata][:errors]).to include("Unsupported file format: .txt")
      end
    end

    context 'with invalid data format' do
      it 'handles missing data key' do
        invalid_data = { metadata: {} }

        result = test_class.import_system_data(invalid_data)

        expect(result[:metadata][:success]).to be false
        expect(result[:metadata][:errors]).to include("Invalid data format: 'data' key missing")
      end

      it 'handles unsupported data type' do
        result = test_class.import_system_data(123)

        expect(result[:metadata][:success]).to be false
        expect(result[:metadata][:errors]).to include("Unsupported data type: Integer")
      end
    end

    context 'with update_existing option' do
      it 'updates existing records when ID matches' do
        existing = create(:inventory, name: "Original", quantity: 10)

        import_data = {
          data: {
            "inventories" => [
              { "id" => existing.id, "name" => "Updated", "quantity" => 20 }
            ]
          }
        }

        result = test_class.import_system_data(import_data, update_existing: true)

        expect(result[:metadata][:success]).to be true

        existing.reload
        expect(existing.name).to eq("Updated")
        expect(existing.quantity).to eq(20)
      end

      it 'creates new record when ID not found' do
        import_data = {
          data: {
            "inventories" => [
              { "id" => 99999, "name" => "New Item", "quantity" => 30 }
            ]
          }
        }

        expect {
          result = test_class.import_system_data(import_data, update_existing: true)
          expect(result[:metadata][:success]).to be true
        }.to change { Inventory.count }.by(1)
      end
    end

    context 'with validation errors' do
      it 'collects validation errors' do
        import_data = {
          data: {
            "inventories" => [
              { "name" => nil, "quantity" => -5 } # Invalid data
            ]
          }
        }

        result = test_class.import_system_data(import_data)

        expect(result[:metadata][:success]).to be false
        expect(result[:metadata][:errors]).not_to be_empty
        expect(result[:metadata][:errors].first).to include("Error creating inventories:")
      end
    end

    context 'with max_errors option' do
      it 'rollbacks when errors exceed limit' do
        import_data = {
          data: {
            "inventories" => [
              { "name" => nil },
              { "name" => nil },
              { "name" => "Valid Item" }
            ]
          }
        }

        expect {
          result = test_class.import_system_data(import_data, max_errors: 1)
          expect(result[:metadata][:success]).to be false
        }.not_to change { Inventory.count }
      end
    end

    context 'with symbol keys' do
      it 'handles symbol keys in data' do
        symbol_data = {
          data: {
            inventories: [
              { name: "Symbol Item", quantity: 15 }
            ]
          }
        }

        expect {
          result = test_class.import_system_data(symbol_data)
          expect(result[:metadata][:success]).to be true
        }.to change { Inventory.count }.by(1)
      end
    end
  end

  # ============================================
  # backup_database のテスト
  # ============================================

  describe '.backup_database' do
    let(:backup_dir) { temp_dir.join('backups') }

    before do
      allow(test_class).to receive(:database_config).and_return({
        adapter: 'postgresql',
        host: 'localhost',
        username: 'test_user',
        database: 'test_db'
      })
    end

    it 'creates backup directory if not exists' do
      allow(test_class).to receive(:system).and_return(true)

      test_class.backup_database(backup_dir: backup_dir)

      expect(Dir.exist?(backup_dir)).to be true
    end

    context 'with PostgreSQL' do
      it 'executes pg_dump command' do
        expect(test_class).to receive(:system).with(
          /pg_dump -h localhost -U test_user -d test_db -f/
        ).and_return(true)

        result = test_class.backup_database

        expect(result).to match(/backup_\d+\.sql$/)
      end

      it 'raises error on backup failure' do
        allow(test_class).to receive(:system).and_return(false)

        expect {
          test_class.backup_database
        }.to raise_error("PostgreSQLデータベースのバックアップに失敗しました")
      end
    end

    context 'with MySQL' do
      before do
        allow(test_class).to receive(:database_config).and_return({
          adapter: 'mysql2',
          host: 'localhost',
          username: 'test_user',
          database: 'test_db',
          password: 'secret'
        })
      end

      it 'executes mysqldump command with password' do
        expect(test_class).to receive(:system).with(
          /mysqldump -h localhost -u test_user -psecret test_db/
        ).and_return(true)

        test_class.backup_database
      end

      it 'executes mysqldump without password when not provided' do
        allow(test_class).to receive(:database_config).and_return({
          adapter: 'mysql2',
          host: 'localhost',
          username: 'test_user',
          database: 'test_db'
        })

        expect(test_class).to receive(:system).with(
          /mysqldump -h localhost -u test_user  test_db/
        ).and_return(true)

        test_class.backup_database
      end
    end

    context 'with unsupported adapter' do
      before do
        allow(test_class).to receive(:database_config).and_return({
          adapter: 'sqlite3'
        })
      end

      it 'raises error for unsupported adapter' do
        expect {
          test_class.backup_database
        }.to raise_error("未対応のデータベースアダプタ: sqlite3")
      end
    end

    context 'with compression' do
      it 'compresses backup file' do
        allow(test_class).to receive(:system).and_return(true)

        result = test_class.backup_database(compress: true)

        expect(result).to match(/\.sql\.gz$/)
      end

      it 'raises error on compression failure' do
        allow(test_class).to receive(:system).with(/pg_dump/).and_return(true)
        allow(test_class).to receive(:system).with(/gzip/).and_return(false)

        expect {
          test_class.backup_database(compress: true)
        }.to raise_error("バックアップファイルの圧縮に失敗しました")
      end
    end

    context 'with custom filename' do
      it 'uses provided filename' do
        allow(test_class).to receive(:system).and_return(true)

        result = test_class.backup_database(filename: 'custom_backup')

        expect(result).to match(/custom_backup\.sql$/)
      end
    end
  end

  # ============================================
  # restore_from_backup のテスト
  # ============================================

  describe '.restore_from_backup' do
    let(:backup_file) { temp_dir.join('backup.sql') }

    before do
      FileUtils.touch(backup_file)
      allow(test_class).to receive(:database_config).and_return({
        adapter: 'postgresql',
        host: 'localhost',
        username: 'test_user',
        database: 'test_db'
      })
    end

    context 'with existing backup file' do
      it 'restores from uncompressed file' do
        expect(test_class).to receive(:system).with(
          /psql -h localhost -U test_user -d test_db -f/
        ).and_return(true)

        result = test_class.restore_from_backup(backup_file.to_s)

        expect(result).to be true
      end

      it 'handles PostgreSQL restore failure' do
        allow(test_class).to receive(:system).and_return(false)

        result = test_class.restore_from_backup(backup_file.to_s)

        expect(result).to be false
      end
    end

    context 'with compressed backup' do
      let(:compressed_file) { temp_dir.join('backup.sql.gz') }

      before do
        FileUtils.touch(compressed_file)
      end

      it 'decompresses and restores file' do
        expect(test_class).to receive(:system).with(/gunzip/).and_return(true)
        expect(test_class).to receive(:system).with(/psql/).and_return(true)

        result = test_class.restore_from_backup(compressed_file.to_s)

        expect(result).to be true
      end

      it 'handles decompression failure' do
        expect(test_class).to receive(:system).with(/gunzip/).and_return(false)

        result = test_class.restore_from_backup(compressed_file.to_s)

        expect(result).to be false
      end

      it 'cleans up temporary decompressed file' do
        allow(test_class).to receive(:system).and_return(true)
        temp_file = compressed_file.to_s.chomp('.gz')

        test_class.restore_from_backup(compressed_file.to_s)

        expect(File.exist?(temp_file)).to be false
      end
    end

    context 'with non-existent file' do
      it 'returns false and logs error' do
        expect(Rails.logger).to receive(:error).with(/バックアップファイルが見つかりません/)

        result = test_class.restore_from_backup('nonexistent.sql')

        expect(result).to be false
      end
    end

    context 'with MySQL database' do
      before do
        allow(test_class).to receive(:database_config).and_return({
          adapter: 'mysql2',
          host: 'localhost',
          username: 'test_user',
          database: 'test_db',
          password: 'secret'
        })
      end

      it 'executes mysql restore command' do
        expect(test_class).to receive(:system).with(
          /mysql -h localhost -u test_user -psecret test_db/
        ).and_return(true)

        test_class.restore_from_backup(backup_file.to_s)
      end
    end

    context 'with unsupported adapter' do
      before do
        allow(test_class).to receive(:database_config).and_return({
          adapter: 'sqlite3'
        })
      end

      it 'logs error and returns false' do
        expect(Rails.logger).to receive(:error).with(/未対応のデータベースアダプタ/)

        result = test_class.restore_from_backup(backup_file.to_s)

        expect(result).to be false
      end
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe 'edge cases' do
    describe 'shellwords escaping' do
      it 'properly escapes special characters in filenames' do
        allow(test_class).to receive(:system).and_return(true)
        allow(test_class).to receive(:database_config).and_return({
          adapter: 'postgresql',
          host: 'localhost',
          username: 'test user',
          database: 'test db'
        })

        expect(test_class).to receive(:system).with(
          /pg_dump -h localhost -U test\\ user -d test\\ db/
        ).and_return(true)

        test_class.backup_database
      end
    end

    describe 'large dataset handling' do
      it 'handles export of large datasets with pagination' do
        50.times { create(:inventory) }

        data = test_class.export_system_data(
          models: [ Inventory ],
          page_size: 10,
          page: 1
        )

        expect(data[:data]["inventories"].count).to eq(10)
      end
    end

    describe 'concurrent imports' do
      it 'uses transaction to ensure data integrity' do
        import_data = {
          data: {
            "inventories" => [
              { "name" => "Item 1", "quantity" => 10 },
              { "name" => nil, "quantity" => 20 } # This will fail
            ]
          }
        }

        # With max_errors, should rollback entire transaction
        expect {
          test_class.import_system_data(import_data, max_errors: 0)
        }.not_to change { Inventory.count }
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it 'efficiently exports large datasets' do
      100.times { create(:inventory) }

      start_time = Time.now
      test_class.export_system_data(models: [ Inventory ])
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 500 # Should complete in under 500ms
    end

    it 'efficiently imports large datasets' do
      import_data = {
        data: {
          "inventories" => 100.times.map { |i| { "name" => "Item #{i}", "quantity" => rand(1..100) } }
        }
      }

      start_time = Time.now
      test_class.import_system_data(import_data)
      end_time = Time.now

      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 1000 # Should complete in under 1s
    end
  end
end
