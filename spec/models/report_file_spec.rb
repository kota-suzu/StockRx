# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# ReportFileモデルテスト
# ============================================================================
# 目的:
#   - レポートファイルモデルの基本機能テスト
#   - バリデーション・スコープ・メソッドの検証
#   - ファイル管理機能の安全性確認
#
# 設計思想:
#   - ファイル操作の安全性確保
#   - データ整合性の検証
#   - 保持期間ポリシーの正確性確認
#
# 横展開確認:
#   - 他のモデルテストとの統一パターン
#   - ファイル関連テストの体系化
#   - セキュリティテストの強化
# ============================================================================

RSpec.describe ReportFile, type: :model do
  # ============================================================================
  # テスト用データセットアップ
  # ============================================================================

  let(:admin) { create(:admin) }
  let(:target_period) { Date.current.beginning_of_month }

  # ============================================================================
  # 正常系テスト - バリデーション
  # ============================================================================

  describe 'バリデーション' do
    subject { build(:report_file, admin: admin) }

    it '有効なファクトリデータでバリデーションが通ること' do
      expect(subject).to be_valid
    end

    describe '必須フィールド' do
      it 'report_typeが必須であること' do
        subject.report_type = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:report_type]).to include("can't be blank")
      end

      it 'file_formatが必須であること' do
        subject.file_format = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:file_format]).to include("can't be blank")
      end

      it 'report_periodが必須であること' do
        subject.report_period = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:report_period]).to include("can't be blank")
      end

      it 'file_nameが必須であること' do
        subject.file_name = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:file_name]).to include("can't be blank")
      end

      it 'file_pathが必須であること' do
        subject.file_path = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:file_path]).to include("can't be blank")
      end

      it 'generated_atが必須であること' do
        subject.generated_at = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:generated_at]).to include("can't be blank")
      end
    end

    describe '列挙型バリデーション' do
      it '有効なreport_typeのみ受け入れること' do
        ReportFile::REPORT_TYPES.each do |type|
          subject.report_type = type
          expect(subject).to be_valid
        end

        subject.report_type = 'invalid_type'
        expect(subject).not_to be_valid
        expect(subject.errors[:report_type]).to include('is not included in the list')
      end

      it '有効なfile_formatのみ受け入れること' do
        ReportFile::FILE_FORMATS.each do |format|
          subject.file_format = format
          expect(subject).to be_valid
        end

        subject.file_format = 'invalid_format'
        expect(subject).not_to be_valid
        expect(subject.errors[:file_format]).to include('is not included in the list')
      end

      it '有効なstorage_typeのみ受け入れること' do
        ReportFile::STORAGE_TYPES.each do |type|
          subject.storage_type = type
          expect(subject).to be_valid
        end

        subject.storage_type = 'invalid_storage'
        expect(subject).not_to be_valid
        expect(subject.errors[:storage_type]).to include('is not included in the list')
      end
    end

    describe '文字数制限' do
      it 'file_nameが255文字以内であること' do
        subject.file_name = 'a' * 255
        expect(subject).to be_valid

        subject.file_name = 'a' * 256
        expect(subject).not_to be_valid
        expect(subject.errors[:file_name]).to include('is too long (maximum is 255 characters)')
      end

      it 'file_pathが500文字以内であること' do
        subject.file_path = 'a' * 500
        expect(subject).to be_valid

        subject.file_path = 'a' * 501
        expect(subject).not_to be_valid
        expect(subject.errors[:file_path]).to include('is too long (maximum is 500 characters)')
      end
    end

    describe '数値バリデーション' do
      it 'file_sizeが正の数であること' do
        subject.file_size = 1000
        expect(subject).to be_valid

        subject.file_size = 0
        expect(subject).not_to be_valid
        expect(subject.errors[:file_size]).to include('must be greater than 0')

        subject.file_size = -1
        expect(subject).not_to be_valid
      end

      it 'download_countが0以上であること' do
        subject.download_count = 0
        expect(subject).to be_valid

        subject.download_count = 10
        expect(subject).to be_valid

        subject.download_count = -1
        expect(subject).not_to be_valid
        expect(subject.errors[:download_count]).to include('must be greater than or equal to 0')
      end
    end
  end

  # ============================================================================
  # 正常系テスト - カスタムバリデーション
  # ============================================================================

  describe 'カスタムバリデーション' do
    subject { build(:report_file, admin: admin) }

    describe '日付整合性バリデーション' do
      it 'expires_atがgenerated_atより後の日付であること' do
        subject.generated_at = Time.current
        subject.expires_at = Date.current + 1.day
        expect(subject).to be_valid

        subject.expires_at = Date.current - 1.day
        expect(subject).not_to be_valid
        expect(subject.errors[:expires_at]).to include('は生成日時より後の日付である必要があります')
      end
    end

    describe 'ファイルパス形式バリデーション' do
      it '不正なパス表記を拒否すること' do
        subject.file_path = '/path/../dangerous/file.xlsx'
        expect(subject).not_to be_valid
        expect(subject.errors[:file_path]).to include('に不正なパス表記が含まれています')
      end

      it 'ファイル形式に対応する拡張子を要求すること' do
        subject.file_format = 'excel'
        subject.file_path = '/path/to/file.xlsx'
        expect(subject).to be_valid

        subject.file_path = '/path/to/file.pdf'
        expect(subject).not_to be_valid
        expect(subject.errors[:file_path]).to include('はファイル形式(excel)に対応する拡張子である必要があります')
      end
    end

    describe '保持ポリシー整合性バリデーション' do
      it '永続保持ポリシーではexpires_atがnilであること' do
        subject.retention_policy = 'permanent'
        subject.expires_at = nil
        expect(subject).to be_valid

        subject.expires_at = Date.current + 1.year
        expect(subject).not_to be_valid
        expect(subject.errors[:expires_at]).to include('は永続保持ポリシーでは設定できません')
      end

      it '非永続保持ポリシーではexpires_atが必須であること' do
        subject.retention_policy = 'standard'
        subject.expires_at = Date.current + 90.days
        expect(subject).to be_valid

        subject.expires_at = nil
        expect(subject).not_to be_valid
        expect(subject.errors[:expires_at]).to include('は非永続保持ポリシーでは必須です')
      end
    end
  end

  # ============================================================================
  # 正常系テスト - ユニーク制約
  # ============================================================================

  describe 'ユニーク制約' do
    let!(:existing_file) do
      create(:report_file,
             admin: admin,
             report_type: 'monthly_summary',
             file_format: 'excel',
             report_period: target_period,
             status: 'active')
    end

    it '同一期間・タイプ・フォーマットのアクティブファイルは重複不可' do
      duplicate_file = build(:report_file,
                            admin: admin,
                            report_type: 'monthly_summary',
                            file_format: 'excel',
                            report_period: target_period,
                            status: 'active')

      expect(duplicate_file).not_to be_valid
      expect(duplicate_file.errors[:report_type]).to include('同一期間・フォーマットのアクティブレポートが既に存在します')
    end

    it 'アーカイブ済みファイルとの重複は許可' do
      existing_file.update!(status: 'archived')

      duplicate_file = build(:report_file,
                            admin: admin,
                            report_type: 'monthly_summary',
                            file_format: 'excel',
                            report_period: target_period,
                            status: 'active')

      expect(duplicate_file).to be_valid
    end

    it '異なるフォーマットなら同一期間でも作成可能' do
      pdf_file = build(:report_file,
                      admin: admin,
                      report_type: 'monthly_summary',
                      file_format: 'pdf',
                      report_period: target_period,
                      status: 'active')

      expect(pdf_file).to be_valid
    end
  end

  # ============================================================================
  # 正常系テスト - アソシエーション
  # ============================================================================

  describe 'アソシエーション' do
    it 'adminに属すること' do
      report_file = create(:report_file, admin: admin)
      expect(report_file.admin).to eq(admin)
    end

    it 'adminが削除されるとreport_fileも削除されること' do
      report_file = create(:report_file, admin: admin)
      expect { admin.destroy }.to change(ReportFile, :count).by(-1)
    end
  end

  # ============================================================================
  # 正常系テスト - スコープ
  # ============================================================================

  describe 'スコープ' do
    let!(:active_file) { create(:report_file, admin: admin, status: 'active') }
    let!(:archived_file) { create(:archived_report_file, admin: admin) }
    let!(:deleted_file) { create(:deleted_report_file, admin: admin) }
    let!(:expired_file) { create(:expired_report_file, admin: admin) }

    describe '基本スコープ' do
      it 'activeスコープが正しく動作すること' do
        expect(ReportFile.active).to include(active_file)
        expect(ReportFile.active).not_to include(archived_file, deleted_file)
      end

      it 'archivedスコープが正しく動作すること' do
        expect(ReportFile.archived).to include(archived_file)
        expect(ReportFile.archived).not_to include(active_file, deleted_file)
      end

      it 'deletedスコープが正しく動作すること' do
        expect(ReportFile.deleted).to include(deleted_file)
        expect(ReportFile.deleted).not_to include(active_file, archived_file)
      end
    end

    describe '検索スコープ' do
      it 'by_typeスコープが正しく動作すること' do
        monthly_file = create(:report_file, admin: admin, report_type: 'monthly_summary')
        analysis_file = create(:report_file, admin: admin, report_type: 'inventory_analysis')

        expect(ReportFile.by_type('monthly_summary')).to include(monthly_file)
        expect(ReportFile.by_type('monthly_summary')).not_to include(analysis_file)
      end

      it 'by_formatスコープが正しく動作すること' do
        excel_file = create(:report_file, admin: admin, file_format: 'excel')
        pdf_file = create(:pdf_report_file, admin: admin)

        expect(ReportFile.by_format('excel')).to include(excel_file)
        expect(ReportFile.by_format('excel')).not_to include(pdf_file)
      end
    end

    describe '保持期限スコープ' do
      it 'expiredスコープが期限切れファイルを返すこと' do
        expect(ReportFile.expired).to include(expired_file)
        expect(ReportFile.expired).not_to include(active_file)
      end

      it 'expiring_soonスコープが期限間近ファイルを返すこと' do
        expiring_file = create(:expiring_soon_report_file, admin: admin)
        expect(ReportFile.expiring_soon).to include(expiring_file)
        expect(ReportFile.expiring_soon).not_to include(active_file)
      end
    end

    describe 'アクセス統計スコープ' do
      let!(:frequent_file) { create(:frequently_accessed_report_file, admin: admin) }
      let!(:unused_file) { create(:unused_report_file, admin: admin) }

      it 'frequently_accessedスコープが正しく動作すること' do
        expect(ReportFile.frequently_accessed).to include(frequent_file)
        expect(ReportFile.frequently_accessed).not_to include(unused_file)
      end

      it 'never_accessedスコープが正しく動作すること' do
        expect(ReportFile.never_accessed).to include(unused_file)
        expect(ReportFile.never_accessed).not_to include(frequent_file)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - インスタンスメソッド
  # ============================================================================

  describe 'インスタンスメソッド' do
    subject { create(:report_file, :with_physical_file, admin: admin) }

    describe 'ファイル存在確認' do
      it 'file_exists?が物理ファイルの存在を正しく判定すること' do
        expect(subject.file_exists?).to be true

        File.delete(subject.file_path)
        expect(subject.file_exists?).to be false
      end
    end

    describe 'ファイルサイズ取得' do
      it 'actual_file_sizeが実際のファイルサイズを返すこと' do
        actual_size = File.size(subject.file_path)
        expect(subject.actual_file_size).to eq(actual_size)
      end
    end

    describe 'アクセス記録' do
      it 'record_access!でアクセス統計が更新されること' do
        initial_count = subject.download_count
        subject.record_access!

        expect(subject.reload.download_count).to eq(initial_count + 1)
        expect(subject.last_accessed_at).to be_within(1.second).of(Time.current)
      end

      it 'record_delivery!で配信統計が更新されること' do
        initial_count = subject.email_delivery_count
        subject.record_delivery!

        expect(subject.reload.email_delivery_count).to eq(initial_count + 1)
        expect(subject.last_delivered_at).to be_within(1.second).of(Time.current)
      end
    end

    describe 'ステータス変更' do
      it 'archive!でアーカイブ状態に変更されること' do
        expect(subject.archive!).to be true
        expect(subject.reload.status).to eq('archived')
        expect(subject.archived_at).to be_within(1.second).of(Time.current)
      end

      it 'soft_delete!で削除状態に変更されること' do
        expect(subject.soft_delete!).to be true
        expect(subject.reload.status).to eq('deleted')
        expect(subject.deleted_at).to be_within(1.second).of(Time.current)
      end

      it 'hard_delete!で物理ファイルとレコードが削除されること' do
        file_path = subject.file_path
        subject_id = subject.id

        expect(File.exist?(file_path)).to be true
        expect(subject.hard_delete!).to be true
        expect(File.exist?(file_path)).to be false
        expect(ReportFile.find_by(id: subject_id)).to be_nil
      end
    end

    describe '保持期限延長' do
      it 'extend_retention!で保持期限が延長されること' do
        original_expires_at = subject.expires_at
        subject.extend_retention!('extended')

        expect(subject.reload.retention_policy).to eq('extended')
        expect(subject.expires_at).to be > original_expires_at
      end
    end
  end

  # ============================================================================
  # 正常系テスト - 状態確認メソッド
  # ============================================================================

  describe '状態確認メソッド' do
    it '各ステータスメソッドが正しく動作すること' do
      active_file = create(:report_file, admin: admin, status: 'active')
      archived_file = create(:archived_report_file, admin: admin)
      deleted_file = create(:deleted_report_file, admin: admin)

      expect(active_file.active?).to be true
      expect(active_file.archived?).to be false
      expect(active_file.deleted?).to be false

      expect(archived_file.active?).to be false
      expect(archived_file.archived?).to be true
      expect(archived_file.deleted?).to be false

      expect(deleted_file.active?).to be false
      expect(deleted_file.archived?).to be false
      expect(deleted_file.deleted?).to be true
    end

    it '期限関連メソッドが正しく動作すること' do
      expired_file = create(:expired_report_file, admin: admin)
      expiring_file = create(:expiring_soon_report_file, admin: admin)
      permanent_file = create(:permanent_report_file, admin: admin)

      expect(expired_file.expired?).to be true
      expect(expired_file.expiring_soon?).to be false

      expect(expiring_file.expired?).to be false
      expect(expiring_file.expiring_soon?).to be true

      expect(permanent_file.permanent?).to be true
      expect(permanent_file.expired?).to be false
    end
  end

  # ============================================================================
  # 正常系テスト - フォーマット・表示メソッド
  # ============================================================================

  describe 'フォーマット・表示メソッド' do
    subject { create(:report_file, admin: admin, file_size: 1024 * 1024) } # 1MB

    it 'formatted_file_sizeが人間読みやすい形式で返されること' do
      expect(subject.formatted_file_size).to eq('1.0 MB')
    end

    it 'display_nameが適切な形式で返されること' do
      expected_name = "#{subject.report_type.humanize} - #{subject.report_period.strftime('%Y年%m月')} (#{subject.file_format.upcase})"
      expect(subject.display_name).to eq(expected_name)
    end

    it 'short_file_hashがハッシュの先頭8文字を返すこと' do
      subject.file_hash = 'abcdef1234567890'
      expect(subject.short_file_hash).to eq('abcdef12')
    end
  end

  # ============================================================================
  # 正常系テスト - クラスメソッド
  # ============================================================================

  describe 'クラスメソッド' do
    describe '.cleanup_expired_files' do
      let!(:expired_file) { create(:expired_report_file, admin: admin, status: 'active') }
      let!(:active_file) { create(:report_file, admin: admin, status: 'active') }

      it '期限切れファイルが適切にクリーンアップされること' do
        cleaned_count = ReportFile.cleanup_expired_files
        expect(cleaned_count).to eq(1)
        expect(expired_file.reload.status).to eq('deleted')
        expect(active_file.reload.status).to eq('active')
      end
    end

    describe '.storage_statistics' do
      before do
        create_list(:report_file, 3, admin: admin, file_size: 1000)
        create_list(:pdf_report_file, 2, admin: admin, file_size: 2000)
      end

      it 'ストレージ統計が正しく計算されること' do
        stats = ReportFile.storage_statistics

        expect(stats[:total_files]).to eq(5)
        expect(stats[:total_size]).to eq(7000) # 3*1000 + 2*2000
        expect(stats[:by_format]['excel']).to eq(3)
        expect(stats[:by_format]['pdf']).to eq(2)
        expect(stats[:average_size]).to eq(1400) # 7000/5
      end
    end

    describe '.find_report' do
      let!(:target_file) do
        create(:report_file,
               admin: admin,
               report_type: 'monthly_summary',
               file_format: 'excel',
               report_period: target_period,
               status: 'active')
      end

      it '指定された条件のレポートファイルが取得できること' do
        found_file = ReportFile.find_report('monthly_summary', 'excel', target_period)
        expect(found_file).to eq(target_file)
      end

      it '条件に一致しないファイルはnilを返すこと' do
        found_file = ReportFile.find_report('monthly_summary', 'pdf', target_period)
        expect(found_file).to be_nil
      end
    end
  end

  # ============================================================================
  # 境界値・エラーケーステスト
  # ============================================================================

  describe '境界値・エラーケース' do
    it 'ファイルサイズ0でバリデーションエラーになること' do
      file = build(:report_file, admin: admin, file_size: 0)
      expect(file).not_to be_valid
    end

    it '空文字フィールドでバリデーションエラーになること' do
      file = build(:report_file, admin: admin, file_name: '')
      expect(file).not_to be_valid
    end

    it 'nilのfile_hashでも正常に動作すること' do
      file = create(:report_file, admin: admin, file_hash: nil)
      expect(file.short_file_hash).to eq('N/A')
    end
  end

  # ============================================================================
  # コールバックテスト
  # ============================================================================

  describe 'コールバック' do
    it 'before_validationでデフォルト値が設定されること' do
      file = ReportFile.new(
        admin: admin,
        report_type: 'monthly_summary',
        file_format: 'excel',
        report_period: target_period,
        file_name: 'test.xlsx',
        file_path: '/tmp/test.xlsx'
      )
      file.valid?

      expect(file.status).to eq('active')
      expect(file.retention_policy).to eq('standard')
      expect(file.checksum_algorithm).to eq('sha256')
      expect(file.storage_type).to eq('local')
      expect(file.generated_at).to be_present
    end
  end

  # ============================================================================
  # 横展開確認項目（メタ認知的チェックリスト）
  # ============================================================================

  # TODO: 🟢 Phase 3（推奨）- モデルテストパターンの標準化
  # - 他のモデルテストとの統一パターン
  # - ファイル関連モデルテストの体系化
  # - バリデーションテストの強化

  # TODO: 🟡 Phase 2（中）- ファイル操作セキュリティテスト
  # - ファイルパス検証テストの強化
  # - 権限チェックテストの実装
  # - ファイル改ざん検知テストの追加

  # TODO: 🟢 Phase 3（推奨）- パフォーマンステスト
  # - 大量ファイルでのスコープ性能テスト
  # - ファイルハッシュ計算性能テスト
  # - 一括操作の性能テスト
end
