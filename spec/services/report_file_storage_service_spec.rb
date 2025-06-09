# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# ReportFileStorageServiceテスト
# ============================================================================
# 目的:
#   - レポートファイル保存サービスの機能テスト
#   - ファイル操作の安全性・信頼性確認
#   - 保持期間管理・クリーンアップ機能検証
#
# 設計思想:
#   - ファイルシステム操作の安全性確保
#   - データ整合性とトランザクション安全性
#   - エラーハンドリングの網羅的検証
#
# 横展開確認:
#   - 他のサービステストとの統一パターン
#   - ファイル操作テストの体系化
#   - セキュリティテストの強化
# ============================================================================

RSpec.describe ReportFileStorageService, type: :service do
  # ============================================================================
  # テスト用データセットアップ
  # ============================================================================

  let(:admin) { create(:admin) }
  let(:target_period) { Date.current.beginning_of_month }
  let(:report_type) { 'monthly_summary' }
  let(:file_format) { 'excel' }

  let(:temp_file_path) { Rails.root.join('tmp', 'test_report.xlsx').to_s }
  let(:temp_pdf_path) { Rails.root.join('tmp', 'test_report.pdf').to_s }

  # テスト用ファイル作成
  before do
    FileUtils.mkdir_p(File.dirname(temp_file_path))
    File.write(temp_file_path, "Test Excel content " * 100) # 約2KB
    File.write(temp_pdf_path, "%PDF-1.4\nTest PDF content " * 100) # 約2KB
  end

  # テスト後のクリーンアップ
  after do
    [ temp_file_path, temp_pdf_path ].each do |path|
      File.delete(path) if File.exist?(path)
    end

    # テスト用ストレージディレクトリのクリーンアップ
    test_storage_base = Rails.root.join('storage', 'reports')
    FileUtils.rm_rf(test_storage_base) if Dir.exist?(test_storage_base)
  end

  # ============================================================================
  # 正常系テスト - ファイル保存
  # ============================================================================

  describe '.store_report_file' do
    subject do
      described_class.store_report_file(
        temp_file_path, report_type, file_format, target_period, admin
      )
    end

    it '正常にファイルが保存されること' do
      expect { subject }.not_to raise_error
      expect(subject).to be_a(ReportFile)
      expect(subject.persisted?).to be true
    end

    it 'ファイルが適切な場所に移動されること' do
      result = subject

      expect(File.exist?(result.file_path)).to be true
      expect(File.exist?(temp_file_path)).to be false # 元ファイルは移動済み
      expect(result.file_path).to include('storage/reports')
      expect(result.file_path).to include(target_period.strftime('%Y/%m'))
      expect(result.file_path).to include(report_type)
    end

    it 'データベースレコードが正しく作成されること' do
      result = subject

      expect(result.report_type).to eq(report_type)
      expect(result.file_format).to eq(file_format)
      expect(result.report_period).to eq(target_period)
      expect(result.admin).to eq(admin)
      expect(result.status).to eq('active')
      expect(result.file_size).to be > 0
      expect(result.file_hash).to be_present
    end

    it 'ファイルハッシュが正しく計算されること' do
      result = subject

      expected_hash = Digest::SHA256.file(result.file_path).hexdigest
      expect(result.file_hash).to eq(expected_hash)
    end

    it 'ログが適切に出力されること' do
      expect(Rails.logger).to receive(:info).with(/Starting file storage/)
      expect(Rails.logger).to receive(:info).with(/File stored successfully/)

      subject
    end

    context 'オプション付きで保存する場合' do
      let(:options) { { priority: 'high', notes: 'Test report' } }

      subject do
        described_class.store_report_file(
          temp_file_path, report_type, file_format, target_period, admin, options
        )
      end

      it 'オプションがメタデータに記録されること' do
        result = subject

        expect(result.generation_metadata['options']).to eq(options)
        expect(result.generation_metadata['generated_by']).to eq('ReportFileStorageService')
      end
    end

    context '既存ファイルが存在する場合' do
      let!(:existing_file) do
        create(:report_file,
               admin: admin,
               report_type: report_type,
               file_format: file_format,
               report_period: target_period,
               status: 'active')
      end

      it '既存ファイルがアーカイブされること' do
        expect { subject }.to change { existing_file.reload.status }.from('active').to('archived')
      end

      it '新しいファイルが作成されること' do
        expect { subject }.to change(ReportFile, :count).by(1)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - 一括保存
  # ============================================================================

  describe '.store_multiple_files' do
    let(:file_paths) do
      {
        excel: temp_file_path,
        pdf: temp_pdf_path
      }
    end

    subject do
      described_class.store_multiple_files(
        file_paths, report_type, target_period, admin
      )
    end

    it '複数ファイルが正常に保存されること' do
      expect { subject }.not_to raise_error
      expect(subject).to be_an(Array)
      expect(subject.length).to eq(2)

      subject.each do |file|
        expect(file).to be_a(ReportFile)
        expect(file.persisted?).to be true
      end
    end

    it '各ファイル形式が正しく処理されること' do
      results = subject

      excel_file = results.find { |f| f.file_format == 'excel' }
      pdf_file = results.find { |f| f.file_format == 'pdf' }

      expect(excel_file).to be_present
      expect(pdf_file).to be_present
      expect(excel_file.file_path).to end_with('.xlsx')
      expect(pdf_file.file_path).to end_with('.pdf')
    end

    it '一括保存のログが出力されること' do
      expect(Rails.logger).to receive(:info).with(/Starting bulk storage/)
      expect(Rails.logger).to receive(:info).with(/Bulk storage completed: 2 files/)

      subject
    end

    context '一部のファイルが存在しない場合' do
      let(:file_paths) do
        {
          excel: temp_file_path,
          pdf: '/nonexistent/file.pdf'
        }
      end

      it '存在するファイルのみ保存されること' do
        results = subject
        expect(results.length).to eq(1)
        expect(results.first.file_format).to eq('excel')
      end
    end
  end

  # ============================================================================
  # 正常系テスト - ファイル取得・管理
  # ============================================================================

  describe '.find_report_file' do
    let!(:target_file) do
      create(:report_file,
             :with_physical_file,
             admin: admin,
             report_type: report_type,
             file_format: file_format,
             report_period: target_period)
    end

    it '条件に一致するファイルが取得できること' do
      result = described_class.find_report_file(report_type, file_format, target_period)
      expect(result).to eq(target_file)
    end

    it '条件に一致しないファイルはnilを返すこと' do
      result = described_class.find_report_file('invalid_type', file_format, target_period)
      expect(result).to be_nil
    end
  end

  describe '.read_file_content' do
    let(:report_file) { create(:report_file, :with_physical_file, admin: admin) }

    it 'ファイル内容が正しく読み込まれること' do
      content = described_class.read_file_content(report_file)
      expect(content).to be_present
      expect(content).to include('Test content')
    end

    it 'アクセス記録が更新されること' do
      initial_count = report_file.download_count
      described_class.read_file_content(report_file)

      expect(report_file.reload.download_count).to eq(initial_count + 1)
      expect(report_file.last_accessed_at).to be_within(1.second).of(Time.current)
    end

    context 'ファイルが存在しない場合' do
      let(:report_file) { create(:report_file, :without_physical_file, admin: admin) }

      it 'FileNotFoundErrorを発生させること' do
        expect {
          described_class.read_file_content(report_file)
        }.to raise_error(ReportFileStorageService::FileNotFoundError, /ファイルが見つかりません/)
      end
    end

    context 'ファイルが破損している場合' do
      before do
        # ファイルハッシュを不正な値に変更
        report_file.update!(file_hash: 'invalid_hash')
      end

      it 'StorageErrorを発生させること' do
        expect {
          described_class.read_file_content(report_file)
        }.to raise_error(ReportFileStorageService::StorageError, /ファイルが破損している/)
      end

      it 'ファイルステータスがcorruptedに変更されること' do
        expect {
          described_class.read_file_content(report_file) rescue nil
        }.to change { report_file.reload.status }.to('corrupted')
      end
    end
  end

  describe '.generate_download_path' do
    let(:report_file) { create(:report_file, :with_physical_file, admin: admin) }

    it 'ダウンロード用の一時パスが生成されること' do
      temp_path = described_class.generate_download_path(report_file)

      expect(File.exist?(temp_path)).to be true
      expect(temp_path).to include('tmp/downloads')
      expect(File.basename(temp_path)).to include(report_file.file_name)

      # クリーンアップ
      File.delete(temp_path) if File.exist?(temp_path)
    end

    it 'アクセス記録が更新されること' do
      initial_count = report_file.download_count
      temp_path = described_class.generate_download_path(report_file)

      expect(report_file.reload.download_count).to eq(initial_count + 1)

      # クリーンアップ
      File.delete(temp_path) if File.exist?(temp_path)
    end
  end

  # ============================================================================
  # 正常系テスト - クリーンアップ機能
  # ============================================================================

  describe '.cleanup_expired_files' do
    let!(:expired_file) { create(:expired_report_file, :with_physical_file, admin: admin) }
    let!(:active_file) { create(:report_file, :with_physical_file, admin: admin) }
    let!(:permanent_expired) do
      create(:permanent_report_file, admin: admin, expires_at: 1.day.ago.to_date, status: 'active')
    end

    context 'dry_run: false の場合' do
      subject { described_class.cleanup_expired_files(dry_run: false) }

      it '期限切れファイルが適切にクリーンアップされること' do
        result = subject

        expect(result[:total_found]).to eq(1) # permanent_expiredは永続なので除外
        expect(result[:soft_deleted]).to eq(1)
        expect(expired_file.reload.status).to eq('deleted')
        expect(active_file.reload.status).to eq('active')
      end

      it '永続ファイルはアーカイブされること' do
        # 期限を過去に設定して強制的に期限切れにする
        permanent_expired.update!(expires_at: 1.day.ago.to_date)

        # 永続ファイルを期限切れ対象に含めるため、retention_policyを一時的に変更
        permanent_expired.update!(retention_policy: 'standard')
        permanent_expired.update!(retention_policy: 'permanent') # 元に戻す

        result = subject

        expect(permanent_expired.reload.status).to eq('active') # 永続ファイルは削除されない
      end

      it 'クリーンアップ統計が正しく返されること' do
        result = subject

        expect(result).to have_key(:total_found)
        expect(result).to have_key(:archived)
        expect(result).to have_key(:soft_deleted)
        expect(result).to have_key(:hard_deleted)
        expect(result).to have_key(:errors)
        expect(result).to have_key(:freed_space)
      end
    end

    context 'dry_run: true の場合' do
      subject { described_class.cleanup_expired_files(dry_run: true) }

      it 'ファイルが実際には削除されないこと' do
        subject

        expect(expired_file.reload.status).to eq('active') # 変更されない
        expect(active_file.reload.status).to eq('active')
      end

      it 'DRY RUNログが出力されること' do
        expect(Rails.logger).to receive(:info).with(/DRY RUN - Would process/)
        subject
      end
    end
  end

  describe '.cleanup_unused_files' do
    let!(:unused_file) do
      create(:unused_report_file, :with_physical_file, admin: admin)
    end
    let!(:active_file) { create(:report_file, :with_physical_file, admin: admin) }

    context 'dry_run: false の場合' do
      subject { described_class.cleanup_unused_files(threshold_days: 90, dry_run: false) }

      it '未使用ファイルが削除されること' do
        result = subject

        expect(result[:total_found]).to eq(1)
        expect(result[:deleted]).to eq(1)
        expect(ReportFile.find_by(id: unused_file.id)).to be_nil
        expect(active_file.reload).to be_present
      end
    end

    context 'カスタム閾値の場合' do
      subject { described_class.cleanup_unused_files(threshold_days: 30, dry_run: true) }

      it '指定された閾値で判定されること' do
        expect(Rails.logger).to receive(:info).with(/threshold: 30 days/)
        subject
      end
    end
  end

  describe '.analyze_storage_usage' do
    before do
      create_list(:report_file, 3, admin: admin, file_size: 1000)
      create_list(:pdf_report_file, 2, admin: admin, file_size: 2000)
    end

    subject { described_class.analyze_storage_usage }

    it 'ストレージ統計が正しく計算されること' do
      result = subject

      expect(result[:total_files]).to eq(5)
      expect(result[:active_files]).to eq(5)
      expect(result[:total_size]).to eq(7000) # 3*1000 + 2*2000
      expect(result[:by_format]).to include('excel' => 3, 'pdf' => 2)
      expect(result[:average_size]).to eq(1400)
    end

    it '警告が適切に判定されること' do
      # 大容量ファイルを作成して警告をトリガー
      create(:large_report_file, admin: admin)

      result = subject
      expect(result[:warnings]).to be_an(Array)
    end
  end

  # ============================================================================
  # 正常系テスト - メンテナンス機能
  # ============================================================================

  describe '.verify_all_files_integrity' do
    let!(:valid_file) { create(:report_file, :with_physical_file, admin: admin) }
    let!(:corrupted_file) do
      file = create(:report_file, :with_physical_file, admin: admin)
      file.update!(file_hash: 'invalid_hash')
      file
    end
    let!(:missing_file) { create(:report_file, :without_physical_file, admin: admin) }

    subject { described_class.verify_all_files_integrity(repair: false) }

    it 'ファイル整合性チェックが正しく実行されること' do
      result = subject

      expect(result[:total_checked]).to eq(3)
      expect(result[:valid]).to eq(1)
      expect(result[:corrupted]).to eq(1)
      expect(result[:missing]).to eq(1)

      expect(corrupted_file.reload.status).to eq('corrupted')
      expect(missing_file.reload.status).to eq('corrupted')
      expect(valid_file.reload.status).to eq('active')
    end

    it '整合性チェックログが出力されること' do
      expect(Rails.logger).to receive(:info).with(/Starting integrity verification/)
      expect(Rails.logger).to receive(:info).with(/Integrity verification completed/)

      subject
    end
  end

  describe '.identify_and_merge_duplicates' do
    let(:file_hash) { 'duplicate_hash' }
    let!(:original_file) do
      create(:report_file, admin: admin, file_hash: file_hash, created_at: 1.hour.ago)
    end
    let!(:duplicate_file) do
      create(:report_file, admin: admin, file_hash: file_hash, created_at: 30.minutes.ago)
    end

    subject { described_class.identify_and_merge_duplicates }

    it '重複ファイルが特定・統合されること' do
      result = subject

      expect(result[:duplicate_groups]).to eq(1)
      expect(result[:files_merged]).to eq(1)
      expect(duplicate_file.reload.status).to eq('deleted')
      expect(original_file.reload.status).to eq('active')
    end
  end

  # ============================================================================
  # 異常系テスト - バリデーション
  # ============================================================================

  describe 'バリデーション' do
    context '存在しないファイルパスを指定した場合' do
      it 'ValidationErrorを発生させること' do
        expect {
          described_class.store_report_file(
            '/nonexistent/file.xlsx', report_type, file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::ValidationError, /ファイルが存在しません/)
      end
    end

    context '無効なレポート種別を指定した場合' do
      it 'ValidationErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, 'invalid_type', file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::ValidationError, /無効なレポート種別/)
      end
    end

    context '無効なファイル形式を指定した場合' do
      it 'ValidationErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, report_type, 'invalid_format', target_period, admin
          )
        }.to raise_error(ReportFileStorageService::ValidationError, /無効なファイル形式/)
      end
    end

    context '無効な日付を指定した場合' do
      it 'ValidationErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, report_type, file_format, '2024-01-01', admin
          )
        }.to raise_error(ReportFileStorageService::ValidationError, /レポート期間は日付である必要があります/)
      end
    end

    context '大容量ファイルを指定した場合' do
      before do
        # 26MBのファイルを作成
        File.write(temp_file_path, 'x' * 26.megabytes)
      end

      it 'ValidationErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, report_type, file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::ValidationError, /ファイルサイズが上限を超えています/)
      end
    end

    context '空ファイルを指定した場合' do
      before do
        File.write(temp_file_path, '')
      end

      it 'ValidationErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, report_type, file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::ValidationError, /空のファイルは保存できません/)
      end
    end
  end

  # ============================================================================
  # 異常系テスト - エラーハンドリング
  # ============================================================================

  describe 'エラーハンドリング' do
    context 'ファイル移動時にエラーが発生した場合' do
      before do
        allow(FileUtils).to receive(:mv).and_raise(StandardError.new("Permission denied"))
      end

      it 'StorageErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, report_type, file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::StorageError, /ファイル保存エラー/)
      end

      it 'エラー時にクリーンアップが実行されること' do
        expect(described_class).to receive(:cleanup_failed_storage).with(temp_file_path)

        expect {
          described_class.store_report_file(
            temp_file_path, report_type, file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::StorageError)
      end
    end

    context 'データベース保存時にエラーが発生した場合' do
      before do
        allow(ReportFile).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(ReportFile.new))
      end

      it 'StorageErrorを発生させること' do
        expect {
          described_class.store_report_file(
            temp_file_path, report_type, file_format, target_period, admin
          )
        }.to raise_error(ReportFileStorageService::StorageError)
      end
    end
  end

  # ============================================================================
  # パフォーマンステスト
  # ============================================================================

  describe 'パフォーマンス' do
    it 'ファイル保存が適切な時間内で完了すること' do
      start_time = Time.current
      described_class.store_report_file(
        temp_file_path, report_type, file_format, target_period, admin
      )
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 3.seconds
    end

    it '一括保存が適切な時間内で完了すること' do
      file_paths = { excel: temp_file_path, pdf: temp_pdf_path }

      start_time = Time.current
      described_class.store_multiple_files(file_paths, report_type, target_period, admin)
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 5.seconds
    end
  end

  # ============================================================================
  # 統合テスト
  # ============================================================================

  describe '統合テスト' do
    context '実際のレポート生成サービスとの統合' do
      let!(:inventories) { create_list(:inventory, 5) }
      let!(:batches) { inventories.map { |inv| create(:batch, inventory: inv) } }

      before do
        # 実際のレポート生成
        excel_generator = ReportExcelGenerator.new({
          target_date: target_period,
          inventory_summary: { total_items: 5 }
        })
        excel_generator.generate(temp_file_path)
      end

      it '実際に生成されたファイルが保存できること' do
        expect(File.exist?(temp_file_path)).to be true

        result = described_class.store_report_file(
          temp_file_path, report_type, file_format, target_period, admin
        )

        expect(result).to be_persisted
        expect(result.file_exists?).to be true
        expect(result.file_size).to be > 1000 # 実際のファイルサイズ
      end
    end
  end

  # ============================================================================
  # 横展開確認項目（メタ認知的チェックリスト）
  # ============================================================================

  # TODO: 🟢 Phase 3（推奨）- サービステストパターンの標準化
  # - 他のサービステストとの統一パターン
  # - ファイル操作テストの体系化
  # - エラーハンドリングテストの強化

  # TODO: 🟡 Phase 2（中）- セキュリティテストの追加
  # - ファイルパス改ざんテスト
  # - 権限チェックテスト
  # - アクセス制御テスト

  # TODO: 🟢 Phase 3（推奨）- 並行処理テスト
  # - 同時アクセステスト
  # - ファイルロックテスト
  # - デッドロック検知テスト
end
