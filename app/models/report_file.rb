# frozen_string_literal: true

# ============================================================================
# ReportFile Model
# ============================================================================
# 目的: 生成されたレポートファイルの管理とメタデータ追跡
# 機能: ファイル保存・検索・保持期間管理・アクセス統計

class ReportFile < ApplicationRecord
  # ============================================================================
  # アソシエーション
  # ============================================================================

  belongs_to :admin

  # ============================================================================
  # 列挙型定義
  # ============================================================================

  # レポート種別
  REPORT_TYPES = %w[
    monthly_summary
    inventory_analysis
    expiry_analysis
    stock_movement_analysis
    custom_report
  ].freeze

  # ファイル形式
  FILE_FORMATS = %w[excel pdf csv json].freeze

  # 保存場所
  STORAGE_TYPES = %w[local s3 gcs azure].freeze

  # 保持ポリシー
  RETENTION_POLICIES = %w[
    temporary
    standard
    extended
    permanent
  ].freeze

  # ファイル状態
  STATUSES = %w[
    active
    archived
    deleted
    corrupted
    processing
  ].freeze

  # チェックサムアルゴリズム
  CHECKSUM_ALGORITHMS = %w[md5 sha1 sha256 sha512].freeze

  # ============================================================================
  # バリデーション
  # ============================================================================

  validates :report_type, presence: true, inclusion: { in: REPORT_TYPES }
  validates :file_format, presence: true, inclusion: { in: FILE_FORMATS }
  validates :report_period, presence: true
  validates :file_name, presence: true, length: { maximum: 255 }
  validates :file_path, presence: true, length: { maximum: 500 }
  validates :storage_type, presence: true, inclusion: { in: STORAGE_TYPES }
  validates :generated_at, presence: true
  validates :retention_policy, inclusion: { in: RETENTION_POLICIES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :checksum_algorithm, inclusion: { in: CHECKSUM_ALGORITHMS }

  # 数値フィールドのバリデーション
  validates :file_size, numericality: { greater_than: 0, allow_nil: true }
  validates :download_count, numericality: { greater_than_or_equal_to: 0 }
  validates :email_delivery_count, numericality: { greater_than_or_equal_to: 0 }

  # 日付の論理的整合性確認
  validate :validate_date_consistency
  validate :validate_file_path_format
  validate :validate_retention_policy_consistency

  # ユニーク制約（アクティブなファイルのみ）
  validates :report_type, uniqueness: {
    scope: [ :file_format, :report_period, :status ],
    conditions: -> { where(status: "active") },
    message: "同一期間・フォーマットのアクティブレポートが既に存在します"
  }

  # ============================================================================
  # スコープ
  # ============================================================================

  scope :active, -> { where(status: "active") }
  scope :archived, -> { where(status: "archived") }
  scope :deleted, -> { where(status: "deleted") }
  scope :by_type, ->(type) { where(report_type: type) }
  scope :by_format, ->(format) { where(file_format: format) }
  scope :by_period, ->(period) { where(report_period: period) }
  scope :recent, -> { order(generated_at: :desc) }
  scope :oldest_first, -> { order(generated_at: :asc) }

  # 保持期限関連
  scope :expired, -> { where("expires_at < ?", Date.current) }
  scope :expiring_soon, ->(days = 7) { where(expires_at: Date.current..(Date.current + days.days)) }
  scope :permanent, -> { where(retention_policy: "permanent") }

  # アクセス統計関連
  scope :frequently_accessed, -> { where("download_count > ?", 10) }
  scope :never_accessed, -> { where(download_count: 0, last_accessed_at: nil) }
  scope :recently_accessed, ->(days = 30) { where("last_accessed_at > ?", days.days.ago) }

  # ============================================================================
  # コールバック
  # ============================================================================

  before_validation :set_default_values
  before_create :calculate_file_hash
  before_create :set_retention_expiry
  after_create :log_file_creation
  before_destroy :cleanup_physical_file

  # ============================================================================
  # インスタンスメソッド
  # ============================================================================

  # ファイルの物理的存在確認
  def file_exists?
    case storage_type
    when "local"
      File.exist?(file_path)
    when "s3"
      # TODO: 🟡 Phase 2（中）- S3存在確認の実装
      false
    when "gcs"
      # TODO: 🟡 Phase 2（中）- GCS存在確認の実装
      false
    else
      false
    end
  end

  # ファイルサイズの取得（物理ファイルから）
  def actual_file_size
    return nil unless file_exists?

    case storage_type
    when "local"
      File.size(file_path)
    when "s3"
      # TODO: 🟡 Phase 2（中）- S3ファイルサイズ取得の実装
      nil
    else
      nil
    end
  end

  # ファイル整合性の確認
  def verify_integrity
    return false unless file_exists?

    current_hash = calculate_current_file_hash
    current_hash == file_hash
  end

  # アクセス記録の更新
  def record_access!
    increment!(:download_count)
    update!(last_accessed_at: Time.current)
    Rails.logger.info "[ReportFile] File accessed: #{file_name} (downloads: #{download_count})"
  end

  # 配信記録の更新
  def record_delivery!
    increment!(:email_delivery_count)
    update!(last_delivered_at: Time.current)
    Rails.logger.info "[ReportFile] File delivered via email: #{file_name} (deliveries: #{email_delivery_count})"
  end

  # アーカイブ処理
  def archive!
    return false if archived? || deleted?

    update!(status: "archived", archived_at: Time.current)
    Rails.logger.info "[ReportFile] File archived: #{file_name}"
    true
  end

  # 論理削除処理
  def soft_delete!
    return false if deleted?

    update!(status: "deleted", deleted_at: Time.current)
    Rails.logger.info "[ReportFile] File soft deleted: #{file_name}"
    true
  end

  # 物理削除処理
  def hard_delete!
    physical_deleted = delete_physical_file
    database_deleted = destroy

    Rails.logger.info "[ReportFile] File hard deleted: #{file_name} (physical: #{physical_deleted}, db: #{database_deleted})"
    physical_deleted && database_deleted
  end

  # 保持期限の延長
  def extend_retention!(new_policy = "extended")
    return false unless RETENTION_POLICIES.include?(new_policy)

    update!(
      retention_policy: new_policy,
      expires_at: calculate_expiry_date(new_policy)
    )
  end

  # ============================================================================
  # 状態確認メソッド
  # ============================================================================

  def active?
    status == "active"
  end

  def archived?
    status == "archived"
  end

  def deleted?
    status == "deleted"
  end

  def corrupted?
    status == "corrupted"
  end

  def processing?
    status == "processing"
  end

  def expired?
    expires_at && expires_at < Date.current
  end

  def expiring_soon?(days = 7)
    expires_at && expires_at <= Date.current + days.days
  end

  def permanent?
    retention_policy == "permanent"
  end

  def frequently_accessed?
    download_count > 10
  end

  def never_accessed?
    download_count == 0 && last_accessed_at.nil?
  end

  # ============================================================================
  # フォーマット・表示メソッド
  # ============================================================================

  def formatted_file_size
    return "Unknown" unless file_size

    units = %w[B KB MB GB TB]
    size = file_size.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end

  def display_name
    "#{report_type.humanize} - #{report_period.strftime('%Y年%m月')} (#{file_format.upcase})"
  end

  def short_file_hash
    file_hash&.first(8) || "N/A"
  end

  # ============================================================================
  # クラスメソッド
  # ============================================================================

  class << self
    # 期限切れファイルのクリーンアップ
    def cleanup_expired_files
      expired_files = expired.active
      cleaned_count = 0

      expired_files.find_each do |file|
        if file.permanent?
          file.archive!
        else
          file.soft_delete!
        end
        cleaned_count += 1
      end

      Rails.logger.info "[ReportFile] Cleaned up #{cleaned_count} expired files"
      cleaned_count
    end

    # 使用されていないファイルの特定
    def identify_unused_files(days_threshold = 90)
      threshold_date = days_threshold.days.ago

      where(
        "(last_accessed_at IS NULL AND created_at < ?) OR (last_accessed_at < ?)",
        threshold_date, threshold_date
      ).where(download_count: 0..1) # ほとんどアクセスされていない
    end

    # ストレージ使用量統計
    def storage_statistics
      {
        total_files: count,
        active_files: active.count,
        total_size: sum(:file_size) || 0,
        by_format: group(:file_format).count,
        by_type: group(:report_type).count,
        by_storage: group(:storage_type).sum(:file_size),
        average_size: average(:file_size)&.round || 0
      }
    end

    # 特定期間のレポートファイル検索
    def find_report(report_type, file_format, report_period)
      active.find_by(
        report_type: report_type,
        file_format: file_format,
        report_period: report_period
      )
    end
  end

  private

  # ============================================================================
  # プライベートメソッド
  # ============================================================================

  def set_default_values
    self.generated_at ||= Time.current
    self.status ||= "active"
    self.retention_policy ||= "standard"
    self.checksum_algorithm ||= "sha256"
    self.storage_type ||= "local"
  end

  def calculate_file_hash
    return unless file_exists?

    self.file_hash = calculate_current_file_hash
    self.file_size = actual_file_size
  end

  def calculate_current_file_hash
    return nil unless file_exists? && storage_type == "local"

    case checksum_algorithm
    when "md5"
      Digest::MD5.file(file_path).hexdigest
    when "sha1"
      Digest::SHA1.file(file_path).hexdigest
    when "sha256"
      Digest::SHA256.file(file_path).hexdigest
    when "sha512"
      Digest::SHA512.file(file_path).hexdigest
    else
      Digest::SHA256.file(file_path).hexdigest
    end
  rescue => e
    Rails.logger.error "[ReportFile] Failed to calculate file hash: #{e.message}"
    nil
  end

  def set_retention_expiry
    self.expires_at = calculate_expiry_date(retention_policy)
  end

  def calculate_expiry_date(policy)
    base_date = generated_at&.to_date || Date.current

    case policy
    when "temporary"
      base_date + 7.days
    when "standard"
      base_date + 90.days
    when "extended"
      base_date + 365.days
    when "permanent"
      nil
    else
      base_date + 90.days
    end
  end

  def delete_physical_file
    return true unless file_exists?

    case storage_type
    when "local"
      File.delete(file_path)
      true
    when "s3"
      # TODO: 🟡 Phase 2（中）- S3ファイル削除の実装
      false
    else
      false
    end
  rescue => e
    Rails.logger.error "[ReportFile] Failed to delete physical file: #{e.message}"
    false
  end

  def cleanup_physical_file
    delete_physical_file if file_exists?
  end

  def log_file_creation
    Rails.logger.info "[ReportFile] New report file created: #{display_name} (#{formatted_file_size})"
  end

  # ============================================================================
  # バリデーションメソッド
  # ============================================================================

  def validate_date_consistency
    return unless generated_at && expires_at

    if expires_at < generated_at.to_date
      errors.add(:expires_at, "は生成日時より後の日付である必要があります")
    end
  end

  def validate_file_path_format
    return unless file_path

    # 不正なパス文字の確認
    if file_path.include?("..")
      errors.add(:file_path, "に不正なパス表記が含まれています")
    end

    # ファイル拡張子の確認
    expected_extension = case file_format
    when "excel" then ".xlsx"
    when "pdf" then ".pdf"
    when "csv" then ".csv"
    when "json" then ".json"
    end

    unless file_path.end_with?(expected_extension)
      errors.add(:file_path, "はファイル形式(#{file_format})に対応する拡張子である必要があります")
    end
  end

  def validate_retention_policy_consistency
    return unless retention_policy && expires_at

    if retention_policy == "permanent" && expires_at
      errors.add(:expires_at, "は永続保持ポリシーでは設定できません")
    end

    if retention_policy != "permanent" && expires_at.nil?
      errors.add(:expires_at, "は非永続保持ポリシーでは必須です")
    end
  end
end
