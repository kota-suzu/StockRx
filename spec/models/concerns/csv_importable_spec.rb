# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CsvImportable, type: :model do
  let(:test_model_class) do
    Class.new(ApplicationRecord) do
      include CsvImportable
      include InventoryLoggable
      
      self.table_name = 'inventories'
      
      validates :name, presence: true
      validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
      validates :price, presence: true, numericality: { greater_than_or_equal_to: 0 }
      
      def self.name
        'Inventory'
      end
    end
  end

  let(:csv_content) do
    <<~CSV
      name,quantity,price,status
      テスト商品1,10,100,active
      テスト商品2,20,200,active
      テスト商品3,30,300,inactive
    CSV
  end

  let(:csv_file) do
    file = Tempfile.new(['test', '.csv'])
    file.write(csv_content)
    file.rewind
    file
  end

  after do
    csv_file.close
    csv_file.unlink if csv_file
  end

  describe '#bulk_insert' do
    it 'record_timestamps: trueオプションでタイムスタンプが自動設定される' do
      # テスト用のレコードを作成
      records = [
        test_model_class.new(name: 'テスト1', quantity: 10, price: 100, status: 'active'),
        test_model_class.new(name: 'テスト2', quantity: 20, price: 200, status: 'active')
      ]

      # 事前の件数を確認
      initial_count = test_model_class.count

      # バルクインサート実行
      result = test_model_class.send(:bulk_insert, records)

      # 件数が増加したことを確認
      expect(test_model_class.count).to eq(initial_count + 2)

      # 挿入されたレコードのタイムスタンプが設定されていることを確認
      inserted_records = test_model_class.last(2)
      inserted_records.each do |record|
        expect(record.created_at).to be_present
        expect(record.updated_at).to be_present
        expect(record.created_at).to be_within(1.second).of(Time.current)
        expect(record.updated_at).to be_within(1.second).of(Time.current)
      end

      # insert_allの戻り値が正しく返されることを確認
      expect(result).to be_an(ActiveRecord::Result)
      # SQLiteではresult.rowsが空の場合があるので、実際のレコード数で確認
      expect(test_model_class.count - initial_count).to eq(2)
    end

    it '空のレコード配列の場合は何もしない' do
      expect {
        test_model_class.send(:bulk_insert, [])
      }.not_to change(test_model_class, :count)
    end

    it 'nilが渡された場合は何もしない' do
      expect {
        test_model_class.send(:bulk_insert, nil)
      }.not_to change(test_model_class, :count)
    end
  end

  describe '#import_from_csv' do
    it 'CSVファイルから正常にデータをインポートできる' do
      result = test_model_class.import_from_csv(csv_file.path)

      expect(result[:valid_count]).to eq(3)
      expect(result[:update_count]).to eq(0)
      expect(result[:invalid_records]).to be_empty

      # インポートされたデータの確認
      imported_records = test_model_class.last(3)
      expect(imported_records.map(&:name)).to include('テスト商品1', 'テスト商品2', 'テスト商品3')
      
      # タイムスタンプが正しく設定されていることを確認
      imported_records.each do |record|
        expect(record.created_at).to be_present
        expect(record.updated_at).to be_present
      end
    end

    it '在庫ログが正しく作成される' do
      initial_log_count = InventoryLog.count

      test_model_class.import_from_csv(csv_file.path)

      # 在庫ログが3件作成されることを確認
      expect(InventoryLog.count).to eq(initial_log_count + 3)
      
      # 最新の在庫ログの確認
      recent_logs = InventoryLog.last(3)
      recent_logs.each do |log|
        expect(log.operation_type).to eq('add')
        expect(log.note).to eq('CSVインポートによる登録')
        expect(log.created_at).to be_present
        expect(log.updated_at).to be_present
      end
    end

    it '不正なデータがある場合は適切にエラーハンドリングする' do
      invalid_csv = <<~CSV
        name,quantity,price,status
        ,10,100,active
        テスト商品2,-5,200,active
        テスト商品3,30,-100,inactive
      CSV

      invalid_file = Tempfile.new(['invalid', '.csv'])
      invalid_file.write(invalid_csv)
      invalid_file.rewind

      begin
        result = test_model_class.import_from_csv(invalid_file.path)

        expect(result[:valid_count]).to eq(0)
        expect(result[:update_count]).to eq(0)
        expect(result[:invalid_records].size).to eq(3)
      ensure
        invalid_file.close
        invalid_file.unlink
      end
    end
  end

  describe 'Rails 7互換性' do
    it 'insert_allがrecord_timestamps: trueオプションを使用している' do
      records = [
        test_model_class.new(name: 'Rails7テスト', quantity: 1, price: 1, status: 'active')
      ]

      # insert_allメソッドをモック
      expect(test_model_class).to receive(:insert_all)
        .with(anything, record_timestamps: true)
        .and_call_original

      test_model_class.send(:bulk_insert, records)
    end
  end
end