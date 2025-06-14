# frozen_string_literal: true

# ============================================================================
# ReportFile Factory
# ============================================================================
# 目的: テスト用のReportFileオブジェクト生成
# 機能: 各種レポートファイルパターンの生成・テストデータ作成

FactoryBot.define do
  factory :report_file do
    # ============================================
    # 基本属性
    # ============================================

    association :admin

    report_type { 'monthly_summary' }
    file_format { 'excel' }
    sequence(:report_period) { |n| (Date.current.beginning_of_month - n.months) }

    # ファイル情報（初期値、後でコールバックで修正）
    sequence(:file_name) { |n| "monthly_report_#{n}.xlsx" }
    sequence(:file_path) { |n| Rails.root.join('tmp', 'test_reports', "report_#{n}.xlsx").to_s }
    storage_type { 'local' }
    file_size { rand(100_000..2_000_000) } # 100KB - 2MB
    file_hash { SecureRandom.hex(32) }

    # メタデータ
    generated_at { Time.current }
    generation_metadata do
      {
        generated_by: 'ReportFileStorageService',
        generation_time: Time.current,
        rails_env: Rails.env,
        options: {}
      }
    end

    # ステータス
    status { 'active' }
    retention_policy { 'standard' }
    expires_at { 90.days.from_now.to_date }

    # アクセス統計
    download_count { 0 }
    email_delivery_count { 0 }

    # チェックサム
    checksum_algorithm { 'sha256' }

    # ============================================
    # ファイル作成コールバック
    # ============================================

    after(:build) do |report_file|
      # ファイル形式に応じた拡張子の修正
      extension = case report_file.file_format
      when 'excel' then '.xlsx'
      when 'pdf' then '.pdf'
      when 'csv' then '.csv'
      when 'json' then '.json'
      else '.xlsx'
      end

      # file_nameの拡張子を修正
      if report_file.file_name
        base_name = report_file.file_name.sub(/\.\w+$/, '')
        report_file.file_name = "#{base_name}#{extension}"
      end

      # file_pathの拡張子を修正
      if report_file.file_path
        base_path = report_file.file_path.sub(/\.\w+$/, '')
        report_file.file_path = "#{base_path}#{extension}"
      end
    end


    before(:create) do |report_file|
      # テスト用の実際のファイルを作成
      FileUtils.mkdir_p(File.dirname(report_file.file_path))

      # ファイル形式に応じたダミーコンテンツ
      content = case report_file.file_format
      when 'excel'
                 ReportFileFactoryHelpers.generate_dummy_excel_content
      when 'pdf'
                 ReportFileFactoryHelpers.generate_dummy_pdf_content
      when 'csv'
                 ReportFileFactoryHelpers.generate_dummy_csv_content
      when 'json'
                 ReportFileFactoryHelpers.generate_dummy_json_content
      else
                 "Dummy content for #{report_file.file_format}"
      end

      File.write(report_file.file_path, content)
    end

    after(:create) do |report_file|
      # テスト向けに物理ファイルサイズとハッシュを実際のファイルから取得
      # ただし、明示的に異なる値が設定されている場合は尊重する
      if File.exist?(report_file.file_path)
        actual_size = File.size(report_file.file_path)
        actual_hash = Digest::SHA256.file(report_file.file_path).hexdigest

        # ファイルサイズの更新（テストで明示的に大きなサイズが設定されている場合は保持）
        if report_file.file_size.nil? || report_file.file_size < 2_000_000  # 2MB未満は実サイズに更新
          report_file.update_column(:file_size, actual_size)
        end

        # ファイルハッシュの更新（明示的にnilが設定されている場合以外）
        unless report_file.file_hash == "explicit_nil_for_test"
          report_file.update_column(:file_hash, actual_hash)
        end
      end
    end

    # ============================================
    # ファクトリーバリエーション
    # ============================================

    # PDF レポート
    factory :pdf_report_file do
      file_format { 'pdf' }
      sequence(:file_name) { |n| "monthly_summary_#{n}.pdf" }
      sequence(:file_path) { |n| Rails.root.join('tmp', 'test_reports', "summary_#{n}.pdf").to_s }
    end

    # CSV エクスポート
    factory :csv_report_file do
      file_format { 'csv' }
      report_type { 'inventory_analysis' }
      sequence(:file_name) { |n| "inventory_export_#{n}.csv" }
      sequence(:file_path) { |n| Rails.root.join('tmp', 'test_reports', "export_#{n}.csv").to_s }
    end

    # JSON データエクスポート
    factory :json_report_file do
      file_format { 'json' }
      report_type { 'stock_movement_analysis' }
      sequence(:file_name) { |n| "movement_data_#{n}.json" }
      sequence(:file_path) { |n| Rails.root.join('tmp', 'test_reports', "movement_#{n}.json").to_s }
    end

    # アーカイブ済みファイル
    factory :archived_report_file do
      status { 'archived' }
      archived_at { 1.month.ago }
      retention_policy { 'extended' }
      expires_at { 1.year.from_now.to_date }
    end

    # 削除済みファイル
    factory :deleted_report_file do
      status { 'deleted' }
      deleted_at { 1.week.ago }
    end

    # 期限切れファイル
    factory :expired_report_file do
      retention_policy { 'temporary' }
      generated_at { 10.days.ago }
      expires_at { 1.day.ago.to_date }
    end

    # 高頻度アクセスファイル
    factory :frequently_accessed_report_file do
      download_count { rand(20..100) }
      email_delivery_count { rand(5..20) }
      last_accessed_at { rand(1..7).days.ago }
      last_delivered_at { rand(1..14).days.ago }
    end

    # 未使用ファイル
    factory :unused_report_file do
      download_count { 0 }
      email_delivery_count { 0 }
      last_accessed_at { nil }
      last_delivered_at { nil }
      created_at { 120.days.ago }
    end

    # 破損ファイル
    factory :corrupted_report_file do
      status { 'corrupted' }
      file_hash { 'invalid_hash' }
    end

    # 永続保持ファイル
    factory :permanent_report_file do
      retention_policy { 'permanent' }
      expires_at { nil }
      report_type { 'custom_report' }
      notes { '重要な監査用レポート - 永続保持' }
    end

    # 大容量ファイル
    factory :large_report_file do
      file_size { rand(20_000_000..25_000_000) } # 20-25MB
      notes { '大容量レポートファイル' }
    end

    # 期限間近ファイル
    factory :expiring_soon_report_file do
      expires_at { 3.days.from_now.to_date }
      retention_policy { 'temporary' }
    end

    # ============================================
    # トレイト（特性）
    # ============================================

    trait :with_physical_file do
      after(:build) do |report_file|
        FileUtils.mkdir_p(File.dirname(report_file.file_path))
        File.write(report_file.file_path, "Test content for #{report_file.file_name}")
      end
    end

    trait :without_physical_file do
      # ファイル作成をスキップするため、基本のbefore(:create)を無効化
      before(:create) { |report_file| nil } # 何もしない

      after(:create) do |report_file|
        # 念のため、存在する場合は削除
        File.delete(report_file.file_path) if File.exist?(report_file.file_path)
        # ファイルサイズとハッシュも無効化
        report_file.update_columns(file_size: nil, file_hash: nil)
      end
    end

    trait :current_month do
      report_period { Date.current.beginning_of_month }
    end

    trait :last_month do
      report_period { 1.month.ago.beginning_of_month }
    end

    trait :last_year do
      report_period { 1.year.ago.beginning_of_month }
    end

    trait :with_detailed_metadata do
      generation_metadata do
        {
          generated_by: 'ReportFileStorageService',
          generation_time: Time.current,
          rails_env: Rails.env,
          source_data_count: rand(100..1000),
          processing_duration_ms: rand(1000..5000),
          memory_usage_mb: rand(50..200),
          options: {
            include_details: true,
            format_options: { charts: true, summary: true }
          }
        }
      end
    end
  end
