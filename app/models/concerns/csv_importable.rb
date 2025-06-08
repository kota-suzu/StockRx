# frozen_string_literal: true

module CsvImportable
  extend ActiveSupport::Concern

  # クラスメソッド
  module ClassMethods
    def import_from_csv(file_path, options = {})
      require "csv"
      require "digest/md5"

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
        record.attributes.except("id", "created_at", "updated_at")
      end

      # 在庫ログ作成のため、挿入前の最大IDを記録
      baseline_max_id = maximum(:id) || 0 if self.name == "Inventory"

      # Rails 7+の場合はinsert_allでrecord_timestamps: trueオプションを使用
      result = insert_all(attributes, record_timestamps: true)

      # 在庫ログ用のデータを作成（bulk_insertでは通常のコールバックが動作しないため）
      if self.name == "Inventory"
        # MySQLとPostgreSQLの差異に対応した正確なIDマッピング
        create_accurate_inventory_logs(records, result, baseline_max_id)
      end

      result
    end

    private

    # より正確な在庫ログ作成（名前の重複に対応）
    def create_accurate_inventory_logs(records, insert_result, baseline_max_id)
      return if records.blank?

      # PostgreSQLの場合はRETURNING句でIDを取得
      if insert_result.respond_to?(:rows) && insert_result.rows.present?
        inserted_ids = insert_result.rows.flatten
        create_bulk_inventory_logs(records, inserted_ids)
      else
        # MySQLの場合：直接的なIDマッピング実装
        create_mysql_inventory_logs_direct(records, baseline_max_id)
      end
    end

    # PostgreSQL用の効率的な一括ログ作成
    def create_bulk_inventory_logs(records, inserted_ids)
      return if records.blank? || inserted_ids.blank?

      log_entries = []

      records.each_with_index do |record, index|
        # レコードと挿入されたIDを1:1でマッピング
        inventory_id = inserted_ids[index]
        next unless inventory_id

        log_entries << {
          inventory_id: inventory_id,
          delta: record.quantity,
          operation_type: "add",
          previous_quantity: 0,
          current_quantity: record.quantity,
          note: "CSVインポートによる登録",
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      if log_entries.present?
        InventoryLog.insert_all(log_entries, record_timestamps: false)
        Rails.logger.info("CSVインポート完了: #{log_entries.size}件の在庫ログを作成")
      end
    end

    # MySQL用の直接的なIDマッピング（トランザクション内で安全）
    def create_mysql_inventory_logs_direct(records, baseline_max_id)
      log_entries = []

      # insert_all後の新しいレコードを範囲で取得
      # トランザクション内でもCOMMITされているので検索可能
      new_records = where("id > ?", baseline_max_id).order(:id).limit(records.size)

      # レコードを順序で対応させる（同じ順序で挿入されるはず）
      records.each_with_index do |record, index|
        inserted_record = new_records[index]

        if inserted_record
          log_entries << {
            inventory_id: inserted_record.id,
            delta: record.quantity,
            operation_type: "add",
            previous_quantity: 0,
            current_quantity: record.quantity,
            note: "CSVインポートによる登録",
            created_at: Time.current,
            updated_at: Time.current
          }
        else
          Rails.logger.warn("CSVインポート: レコードマッピング失敗 #{record.name}")
        end
      end

      if log_entries.present?
        InventoryLog.insert_all(log_entries, record_timestamps: false)
        Rails.logger.info("CSVインポート完了: #{log_entries.size}件の在庫ログを作成")
      end
    end

    # MySQL用のバッチ挿入後の確実なIDマッピング（複雑版 - 今回は使用しない）
    def create_mysql_inventory_logs_with_transaction(records)
      puts "=== MySQL在庫ログ作成開始 ==="
      puts "records count: #{records.size}"

      # TODO: 🟡 重要 - Phase 2（推定1日）- MySQLでの確実なIDマッピング実装
      # 問題: 従来の名前ベース検索では複数の同名商品がある場合に不正確
      # 解決策: 挿入前後のID範囲とハッシュ値を組み合わせた確実なマッピング
      #
      # ベストプラクティス適用:
      # - バッチ挿入のパフォーマンスを維持
      # - データベース固有機能の抽象化
      # - 競合状態に対する堅牢性
      # - トレーサビリティの確保

      log_entries = []

      ActiveRecord::Base.transaction do
        # 挿入前の最大IDを記録（ベースライン）
        baseline_max_id = maximum(:id) || 0
        puts "baseline_max_id: #{baseline_max_id}"

        # 各レコードのハッシュ値を計算（識別用）
        records_with_hash = records.map.with_index do |record, index|
          # 複数の属性を組み合わせたハッシュ値で一意性を確保
          hash_source = "#{record.name}_#{record.price}_#{record.quantity}_#{index}"
          hash_value = Digest::MD5.hexdigest(hash_source)

          {
            record: record,
            index: index,
            hash_value: hash_value
          }
        end

        Rails.logger.debug("records_with_hash prepared: #{records_with_hash.size}")

        # 挿入直後のレコードをハッシュ値で確実に特定
        # 注意: この方法はバッチ挿入のパフォーマンスは保持するが、
        # 完全に同一の商品が複数ある場合は依然として制限がある
        start_time = Time.current

        records_with_hash.each do |item|
          record = item[:record]
          Rails.logger.debug("処理中レコード: #{record.name}")

          # 最も確実な方法：挿入直後の一意な組み合わせで検索
          search_conditions = {
            name: record.name,
            price: record.price,
            quantity: record.quantity
          }

          # 挿入後の時間範囲で絞り込み（競合を最小化）
          candidate_records = where(search_conditions)
                              .where("id > ?", baseline_max_id)
                              .where("created_at >= ?", start_time - 1.second)
                              .order(:id)

          Rails.logger.debug("candidate_records count: #{candidate_records.count}")

          if candidate_records.count == 1
            # 一意に特定できた場合
            inserted_record = candidate_records.first
            Rails.logger.debug("一意に特定: #{inserted_record.id}")
          elsif candidate_records.count > 1
            # 複数該当する場合は最初のもの（警告ログ出力）
            inserted_record = candidate_records.first
            Rails.logger.warn("CSVインポート: 複数の候補が見つかりました。#{record.name} (ID: #{inserted_record.id})")
          else
            # 見つからない場合（エラーログ出力）
            Rails.logger.error("CSVインポート: レコードが見つかりません。#{record.name}")
            Rails.logger.debug("検索条件: #{search_conditions}")
            Rails.logger.debug("baseline_max_id: #{baseline_max_id}, start_time: #{start_time}")
            next
          end

          log_entries << {
            inventory_id: inserted_record.id,
            delta: record.quantity,
            operation_type: "add",
            previous_quantity: 0,
            current_quantity: record.quantity,
            note: "CSVインポートによる登録",
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        Rails.logger.debug("log_entries count: #{log_entries.size}")

        # バッチで在庫ログを挿入
        if log_entries.present?
          InventoryLog.insert_all(log_entries, record_timestamps: false)
          Rails.logger.info("CSVインポート完了: #{log_entries.size}件の在庫ログを作成")
        else
          Rails.logger.warn("在庫ログエントリが作成されませんでした")
        end
      end

    rescue => e
      Rails.logger.error("CSVインポートトランザクションエラー: #{e.message}")
      raise e  # トランザクションロールバックのため再スロー
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

    # TODO: 🔵 長期 - Phase 4（推定2-3週間）- CSVインポート機能の包括的拡張
    #
    # 1. 高度なバリデーション機能
    #    - カスタムバリデーションルールの設定
    #    - 複数カラム間のデータ整合性チェック
    #    - 外部キー制約の自動検証
    #    - ビジネスルールに基づく検証（在庫数量の妥当性等）
    #
    # 2. インポート進捗の可視化改善
    #    - WebSocketを活用したリアルタイム進捗表示
    #    - バックグラウンドジョブでの非同期実行
    #    - 進捗通知のメール送信機能
    #    - エラー発生時の自動リトライ機能
    #
    # 3. エラーハンドリングの高度化
    #    - エラー行の詳細な特定機能（行番号、カラム名、値）
    #    - エラー修正のためのプレビュー機能
    #    - 部分インポートの再実行機能
    #    - CSVフォーマット検証の強化
    #
    # 4. パフォーマンス最適化
    #    - 大容量ファイル（10万行以上）の効率的処理
    #    - メモリ使用量の最適化（ストリーミング処理）
    #    - データベース接続プールの効率的利用
    #    - バッチサイズの動的調整
    #
    # 5. セキュリティ強化
    #    - ファイルタイプの厳格な検証
    #    - 悪意のあるペイロードの検出
    #    - アクセス権限の細かい制御
    #    - 監査ログの充実
    #
    # 6. 国際化対応
    #    - 多言語での列名対応
    #    - ロケール別のデータフォーマット対応
    #    - 通貨・日付形式の自動変換
    #
    # 7. 外部システム連携
    #    - API経由でのデータ同期
    #    - FTP/SFTPでの自動ファイル取得
    #    - 他システムとのデータフォーマット変換
    #
    # 8. 横展開確認事項
    #    - 他のモデル（Receipt, Shipment等）での同様機能の実装
    #    - 共通のCSVインポート基盤クラスの作成
    #    - インポート機能のプラガブル化
    #    - テンプレート機能の追加（業界標準フォーマット対応）
  end
end
