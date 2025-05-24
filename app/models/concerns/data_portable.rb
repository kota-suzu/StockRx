# frozen_string_literal: true

module DataPortable
  extend ActiveSupport::Concern

  class_methods do
    # システムデータのエクスポート
    def export_system_data(options = {})
      data = initialize_export_data

      # エクスポート対象モデル
      target_models = options[:models] || [ Inventory, Batch, InventoryLog ]

      export_model_data(data, target_models, options)

      # ファイル出力オプション
      if options[:file]
        return write_export_to_file(data, options)
      end

      # デフォルトはJSONとして返す
      data
    end

    # システムデータのインポート
    def import_system_data(data, options = {})
      results = initialize_import_results

      # データソースの形式によって読み込み方法を変更
      source_data = parse_import_data(data, results)
      return results if results[:metadata][:errors].present?

      # データが正しい形式かチェック
      unless source_data.key?("data") || source_data.key?(:data)
        results[:metadata][:success] = false
        results[:metadata][:errors] << "Invalid data format: 'data' key missing"
        return results
      end

      # シンボルと文字列キーの両方に対応
      import_data = source_data[:data] || source_data["data"]

      process_import_data(import_data, options, results)

      # インポートの結果を返す
      results[:metadata][:success] = results[:metadata][:errors].empty?
      results
    end

    # データベースのバックアップ
    def backup_database(options = {})
      config = database_config
      backup_dir = options[:backup_dir] || Rails.root.join("tmp", "backups")
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      filename = options[:filename] || "backup_#{timestamp}"

      # バックアップディレクトリの作成
      FileUtils.mkdir_p(backup_dir)

      backup_file = File.join(backup_dir, "#{filename}.sql")

      case config[:adapter]
      when "postgresql"
        backup_postgres_database(config, backup_file)
      when "mysql2"
        backup_mysql_database(config, backup_file)
      else
        raise "未対応のデータベースアダプタ: #{config[:adapter]}"
      end

      # 圧縮オプション
      if options[:compress]
        compress_backup_file(backup_file)
        backup_file = "#{backup_file}.gz"
      end

      backup_file
    end

    # バックアップからのリストア
    def restore_from_backup(backup_file, options = {})
      require "shellwords"

      # ファイルの存在確認
      unless File.exist?(backup_file)
        Rails.logger.error("バックアップファイルが見つかりません: #{backup_file}")
        return false
      end

      # 圧縮ファイルの展開
      if backup_file.end_with?(".gz")
        temp_file = backup_file.chomp(".gz")
        safe_backup_file = Shellwords.escape(backup_file)
        safe_temp_file = Shellwords.escape(temp_file)

        unzip_result = system "gunzip -c #{safe_backup_file} > #{safe_temp_file}"
        unless unzip_result
          Rails.logger.error("バックアップファイルの解凍に失敗しました")
          return false
        end

        backup_file = temp_file
      end

      # データベースリストア
      config = database_config
      result = restore_database(config, backup_file)

      # 一時ファイルの削除
      File.delete(backup_file) if backup_file != options[:backup_file] && File.exist?(backup_file)

      result
    end

    private

    # エクスポートデータの初期化
    def initialize_export_data
      {
        metadata: {
          exported_at: Time.current,
          version: "1.0",
          models: []
        },
        data: {}
      }
    end

    # モデルデータのエクスポート
    def export_model_data(data, target_models, options)
      target_models.each do |model|
        model_name = model.name.underscore.pluralize
        data[:metadata][:models] << model_name

        records = fetch_records_for_export(model, options)

        # データ形式変換
        data[:data][model_name] = records.as_json(
          except: options[:except],
          methods: options[:methods],
          include: options[:include]
        )
      end
    end

    # エクスポート用レコードの取得
    def fetch_records_for_export(model, options)
      # 各モデルのデータをエクスポート
      records = if options[:start_date] && options[:end_date] && model.column_names.include?("created_at")
                  model.where(created_at: options[:start_date]..options[:end_date])
      else
                  model.all
      end

      # ページネーション処理（大量データ対応）
      if options[:page_size]
        page = options[:page] || 1
        records = records.offset((page - 1) * options[:page_size]).limit(options[:page_size])
      end

      # 関連データのインクルード処理
      if options[:include]
        model_name = model.name.underscore.pluralize
        includes = options[:include][model_name.to_sym]
        records = records.includes(includes) if includes.present?
      end

      records
    end

    # ファイルへの書き出し
    def write_export_to_file(data, options)
      file_format = options[:format] || :json
      file_path = options[:file_path] || Rails.root.join("tmp", "export_#{Time.current.to_i}.#{file_format}")

      case file_format.to_sym
      when :json
        File.write(file_path, data.to_json)
      when :yaml
        File.write(file_path, data.to_yaml)
      when :csv
        write_csv_export(data, file_path, file_format)
      end

      file_path
    end

    # CSVエクスポート
    def write_csv_export(data, file_path, file_format)
      # 各モデルごとにCSVファイルを作成
      data[:data].each do |model_name, records|
        csv_path = file_path.sub(".#{file_format}", "_#{model_name}.csv")
        CSV.open(csv_path, "wb") do |csv|
          if records.any?
            # ヘッダー行
            csv << records.first.keys

            # データ行
            records.each do |record|
              csv << record.values
            end
          end
        end
      end
    end

    # インポート結果の初期化
    def initialize_import_results
      {
        metadata: {
          imported_at: Time.current,
          success: true,
          errors: []
        },
        counts: {}
      }
    end

    # インポートデータのパース
    def parse_import_data(data, results)
      case data
      when String
        parse_string_import_data(data, results)
      when Hash
        data
      else
        results[:metadata][:success] = false
        results[:metadata][:errors] << "Unsupported data type: #{data.class.name}"
        nil
      end
    end

    # 文字列データのパース
    def parse_string_import_data(data, results)
      if File.exist?(data)
        parse_file_import_data(data, results)
      else
        begin
          JSON.parse(data)
        rescue JSON::ParserError
          results[:metadata][:success] = false
          results[:metadata][:errors] << "Invalid JSON string"
          nil
        end
      end
    end

    # ファイルデータのパース
    def parse_file_import_data(file_path, results)
      if file_path.end_with?(".json")
        JSON.parse(File.read(file_path))
      elsif file_path.end_with?(".yaml", ".yml")
        YAML.load_file(file_path)
      else
        results[:metadata][:success] = false
        results[:metadata][:errors] << "Unsupported file format: #{File.extname(file_path)}"
        nil
      end
    end

    # インポートデータの処理
    def process_import_data(import_data, options, results)
      ActiveRecord::Base.transaction do
        import_data.each do |model_name, records|
          process_model_import(model_name, records, options, results)
        end

        # エラーが多すぎる場合はロールバック
        if options[:max_errors] && results[:metadata][:errors].size > options[:max_errors]
          results[:metadata][:success] = false
          raise ActiveRecord::Rollback
        end
      end
    end

    # モデルごとのインポート処理
    def process_model_import(model_name, records, options, results)
      # モデル名から対応するクラスを取得
      model_class = model_name.to_s.singularize.camelize.constantize
      count = 0

      records.each do |record_data|
        # IDが存在する場合、更新または作成
        if record_data["id"] && options[:update_existing]
          process_existing_record_import(model_class, record_data, results, model_name, count)
        else
          process_new_record_import(model_class, record_data, results, model_name, count)
        end
      end

      results[:counts][model_name] = count
    end

    # 既存レコードのインポート処理
    def process_existing_record_import(model_class, record_data, results, model_name, count)
      record = model_class.find_by(id: record_data["id"])
      if record
        # 既存レコードを更新
        if record.update(record_data.except("id", "created_at", "updated_at"))
          count += 1
        else
          results[:metadata][:errors] << "Error updating #{model_name} #{record_data['id']}: #{record.errors.full_messages.join(', ')}"
        end
      else
        # 新規レコードを作成（IDは維持）
        record = model_class.new(record_data.except("created_at", "updated_at"))
        if record.save
          count += 1
        else
          results[:metadata][:errors] << "Error creating #{model_name} #{record_data['id']}: #{record.errors.full_messages.join(', ')}"
        end
      end
    end

    # 新規レコードのインポート処理
    def process_new_record_import(model_class, record_data, results, model_name, count)
      # 新規レコードを作成（IDは自動生成）
      record = model_class.new(record_data.except("id", "created_at", "updated_at"))
      if record.save
        count += 1
      else
        results[:metadata][:errors] << "Error creating #{model_name}: #{record.errors.full_messages.join(', ')}"
      end
    end

    # データベース設定の取得
    def database_config
      ActiveRecord::Base.connection_db_config.configuration_hash
    end

    # PostgreSQLデータベースのバックアップ
    def backup_postgres_database(config, backup_file)
      require "shellwords"

      host = Shellwords.escape(config[:host] || "localhost")
      username = Shellwords.escape(config[:username])
      database = Shellwords.escape(config[:database])
      safe_backup_file = Shellwords.escape(backup_file)

      cmd = "pg_dump -h #{host} -U #{username} -d #{database} -f #{safe_backup_file}"
      result = system(cmd)

      unless result
        raise "PostgreSQLデータベースのバックアップに失敗しました"
      end
    end

    # MySQLデータベースのバックアップ
    def backup_mysql_database(config, backup_file)
      require "shellwords"

      host = Shellwords.escape(config[:host] || "localhost")
      username = Shellwords.escape(config[:username])
      database = Shellwords.escape(config[:database])
      safe_backup_file = Shellwords.escape(backup_file)

      password_option = config[:password] ? "-p#{Shellwords.escape(config[:password])}" : ""

      cmd = "mysqldump -h #{host} -u #{username} #{password_option} #{database} > #{safe_backup_file}"
      result = system(cmd)

      unless result
        raise "MySQLデータベースのバックアップに失敗しました"
      end
    end

    # バックアップファイルの圧縮
    def compress_backup_file(backup_file)
      require "shellwords"

      safe_backup_file = Shellwords.escape(backup_file)
      result = system("gzip #{safe_backup_file}")

      unless result
        raise "バックアップファイルの圧縮に失敗しました"
      end
    end

    # データベースのリストア
    def restore_database(config, backup_file)
      require "shellwords"

      safe_backup_file = Shellwords.escape(backup_file)

      case config[:adapter]
      when "postgresql"
        host = Shellwords.escape(config[:host] || "localhost")
        username = Shellwords.escape(config[:username])
        database = Shellwords.escape(config[:database])

        result = system "psql -h #{host} -U #{username} -d #{database} -f #{safe_backup_file}"
      when "mysql2"
        host = Shellwords.escape(config[:host] || "localhost")
        username = Shellwords.escape(config[:username])
        database = Shellwords.escape(config[:database])

        password_option = ""
        if config[:password]
          password_option = "-p#{Shellwords.escape(config[:password])}"
        end

        result = system "mysql -h #{host} -u #{username} #{password_option} #{database} < #{safe_backup_file}"
      else
        Rails.logger.error("未対応のデータベースアダプタ: #{config[:adapter]}")
        return false
      end

      if result
        Rails.logger.info("データベースのリストアが完了しました")
      else
        Rails.logger.error("データベースのリストアに失敗しました")
      end

      result
    end

    # TODO: データポータビリティ機能の拡張
    # 1. 暗号化機能
    #    - エクスポートデータの暗号化
    #    - パスワード保護されたアーカイブの作成
    #    - 公開鍵暗号による安全なデータ転送
    #
    # 2. 差分バックアップ機能
    #    - 前回バックアップからの差分抽出
    #    - 増分バックアップの管理
    #    - バックアップスケジューリング機能
    #
    # 3. クロスプラットフォーム対応
    #    - 異なるDB間でのデータ移行機能
    #    - スキーマ変換機能
    #    - データ型の自動マッピング
  end
end
