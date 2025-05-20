module CsvImportable
  extend ActiveSupport::Concern

  module ClassMethods
    def import_from_csv(file_path, options = {})
      require "csv"

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

      CSV.foreach(file_path, headers: options[:headers], encoding: "UTF-8") do |row|
        attributes = row_to_attributes(row, options[:column_mapping])
        begin
          record = new(attributes)

          if record.valid?
            records << record.attributes.except("id", "created_at", "updated_at")
          else
            invalid_records << { row: row.to_h, errors: record.errors.full_messages }
            # TODO: options[:skip_invalid] が true の場合、ここで next するか検討。
            # 現在のデフォルトは false なので、エラーがあっても処理は続行される（エラーとして記録される）。
          end
        rescue ArgumentError => e # enumなどで不正な値が来た場合
          invalid_records << { row: row.to_h, errors: [ e.message ] }
          # TODO: 同様に options[:skip_invalid] の挙動を考慮。
        end

        # バッチサイズに達したらバルクインサート
        if records.size >= options[:batch_size]
          imported_count += bulk_insert(records).rows.count
          records = []
        end
      end

      imported_count += bulk_insert(records).rows.count if records.any?
      # TODO: bulk_insert(records).count の方が ActiveRecord 7.0 以降ではより正確かもしれません。
      #       insert_all の返り値である ActiveRecord::Result オブジェクトの count メソッドは挿入された行数を返します。
      #       現状の .rows.count でも動作するはずですが、ドキュメントと照らし合わせて確認を推奨します。
      Rails.logger.info("CSVインポート完了: #{imported_count}件取込, #{invalid_records.size}件エラー")

      { imported: imported_count, invalid: invalid_records }
    end

    def row_to_attributes(row, column_mapping)
      attributes = {}

      row.each do |header, value|
        attribute_name = column_mapping[header] || header.to_s.underscore
        if column_names.include?(attribute_name)
          # statusカラムの場合、小文字に変換し前後の空白を除去してenumが正しく処理できるようにする
          processed_value = (attribute_name == "status" && value.is_a?(String)) ? value.strip.downcase : value
          attributes[attribute_name] = processed_value
        end
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

    def bulk_insert(records)
      return insert_all([]) if records.empty?
      insert_all(records.map { |attrs| attrs.merge(created_at: Time.current, updated_at: Time.current) })
    end
  end
end
