# frozen_string_literal: true

module CsvImportable
  extend ActiveSupport::Concern

  # クラスメソッド
  module ClassMethods
    def import_from_csv(file_path, options = {})
      require "csv"

      options = prepare_import_options(options)
      result = process_csv_import(file_path, options)

      Rails.logger.info("CSVインポート完了: #{result[:valid_count] + result[:update_count]}件取込, #{result[:invalid_records].size}件エラー")
      result
    end

    # CSVからのデータエクスポート機能
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

    # インポートオプションの準備
    def prepare_import_options(options)
      default_options = {
        batch_size: 1000,
        headers: true,
        skip_invalid: false,
        column_mapping: {},
        update_existing: false,
        unique_key: "name"
      }

      default_options.merge(options)
    end

    # CSV処理のメイン処理
    def process_csv_import(file_path, options)
      valid_records = []
      invalid_records = []
      update_records = []

      Rails.logger.info("CSVインポート開始: #{file_path}")

      # ファイルパスまたはアップロードされたファイルを処理
      file_path = file_path.respond_to?(:path) ? file_path.path : file_path

      ActiveRecord::Base.transaction do
        process_csv_rows(file_path, options, valid_records, invalid_records, update_records)

        # 残りのレコードを処理
        bulk_insert(valid_records) if valid_records.present?
        bulk_update(update_records) if update_records.present?
      end

      {
        valid_count: valid_records.size,
        update_count: update_records.size,
        invalid_records: invalid_records
      }
    end

    # CSVの各行を処理
    def process_csv_rows(file_path, options, valid_records, invalid_records, update_records)
      CSV.foreach(file_path, headers: options[:headers], encoding: "UTF-8") do |row|
        attributes = row_to_attributes(row, options[:column_mapping])

        existing_record = find_existing_record(row, options)

        if existing_record
          process_existing_record(existing_record, attributes, update_records, invalid_records, row)
        else
          process_new_record(attributes, valid_records, invalid_records, row, options[:skip_invalid])
        end

        # バッチサイズに達したらバルクインサート/更新
        if valid_records.size >= options[:batch_size]
          bulk_insert(valid_records)
          valid_records.clear
        end

        if update_records.size >= options[:batch_size]
          bulk_update(update_records)
          update_records.clear
        end
      end
    end

    # 行データから属性ハッシュへの変換
    def row_to_attributes(row, column_mapping)
      attributes = {}

      # マッピングが指定されていない場合はそのまま変換
      if column_mapping.blank?
        row.to_h.each do |key, value|
          attributes[key] = value if key.present? && column_names.include?(key.to_s)
        end
      else
        # マッピングに従って変換
        column_mapping.each do |from, to|
          attributes[to.to_s] = row[from.to_s] if row[from.to_s].present?
        end
      end

      attributes
    end

    # 既存レコードを検索
    def find_existing_record(row, options)
      return nil unless options[:update_existing] && row[options[:unique_key]].present?

      # 安全なクエリのために許可されたカラム名かチェック
      if %w[name code sku barcode].include?(options[:unique_key])
        # シンボルをカラム名として使用することでSQLインジェクションを防止
        where({ options[:unique_key].to_sym => row[options[:unique_key]] }).first
      else
        # 許可されていないカラム名の場合はデフォルトのnameを使用
        Rails.logger.warn("不正なunique_keyが指定されました: #{options[:unique_key]} - デフォルトの'name'を使用します")
        where(name: row["name"]).first
      end
    end

    # 既存レコードの処理
    def process_existing_record(record, attributes, update_records, invalid_records, row)
      record.assign_attributes(attributes)

      if record.valid?
        update_records << record
      else
        invalid_records << { row: row, errors: record.errors.full_messages }
      end
    end

    # 新規レコードの処理
    def process_new_record(attributes, valid_records, invalid_records, row, skip_invalid)
      record = new(attributes)

      if record.valid?
        valid_records << record
      else
        invalid_records << { row: row, errors: record.errors.full_messages }
        nil if skip_invalid
      end
    rescue ArgumentError => e
      # enum値エラーの場合
      if e.message.include?("is not a valid")
        invalid_records << { row: row, errors: [ e.message ] }
      else
        raise e
      end
      nil if skip_invalid
    end

    # 有効なレコードをバルクインサートするメソッド
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
      create_bulk_inventory_logs(records, result.rows) if result.rows.present? && self.name == "Inventory"

      result
    end

    # 既存レコードをバルク更新するメソッド
    def bulk_update(records)
      return if records.blank?

      records.each do |record|
        # レコード更新（after_saveコールバックが発火）
        record.save!
      end
    rescue => e
      Rails.logger.error("バルク更新エラー: #{e.message}")
      raise e # トランザクションをロールバックするため再スロー
    end

    # TODO: CSVインポート機能の拡張
    # 1. 高度なバリデーション機能
    #    - カスタムバリデーションルールの設定
    #    - 複数カラム間のデータ整合性チェック
    #    - 外部キー制約の自動検証
    #
    # 2. インポート進捗の可視化
    #    - プログレスバーの実装
    #    - バックグラウンドジョブでの実行
    #    - リアルタイム進捗通知
    #
    # 3. エラーハンドリングの改善
    #    - エラー行の詳細な特定機能
    #    - エラー修正のためのプレビュー機能
    #    - 部分インポートの再実行機能
  end
end
