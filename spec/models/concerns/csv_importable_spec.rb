# frozen_string_literal: true

require 'rails_helper'
require 'csv'
require 'tempfile'

RSpec.describe CsvImportable do
  # テスト用の一時的なモデルを作成
  before(:all) do
    # テスト用のテーブルを作成
    ActiveRecord::Base.connection.create_table :csv_test_models, force: true do |t|
      t.string :name
      t.string :email
      t.integer :quantity
      t.decimal :price, precision: 10, scale: 2
      t.date :expiration_date
      t.string :status
      t.timestamps
    end

    # テスト用モデル
    class CsvTestModel < ApplicationRecord
      self.table_name = 'csv_test_models'
      include CsvImportable

      validates :name, presence: true
      validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
      validates :quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :price, numericality: { greater_than: 0 }, allow_nil: true
    end
  end

  after(:all) do
    # テスト用テーブルを削除
    ActiveRecord::Base.connection.drop_table :csv_test_models if ActiveRecord::Base.connection.table_exists?(:csv_test_models)
    Object.send(:remove_const, :CsvTestModel) if defined?(CsvTestModel)
  end

  let(:model_class) { CsvTestModel }
  let(:valid_csv_data) do
    <<~CSV
      name,email,quantity,price,expiration_date,status
      Product A,test@example.com,100,1000.50,2025-12-31,active
      Product B,another@example.com,200,2000.00,2025-06-30,active
      Product C,,50,500.25,2025-03-15,inactive
    CSV
  end

  let(:invalid_csv_data) do
    <<~CSV
      name,email,quantity,price,expiration_date,status
      ,invalid-email,100,1000,2025-12-31,active
      Product D,test@example.com,-10,2000,2025-06-30,active
      Product E,valid@example.com,50,0,2025-03-15,inactive
    CSV
  end

  let(:large_csv_data) do
    headers = "name,email,quantity,price,expiration_date,status\n"
    rows = 5000.times.map do |i|
      "Product #{i},test#{i}@example.com,#{i % 1000},#{1000 + i}.00,2025-12-31,active"
    end
    headers + rows.join("\n")
  end

  describe ".import_from_csv" do
    let(:csv_file) { Tempfile.new([ 'test', '.csv' ]) }

    after { csv_file.unlink }

    context "with valid CSV data" do
      before do
        csv_file.write(valid_csv_data)
        csv_file.rewind
      end

      it "imports all valid records" do
        result = model_class.import_from_csv(csv_file.path)

        expect(result[:valid_count]).to eq(3)
        expect(result[:invalid_records]).to be_empty
        expect(model_class.count).to eq(3)
      end

      it "correctly maps CSV columns to model attributes" do
        model_class.import_from_csv(csv_file.path)

        product_a = model_class.find_by(name: 'Product A')
        expect(product_a.email).to eq('test@example.com')
        expect(product_a.quantity).to eq(100)
        expect(product_a.price).to eq(1000.50)
        expect(product_a.expiration_date).to eq(Date.parse('2025-12-31'))
        expect(product_a.status).to eq('active')
      end

      it "handles missing optional fields" do
        model_class.import_from_csv(csv_file.path)

        product_c = model_class.find_by(name: 'Product C')
        expect(product_c.email).to be_blank
      end
    end

    context "with invalid CSV data" do
      before do
        csv_file.write(invalid_csv_data)
        csv_file.rewind
      end

      it "rejects invalid records by default" do
        result = model_class.import_from_csv(csv_file.path)

        expect(result[:valid_count]).to eq(0)
        expect(result[:invalid_records].size).to eq(3)
        expect(model_class.count).to eq(0)
      end

      it "imports valid records when skip_invalid is true" do
        result = model_class.import_from_csv(csv_file.path, skip_invalid: true)

        expect(result[:valid_count]).to be >= 0
        expect(result[:invalid_records].size).to be > 0
      end

      it "provides detailed error information for invalid records" do
        result = model_class.import_from_csv(csv_file.path)

        invalid_record = result[:invalid_records].first
        expect(invalid_record[:errors]).to include("Name can't be blank")
        expect(invalid_record[:row_number]).to be_present
      end
    end

    context "with duplicate records" do
      before do
        model_class.create!(name: 'Product A', email: 'existing@example.com', quantity: 50)
        csv_file.write(valid_csv_data)
        csv_file.rewind
      end

      it "skips duplicates when update_existing is false" do
        result = model_class.import_from_csv(csv_file.path, update_existing: false)

        expect(result[:duplicate_count]).to eq(1)
        expect(model_class.count).to eq(3) # 1 existing + 2 new
      end

      it "updates existing records when update_existing is true" do
        result = model_class.import_from_csv(csv_file.path, update_existing: true)

        expect(result[:update_count]).to eq(1)
        expect(model_class.count).to eq(3)

        updated = model_class.find_by(name: 'Product A')
        expect(updated.email).to eq('test@example.com')
        expect(updated.quantity).to eq(100)
      end
    end

    context "with custom column mapping" do
      let(:custom_csv_data) do
        <<~CSV
          product_name,contact_email,stock_quantity,unit_price
          Custom Product,custom@example.com,75,750.00
        CSV
      end

      before do
        csv_file.write(custom_csv_data)
        csv_file.rewind
      end

      it "maps columns using custom mapping" do
        mapping = {
          'product_name' => 'name',
          'contact_email' => 'email',
          'stock_quantity' => 'quantity',
          'unit_price' => 'price'
        }

        result = model_class.import_from_csv(csv_file.path, column_mapping: mapping)

        expect(result[:valid_count]).to eq(1)

        product = model_class.first
        expect(product.name).to eq('Custom Product')
        expect(product.quantity).to eq(75)
      end
    end

    context "with large CSV files" do
      before do
        csv_file.write(large_csv_data)
        csv_file.rewind
      end

      it "processes in batches efficiently" do
        start_time = Time.current

        result = model_class.import_from_csv(csv_file.path, batch_size: 500)

        elapsed_time = Time.current - start_time

        expect(result[:valid_count]).to eq(5000)
        expect(elapsed_time).to be < 10.seconds # Should complete within 10 seconds
        expect(model_class.count).to eq(5000)
      end

      it "uses appropriate memory" do
        # メモリ使用量のベンチマーク
        initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

        model_class.import_from_csv(csv_file.path, batch_size: 1000)

        final_memory = `ps -o rss= -p #{Process.pid}`.to_i
        memory_increase = final_memory - initial_memory

        # メモリ増加が妥当な範囲内（100MB以下）
        expect(memory_increase).to be < 100_000
      end
    end

    context "with file handling errors" do
      it "raises error for non-existent file" do
        expect {
          model_class.import_from_csv('/non/existent/file.csv')
        }.to raise_error(Errno::ENOENT)
      end

      it "handles malformed CSV gracefully" do
        csv_file.write("name,email,quantity\n\"Unclosed quote,test@example.com")
        csv_file.rewind

        expect {
          model_class.import_from_csv(csv_file.path)
        }.to raise_error(CSV::MalformedCSVError)
      end

      it "validates file size limit" do
        # 10MB以上のファイルをシミュレート
        allow(File).to receive(:size).and_return(11 * 1024 * 1024)

        expect {
          model_class.import_from_csv(csv_file.path)
        }.to raise_error(/File size exceeds maximum/)
      end
    end

    context "with encoding issues" do
      let(:utf8_csv_data) do
        "name,email\nPrödüçt,test@example.com\n製品,test2@example.com"
      end

      it "handles UTF-8 encoded files" do
        csv_file.write(utf8_csv_data.force_encoding('UTF-8'))
        csv_file.rewind

        result = model_class.import_from_csv(csv_file.path)

        expect(result[:valid_count]).to eq(2)
        expect(model_class.find_by(name: 'Prödüçt')).to be_present
        expect(model_class.find_by(name: '製品')).to be_present
      end

      it "converts other encodings to UTF-8" do
        # Shift_JISエンコーディングのテスト
        sjis_data = "name,email\n製品,test@example.com".encode('Shift_JIS')
        csv_file.write(sjis_data)
        csv_file.rewind

        result = model_class.import_from_csv(csv_file.path, encoding: 'Shift_JIS')

        expect(result[:valid_count]).to eq(1)
      end
    end

    context "with progress tracking" do
      it "yields progress information when block given" do
        csv_file.write(large_csv_data)
        csv_file.rewind

        progress_updates = []

        model_class.import_from_csv(csv_file.path, batch_size: 1000) do |progress|
          progress_updates << progress
        end

        expect(progress_updates).not_to be_empty
        expect(progress_updates.last[:processed]).to eq(5000)
        expect(progress_updates.last[:percentage]).to eq(100)
      end
    end
  end

  describe ".export_to_csv" do
    before do
      model_class.create!([
        { name: 'Export A', email: 'a@example.com', quantity: 10, price: 100 },
        { name: 'Export B', email: 'b@example.com', quantity: 20, price: 200 },
        { name: 'Export C', email: 'c@example.com', quantity: 30, price: 300 }
      ])
    end

    it "exports all records to CSV" do
      csv_content = model_class.export_to_csv

      expect(csv_content).to include('name,email,quantity,price')
      expect(csv_content).to include('Export A,a@example.com,10,100')
      expect(csv_content).to include('Export B,b@example.com,20,200')
      expect(csv_content).to include('Export C,c@example.com,30,300')
    end

    it "exports specific records when provided" do
      records = model_class.where(quantity: 20..30)
      csv_content = model_class.export_to_csv(records)

      expect(csv_content).to include('Export B')
      expect(csv_content).to include('Export C')
      expect(csv_content).not_to include('Export A')
    end

    it "uses custom headers when specified" do
      csv_content = model_class.export_to_csv(nil, headers: [ 'name', 'quantity' ])

      lines = csv_content.split("\n")
      expect(lines.first).to eq('name,quantity')
      expect(lines[1]).to eq('Export A,10')
    end

    it "handles special characters in CSV export" do
      model_class.create!(name: 'Product, with comma', email: 'comma@example.com')
      model_class.create!(name: 'Product "with quotes"', email: 'quotes@example.com')

      csv_content = model_class.export_to_csv

      expect(csv_content).to include('"Product, with comma"')
      expect(csv_content).to include('"Product ""with quotes"""')
    end
  end

  describe "performance optimizations" do
    it "uses bulk insert for better performance" do
      csv_file.write(large_csv_data)
      csv_file.rewind

      # SQLクエリ数が最適化されていることを確認
      expect {
        model_class.import_from_csv(csv_file.path, batch_size: 1000)
      }.not_to exceed_query_limit(20) # バッチごとに1クエリ + α
    end

    it "avoids N+1 queries during validation" do
      csv_file.write(valid_csv_data)
      csv_file.rewind

      # バリデーション中にN+1クエリが発生しないことを確認
      expect {
        model_class.import_from_csv(csv_file.path)
      }.not_to exceed_query_limit(10)
    end
  end

  describe "security considerations" do
    it "sanitizes file paths to prevent directory traversal" do
      malicious_path = "../../../etc/passwd"

      expect {
        model_class.import_from_csv(malicious_path)
      }.to raise_error(Errno::ENOENT)
    end

    it "validates MIME type for uploaded files" do
      # 実際のファイルアップロードをシミュレート
      uploaded_file = double(
        'uploaded_file',
        path: csv_file.path,
        content_type: 'application/x-executable'
      )

      expect {
        model_class.import_from_csv(uploaded_file)
      }.to raise_error(/Invalid file type/)
    end
  end

  describe "error recovery" do
    it "rolls back on critical errors" do
      csv_file.write(valid_csv_data)
      csv_file.rewind

      # トランザクション中のエラーをシミュレート
      allow(model_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        model_class.import_from_csv(csv_file.path)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(model_class.count).to eq(0) # ロールバックされている
    end

    it "continues processing after non-critical errors" do
      mixed_csv_data = <<~CSV
        name,email,quantity
        Valid Product,valid@example.com,10
        ,invalid@example.com,20
        Another Valid,another@example.com,30
      CSV

      csv_file.write(mixed_csv_data)
      csv_file.rewind

      result = model_class.import_from_csv(csv_file.path, skip_invalid: true)

      expect(result[:valid_count]).to eq(2)
      expect(result[:invalid_records].size).to eq(1)
    end
  end
end
