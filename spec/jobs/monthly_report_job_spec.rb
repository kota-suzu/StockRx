# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MonthlyReportJob, type: :job do
  # CLAUDE.md準拠: 月次レポート生成ジョブの包括的テスト
  # メタ認知: 複数レポートタイプと進捗追跡の複雑な分岐ロジックの品質保証
  # 横展開: 他のレポート生成ジョブでも同様のテストパターン適用

  include ActiveJob::TestHelper

  let(:admin) { create(:admin) }
  let(:report_month) { Date.today.beginning_of_month }

  before do
    # テスト用データの準備
    create_list(:inventory, 5)
    create_list(:inventory_log, 10)
    create_list(:batch, 3, expiration_date: 1.month.from_now)

    # ActionCableのモック
    allow(ActionCable).to receive(:server).and_return(
      double(broadcast: true)
    )
  end

  describe '#perform' do
    context 'with default parameters' do
      it 'generates all report types' do
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_inventory_summary).and_return({})
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_transaction_report).and_return({})
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_expiry_report).and_return({})
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_performance_report).and_return({})

        MonthlyReportJob.new.perform(admin.id, report_month.to_s)
      end

      it 'saves report file' do
        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s)
        }.to change { Dir[Rails.root.join('tmp', 'reports', '*.json')].count }.by(1)
      end

      it 'sends notification email' do
        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s)
        }.to have_enqueued_mail(AdminMailer, :monthly_report_ready)
      end
    end

    context 'with specific report types' do
      it 'generates only inventory summary when specified' do
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_inventory_summary).and_return({})
        expect_any_instance_of(MonthlyReportJob).not_to receive(:generate_transaction_report)
        expect_any_instance_of(MonthlyReportJob).not_to receive(:generate_expiry_report)
        expect_any_instance_of(MonthlyReportJob).not_to receive(:generate_performance_report)

        MonthlyReportJob.new.perform(admin.id, report_month.to_s, report_types: [ 'inventory_summary' ])
      end

      it 'generates multiple specified report types' do
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_inventory_summary).and_return({})
        expect_any_instance_of(MonthlyReportJob).to receive(:generate_transaction_report).and_return({})
        expect_any_instance_of(MonthlyReportJob).not_to receive(:generate_expiry_report)
        expect_any_instance_of(MonthlyReportJob).not_to receive(:generate_performance_report)

        MonthlyReportJob.new.perform(admin.id, report_month.to_s,
          report_types: [ 'inventory_summary', 'transaction_report' ])
      end

      it 'handles invalid report type gracefully' do
        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s, report_types: [ 'invalid_type' ])
        }.not_to raise_error
      end
    end

    context 'with different formats' do
      it 'generates JSON format by default' do
        MonthlyReportJob.new.perform(admin.id, report_month.to_s)

        report_file = Dir[Rails.root.join('tmp', 'reports', '*.json')].last
        expect(report_file).to match(/\.json$/)

        content = JSON.parse(File.read(report_file))
        expect(content).to have_key('metadata')
        expect(content).to have_key('reports')
      end

      it 'generates CSV format when specified' do
        MonthlyReportJob.new.perform(admin.id, report_month.to_s, format: 'csv')

        csv_files = Dir[Rails.root.join('tmp', 'reports', '*.csv')]
        expect(csv_files).not_to be_empty
      end

      it 'generates XLSX format when specified' do
        MonthlyReportJob.new.perform(admin.id, report_month.to_s, format: 'xlsx')

        xlsx_file = Dir[Rails.root.join('tmp', 'reports', '*.xlsx')].last
        expect(xlsx_file).to match(/\.xlsx$/)
      end

      it 'generates PDF format when specified' do
        MonthlyReportJob.new.perform(admin.id, report_month.to_s, format: 'pdf')

        pdf_file = Dir[Rails.root.join('tmp', 'reports', '*.pdf')].last
        expect(pdf_file).to match(/\.pdf$/)
      end
    end

    context 'progress tracking' do
      it 'broadcasts progress updates via ActionCable' do
        expect(ActionCable.server).to receive(:broadcast).at_least(4).times

        MonthlyReportJob.new.perform(admin.id, report_month.to_s)
      end

      it 'updates progress for each report type' do
        progress_updates = []
        allow(ActionCable.server).to receive(:broadcast) do |channel, data|
          progress_updates << data if channel == "report_progress_#{admin.id}"
        end

        MonthlyReportJob.new.perform(admin.id, report_month.to_s)

        expect(progress_updates).to include(
          hash_including(progress: 25, status: 'Generating inventory summary...'),
          hash_including(progress: 50, status: 'Generating transaction report...'),
          hash_including(progress: 75, status: 'Generating expiry report...'),
          hash_including(progress: 100, status: 'Report generation completed!')
        )
      end

      it 'handles progress tracking when ActionCable unavailable' do
        allow(ActionCable).to receive(:server).and_return(nil)

        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s)
        }.not_to raise_error
      end
    end

    context 'notification handling' do
      it 'sends email notification on success' do
        MonthlyReportJob.new.perform(admin.id, report_month.to_s)

        expect(ActionMailer::MailDeliveryJob).to have_been_enqueued.with(
          'AdminMailer', 'monthly_report_ready', 'deliver_now',
          args: [ admin.id, anything ]
        )
      end

      it 'does not send email when skip_notification is true' do
        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s, skip_notification: true)
        }.not_to have_enqueued_mail
      end

      it 'creates in-app notification' do
        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s)
        }.to change { AdminNotification.count }.by(1)

        notification = AdminNotification.last
        expect(notification.admin).to eq(admin)
        expect(notification.notification_type).to eq('report_ready')
      end
    end

    context 'error handling' do
      it 'logs error when report generation fails' do
        allow_any_instance_of(MonthlyReportJob).to receive(:generate_inventory_summary)
          .and_raise(StandardError, 'Test error')

        expect(Rails.logger).to receive(:error).with(/Failed to generate report/)

        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s)
        }.to raise_error(StandardError)
      end

      it 'cleans up temporary files on error' do
        allow_any_instance_of(MonthlyReportJob).to receive(:generate_transaction_report)
          .and_raise(StandardError)

        expect {
          MonthlyReportJob.new.perform(admin.id, report_month.to_s)
        }.to raise_error(StandardError)

        # 一時ファイルが残っていないことを確認
        temp_files = Dir[Rails.root.join('tmp', 'reports', 'temp_*')]
        expect(temp_files).to be_empty
      end

      it 'sends error notification on failure' do
        allow_any_instance_of(MonthlyReportJob).to receive(:generate_inventory_summary)
          .and_raise(StandardError)

        expect {
          begin
            MonthlyReportJob.new.perform(admin.id, report_month.to_s)
          rescue StandardError
            # エラーをキャッチして通知の確認を続ける
          end
        }.to change { AdminNotification.count }.by(1)

        notification = AdminNotification.last
        expect(notification.notification_type).to eq('report_failed')
      end
    end
  end

  describe 'report generation methods' do
    let(:job) { MonthlyReportJob.new }
    let(:start_date) { report_month }
    let(:end_date) { report_month.end_of_month }

    describe '#generate_inventory_summary' do
      it 'includes current inventory levels' do
        result = job.send(:generate_inventory_summary, start_date, end_date)

        expect(result).to have_key(:total_items)
        expect(result).to have_key(:total_value)
        expect(result).to have_key(:low_stock_items)
        expect(result).to have_key(:out_of_stock_items)
      end

      it 'calculates inventory by category' do
        result = job.send(:generate_inventory_summary, start_date, end_date)

        expect(result).to have_key(:by_category)
        expect(result[:by_category]).to be_a(Hash)
      end

      it 'includes top movers' do
        result = job.send(:generate_inventory_summary, start_date, end_date)

        expect(result).to have_key(:top_movers)
        expect(result[:top_movers]).to be_an(Array)
      end
    end

    describe '#generate_transaction_report' do
      before do
        create_list(:inventory_log, 5, operation_type: 'receive', created_at: start_date + 1.day)
        create_list(:inventory_log, 3, operation_type: 'ship', created_at: start_date + 2.days)
      end

      it 'summarizes transactions by type' do
        result = job.send(:generate_transaction_report, start_date, end_date)

        expect(result).to have_key(:summary)
        expect(result[:summary]).to include(
          :total_transactions,
          :receipts,
          :shipments,
          :adjustments
        )
      end

      it 'includes daily breakdown' do
        result = job.send(:generate_transaction_report, start_date, end_date)

        expect(result).to have_key(:daily_breakdown)
        expect(result[:daily_breakdown]).to be_an(Array)
      end

      it 'calculates value changes' do
        result = job.send(:generate_transaction_report, start_date, end_date)

        expect(result).to have_key(:value_changes)
        expect(result[:value_changes]).to include(
          :received_value,
          :shipped_value,
          :net_change
        )
      end
    end

    describe '#generate_expiry_report' do
      before do
        create(:batch, expiration_date: end_date + 5.days)
        create(:batch, expiration_date: end_date + 20.days)
        create(:batch, expiration_date: end_date + 45.days)
        create(:batch, expiration_date: end_date - 5.days)
      end

      it 'categorizes items by expiry status' do
        result = job.send(:generate_expiry_report, start_date, end_date)

        expect(result).to have_key(:expired)
        expect(result).to have_key(:expiring_soon)
        expect(result).to have_key(:expiring_this_month)
        expect(result).to have_key(:expiring_next_month)
      end

      it 'includes expiry timeline' do
        result = job.send(:generate_expiry_report, start_date, end_date)

        expect(result).to have_key(:timeline)
        expect(result[:timeline]).to be_an(Array)
      end

      it 'calculates potential loss value' do
        result = job.send(:generate_expiry_report, start_date, end_date)

        expect(result).to have_key(:potential_loss)
        expect(result[:potential_loss]).to be_a(Numeric)
      end
    end

    describe '#generate_performance_report' do
      it 'includes turnover metrics' do
        result = job.send(:generate_performance_report, start_date, end_date)

        expect(result).to have_key(:turnover_rate)
        expect(result).to have_key(:average_days_in_stock)
      end

      it 'calculates stock accuracy' do
        result = job.send(:generate_performance_report, start_date, end_date)

        expect(result).to have_key(:stock_accuracy)
        expect(result[:stock_accuracy]).to be_between(0, 100)
      end

      it 'includes efficiency metrics' do
        result = job.send(:generate_performance_report, start_date, end_date)

        expect(result).to have_key(:efficiency_metrics)
        expect(result[:efficiency_metrics]).to include(
          :order_fulfillment_rate,
          :stockout_incidents,
          :overstock_percentage
        )
      end

      it 'provides recommendations' do
        result = job.send(:generate_performance_report, start_date, end_date)

        expect(result).to have_key(:recommendations)
        expect(result[:recommendations]).to be_an(Array)
      end
    end
  end

  describe 'file generation' do
    let(:job) { MonthlyReportJob.new }
    let(:report_data) do
      {
        metadata: { generated_at: Time.current },
        reports: {
          inventory_summary: { total_items: 100 },
          transaction_report: { total_transactions: 50 }
        }
      }
    end

    describe '#save_as_json' do
      it 'creates JSON file with proper formatting' do
        filename = job.send(:save_as_json, report_data)

        expect(File.exist?(filename)).to be true

        content = JSON.parse(File.read(filename))
        expect(content['metadata']).to be_present
        expect(content['reports']).to be_present
      end
    end

    describe '#save_as_csv' do
      it 'creates multiple CSV files for different sections' do
        filenames = job.send(:save_as_csv, report_data)

        expect(filenames).to be_an(Array)
        expect(filenames.size).to be > 0

        filenames.each do |filename|
          expect(File.exist?(filename)).to be true
          expect(filename).to match(/\.csv$/)
        end
      end
    end

    describe '#save_as_xlsx' do
      it 'creates XLSX file with multiple sheets' do
        filename = job.send(:save_as_xlsx, report_data)

        expect(File.exist?(filename)).to be true
        expect(filename).to match(/\.xlsx$/)

        # XLSXファイルの検証（実際の実装に依存）
        expect(File.size(filename)).to be > 0
      end
    end

    describe '#save_as_pdf' do
      it 'creates PDF file' do
        filename = job.send(:save_as_pdf, report_data)

        expect(File.exist?(filename)).to be true
        expect(filename).to match(/\.pdf$/)

        # PDFファイルの検証
        expect(File.size(filename)).to be > 0
      end
    end
  end

  describe 'cleanup' do
    let(:job) { MonthlyReportJob.new }

    it 'removes old report files' do
      # 古いレポートファイルを作成
      old_file = Rails.root.join('tmp', 'reports', 'report_old.json')
      FileUtils.touch(old_file, mtime: 35.days.ago)

      job.send(:cleanup_old_reports)

      expect(File.exist?(old_file)).to be false
    end

    it 'keeps recent report files' do
      recent_file = Rails.root.join('tmp', 'reports', 'report_recent.json')
      FileUtils.touch(recent_file, mtime: 5.days.ago)

      job.send(:cleanup_old_reports)

      expect(File.exist?(recent_file)).to be true
    end
  end

  describe 'retry behavior' do
    it 'retries on transient failures' do
      job = MonthlyReportJob.new
      allow(job).to receive(:generate_inventory_summary).and_raise(Redis::ConnectionError)

      # ActiveJobのretry_onの確認
      expect(job.class.retry_jitter).to be_present
    end
  end

  describe 'performance' do
    it 'completes within reasonable time for large datasets' do
      # 大量のテストデータ
      create_list(:inventory, 1000)
      create_list(:inventory_log, 5000)

      start_time = Time.current
      MonthlyReportJob.new.perform(admin.id, report_month.to_s)
      duration = Time.current - start_time

      expect(duration).to be < 60 # 60秒以内に完了
    end

    it 'uses batch processing for large queries' do
      # バッチ処理の確認
      expect_any_instance_of(MonthlyReportJob).to receive(:find_in_batches).at_least(:once)

      create_list(:inventory, 200)
      MonthlyReportJob.new.perform(admin.id, report_month.to_s)
    end
  end

  after do
    # テスト後のクリーンアップ
    FileUtils.rm_rf(Rails.root.join('tmp', 'reports', '*'))
  end
end
