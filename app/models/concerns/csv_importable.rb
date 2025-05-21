module CsvImportable
  extend ActiveSupport::Concern

  module ClassMethods
    def import_from_csv(file_path, options = {})
      require 'csv'

      default_options = {
        batch_size: 1000,
        headers: true,
        skip_invalid: false,
        column_mapping: {}
      }

      options = default_options.merge(options)

      records = []
      invalid_records = []
      imported_count = 0

      Rails.logger.info("CSVインポート開始: #{file_path}")

      CSV.foreach(file_path, headers: options[:headers], encoding: 'UTF-8') do |row|
        attributes = row_to_attributes(row, options[:column_mapping])
        record = new(attributes)

        if record.valid?
          records << record
        else
          invalid_records << { row: row, errors: record.errors.full_messages }
          next if options[:skip_invalid]
        end

        if records.size >= options[:batch_size]
          imported_count += bulk_insert(records).count
          records = []
        end
      end

      imported_count += bulk_insert(records).count if records.any?

      Rails.logger.info("CSVインポート完了: #{imported_count}件取込, #{invalid_records.size}件エラー")

      { imported: imported_count, invalid: invalid_records }
    end

    def row_to_attributes(row, column_mapping)
      attributes = {}

      row.each do |header, value|
        attribute_name = column_mapping[header] || header.to_s.underscore
        attributes[attribute_name] = value if column_names.include?(attribute_name)
      end

      attributes
    end

    def export_to_csv(records = nil, options = {})
      require 'csv'

      records ||= all

      headers = options[:headers] || column_names

      CSV.generate do |csv|
        csv << headers

        records.find_each do |record|
          csv << headers.map { |header| record.send(header) }
        end
      end
    end

    private

    def bulk_insert(records)
      attrs = records.map do |record|
        record.attributes.slice(*column_names).except('id').merge(created_at: Time.current, updated_at: Time.current)
      end
      insert_all(attrs)
    end
  end
end
