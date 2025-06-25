# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MonthlyReportJob, type: :job do
  # CLAUDE.md準拠: 月次レポート生成ジョブの包括的テスト
  # メタ認知: 長時間実行・複雑なデータ処理・進捗管理の品質保証
  # 横展開: 他のレポート系ジョブでも同様のテストパターン適用

  include ActiveJob::TestHelper

  let(:admin) { create(:admin) }
  let(:target_date) { Date.current.last_month.beginning_of_month }
  let(:report_types) { %w[inventory_summary expiry_analysis] }
  let(:output_formats) { %w[csv pdf excel] }

  # テストデータの準備
  before do
    # 在庫データ作成
    @inventory1 = create(:inventory, name: "Medicine A", quantity: 100, price: 500, status: 'active')
    @inventory2 = create(:inventory, name: "Equipment B", quantity: 5, price: 10000, status: 'active')
    @inventory3 = create(:inventory, name: "Supply C", quantity: 0, price: 100, status: 'discontinued')

    # バッチデータ作成（期限管理テスト用）
    @batch1 = create(:batch, inventory: @inventory1, lot_code: 'LOT001', expires_on: 30.days.from_now, quantity: 50)
    @batch2 = create(:batch, inventory: @inventory1, lot_code: 'LOT002', expires_on: 5.days.from_now, quantity: 30)
    @batch3 = create(:batch, inventory: @inventory2, lot_code: 'LOT003', expires_on: 1.year.from_now, quantity: 3)

    # ProgressNotifierのモック
    allow_any_instance_of(described_class).to receive(:initialize_progress).and_return("progress_key_123")
    allow_any_instance_of(described_class).to receive(:update_progress).and_return(true)
    allow_any_instance_of(described_class).to receive(:notify_completion).and_return(true)
    allow_any_instance_of(described_class).to receive(:notify_error).and_return(true)

    # ActionCableのモック
    allow(ActionCable.server).to receive(:broadcast)

    # ファイル生成のモック
    allow(CSV).to receive(:open).and_yield([])
    allow(File).to receive(:size).and_return(1024)
    allow(File).to receive(:basename).and_return("report.csv")

    # メーラーのモック
    allow(AdminMailer).to receive_message_chain(:monthly_report_complete, :deliver_now)
    allow(AdminMailer).to receive_message_chain(:system_error_alert, :deliver_now)
  end

  describe "#perform" do
    context "正常実行" do
      it "デフォルトパラメータで実行される" do
        expect {
          perform_enqueued_jobs do
            described_class.perform_later
          end
        }.not_to raise_error
      end

      it "指定されたパラメータで実行される" do
        job_result = nil

        expect {
          perform_enqueued_jobs do
            job_result = described_class.perform_now(
              target_date,
              admin.id,
              report_types,
              output_formats,
              true
            )
          end
        }.not_to raise_error

        expect(job_result[:status]).to eq("success")
        expect(job_result[:target_date]).to eq(target_date)
        expect(job_result[:generated_files]).to be_present
      end

      it "進捗追跡が正しく更新される" do
        job_instance = described_class.new

        expect(job_instance).to receive(:initialize_progress).with(
          admin.id,
          anything,
          "monthly_report",
          hash_including(
            target_date: target_date.iso8601,
            report_types: report_types
          )
        )

        expect(job_instance).to receive(:update_progress).at_least(:once)
        expect(job_instance).to receive(:notify_completion)

        job_instance.perform(target_date, admin.id, report_types, output_formats, true)
      end

      it "複数のレポートタイプを処理する" do
        all_report_types = %w[inventory_summary expiry_analysis sales_summary performance_metrics]

        job_result = described_class.perform_now(
          target_date,
          admin.id,
          all_report_types,
          %w[csv],
          false
        )

        expect(job_result[:status]).to eq("success")
        expect(job_result[:report_data]).to have_key(:inventory_summary)
        expect(job_result[:report_data]).to have_key(:expiry_analysis)
        expect(job_result[:report_data]).to have_key(:sales_summary)
        expect(job_result[:report_data]).to have_key(:performance_metrics)
      end
    end

    context "ファイル生成" do
      before do
        allow(File).to receive(:size).and_return(2048)
        allow(Rails.root).to receive(:join).and_return(Pathname.new("/tmp/test_report.csv"))
      end

      it "CSV形式でレポートを生成する" do
        csv_data = []
        allow(CSV).to receive(:open).and_yield(csv_data)

        job_result = described_class.perform_now(
          target_date,
          admin.id,
          [ 'inventory_summary' ],
          [ 'csv' ],
          false
        )

        expect(job_result[:generated_files]).to be_present
        expect(job_result[:generated_files].first).to include('.csv')
      end

      it "複数の出力形式でファイルを生成する" do
        # PDF・Excelジェネレーターのモック
        pdf_generator = double('ReportPdfGenerator')
        excel_generator = double('ReportExcelGenerator')

        allow(ReportPdfGenerator).to receive(:new).and_return(pdf_generator)
        allow(ReportExcelGenerator).to receive(:new).and_return(excel_generator)
        allow(pdf_generator).to receive(:generate).and_return('/tmp/report.pdf')
        allow(excel_generator).to receive(:generate).and_return('/tmp/report.xlsx')

        job_result = described_class.perform_now(
          target_date,
          admin.id,
          [ 'inventory_summary' ],
          [ 'csv', 'pdf', 'excel' ],
          false
        )

        expect(job_result[:generated_files].size).to eq(3)
      end

      it "ファイル生成失敗時にフォールバックCSVを作成する" do
        # PDF生成を失敗させる
        allow(ReportPdfGenerator).to receive(:new).and_raise(StandardError.new("PDF generation failed"))

        csv_data = []
        allow(CSV).to receive(:open).and_yield(csv_data)

        job_result = described_class.perform_now(
          target_date,
          admin.id,
          [ 'inventory_summary' ],
          [ 'pdf' ],
          false
        )

        # フォールバックCSVが生成される
        expect(job_result[:generated_files]).not_to be_empty
      end
    end

    context "通知機能" do
      it "管理者に完了通知を送信する" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "admin_#{admin.id}",
          hash_including(
            type: "monthly_report_complete",
            message: include("月次レポート生成完了")
          )
        )

        described_class.perform_now(target_date, admin.id, report_types, [ 'csv' ], true)
      end

      it "メール通知が有効な場合にメールを送信する" do
        expect(AdminMailer).to receive(:monthly_report_complete).and_call_original

        described_class.perform_now(target_date, admin.id, report_types, [ 'csv' ], true)
      end

      it "メール通知が無効な場合にメールを送信しない" do
        expect(AdminMailer).not_to receive(:monthly_report_complete)

        described_class.perform_now(target_date, admin.id, report_types, [ 'csv' ], false)
      end

      it "全管理者に通知する（admin_id未指定時）" do
        admin2 = create(:admin)

        expect(ActionCable.server).to receive(:broadcast).with("admin_#{admin.id}", anything)
        expect(ActionCable.server).to receive(:broadcast).with("admin_#{admin2.id}", anything)

        described_class.perform_now(target_date, nil, report_types, [ 'csv' ], true)
      end
    end

    context "エラーハンドリング" do
      it "例外発生時にエラー通知を送信する" do
        allow_any_instance_of(described_class).to receive(:generate_inventory_summary).and_raise(StandardError.new("Test error"))

        expect(ActionCable.server).to receive(:broadcast).with(
          "admin_#{admin.id}",
          hash_including(
            type: "monthly_report_error",
            error_class: "StandardError"
          )
        )

        expect {
          described_class.perform_now(target_date, admin.id, report_types, [ 'csv' ], true)
        }.to raise_error(StandardError)
      end

      it "エラー時にシステムアラートメールを送信する" do
        allow_any_instance_of(described_class).to receive(:generate_inventory_summary).and_raise(StandardError.new("Test error"))

        expect(AdminMailer).to receive(:system_error_alert).and_call_original

        expect {
          described_class.perform_now(target_date, admin.id, report_types, [ 'csv' ], true)
        }.to raise_error(StandardError)
      end

      it "不明なレポートタイプを適切に処理する" do
        expect(Rails.logger).to receive(:warn).with("Unknown report type: unknown_type")

        job_result = described_class.perform_now(
          target_date,
          admin.id,
          [ 'unknown_type' ],
          [ 'csv' ],
          false
        )

        expect(job_result[:status]).to eq("success")
      end

      it "不明な出力形式を適切に処理する" do
        expect(Rails.logger).to receive(:warn).with(include("Unknown output format"))

        job_result = described_class.perform_now(
          target_date,
          admin.id,
          [ 'inventory_summary' ],
          [ 'unknown_format' ],
          false
        )

        # フォールバックCSVが生成される
        expect(job_result[:generated_files]).not_to be_empty
      end
    end
  end

  describe "レポートデータ生成" do
    let(:job) { described_class.new }

    describe "#generate_inventory_summary" do
      it "在庫サマリーデータを生成する" do
        summary = job.send(:generate_inventory_summary, target_date)

        expect(summary).to include(
          :total_items,
          :total_value,
          :low_stock_items,
          :high_value_items,
          :average_quantity,
          :categories_breakdown
        )

        expect(summary[:total_items]).to eq(3)
        expect(summary[:total_value]).to eq(105 * 500 + 5 * 10000 + 0 * 100) # 在庫×価格の合計
        expect(summary[:high_value_items]).to eq(1) # 10,000円以上のアイテム
      end
    end

    describe "#generate_sales_summary" do
      it "売上サマリーデータを生成する（将来実装用）" do
        summary = job.send(:generate_sales_summary, target_date)

        expect(summary).to include(
          :total_sales,
          :orders_count,
          :average_order_value,
          :top_selling_items,
          :monthly_trend
        )

        # 現在は0/空の値が返される
        expect(summary[:total_sales]).to eq(0)
        expect(summary[:orders_count]).to eq(0)
      end
    end

    describe "#generate_expiry_analysis" do
      it "期限分析データを生成する" do
        analysis = job.send(:generate_expiry_analysis, target_date)

        expect(analysis).to include(
          :expiring_next_month,
          :expiring_next_quarter,
          :expired_items,
          :expiry_value_risk,
          :recommended_actions
        )

        expect(analysis[:recommended_actions]).to be_an(Array)
        expect(analysis[:recommended_actions]).not_to be_empty
      end
    end

    describe "#generate_performance_metrics" do
      it "パフォーマンス指標を生成する" do
        metrics = job.send(:generate_performance_metrics, target_date)

        expect(metrics).to include(
          :inventory_turnover,
          :stock_accuracy,
          :fulfillment_rate,
          :carrying_cost,
          :stockout_incidents
        )

        expect(metrics[:stock_accuracy]).to eq(95.0)
        expect(metrics[:fulfillment_rate]).to eq(98.5)
      end
    end
  end

  describe "推奨事項生成" do
    let(:job) { described_class.new }

    it "低在庫アイテムの推奨事項を生成する" do
      report_data = {
        inventory_summary: {
          total_items: 10,
          total_value: 50000,
          low_stock_items: 3
        }
      }

      recommendations = job.send(:generate_integrated_recommendations, report_data)

      expect(recommendations).to include(match(/低在庫アイテム.*3件.*発注検討/))
    end

    it "高価値在庫の推奨事項を生成する" do
      report_data = {
        inventory_summary: {
          total_items: 10,
          total_value: 100000, # 平均10,000円/アイテム
          low_stock_items: 0
        }
      }

      recommendations = job.send(:generate_integrated_recommendations, report_data)

      expect(recommendations).to include(match(/高価値在庫.*セキュリティ管理/))
    end

    it "期限切れアイテムの推奨事項を生成する" do
      report_data = {
        inventory_summary: { total_items: 10, total_value: 5000, low_stock_items: 0 },
        expiry_analysis: {
          expiry_summary: {
            expired_items: 2,
            expiring_soon: 6
          }
        }
      }

      recommendations = job.send(:generate_integrated_recommendations, report_data)

      expect(recommendations).to include(match(/期限切れアイテム.*2件.*処分/))
      expect(recommendations).to include(match(/3日以内期限切れアイテム.*6件.*緊急対応/))
    end

    it "良好な状況でのデフォルト推奨事項を生成する" do
      report_data = {
        inventory_summary: {
          total_items: 10,
          total_value: 5000,
          low_stock_items: 0
        },
        expiry_analysis: {
          expiry_summary: {
            expired_items: 0,
            expiring_soon: 1
          }
        }
      }

      recommendations = job.send(:generate_integrated_recommendations, report_data)

      expect(recommendations).to include(match(/現在の在庫状況は良好/))
    end
  end

  describe "パフォーマンススコア計算" do
    let(:job) { described_class.new }

    it "総合パフォーマンススコアを計算する" do
      report_data = {
        inventory_summary: {
          total_items: 100,
          low_stock_items: 10 # 10%の低在庫
        },
        expiry_analysis: {
          expired_items: 5 # 5%の期限切れ
        },
        performance_metrics: {
          stock_accuracy: 95.0,
          fulfillment_rate: 98.0
        }
      }

      score = job.send(:calculate_overall_performance_score, report_data)

      expect(score).to be_a(Float)
      expect(score).to be_between(0, 100)

      # スコア計算の妥当性確認
      # 在庫効率: 50 - (0.1 * 50) = 45
      # 期限管理: 30 - (0.05 * 30) = 28.5
      # パフォーマンス: (95 * 0.1) + (98 * 0.1) = 19.3
      expected_score = 45 + 28.5 + 19.3
      expect(score).to be_within(0.1).of(expected_score)
    end

    it "データが不足している場合でも適切に処理する" do
      report_data = {
        inventory_summary: {
          total_items: 50,
          low_stock_items: 5
        }
        # expiry_analysis と performance_metrics が欠如
      }

      score = job.send(:calculate_overall_performance_score, report_data)

      expect(score).to be_a(Float)
      expect(score).to be >= 0
    end
  end

  describe "ヘルパーメソッド" do
    let(:job) { described_class.new }

    describe "#expiring_items_count" do
      it "指定日数以内に期限切れになるアイテム数を計算する" do
        count = job.send(:expiring_items_count, 30)

        # 30日以内に期限切れになるバッチを持つ在庫は1つ
        expect(count).to eq(1)
      end
    end

    describe "#expired_items_count" do
      it "既に期限切れのアイテム数を計算する" do
        # 過去の期限切れバッチを作成
        create(:batch, inventory: @inventory3, expires_on: 1.day.ago, quantity: 10)

        count = job.send(:expired_items_count)
        expect(count).to eq(1)
      end
    end

    describe "#calculate_expiry_value_risk" do
      it "期限切れリスクの金額を計算する" do
        value_risk = job.send(:calculate_expiry_value_risk)

        # 30日以内期限切れバッチの価値合計
        # batch2: inventory1の価格500円 × batch2の数量30個 = 15,000円
        expect(value_risk).to eq(500 * 30)
      end
    end

    describe "#calculate_carrying_cost" do
      it "在庫保有コストを計算する" do
        carrying_cost = job.send(:calculate_carrying_cost)

        total_value = 105 * 500 + 5 * 10000 + 0 * 100
        expected_cost = total_value * 0.15

        expect(carrying_cost).to eq(expected_cost)
      end
    end

    describe "#count_stockout_incidents" do
      before do
        # 在庫ログ作成
        create(:inventory_log,
          inventory: @inventory3,
          operation_type: 'sold',
          created_at: target_date + 10.days
        )
      end

      it "在庫切れインシデント数を集計する" do
        incidents = job.send(:count_stockout_incidents, target_date)

        expect(incidents).to eq(1)
      end
    end

    describe "#select_primary_file" do
      it "PDF優先でプライマリファイルを選択する" do
        files = [ '/tmp/report.csv', '/tmp/report.pdf', '/tmp/report.xlsx' ]

        primary = job.send(:select_primary_file, files)
        expect(primary).to eq('/tmp/report.pdf')
      end

      it "PDFがない場合はExcelを選択する" do
        files = [ '/tmp/report.csv', '/tmp/report.xlsx' ]

        primary = job.send(:select_primary_file, files)
        expect(primary).to eq('/tmp/report.xlsx')
      end

      it "PDFもExcelもない場合はCSVを選択する" do
        files = [ '/tmp/report.csv', '/tmp/other.txt' ]

        primary = job.send(:select_primary_file, files)
        expect(primary).to eq('/tmp/report.csv')
      end

      it "該当するファイルがない場合は最初のファイルを選択する" do
        files = [ '/tmp/report.txt', '/tmp/other.log' ]

        primary = job.send(:select_primary_file, files)
        expect(primary).to eq('/tmp/report.txt')
      end
    end
  end

  describe "CSV生成" do
    let(:job) { described_class.new }

    it "レポートデータをCSV形式で出力する" do
      report_data = {
        inventory_summary: {
          total_items: 10,
          total_value: 50000,
          low_stock_items: 2,
          high_value_items: 3,
          average_quantity: 25.5
        },
        expiry_analysis: {
          expiring_next_month: 1,
          expiring_next_quarter: 3,
          expired_items: 0,
          expiry_value_risk: 5000
        }
      }

      csv_rows = []
      allow(CSV).to receive(:open).and_yield(csv_rows)
      allow(Rails.root).to receive(:join).and_return(Pathname.new("/tmp/test_report.csv"))

      file_path = job.send(:generate_csv_report, target_date, report_data)

      expect(file_path).to include('monthly_report_')
      expect(file_path).to end_with('.csv')

      # CSVに適切なデータが書き込まれることを確認
      expect(csv_rows).not_to be_empty
    end
  end

  describe "Sidekiq設定" do
    it "正しいキューが設定されている" do
      expect(described_class.queue_name).to eq('reports')
    end

    it "適切なSidekiqオプションが設定されている" do
      sidekiq_options = described_class.sidekiq_options_hash

      expect(sidekiq_options['retry']).to eq(1)
      expect(sidekiq_options['backtrace']).to be true
      expect(sidekiq_options['queue']).to eq(:reports)
      expect(sidekiq_options['timeout']).to eq(600)
    end
  end

  describe "機密情報保護" do
    it "機密情報フィルタリング設定が定義されている" do
      expect(described_class::SENSITIVE_REPORT_PARAMS).to include(
        'email_list', 'recipient_data', 'financial_data'
      )
    end

    it "財務データ保護レベルが設定されている" do
      expect(described_class::FINANCIAL_PROTECTION_LEVEL).to eq(:strict)
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1-2日
  # 横展開: ImportInventoriesJobと同等のテスト網羅性達成
  #
  # 1. 大規模データ処理テスト
  #    - 10,000件以上の在庫データでのパフォーマンステスト
  #    - メモリ使用量監視テスト
  #    - タイムアウト処理テスト
  #
  # 2. 並行実行テスト
  #    - 複数の月次レポートジョブ同時実行
  #    - リソース競合の検証
  #    - ファイルロック機能テスト
  #
  # 3. レポート品質検証テスト
  #    - 生成されたCSV/PDF/Excelファイルの内容検証
  #    - データ整合性チェック
  #    - 文字化け・エンコーディングテスト
  #
  # 4. 統合テスト
  #    - ActionCable通知の実際の受信テスト
  #    - メール配信の実際のテスト（test環境）
  #    - ProgressNotifierとの完全統合テスト
  #
  # 5. セキュリティテスト
  #    - 権限のない管理者での実行テスト
  #    - 機密情報フィルタリング動作確認
  #    - ファイルアクセス権限テスト
end
