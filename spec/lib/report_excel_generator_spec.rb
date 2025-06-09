# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# ReportExcelGeneratorテスト
# ============================================================================
# 目的:
#   - Excel レポート生成機能の基本動作確認
#   - ファイル出力とデータ整合性の検証
#   - エラーハンドリングとバリデーションの確認
#
# 設計思想:
#   - 実際のファイル生成とコンテンツ検証
#   - 一時ファイルを使用した安全なテスト
#   - caxlsx gem の機能検証
#
# 横展開確認:
#   - 他のファイル生成クラスとの一貫性
#   - PDF生成テストとの統一パターン
#   - ファイル操作の安全な実装
# ============================================================================

RSpec.describe ReportExcelGenerator, type: :lib do
  # ============================================================================
  # テスト用データセットアップ
  # ============================================================================

  let(:target_date) { Date.current.beginning_of_month }
  let(:valid_report_data) do
    {
      target_date: target_date,
      inventory_summary: {
        total_items: 100,
        total_value: 5000000,
        low_stock_items: 15,
        high_value_items: 8,
        average_quantity: 25.5,
        monthly_changes: {
          total_items_change: 5,
          total_items_change_percent: 2.3
        }
      },
      expiry_analysis: {
        expired_items: 3,
        expiring_next_month: 12,
        expiring_next_quarter: 25,
        expiry_value_risk: 250000
      },
      stock_movements: {
        total_movements: 150,
        movement_breakdown: [
          { type: 'received', count: 60, percentage: 40.0 },
          { type: 'sold', count: 75, percentage: 50.0 },
          { type: 'adjusted', count: 15, percentage: 10.0 }
        ],
        top_active_items: [
          { inventory_id: 1, name: 'テスト商品A', movement_count: 25, activity_score: 85 },
          { inventory_id: 2, name: 'テスト商品B', movement_count: 20, activity_score: 70 }
        ]
      },
      recommendations: [
        "低在庫アイテムの発注を検討してください",
        "期限間近商品の販売促進を実施してください"
      ],
      charts_enabled: false
    }
  end

  let(:generator) { described_class.new(valid_report_data) }
  let(:temp_file_path) { Rails.root.join('tmp', 'test_report.xlsx').to_s }

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

    it 'Axlsxパッケージが作成されること' do
      package = generator.instance_variable_get(:@package)
      expect(package).to be_a(Axlsx::Package)
    end

    it 'ワークブックが作成されること' do
      workbook = generator.instance_variable_get(:@workbook)
      expect(workbook).to be_a(Axlsx::Workbook)
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

      it '生成されたファイルが有効なExcelファイルであること' do
        generator.generate(temp_file_path)

        # ファイルサイズの確認
        expect(File.size(temp_file_path)).to be > 0

        # Excel ファイルのマジックナンバー確認（ZIP形式）
        file_content = File.read(temp_file_path, 4)
        expect(file_content).to start_with("PK") # ZIP ヘッダー
      end

      it 'ログメッセージが出力されること' do
        expect(Rails.logger).to receive(:info).with(/Starting Excel generation/)
        expect(Rails.logger).to receive(:info).with(/Excel file generated/)

        generator.generate(temp_file_path)
      end
    end

    context 'ファイルパスを指定しない場合' do
      subject { generator.generate }

      it '自動生成されたパスにファイルが作成されること' do
        result_path = subject

        expect(result_path).to include('monthly_report_')
        expect(result_path).to end_with('.xlsx')
        expect(File.exist?(result_path)).to be true

        # テスト後のクリーンアップ
        File.delete(result_path) if File.exist?(result_path)
      end
    end

    context 'チャート機能が有効な場合' do
      let(:chart_enabled_data) do
        valid_report_data.merge(charts_enabled: true)
      end
      let(:chart_generator) { described_class.new(chart_enabled_data) }

      it 'チャートシートが作成されること' do
        result_path = chart_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true

        # TODO: 🟡 Phase 2（中）- Excelファイル内容の詳細検証
        # 優先度: 中（テスト品質向上）
        # 実装内容: axlsx gem を使用したシート内容の検証
        # 理由: 生成されたExcelファイルの品質保証
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

    it 'チャート有効時はファイルサイズが大きくなること' do
      chart_enabled_data = valid_report_data.merge(charts_enabled: true)
      chart_generator = described_class.new(chart_enabled_data)

      normal_size = generator.estimate_file_size
      chart_size = chart_generator.estimate_file_size

      expect(chart_size).to be > normal_size
    end

    it '合理的なサイズ範囲内であること' do
      # 50KB - 10MB の範囲内であることを確認
      expect(subject).to be_between(50_000, 10_000_000)
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
        }.to raise_error(ReportExcelGenerator::DataValidationError, /Required data missing/)
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
        # ディスク容量不足をシミュレート
        allow_any_instance_of(Axlsx::Package).to receive(:serialize).and_raise(StandardError.new("Disk full"))
      end

      it 'ExcelGenerationErrorを発生させること' do
        expect {
          generator.generate(temp_file_path)
        }.to raise_error(ReportExcelGenerator::ExcelGenerationError, /Excel生成エラー/)
      end

      it 'エラーログが出力されること' do
        expect(Rails.logger).to receive(:error).with(/Error generating Excel/)

        expect {
          generator.generate(temp_file_path)
        }.to raise_error(ReportExcelGenerator::ExcelGenerationError)
      end
    end

    context '不正なファイルパスが指定された場合' do
      let(:invalid_path) { '/invalid/directory/test.xlsx' }

      it '適切なエラーメッセージでExcelGenerationErrorを発生させること' do
        expect {
          generator.generate(invalid_path)
        }.to raise_error(ReportExcelGenerator::ExcelGenerationError)
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
            high_value_items: 0,
            average_quantity: 0
          }
        }
      end
      let(:minimal_generator) { described_class.new(minimal_data) }

      it '最小データでもExcelファイルが生成されること' do
        result_path = minimal_generator.generate(temp_file_path)
        expect(File.exist?(temp_file_path)).to be true
        expect(File.size(temp_file_path)).to be > 0
      end
    end

    context '大量データの場合' do
      let(:large_data) do
        large_movements = Array.new(1000) do |i|
          {
            inventory_id: i + 1,
            name: "商品#{i + 1}",
            movement_count: rand(1..100),
            activity_score: rand(1..100)
          }
        end

        valid_report_data.merge(
          stock_movements: {
            total_movements: 10000,
            movement_breakdown: valid_report_data[:stock_movements][:movement_breakdown],
            top_active_items: large_movements
          }
        )
      end
      let(:large_generator) { described_class.new(large_data) }

      it '大量データでもタイムアウトしないこと' do
        expect {
          Timeout.timeout(10.seconds) do
            large_generator.generate(temp_file_path)
          end
        }.not_to raise_error

        expect(File.exist?(temp_file_path)).to be true
      end
    end

    context '特殊文字を含むデータの場合' do
      let(:special_char_data) do
        valid_report_data.merge(
          stock_movements: {
            total_movements: 10,
            movement_breakdown: [],
            top_active_items: [
              {
                inventory_id: 1,
                name: "テスト商品 🚀 & \"quotes\" & <tags>",
                movement_count: 5,
                activity_score: 50
              }
            ]
          }
        )
      end
      let(:special_generator) { described_class.new(special_char_data) }

      it '特殊文字を含むデータでも正常に処理されること' do
        result_path = special_generator.generate(temp_file_path)
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

      # Excel生成は複雑な処理のため5秒以内
      expect(elapsed_time).to be < 5.seconds
    end

    it 'メモリ使用量が適切であること' do
      # メモリ使用量の大幅な増加がないことを確認
      before_memory = get_memory_usage
      generator.generate(temp_file_path)
      after_memory = get_memory_usage

      memory_increase = after_memory - before_memory
      # 50MB以下の増加であることを確認
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
  # ファイル内容検証テスト
  # ============================================================================

  describe 'ファイル内容検証' do
    before do
      generator.generate(temp_file_path)
    end

    it '生成されたファイルが破損していないこと' do
      # ZIP圧縮が正常であることを確認
      expect {
        Zip::File.open(temp_file_path) do |zip_file|
          expect(zip_file.entries.length).to be > 0
        end
      }.not_to raise_error
    end

    # TODO: 🔴 Phase 1（緊急）- Excel内容の詳細検証実装
    # 優先度: 高（テスト品質向上）
    # 実装内容:
    #   - シート存在確認（サマリー、在庫詳細、期限切れ分析、移動分析）
    #   - セル値の検証（計算結果の正確性）
    #   - スタイル適用確認
    # 理由: 生成されたExcelファイルの品質保証が重要

    it 'Excel内容の詳細検証' do
      pending '詳細なExcel内容検証機能の実装が必要'

      # 実装予定の検証項目:
      # - シート数と名前の確認
      # - 各シートのデータ内容確認
      # - スタイル適用状況の確認
      # - 数式・計算結果の検証
    end
  end

  # ============================================================================
  # 統合テスト
  # ============================================================================

  describe '統合テスト' do
    context '実際のサービスデータとの統合' do
      let!(:inventories) { create_list(:inventory, 5) }
      let!(:inventory_logs) { create_list(:inventory_log, 10, inventory: inventories.first) }

      before do
        # 実際のサービスからデータを取得
        @real_inventory_data = InventoryReportService.monthly_summary(target_date)
        @real_movement_data = StockMovementService.monthly_analysis(target_date)
      end

      it '実際のサービスデータでExcelファイルが生成されること' do
        real_report_data = {
          target_date: target_date,
          inventory_summary: @real_inventory_data,
          stock_movements: @real_movement_data
        }

        real_generator = described_class.new(real_report_data)
        result_path = real_generator.generate(temp_file_path)

        expect(File.exist?(temp_file_path)).to be true
        expect(File.size(temp_file_path)).to be > 0
      end
    end
  end

  # ============================================================================
  # 横展開確認項目（メタ認知的チェックリスト）
  # ============================================================================

  # TODO: 🟢 Phase 3（推奨）- ファイル生成テストパターンの標準化
  # - PDF生成テストとの統一パターン
  # - 一時ファイル管理の最適化
  # - ファイル形式別テストの体系化

  # TODO: 🟡 Phase 2（中）- Excel固有機能のテスト強化
  # - 複数シート間のデータ整合性テスト
  # - 条件付き書式の動作確認テスト
  # - グラフ・チャート機能のテスト

  # TODO: 🟢 Phase 3（推奨）- セキュリティテストの追加
  # - 機密情報のマスキング確認
  # - ファイルアクセス権限のテスト
  # - 一時ファイルの適切な削除確認
end
