# frozen_string_literal: true

# ============================================================================
# ReportFileStorageService
# ============================================================================
# 目的: レポートファイルの保存・管理・取得機能
# 機能: ファイル保存、メタデータ記録、保持期間管理、クリーンアップ

class ReportFileStorageService
  # ============================================================================
  # カスタム例外
  # ============================================================================

  class StorageError < StandardError; end
  class FileNotFoundError < StorageError; end
  class ValidationError < StorageError; end
  class InsufficientSpaceError < StorageError; end

  # ============================================================================
  # 定数定義
  # ============================================================================

  # デフォルト保存ディレクトリ
  DEFAULT_STORAGE_BASE = Rails.root.join("storage", "reports").freeze

  # ファイルサイズ上限（25MB）
  MAX_FILE_SIZE = 25.megabytes.freeze

  # 保存ディレクトリ構造
  DIRECTORY_STRUCTURE = "%Y/%m".freeze

  # バックアップ設定
  BACKUP_ENABLED = Rails.env.production?

  # ============================================================================
  # クラスメソッド - ファイル保存
  # ============================================================================

  class << self
    # レポートファイルの保存
    # @param file_path [String] 生成されたファイルのパス
    # @param report_type [String] レポート種別
    # @param file_format [String] ファイル形式
    # @param report_period [Date] レポート対象期間
    # @param admin [Admin] 生成実行者
    # @param options [Hash] 追加オプション
    # @return [ReportFile] 保存されたレポートファイルレコード
    def store_report_file(file_path, report_type, file_format, report_period, admin, options = {})
      Rails.logger.info "[ReportFileStorageService] Starting file storage: #{file_path}"

      # メタ認知的アプローチ：保存前の事前検証
      validate_storage_parameters(file_path, report_type, file_format, report_period, admin)

      begin
        # 既存ファイルの確認と処理
        handle_existing_file(report_type, file_format, report_period)

        # ファイルの移動と保存
        stored_path = move_to_storage_location(file_path, report_type, file_format, report_period)

        # データベースレコードの作成
        report_file = create_report_file_record(
          stored_path, report_type, file_format, report_period, admin, options
        )

        # バックアップ作成（本番環境のみ）
        create_backup_if_needed(report_file) if BACKUP_ENABLED

        Rails.logger.info "[ReportFileStorageService] File stored successfully: #{report_file.id}"
        report_file

      rescue => e
        # エラー時のクリーンアップ
        cleanup_failed_storage(file_path)
        raise StorageError, "ファイル保存エラー: #{e.message}"
      end
    end

    # 一括保存（Excel + PDF同時保存）
    # @param file_paths [Hash] ファイルパス（:excel, :pdf）
    # @param report_type [String] レポート種別
    # @param report_period [Date] レポート対象期間
    # @param admin [Admin] 生成実行者
    # @param options [Hash] 追加オプション
    # @return [Array<ReportFile>] 保存されたレポートファイルリスト
    def store_multiple_files(file_paths, report_type, report_period, admin, options = {})
      Rails.logger.info "[ReportFileStorageService] Starting bulk storage for #{file_paths.keys.join(', ')}"

      stored_files = []

      file_paths.each do |format, path|
        next unless path && File.exist?(path)

        stored_file = store_report_file(path, report_type, format.to_s, report_period, admin, options)
        stored_files << stored_file
      end

      Rails.logger.info "[ReportFileStorageService] Bulk storage completed: #{stored_files.count} files"
      stored_files
    end

    # ============================================================================
    # クラスメソッド - ファイル取得・管理
    # ============================================================================

    # レポートファイルの取得
    # @param report_type [String] レポート種別
    # @param file_format [String] ファイル形式
    # @param report_period [Date] レポート対象期間
    # @return [ReportFile, nil] レポートファイルレコード
    def find_report_file(report_type, file_format, report_period)
      ReportFile.find_report(report_type, file_format, report_period)
    end

    # ファイル内容の読み込み
    # @param report_file [ReportFile] レポートファイルレコード
    # @return [String] ファイル内容
    def read_file_content(report_file)
      unless report_file.file_exists?
        raise FileNotFoundError, "ファイルが見つかりません: #{report_file.file_path}"
      end

      # 整合性確認
      unless report_file.verify_integrity
        Rails.logger.warn "[ReportFileStorageService] File integrity check failed: #{report_file.id}"
        report_file.update!(status: "corrupted")
        raise StorageError, "ファイルが破損している可能性があります"
      end

      # アクセス記録
      report_file.record_access!

      # ファイル読み込み
      File.read(report_file.file_path)
    end

    # ファイルのダウンロード用パス生成
    # @param report_file [ReportFile] レポートファイルレコード
    # @return [String] ダウンロード用の一時パス
    def generate_download_path(report_file)
      unless report_file.file_exists?
        raise FileNotFoundError, "ファイルが見つかりません: #{report_file.file_path}"
      end

      # 一時ディレクトリにコピー
      temp_dir = Rails.root.join("tmp", "downloads")
      FileUtils.mkdir_p(temp_dir)

      temp_filename = "#{SecureRandom.hex(8)}_#{report_file.file_name}"
      temp_path = temp_dir.join(temp_filename)

      FileUtils.cp(report_file.file_path, temp_path)

      # アクセス記録
      report_file.record_access!

      temp_path.to_s
    end

    # ============================================================================
    # クラスメソッド - 保持期間・クリーンアップ管理
    # ============================================================================

    # 期限切れファイルの自動クリーンアップ
    # @param dry_run [Boolean] 実際には削除せずにログ出力のみ
    # @return [Hash] クリーンアップ結果統計
    def cleanup_expired_files(dry_run: false)
      Rails.logger.info "[ReportFileStorageService] Starting expired files cleanup (dry_run: #{dry_run})"

      expired_files = ReportFile.expired.active
      cleanup_stats = {
        total_found: expired_files.count,
        archived: 0,
        soft_deleted: 0,
        hard_deleted: 0,
        errors: 0,
        freed_space: 0
      }

      expired_files.find_each do |file|
        begin
          if dry_run
            Rails.logger.info "[ReportFileStorageService] DRY RUN - Would process: #{file.display_name}"
            next
          end

          freed_space = file.file_size || 0

          if file.permanent?
            file.archive!
            cleanup_stats[:archived] += 1
          elsif file.never_accessed? && file.generated_at < 30.days.ago
            file.hard_delete!
            cleanup_stats[:hard_deleted] += 1
            cleanup_stats[:freed_space] += freed_space
          else
            file.soft_delete!
            cleanup_stats[:soft_deleted] += 1
          end

        rescue => e
          Rails.logger.error "[ReportFileStorageService] Cleanup error for file #{file.id}: #{e.message}"
          cleanup_stats[:errors] += 1
        end
      end

      Rails.logger.info "[ReportFileStorageService] Cleanup completed: #{cleanup_stats}"
      cleanup_stats
    end

    # 使用されていないファイルの特定と削除
    # @param threshold_days [Integer] 未使用と判定する日数
    # @param dry_run [Boolean] 実際には削除せずにログ出力のみ
    # @return [Hash] 処理結果統計
    def cleanup_unused_files(threshold_days: 90, dry_run: false)
      Rails.logger.info "[ReportFileStorageService] Starting unused files cleanup (threshold: #{threshold_days} days)"

      unused_files = ReportFile.identify_unused_files(threshold_days)
      cleanup_stats = {
        total_found: unused_files.count,
        deleted: 0,
        errors: 0,
        freed_space: 0
      }

      unused_files.find_each do |file|
        begin
          if dry_run
            Rails.logger.info "[ReportFileStorageService] DRY RUN - Would delete unused: #{file.display_name}"
            next
          end

          freed_space = file.file_size || 0

          if file.hard_delete!
            cleanup_stats[:deleted] += 1
            cleanup_stats[:freed_space] += freed_space
          end

        rescue => e
          Rails.logger.error "[ReportFileStorageService] Error deleting unused file #{file.id}: #{e.message}"
          cleanup_stats[:errors] += 1
        end
      end

      Rails.logger.info "[ReportFileStorageService] Unused files cleanup completed: #{cleanup_stats}"
      cleanup_stats
    end

    # ストレージ使用量の分析
    # @return [Hash] ストレージ統計情報
    def analyze_storage_usage
      stats = ReportFile.storage_statistics

      # 物理ディスク使用量の確認
      if Dir.exist?(DEFAULT_STORAGE_BASE)
        physical_size = calculate_directory_size(DEFAULT_STORAGE_BASE)
        stats[:physical_size] = physical_size
        stats[:size_discrepancy] = (physical_size - stats[:total_size]).abs
      end

      # 使用量警告の判定
      stats[:warnings] = []
      if stats[:total_size] > 1.gigabyte
        stats[:warnings] << "総ファイルサイズが1GBを超えています"
      end

      if stats[:active_files] > 1000
        stats[:warnings] << "アクティブファイル数が1000を超えています"
      end

      Rails.logger.info "[ReportFileStorageService] Storage analysis: #{stats.except(:warnings)}"
      stats
    end

    # ============================================================================
    # クラスメソッド - メンテナンス機能
    # ============================================================================

    # ファイル整合性の一括チェック
    # @param repair [Boolean] 破損ファイルの自動修復を試行するか
    # @return [Hash] チェック結果統計
    def verify_all_files_integrity(repair: false)
      Rails.logger.info "[ReportFileStorageService] Starting integrity verification"

      verification_stats = {
        total_checked: 0,
        valid: 0,
        corrupted: 0,
        missing: 0,
        repaired: 0,
        errors: 0
      }

      ReportFile.active.find_each do |file|
        verification_stats[:total_checked] += 1

        begin
          if file.file_exists?
            if file.verify_integrity
              verification_stats[:valid] += 1
            else
              verification_stats[:corrupted] += 1
              file.update!(status: "corrupted")

              if repair
                # TODO: 🔴 Phase 2（緊急）- ファイル修復機能の実装
                # バックアップからの復元、再生成など
                verification_stats[:repaired] += attempt_file_repair(file)
              end
            end
          else
            verification_stats[:missing] += 1
            file.update!(status: "corrupted")
          end

        rescue => e
          Rails.logger.error "[ReportFileStorageService] Verification error for file #{file.id}: #{e.message}"
          verification_stats[:errors] += 1
        end
      end

      Rails.logger.info "[ReportFileStorageService] Integrity verification completed: #{verification_stats}"
      verification_stats
    end

    # 重複ファイルの特定と統合
    # @return [Hash] 重複処理結果
    def identify_and_merge_duplicates
      Rails.logger.info "[ReportFileStorageService] Starting duplicate identification"

      # ファイルハッシュでグループ化
      duplicates = ReportFile.active
                             .where.not(file_hash: nil)
                             .group(:file_hash)
                             .having("count(*) > 1")
                             .count

      merge_stats = {
        duplicate_groups: duplicates.count,
        files_merged: 0,
        space_freed: 0
      }

      duplicates.keys.each do |hash|
        duplicate_files = ReportFile.active.where(file_hash: hash).order(:created_at)
        master_file = duplicate_files.first
        duplicate_files[1..-1].each do |dup_file|
          merge_stats[:space_freed] += dup_file.file_size || 0
          dup_file.soft_delete!
          merge_stats[:files_merged] += 1
        end
      end

      Rails.logger.info "[ReportFileStorageService] Duplicate merge completed: #{merge_stats}"
      merge_stats
    end

    private

    # ============================================================================
    # プライベートメソッド - バリデーション
    # ============================================================================

    def validate_storage_parameters(file_path, report_type, file_format, report_period, admin)
      unless File.exist?(file_path)
        raise ValidationError, "ファイルが存在しません: #{file_path}"
      end

      unless ReportFile::REPORT_TYPES.include?(report_type)
        raise ValidationError, "無効なレポート種別: #{report_type}"
      end

      unless ReportFile::FILE_FORMATS.include?(file_format)
        raise ValidationError, "無効なファイル形式: #{file_format}"
      end

      unless report_period.is_a?(Date)
        raise ValidationError, "レポート期間は日付である必要があります"
      end

      unless admin.is_a?(Admin)
        raise ValidationError, "管理者オブジェクトが無効です"
      end

      file_size = File.size(file_path)
      if file_size > MAX_FILE_SIZE
        raise ValidationError, "ファイルサイズが上限を超えています: #{file_size} bytes"
      end

      if file_size == 0
        raise ValidationError, "空のファイルは保存できません"
      end
    end

    # ============================================================================
    # プライベートメソッド - ファイル操作
    # ============================================================================

    def handle_existing_file(report_type, file_format, report_period)
      existing_file = ReportFile.find_report(report_type, file_format, report_period)
      return unless existing_file

      Rails.logger.info "[ReportFileStorageService] Existing file found, archiving: #{existing_file.id}"
      existing_file.archive!
    end

    def move_to_storage_location(source_path, report_type, file_format, report_period)
      # 保存先ディレクトリの生成
      storage_dir = DEFAULT_STORAGE_BASE.join(
        report_period.strftime(DIRECTORY_STRUCTURE),
        report_type
      )
      FileUtils.mkdir_p(storage_dir)

      # ファイル名の生成
      timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
      filename = "#{report_type}_#{report_period.strftime('%Y%m')}_#{timestamp}.#{get_file_extension(file_format)}"
      destination_path = storage_dir.join(filename)

      # ファイルの移動
      FileUtils.mv(source_path, destination_path)

      Rails.logger.debug "[ReportFileStorageService] File moved to: #{destination_path}"
      destination_path.to_s
    end

    def create_report_file_record(file_path, report_type, file_format, report_period, admin, options)
      generation_metadata = {
        generated_by: "ReportFileStorageService",
        generation_time: Time.current,
        rails_env: Rails.env,
        options: options
      }

      ReportFile.create!(
        report_type: report_type,
        file_format: file_format,
        report_period: report_period,
        file_name: File.basename(file_path),
        file_path: file_path,
        admin: admin,
        generation_metadata: generation_metadata.deep_stringify_keys,
        generated_at: Time.current
      )
    end

    def get_file_extension(file_format)
      case file_format
      when "excel" then "xlsx"
      when "pdf" then "pdf"
      when "csv" then "csv"
      when "json" then "json"
      else file_format
      end
    end

    def create_backup_if_needed(report_file)
      # TODO: 🟡 Phase 2（中）- バックアップ機能の実装
      # S3、GCS等へのバックアップ保存
      Rails.logger.debug "[ReportFileStorageService] Backup creation skipped (not implemented)"
    end

    def cleanup_failed_storage(file_path)
      File.delete(file_path) if File.exist?(file_path)
    rescue => e
      Rails.logger.error "[ReportFileStorageService] Failed to cleanup file: #{e.message}"
    end

    def calculate_directory_size(directory)
      total_size = 0
      Dir.glob(File.join(directory, "**", "*")).each do |file|
        total_size += File.size(file) if File.file?(file)
      end
      total_size
    end

    def attempt_file_repair(report_file)
      # TODO: 🔴 Phase 2（緊急）- ファイル修復機能の実装
      # バックアップからの復元、元データからの再生成など
      Rails.logger.warn "[ReportFileStorageService] File repair not implemented for: #{report_file.id}"
      0
    end
  end
end
