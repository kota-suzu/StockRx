# frozen_string_literal: true

module DataPortable
  extend ActiveSupport::Concern

  # クラスメソッド
  module ClassMethods
    # システム全体データのエクスポート（複数モデル含む）
    def export_system_data(options = {})
      data = {
        metadata: {
          exported_at: Time.current,
          version: "1.0",
          models: []
        },
        data: {}
      }
      
      # エクスポート対象モデル
      target_models = options[:models] || [Inventory, Batch, InventoryLog]
      
      target_models.each do |model|
        model_name = model.name.underscore.pluralize
        data[:metadata][:models] << model_name
        
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
          includes = options[:include][model_name.to_sym]
          records = records.includes(includes) if includes.present?
        end
        
        # データ形式変換
        data[:data][model_name] = records.as_json(
          except: options[:except],
          methods: options[:methods],
          include: options[:include]
        )
      end
      
      # ファイル出力オプション
      if options[:file]
        file_format = options[:format] || :json
        file_path = options[:file_path] || Rails.root.join("tmp", "export_#{Time.current.to_i}.#{file_format}")
        
        case file_format.to_sym
        when :json
          File.write(file_path, data.to_json)
        when :yaml
          File.write(file_path, data.to_yaml)
        when :csv
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
        
        return file_path
      end
      
      # デフォルトはJSONとして返す
      data
    end
    
    # システム全体データのインポート
    def import_system_data(data, options = {})
      results = {
        metadata: {
          imported_at: Time.current,
          success: true,
          errors: []
        },
        counts: {}
      }
      
      # データソースの形式によって読み込み方法を変更
      source_data = case data
                    when String
                      if File.exist?(data)
                        if data.end_with?(".json")
                          JSON.parse(File.read(data))
                        elsif data.end_with?(".yaml", ".yml")
                          YAML.load_file(data)
                        else
                          results[:metadata][:success] = false
                          results[:metadata][:errors] << "Unsupported file format: #{File.extname(data)}"
                          return results
                        end
                      else
                        begin
                          JSON.parse(data)
                        rescue JSON::ParserError
                          results[:metadata][:success] = false
                          results[:metadata][:errors] << "Invalid JSON string"
                          return results
                        end
                      end
                    when Hash
                      data
                    else
                      results[:metadata][:success] = false
                      results[:metadata][:errors] << "Unsupported data type: #{data.class.name}"
                      return results
                    end
      
      # データが正しい形式かチェック
      unless source_data.key?("data") || source_data.key?(:data)
        results[:metadata][:success] = false
        results[:metadata][:errors] << "Invalid data format: 'data' key missing"
        return results
      end
      
      # シンボルと文字列キーの両方に対応
      import_data = source_data[:data] || source_data["data"]
      
      # トランザクション内でインポート処理
      ActiveRecord::Base.transaction do
        import_data.each do |model_name, records|
          # モデル名から対応するクラスを取得
          model_class = model_name.to_s.singularize.camelize.constantize
          count = 0
          
          records.each do |record_data|
            # IDが存在する場合、更新または作成
            if record_data["id"] && options[:update_existing]
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
            else
              # 新規レコードを作成（IDは自動生成）
              record = model_class.new(record_data.except("id", "created_at", "updated_at"))
              if record.save
                count += 1
              else
                results[:metadata][:errors] << "Error creating #{model_name}: #{record.errors.full_messages.join(', ')}"
              end
            end
          end
          
          results[:counts][model_name] = count
        end
        
        # エラーが多すぎる場合はロールバック
        if options[:max_errors] && results[:metadata][:errors].size > options[:max_errors]
          results[:metadata][:success] = false
          raise ActiveRecord::Rollback
        end
      end
      
      # インポートの結果を返す
      results[:metadata][:success] = results[:metadata][:errors].empty?
      results
    end
    
    # バックアップの作成（DBダンプまたはモデルデータエクスポート）
    def create_backup(options = {})
      backup_dir = options[:directory] || Rails.root.join("backup")
      FileUtils.mkdir_p(backup_dir) unless Dir.exist?(backup_dir)
      
      timestamp = Time.current.strftime("%Y%m%d%H%M%S")
      
      if options[:database]
        # データベースダンプの作成
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        case config[:adapter]
        when "postgresql"
          backup_file = File.join(backup_dir, "#{config[:database]}_#{timestamp}.sql")
          system "pg_dump -h #{config[:host] || 'localhost'} -U #{config[:username]} -d #{config[:database]} -f #{backup_file}"
        when "mysql2"
          backup_file = File.join(backup_dir, "#{config[:database]}_#{timestamp}.sql")
          system "mysqldump -h #{config[:host] || 'localhost'} -u #{config[:username]} #{"-p#{config[:password]}" if config[:password]} #{config[:database]} > #{backup_file}"
        when "sqlite3"
          backup_file = File.join(backup_dir, "#{File.basename(config[:database])}_#{timestamp}.sqlite")
          FileUtils.cp(config[:database], backup_file)
        end
        
        # 圧縮
        if options[:compress]
          system "gzip #{backup_file}"
          backup_file = "#{backup_file}.gz"
        end
        
        return backup_file
      else
        # モデルデータのエクスポート
        backup_file = File.join(backup_dir, "model_data_#{timestamp}.json")
        export_system_data(file: true, file_path: backup_file)
        
        # 圧縮
        if options[:compress]
          system "gzip #{backup_file}"
          backup_file = "#{backup_file}.gz"
        end
        
        return backup_file
      end
    end
    
    # バックアップからのリストア
    def restore_from_backup(backup_file, options = {})
      unless File.exist?(backup_file)
        return { success: false, error: "Backup file not found: #{backup_file}" }
      end
      
      # 圧縮ファイルの展開
      if backup_file.end_with?(".gz")
        temp_file = backup_file.chomp(".gz")
        system "gunzip -c #{backup_file} > #{temp_file}"
        backup_file = temp_file
      end
      
      if backup_file.end_with?(".sql")
        # SQLダンプからのリストア
        config = ActiveRecord::Base.connection_db_config.configuration_hash
        case config[:adapter]
        when "postgresql"
          result = system "psql -h #{config[:host] || 'localhost'} -U #{config[:username]} -d #{config[:database]} -f #{backup_file}"
        when "mysql2"
          result = system "mysql -h #{config[:host] || 'localhost'} -u #{config[:username]} #{"-p#{config[:password]}" if config[:password]} #{config[:database]} < #{backup_file}"
        when "sqlite3"
          # SQLite3は直接ファイルをコピー
          result = FileUtils.cp(backup_file, config[:database])
        end
        
        return { success: result, message: result ? "Database restored successfully" : "Restore failed" }
      elsif backup_file.end_with?(".json")
        # JSONデータからのリストア
        import_result = import_system_data(backup_file, options)
        return { 
          success: import_result[:metadata][:success],
          message: import_result[:metadata][:success] ? "Data restored successfully" : "Restore failed",
          details: import_result
        }
      else
        return { success: false, error: "Unsupported backup format: #{File.extname(backup_file)}" }
      end
    end
  end
end
