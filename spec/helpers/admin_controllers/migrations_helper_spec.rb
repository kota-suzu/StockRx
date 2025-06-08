# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminControllers::MigrationsHelper, type: :helper do
  describe '#status_icon' do
    it 'returns correct icon for each status' do
      expect(helper.status_icon('pending')).to eq('⏳')
      expect(helper.status_icon('running')).to eq('🔄')
      expect(helper.status_icon('completed')).to eq('✅')
      expect(helper.status_icon('failed')).to eq('❌')
      expect(helper.status_icon('rolled_back')).to eq('↩️')
      expect(helper.status_icon('paused')).to eq('⏸️')
      expect(helper.status_icon('cancelled')).to eq('🚫')
      expect(helper.status_icon('unknown')).to eq('❓')
    end
  end

  describe '#humanize_status' do
    it 'returns Japanese status names' do
      expect(helper.humanize_status('pending')).to eq('実行待ち')
      expect(helper.humanize_status('running')).to eq('実行中')
      expect(helper.humanize_status('completed')).to eq('完了')
      expect(helper.humanize_status('failed')).to eq('失敗')
      expect(helper.humanize_status('rolled_back')).to eq('ロールバック済み')
      expect(helper.humanize_status('paused')).to eq('一時停止')
      expect(helper.humanize_status('cancelled')).to eq('キャンセル')
    end
  end

  describe '#status_class' do
    it 'returns appropriate CSS classes' do
      expect(helper.status_class('pending')).to eq('text-muted')
      expect(helper.status_class('running')).to eq('text-info')
      expect(helper.status_class('completed')).to eq('text-success')
      expect(helper.status_class('failed')).to eq('text-danger')
      expect(helper.status_class('rolled_back')).to eq('text-warning')
      expect(helper.status_class('paused')).to eq('text-warning')
      expect(helper.status_class('cancelled')).to eq('text-secondary')
    end
  end

  describe '#format_duration' do
    it 'formats duration correctly' do
      expect(helper.format_duration(nil)).to eq('N/A')
      expect(helper.format_duration(30)).to eq('30秒')
      expect(helper.format_duration(90)).to eq('1分30秒')
      expect(helper.format_duration(3661)).to eq('1時間1分')
    end
  end

  describe '#format_duration_from_now' do
    it 'formats future time duration' do
      future_time = 2.hours.from_now
      expect(helper.format_duration_from_now(future_time)).to include('時間')

      expect(helper.format_duration_from_now(nil)).to eq('N/A')
      expect(helper.format_duration_from_now(1.hour.ago)).to eq('N/A')
    end
  end

  describe '#time_ago_in_words_japanese' do
    it 'formats relative time in Japanese' do
      expect(helper.time_ago_in_words_japanese(30.seconds.ago)).to eq('30秒前')
      expect(helper.time_ago_in_words_japanese(5.minutes.ago)).to eq('5分前')
      expect(helper.time_ago_in_words_japanese(2.hours.ago)).to eq('2時間前')
      expect(helper.time_ago_in_words_japanese(3.days.ago)).to eq('3日前')
      expect(helper.time_ago_in_words_japanese(nil)).to eq('N/A')
    end
  end

  describe '#format_record_count' do
    it 'formats record counts with appropriate units' do
      expect(helper.format_record_count(0)).to eq('0')
      expect(helper.format_record_count(500)).to eq('500')
      expect(helper.format_record_count(1500)).to eq('1.5K')
      expect(helper.format_record_count(2500000)).to eq('2.5M')
      expect(helper.format_record_count(nil)).to eq('0')
    end
  end

  describe '#format_records_per_second' do
    it 'formats processing speed' do
      expect(helper.format_records_per_second(500.5)).to eq('500.5/秒')
      expect(helper.format_records_per_second(1500.0)).to eq('1.5K/秒')
      expect(helper.format_records_per_second(nil)).to eq('N/A')
    end
  end

  describe '#format_percentage' do
    it 'formats percentages' do
      expect(helper.format_percentage(45.678)).to eq('45.7%')
      expect(helper.format_percentage(100.0, precision: 0)).to eq('100%')
      expect(helper.format_percentage(nil)).to eq('0%')
    end
  end

  describe '#progress_bar' do
    it 'generates progress bar HTML' do
      html = helper.progress_bar(75.5)
      expect(html).to include('progress')
      expect(html).to include('75.5%')
      expect(html).to include('width: 75.5%')
    end

    it 'limits percentage to 100%' do
      html = helper.progress_bar(150.0)
      expect(html).to include('width: 100.0%')
    end

    it 'applies appropriate color classes' do
      expect(helper.progress_bar(25)).to include('bg-danger')
      expect(helper.progress_bar(50)).to include('bg-warning')
      expect(helper.progress_bar(80)).to include('bg-success')
    end
  end

  describe '#alert_level_for_metrics' do
    it 'determines alert level based on metrics' do
      expect(helper.alert_level_for_metrics(95, 90, 5)).to eq('danger')
      expect(helper.alert_level_for_metrics(75, 85, 50)).to eq('warning')
      expect(helper.alert_level_for_metrics(50, 60, 500)).to eq('success')
      expect(helper.alert_level_for_metrics(nil, nil, nil)).to eq('success')
    end
  end

  describe '#generate_alert_message' do
    it 'generates appropriate alert messages' do
      message = helper.generate_alert_message(85, 90, 30)
      expect(message).to include('CPU使用率が高い')
      expect(message).to include('メモリ使用率が高い')
      expect(message).to include('処理速度が低下')
    end

    it 'returns nil when no alerts needed' do
      message = helper.generate_alert_message(50, 60, 500)
      expect(message).to be_nil
    end
  end

  describe '#format_config_value' do
    it 'formats different configuration values' do
      expect(helper.format_config_value('batch_size', 1000)).to eq('1,000 レコード/バッチ')
      expect(helper.format_config_value('cpu_threshold', 75)).to eq('75%')
      expect(helper.format_config_value('memory_threshold', 80)).to eq('80%')
      expect(helper.format_config_value('max_retries', 3)).to eq('3 回')
      expect(helper.format_config_value('timeout', 3600)).to eq('3600 秒')
      expect(helper.format_config_value('other', 'value')).to eq('value')
    end

    it 'formats datetime fields' do
      time = Time.parse('2024-01-15 14:30:00')
      expect(helper.format_config_value('started_at', time)).to include('2024/01/15')
    end
  end

  describe '#humanize_phase' do
    it 'returns Japanese phase names' do
      expect(helper.humanize_phase('initialization')).to eq('初期化')
      expect(helper.humanize_phase('schema_change')).to eq('スキーマ変更')
      expect(helper.humanize_phase('data_migration')).to eq('データ移行')
      expect(helper.humanize_phase('index_creation')).to eq('インデックス作成')
      expect(helper.humanize_phase('validation')).to eq('検証')
      expect(helper.humanize_phase('cleanup')).to eq('クリーンアップ')
      expect(helper.humanize_phase('rollback')).to eq('ロールバック')
    end
  end

  describe '#phase_icon' do
    it 'returns appropriate emoji for each phase' do
      expect(helper.phase_icon('initialization')).to eq('🔧')
      expect(helper.phase_icon('schema_change')).to eq('🏗️')
      expect(helper.phase_icon('data_migration')).to eq('📊')
      expect(helper.phase_icon('index_creation')).to eq('🗂️')
      expect(helper.phase_icon('validation')).to eq('✅')
      expect(helper.phase_icon('cleanup')).to eq('🧹')
      expect(helper.phase_icon('rollback')).to eq('↩️')
      expect(helper.phase_icon('unknown')).to eq('📋')
    end
  end

  describe '#dangerous_operation_message' do
    it 'returns appropriate warning messages' do
      rollback_msg = helper.dangerous_operation_message('rollback')
      expect(rollback_msg).to include('ロールバック')
      expect(rollback_msg).to include('元に戻せません')

      cancel_msg = helper.dangerous_operation_message('cancel')
      expect(cancel_msg).to include('キャンセル')
      expect(cancel_msg).to include('不整合')

      force_msg = helper.dangerous_operation_message('force_release')
      expect(force_msg).to include('強制解放')
      expect(force_msg).to include('データ破損')

      default_msg = helper.dangerous_operation_message('unknown')
      expect(default_msg).to eq('この操作を実行しますか？')
    end
  end

  describe '#safe_json_display' do
    it 'safely displays JSON data' do
      data = { key: 'value', number: 42 }
      result = helper.safe_json_display(data)
      expect(result).to include('key')
      expect(result).to include('value')
      expect(result).to include('42')
    end

    it 'truncates long JSON' do
      long_data = { key: 'a' * 200 }
      result = helper.safe_json_display(long_data, max_length: 50)
      expect(result).to include('...')
      expect(result).to include('文字省略')
    end

    it 'handles nil and invalid data' do
      expect(helper.safe_json_display(nil)).to eq('N/A')
    end
  end

  describe 'migration utility methods' do
    let(:admin) { double('Admin', can_execute_migrations?: true) }
    let(:execution) { double('MigrationExecution', can_execute?: true) }

    before do
      allow(helper).to receive(:current_admin).and_return(admin)
    end

    describe '#migration_executable?' do
      it 'checks both execution and admin permissions' do
        expect(helper.migration_executable?(execution)).to be true
      end

      it 'returns false when admin lacks permission' do
        allow(admin).to receive(:can_execute_migrations?).and_return(false)
        expect(helper.migration_executable?(execution)).to be false
      end

      it 'returns false when execution cannot be executed' do
        allow(execution).to receive(:can_execute?).and_return(false)
        expect(helper.migration_executable?(execution)).to be false
      end
    end
  end
end
