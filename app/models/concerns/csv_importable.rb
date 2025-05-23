# frozen_string_literal: true

module CsvImportable
  extend ActiveSupport::Concern

  # クラスメソッド
  module ClassMethods
    def import_from_csv(file_path, options = {})
      require "csv"
      
      default_options = {
        batch_size: 1000,
        headers: true,
        skip_invalid: false,
        column_mapping: {},
        update_existing: false,
        unique_key: "name"
      }
      
      options = default_options.merge(options)
      
      valid_records = []
      invalid_records = []
      update_records = []
      
      Rails.logger.info("CSVインポート開始: #{file_path}")
      
      # ファイルパスまたはアップロードされたファイルを処理
      file_path = file_path.respond_to?(:path) ? file_path.path : file_path
      
      ActiveRecord::Base.transaction do
        CSV.foreach(file_path, headers: options[:headers], encoding: "UTF-8") do |row|
          attributes = row_to_attributes(row, options[:column_mapping])
          
          # 既存レコードの検索（更新モードの場合）
          existing_record = nil
          if options[:update_existing] && row[options[:unique_key]].present?
            # 安全なクエリのために許可されたカラム名かチェック
            if %w[name code sku barcode].include?(options[:unique_key])
              # シンボルをカラム名として使用することでSQLインジェクションを防止
              existing_record = where({ options[:unique_key].to_sym => row[options[:unique_key]] }).first
            else
              # 許可されていないカラム名の場合はデフォルトのnameを使用
              Rails.logger.warn("不正なunique_keyが指定されました: #{options[:unique_key]} - デフォルトの'name'を使用します")
              existing_record = where(name: row["name"]).first
            end
          end
          
          if existing_record
            existing_record.assign_attributes(attributes)
            
            if existing_record.valid?
              update_records << existing_record
            else
              invalid_records << { row: row, errors: existing_record.errors.full_messages }
            end
          else
            record = new(attributes)
            
            if record.valid?
              valid_records << record
            else
              invalid_records << { row: row, errors: record.errors.full_messages }
              next if options[:skip_invalid]
            end
          end
          
          # バッチサイズに達したらバルクインサート
          if valid_records.size >= options[:batch_size]
            bulk_insert(valid_records)
            valid_records = []
          end
          
          if update_records.size >= options[:batch_size]
            bulk_update(update_records)
            update_records = []
          end
        end
        
        # 残りのレコードを処理
        bulk_insert(valid_records) if valid_records.present?
        bulk_update(update_records) if update_records.present?
      end
      
      Rails.logger.info("CSVインポート完了: #{valid_records.size + update_records.size}件取込, #{invalid_records.size}件エラー")
      
      {
        valid_count: valid_records.size,
        update_count: update_records.size,
        invalid_records: invalid_records
      }
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
    
    # 有効なレコードをバルクインサートするプライベートメソッド
    def bulk_insert(records)
      return if records.blank?
      
      # 挿入レコードの属性を収集
      attributes = records.map do |record|
        record.attributes.except("id", "created_at", "updated_at").merge(
          created_at: Time.current,
          updated_at: Time.current
        )
      end
      
      # Rails 6+の場合はinsert_allを使用
      result = insert_all(attributes)
      
      # 在庫ログ用のデータを作成（bulk_insertでは通常のコールバックが動作しないため）
      create_bulk_logs(records, result.rows) if result.rows.present? && self.name == "Inventory"
      
      result
    end
    
    # バルクインサート後のログ一括作成
    def create_bulk_logs(records, inserted_ids)
      return if records.blank? || inserted_ids.blank?
      
      # 実装はInventoryLoggableモジュール内に移動
    end
    
    # バルク更新処理
    def bulk_update(records)
      return if records.blank?
      
      records.each_with_index do |record, index|
        # 500件ごとにログ出力
        Rails.logger.info("更新処理中: #{index + 1}/#{records.size}") if (index % 500).zero? && index.positive?
        
        # 個別に更新して、コールバックを発火させる
        record.save
      end
    end
  end
end
