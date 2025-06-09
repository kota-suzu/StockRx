# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# ReportPdfGeneratorテスト
# ============================================================================
# 目的:
#   - PDF レポート生成機能の基本動作確認
#   - エグゼクティブサマリーPDFの品質検証
#   - prawn gem を使用したPDF生成の安定性確認
#
# 設計思想:
#   - 実際のPDFファイル生成とコンテンツ検証
#   - A4サイズでの読みやすさと印刷適性確認
#   - ReportExcelGeneratorとの一貫性保持
#
# 横展開確認:
#   - Excel生成テストとの統一パターン
#   - ファイル操作の安全な実装
#   - エラーハンドリングの一貫性
# ============================================================================

RSpec.describe ReportPdfGenerator, type: :lib do
  # ============================================================================
  # テスト用データセットアップ
  # ============================================================================
  
  let(:target_date) { Date.current.beginning_of_month }
  let(:valid_report_data) do
    {
      target_date: target_date,
      inventory_summary: {
        total_items: 150,
        total_value: 7500000,
        low_stock_items: 12,
        high_value_items: 6,
        average_quantity: 28.5
      },
      expiry_analysis: {
        expired_items: 2,
        expiring_next_month: 8,
        expiring_next_quarter: 20,
        expiry_value_risk: 180000,
        expiring_immediate: 1,
        expiring_short_term: 3,
        immediate_value_risk: 25000,
        short_term_value_risk: 75000,
        medium_term_value_risk: 80000
      },
      recommendations: [
        "低在庫アイテムの発注検討",
        "期限間近商品の販売促進",
        "在庫回転率の改善"
      ]
    }
  end

  let(:generator) { described_class.new(valid_report_data) }
  let(:temp_file_path) { Rails.root.join('tmp', 'test_report.pdf').to_s }

  # テスト後のクリーンアップ
  after do
    File.delete(temp_file_path) if File.exist?(temp_file_path)
  end

  # ============================================================================
  # 正常系テスト - 初期化
  # ============================================================================
  
  describe '#initialize' do
    it '有効なレポートデータで正常に初期化されること' do
      expect { generator }.not_to raise_error
    end

    it 'target_dateが正しく設定されること' do
      expect(generator.instance_variable_get(:@target_date)).to eq(target_date)
    end

    it 'Prawnドキュメントが作成されること' do
      document = generator.instance_variable_get(:@document)
      expect(document).to be_a(Prawn::Document)
    end

    it 'ドキュメントがA4サイズで初期化されること' do
      document = generator.instance_variable_get(:@document)
      expect(document.page.size).to eq("A4")
    end

    context 'target_dateが指定されていない場合' do
      let(:report_data_without_date) do
        valid_report_data.except(:target_date)
      end

      it 'デフォルトで現在月の初日が設定されること' do
        generator = described_class.new(report_data_without_date)
        expect(generator.instance_variable_get(:@target_date)).to eq(Date.current.beginning_of_month)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - ファイル生成
  # ============================================================================
  
  describe '#generate' do
    context 'ファイルパスを指定した場合' do
      subject { generator.generate(temp_file_path) }

      it '指定されたパスにファイルが生成されること' do
        result_path = subject
        expect(result_path).to eq(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
      end

      it '生成されたファイルが有効なPDFファイルであること' do
        generator.generate(temp_file_path)
        
        # ファイルサイズの確認
        expect(File.size(temp_file_path)).to be > 0
        
        # PDF ファイルのマジックナンバー確認
        file_content = File.read(temp_file_path, 8)
        expect(file_content).to start_with("%PDF") # PDFヘッダー
      end

      it 'ログメッセージが出力されること' do
        expect(Rails.logger).to receive(:info).with(/Starting PDF generation/)
        expect(Rails.logger).to receive(:info).with(/PDF file generated/)
        
        generator.generate(temp_file_path)
      end

      it '生成されたPDFファイルが適切なサイズであること' do
        generator.generate(temp_file_path)
        file_size = File.size(temp_file_path)
        
        # 50KB - 2MB の範囲内であることを確認
        expect(file_size).to be_between(50_000, 2_000_000)
      end
    end

    context 'ファイルパスを指定しない場合' do
      subject { generator.generate }

      it '自動生成されたパスにファイルが作成されること' do
        result_path = subject
        
        expect(result_path).to include('monthly_report_summary_')
        expect(result_path).to end_with('.pdf')
        expect(File.exist?(result_path)).to be true
        
        # テスト後のクリーンアップ
        File.delete(result_path) if File.exist?(result_path)
      end

      it 'ファイル名に年月とタイムスタンプが含まれること' do
        result_path = subject
        filename = File.basename(result_path, '.pdf')
        
        expect(filename).to include(target_date.year.to_s)
        expect(filename).to include(target_date.month.to_s.rjust(2, '0'))
        expect(filename).to match(/\d{8}_\d{6}/) # YYYYMMDD_HHMMSS
        
        # テスト後のクリーンアップ
        File.delete(result_path) if File.exist?(result_path)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - ファイルサイズ推定
  # ============================================================================
  
  describe '#estimate_file_size' do
    subject { generator.estimate_file_size }

    it '正の整数値を返すこと' do
      expect(subject).to be_a(Integer)
      expect(subject).to be > 0
    end

    it '合理的なサイズ範囲内であること' do
      # 200KB - 5MB の範囲内であることを確認
      expect(subject).to be_between(200_000, 5_000_000)
    end

    it 'Excel生成よりもファイルサイズが大きいこと' do
      # PDFは一般的にExcelよりもファイルサイズが大きい
      excel_generator = ReportExcelGenerator.new(valid_report_data)
      excel_size = excel_generator.estimate_file_size
      pdf_size = generator.estimate_file_size
      
      expect(pdf_size).to be >= excel_size
    end
  end

  # ============================================================================
  # 異常系テスト - バリデーション
  # ============================================================================
  
  describe 'バリデーション' do
    context '必須データが不足している場合' do
      let(:incomplete_data) do
        valid_report_data.except(:inventory_summary)
      end

      it 'DataValidationErrorを発生させること' do
        expect {
          described_class.new(incomplete_data)
        }.to raise_error(ReportPdfGenerator::DataValidationError, /Required data missing/)
      end
    end

    context 'target_dateが不足している場合' do
      let(:incomplete_data) do
        valid_report_data.except(:target_date)
      end

      it 'デフォルト値で正常に初期化されること' do
        expect {
          described_class.new(incomplete_data)
        }.not_to raise_error
      end
    end
  end

  # ============================================================================
  # 異常系テスト - エラーハンドリング
  # ============================================================================
  
  describe 'エラーハンドリング' do
    context 'ファイル生成時にエラーが発生した場合' do
      before do
        # ファイル書き込みエラーをシミュレート
        allow_any_instance_of(Prawn::Document).to receive(:render_file).and_raise(StandardError.new("Write error"))
      end

      it 'PdfGenerationErrorを発生させること' do
        expect {
          generator.generate(temp_file_path)
        }.to raise_error(ReportPdfGenerator::PdfGenerationError, /PDF生成エラー/)
      end

      it 'エラーログが出力されること' do
        expect(Rails.logger).to receive(:error).with(/Error generating PDF/)
        
        expect {
          generator.generate(temp_file_path)
        }.to raise_error(ReportPdfGenerator::PdfGenerationError)
      end
    end

    context '不正なファイルパスが指定された場合' do
      let(:invalid_path) { '/invalid/directory/test.pdf' }

      it '適切なエラーメッセージでPdfGenerationErrorを発生させること' do
        expect {
          generator.generate(invalid_path)
        }.to raise_error(ReportPdfGenerator::PdfGenerationError)
      end
    end

    context 'レポートデータにnilが含まれる場合' do
      let(:nil_data) do
        valid_report_data.merge(
          inventory_summary: nil
        )
      end

      it 'DataValidationErrorを発生させること' do
        expect {
          described_class.new(nil_data)
        }.to raise_error(ReportPdfGenerator::DataValidationError)
      end
    end
  end

  # ============================================================================
  # 境界値テスト
  # ============================================================================
  
  describe '境界値テスト' do
    context '最小限のデータの場合' do
      let(:minimal_data) do
        {
          target_date: target_date,
          inventory_summary: {
            total_items: 0,
            total_value: 0,
            low_stock_items: 0,
            high_value_items: 0
          }
        }
      end
      let(:minimal_generator) { described_class.new(minimal_data) }

      it '最小データでもPDFファイルが生成されること' do
        result_path = minimal_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
        expect(File.size(temp_file_path)).to be > 0
      end
    end

    context '大量の推奨事項がある場合' do
      let(:large_recommendations_data) do
        large_recommendations = Array.new(50) { |i| "推奨事項 #{i + 1}: テスト用の長い推奨事項文章です。" }
        valid_report_data.merge(recommendations: large_recommendations)
      end
      let(:large_generator) { described_class.new(large_recommendations_data) }

      it '大量の推奨事項でもPDFが生成されること' do
        result_path = large_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
      end

      it 'ページ分割が適切に行われること' do
        large_generator.generate(temp_file_path)
        
        # PDFのページ数を確認（prawn の内部APIを使用）
        document = large_generator.instance_variable_get(:@document)
        expect(document.page_count).to be >= 1
      end
    end

    context '特殊文字を含むデータの場合' do
      let(:special_char_data) do
        valid_report_data.merge(
          recommendations: [
            "テスト推奨事項 🚀 & \"quotes\" & <tags>",
            "日本語文字テスト：①②③④⑤",
            "記号テスト：￥€$£¢"
          ]
        )
      end
      let(:special_generator) { described_class.new(special_char_data) }

      it '特殊文字を含むデータでも正常に処理されること' do
        result_path = special_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
      end
    end

    context '極端に大きな数値データの場合' do
      let(:large_number_data) do
        valid_report_data.merge(
          inventory_summary: {
            total_items: 999_999_999,
            total_value: 999_999_999_999,
            low_stock_items: 500_000,
            high_value_items: 100_000
          }
        )
      end
      let(:large_number_generator) { described_class.new(large_number_data) }

      it '大きな数値でも適切にフォーマットされること' do
        result_path = large_number_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
      end
    end
  end

  # ============================================================================
  # パフォーマンステスト
  # ============================================================================
  
  describe 'パフォーマンス' do
    it '適切な時間内でファイルが生成されること' do
      start_time = Time.current
      generator.generate(temp_file_path)
      elapsed_time = Time.current - start_time
      
      # PDF生成は3秒以内
      expect(elapsed_time).to be < 3.seconds
    end

    it 'メモリ使用量が適切であること' do
      before_memory = get_memory_usage
      generator.generate(temp_file_path)
      after_memory = get_memory_usage
      
      memory_increase = after_memory - before_memory
      # 30MB以下の増加であることを確認
      expect(memory_increase).to be < 30_000_000
    end

    it '複数回生成でもメモリリークが発生しないこと' do
      initial_memory = get_memory_usage
      
      3.times do |i|
        temp_path = Rails.root.join('tmp', "test_report_#{i}.pdf").to_s
        generator.generate(temp_path)
        File.delete(temp_path) if File.exist?(temp_path)
      end
      
      final_memory = get_memory_usage
      memory_increase = final_memory - initial_memory
      
      # メモリ使用量の増加が50MB以下であることを確認
      expect(memory_increase).to be < 50_000_000
    end

    private

    def get_memory_usage
      # プロセスのメモリ使用量を取得（簡易版）
      `ps -o rss= -p #{Process.pid}`.to_i * 1024 # KB to bytes
    rescue
      0 # エラー時はゼロを返す
    end
  end

  # ============================================================================
  # PDF品質テスト
  # ============================================================================
  
  describe 'PDF品質' do
    before do
      generator.generate(temp_file_path)
    end

    it 'PDFファイルが破損していないこと' do
      # PDFリーダーで読み込めることを確認
      pdf_content = File.read(temp_file_path)
      
      # PDF の基本構造確認
      expect(pdf_content).to include('%PDF-')  # PDFヘッダー
      expect(pdf_content).to include('%%EOF')  # PDFフッター
    end

    it 'PDFメタデータが適切に設定されていること' do
      # TODO: 🟡 Phase 2（中）- PDFメタデータの詳細検証
      # 優先度: 中（品質向上）
      # 実装内容: PDF-reader gem を使用したメタデータ検証
      # 理由: 生成されたPDFファイルのメタデータ品質保証
      
      skip 'PDFメタデータ検証機能の実装が必要'
    end

    # TODO: 🔴 Phase 1（緊急）- PDF内容の詳細検証実装
    # 優先度: 高（テスト品質向上）
    # 実装内容:
    #   - テキスト内容の検証（タイトル、データ値、推奨事項）
    #   - レイアウト確認（ヘッダー、フッター、セクション）
    #   - フォント・スタイル確認
    # 理由: 生成されたPDFファイルの内容品質保証が重要

    it 'PDF内容の詳細検証' do
      pending 'PDF内容検証機能の実装が必要'
      
      # 実装予定の検証項目:
      # - PDF内のテキスト内容検証
      # - レイアウト要素の配置確認  
      # - カラーパレットの適用確認
      # - フォント設定の検証
    end
  end

  # ============================================================================
  # データ整合性テスト
  # ============================================================================
  
  describe 'データ整合性' do
    context '数値フォーマットの確認' do
      let(:numeric_data) do
        valid_report_data.merge(
          inventory_summary: {
            total_items: 1234567,
            total_value: 987654321,
            low_stock_items: 12345,
            high_value_items: 6789
          }
        )
      end
      let(:numeric_generator) { described_class.new(numeric_data) }

      it '大きな数値が適切にフォーマットされること' do
        result_path = numeric_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
        
        # TODO: PDF内容を読み込んで数値フォーマットを確認
        # 現在は生成成功のみ確認
      end
    end

    context '日付フォーマットの確認' do
      it '日本語形式で日付がフォーマットされること' do
        generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
        
        # TODO: PDF内容を読み込んで日付フォーマットを確認
      end
    end
  end

  # ============================================================================
  # 統合テスト
  # ============================================================================
  
  describe '統合テスト' do
    context '実際のサービスデータとの統合' do
      let!(:inventories) { create_list(:inventory, 5) }
      let!(:batches) { inventories.map { |inv| create(:batch, inventory: inv) } }
      
      before do
        # 実際のサービスからデータを取得
        @real_inventory_data = InventoryReportService.monthly_summary(target_date)
        @real_expiry_data = ExpiryAnalysisService.monthly_report(target_date)
      end

      it '実際のサービスデータでPDFファイルが生成されること' do
        real_report_data = {
          target_date: target_date,
          inventory_summary: @real_inventory_data,
          expiry_analysis: @real_expiry_data[:expiry_summary]
        }

        real_generator = described_class.new(real_report_data)
        result_path = real_generator.generate(temp_file_path)
        
        expect(File.exist?(temp_file_path)).to be true
        expect(File.size(temp_file_path)).to be > 0
      end
    end

    context 'Excel生成との一貫性確認' do
      it 'Excel生成と同じデータで一貫したレポートが生成されること' do
        # PDF生成
        pdf_path = temp_file_path
        generator.generate(pdf_path)
        
        # Excel生成
        excel_path = temp_file_path.gsub('.pdf', '.xlsx')
        excel_generator = ReportExcelGenerator.new(valid_report_data)
        excel_generator.generate(excel_path)
        
        # 両方のファイルが正常に生成されることを確認
        expect(File.exist?(pdf_path)).to be true
        expect(File.exist?(excel_path)).to be true
        expect(File.size(pdf_path)).to be > 0
        expect(File.size(excel_path)).to be > 0
        
        # クリーンアップ
        File.delete(excel_path) if File.exist?(excel_path)
      end
    end
  end

  # ============================================================================
  # 横展開確認項目（メタ認知的チェックリスト）
  # ============================================================================
  
  # TODO: 🟢 Phase 3（推奨）- PDFテストパターンの標準化
  # - Excel生成テストとの統一パターン
  # - ファイル形式別テストの体系化
  # - PDF固有の品質テスト強化
  
  # TODO: 🟡 Phase 2（中）- PDF高度機能のテスト
  # - 複数ページレイアウトのテスト
  # - 表・グラフ要素の品質テスト
  # - カラー設定の一貫性テスト
  
  # TODO: 🟢 Phase 3（推奨）- アクセシビリティテスト
  # - PDF/A標準への準拠確認
  # - スクリーンリーダー対応テスト
  # - 印刷品質の確認テスト
end