end

# ============================================
# ヘルパーメソッド（ファクトリー外部定義）
# ============================================

module ReportFileFactoryHelpers
  def self.generate_dummy_excel_content
    # 最小限のExcelファイル構造をシミュレート
    "PK\x03\x04" + "Excel dummy content " * 100
  end

  def self.generate_dummy_pdf_content
    # PDFファイルヘッダーを含むダミーコンテンツ
    "%PDF-1.4\n" + "PDF dummy content " * 100 + "\n%%EOF"
  end

  def self.generate_dummy_csv_content
    # CSV形式のダミーデータ
    csv_content = "ID,Name,Quantity,Value\n"
    (1..50).each do |i|
      csv_content += "#{i},Item #{i},#{rand(1..100)},#{rand(1000..10000)}\n"
    end
    csv_content
  end

  def self.generate_dummy_json_content
    # JSON形式のダミーデータ
    data = {
      report_type: 'stock_movement_analysis',
      generated_at: Time.current.iso8601,
      data: (1..20).map do |i|
        {
          id: i,
          item_name: "Item #{i}",
          movement_count: rand(1..50),
          last_movement: rand(30).days.ago.iso8601
        }
      end,
      summary: {
        total_items: 20,
        total_movements: rand(100..500),
        period: Date.current.strftime('%Y-%m')
      }
    }
    JSON.pretty_generate(data)
  end
end
