module CsvImportable
  extend ActiveSupport::Concern

  module ClassMethods
    def import_from_csv(file_path, options = {})
      require "csv"

      default_options = {
        batch_size: 1000,
        headers: true,
        skip_invalid: false,
        column_mapping: {},
        value_transformers: {} # New option for custom value transformations
      }

      options = default_options.merge(options)

      records_to_insert = []
      invalid_record_details = []
      imported_count = 0
      processed_rows_count = 0

      Rails.logger.info("CSV Import Started: #{file_path} for model #{self.name}")

      CSV.foreach(file_path, headers: options[:headers], encoding: "UTF-8") do |row|
        processed_rows_count += 1
        attributes = row_to_attributes(row, options[:column_mapping], options[:value_transformers])

        # Handle cases where attribute mapping results in no usable attributes
        # (e.g., all headers unmapped or row is effectively empty for the model)
        if attributes.empty? && row.fields.any?(&:present?)
          error_message = "Row resulted in empty attributes after mapping. CSV row: #{row.to_h}"
          Rails.logger.warn("CSV Import Warning for #{self.name}: #{error_message}")
          invalid_record_details << { row: row.to_h, errors: [ error_message ], type: :mapping_error }
          # Even if skip_invalid is false, an empty attribute hash won't create a valid record.
          # So, we skip attempting to instantiate it.
          next
        end

        begin
          record = new(attributes)

          if record.valid?
            records_to_insert << record.attributes.except("id", "created_at", "updated_at")
          else
            invalid_record_details << { row: row.to_h, errors: record.errors.full_messages, type: :validation_error }
            if options[:skip_invalid]
              Rails.logger.info "CSV Import for #{self.name}: Skipping invalid record due to validation errors. Row: #{row.to_h}, Errors: #{record.errors.full_messages.join(', ')}"
              next
            end
          end
        rescue ArgumentError => e # enumなどで不正な値が来た場合
          invalid_record_details << { row: row.to_h, errors: [ e.message ], type: :argument_error }
          if options[:skip_invalid]
            Rails.logger.info "CSV Import for #{self.name}: Skipping record due to ArgumentError. Row: #{row.to_h}, Error: #{e.message}"
            next
          end
        end

        # バッチサイズに達したらバルクインサート
        if records_to_insert.size >= options[:batch_size]
          inserted_this_batch = perform_bulk_insert(records_to_insert)
          imported_count += inserted_this_batch
          Rails.logger.info "CSV Import for #{self.name}: Batch of #{inserted_this_batch} records inserted." if inserted_this_batch > 0
          records_to_insert = []
        end
      end

      # Insert any remaining records
      if records_to_insert.any?
        inserted_this_batch = perform_bulk_insert(records_to_insert)
        imported_count += inserted_this_batch
        Rails.logger.info "CSV Import for #{self.name}: Final batch of #{inserted_this_batch} records inserted." if inserted_this_batch > 0
      end

      Rails.logger.info("CSV Import Completed for #{self.name}: #{processed_rows_count} rows processed, #{imported_count} records imported, #{invalid_record_details.size} invalid records.")

      { imported: imported_count, invalid: invalid_record_details, processed_rows: processed_rows_count }
    end

    def row_to_attributes(row, column_mapping, value_transformers = {})
      attributes = {}
      # Normalize keys for reliable lookup
      normalized_column_mapping = column_mapping.transform_keys { |k| k.is_a?(Symbol) ? k.to_s.downcase : k.to_s.downcase }
      normalized_value_transformers = value_transformers.transform_keys { |k| k.is_a?(Symbol) ? k.to_s : k.to_s }

      row.each do |header, value|
        csv_header_key = header.is_a?(Symbol) ? header.to_s.downcase : header.to_s.downcase
        attribute_name_str = normalized_column_mapping[csv_header_key] || csv_header_key.to_s.underscore

        if column_names.include?(attribute_name_str)
          current_value = value
          if normalized_value_transformers[attribute_name_str].is_a?(Proc)
            begin
              current_value = normalized_value_transformers[attribute_name_str].call(value)
            rescue => e
              Rails.logger.error "CSV Import for #{self.name}: ValueTransformer for '#{attribute_name_str}' failed on value '#{value}'. Error: #{e.message}"
              # Optionally, handle transformer error e.g., by skipping attribute or marking row invalid earlier
            end
          end
          attributes[attribute_name_str] = current_value # Keep attribute keys as strings, consistent with record.attributes
        else
          # Rails.logger.debug "CSV Import for #{self.name}: Header '#{header}' (mapped to/as '#{attribute_name_str}') not in model columns or mapping."
        end
      end

      if attributes.empty? && row.fields.any?(&:present?)
        Rails.logger.warn "CSV Import for #{self.name}: Row processed to empty attributes. Original row: #{row.to_h}. Effective column_mapping: #{normalized_column_mapping}. Model columns: #{column_names.join(', ')}"
      end

      attributes
    end

    def export_to_csv(records = nil, options = {})
      require "csv"

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

    def perform_bulk_insert(records_attributes_array)
      return 0 if records_attributes_array.empty?

      timestamp = Time.current
      records_with_timestamps = records_attributes_array.map do |attrs|
        # Ensure all keys are strings for insert_all, consistent with record.attributes
        # and model column names.
        attrs.stringify_keys.merge("created_at" => timestamp, "updated_at" => timestamp)
      end
      # TODO: Verify if .count is the correct method for the ActiveRecord::Result returned by insert_all
      # or if the direct return value (number of rows) is universally supported by the adapter.
      # For many adapters, insert_all (without `returning` option) returns the number of affected rows directly.
      # If it returns an ActiveRecord::Result, .length or similar might be needed if .count isn't available.
      # However, if records_to_insert is empty, this line isn't the primary issue for "got: 0".
      insert_all(records_with_timestamps).count
    end
  end
end
