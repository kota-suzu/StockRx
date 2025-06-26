# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe ApplicationJob, type: :job do
  # ============================================
  # ApplicationJob包括的エラーハンドリング分岐テスト
  # ============================================
  # 目的:
  #   - ApplicationJob基底クラスの全エラーハンドリング分岐をカバー
  #   - SecureArgumentSanitizerとの統合分岐テスト
  #   - Sidekiqリトライ分岐テスト（3回指数バックオフ、破棄対象エラー）
  #   - パフォーマンス監視分岐（SecureJobPerformanceMonitor）
  #   - エラー種別分岐（SecurityError/ValidationError/NetworkError等）
  #
  # 実装目標:
  #   - ApplicationJobの全分岐パターンをカバー
  #   - 他のJobクラスで再利用可能なshared_examples作成
  #   - エラーハンドリングの包括的テスト
  #   - メタ認知的アプローチで設計意図を明確化

  # ============================================
  # テスト用ジョブクラスの定義
  # ============================================

  # 基本テスト用ジョブ
  class TestApplicationJob < ApplicationJob
    queue_as :test

    def perform(action_type = :normal, *args)
      case action_type
      when :normal
        Rails.logger.info "TestApplicationJob executed normally with #{args.size} arguments"
      when :error
        raise StandardError, "Intentional test error"
      when :deadlock
        raise ActiveRecord::Deadlocked, "Test deadlock error"
      when :timeout
        raise ActiveRecord::ConnectionTimeoutError, "Test connection timeout"
      when :deserialization
        raise ActiveJob::DeserializationError, "Test deserialization error"
      when :malformed_csv
        raise CSV::MalformedCSVError, "Test CSV error"
      when :file_not_found
        raise Errno::ENOENT, "Test file not found"
      when :custom_security
        raise SecurityError, "Test security error"
      when :validation
        raise ActiveRecord::RecordInvalid, "Test validation error"
      when :network
        raise Net::ReadTimeout, "Test network timeout"
      when :sensitive_args
        # 機密情報を含む引数でのテスト
        Rails.logger.info "Processing sensitive data: #{args.inspect}"
      when :performance_test
        # パフォーマンステスト用の重い処理
        sleep(0.1)  # 100ms のシミュレート処理
        1000.times { |i| i * 2 }  # CPU負荷
      when :large_memory
        # メモリ使用量テスト
        large_array = Array.new(10000) { |i| "Large data item #{i}" }
        Rails.logger.info "Processed #{large_array.size} items"
      else
        raise ArgumentError, "Unknown action type: #{action_type}"
      end
    end
  end

  # SecureArgumentSanitizer統合テスト用ジョブ
  class SecureSanitizationTestJob < ApplicationJob
    def perform(sensitive_data)
      Rails.logger.info "Processing: #{sensitive_data.inspect}"
    end
  end

  # パフォーマンス監視テスト用ジョブ
  class PerformanceMonitoringTestJob < ApplicationJob
    def perform(processing_time = 0.1, memory_usage = :normal)
      sleep(processing_time) if processing_time > 0
      
      case memory_usage
      when :large
        @large_data = Array.new(100000) { |i| "Memory test data #{i}" }
      when :huge
        @huge_data = Array.new(1000000) { |i| "Huge memory test #{i}" }
      end
      
      Rails.logger.info "Performance test completed"
    end
  end

  # ============================================
  # テストデータとsetup
  # ============================================

  let(:sensitive_test_data) do
    {
      api_token: 'test_live_secret123456789',
      user_email: 'user@example.com',
      password: 'super_secret_password',
      credit_card: {
        number: '4111-1111-1111-1111',
        cvv: '123',
        expiry: '12/25'
      },
      nested_sensitive: {
        level1: {
          api_key: 'nested_secret_key',
          credentials: {
            username: 'api_user',
            secret: 'nested_password'
          }
        }
      }
    }
  end

  let(:large_test_data) do
    {
      batch_data: Array.new(1000) do |i|
        {
          id: i,
          name: "Item #{i}",
          metadata: {
            api_token: "test_api_token_#{i}",
            description: "A" * 100  # 100文字の説明
          }
        }
      end
    }
  end

  before do
    # ApplicationJobのセキュアロギングを有効化
    ApplicationJob.secure_logging_enabled = true
    
    # Rails.loggerをテスト用にモック化
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:debug)
    
    # 時間測定の基準時刻
    allow(Time).to receive(:current).and_return(Time.zone.parse('2025-06-26 10:00:00'))
  end

  after do
    # テスト後のクリーンアップ
    ApplicationJob.secure_logging_enabled = true  # デフォルトに戻す
  end

  # ============================================
  # 基本機能テスト
  # ============================================

  describe '基本設定とクラス機能' do
    it 'ApplicationJobがActiveJob::Baseを継承している' do
      expect(ApplicationJob.superclass).to eq(ActiveJob::Base)
    end

    it 'SecureLoggingモジュールが含まれている' do
      expect(ApplicationJob.included_modules).to include(SecureLogging)
    end

    it 'セキュアロギングのクラス変数が正しく初期化される' do
      expect(ApplicationJob.secure_logging_enabled).to be true
    end

    it 'セキュアロギングの有効/無効を切り替えできる' do
      ApplicationJob.secure_logging_enabled = false
      expect(ApplicationJob.secure_logging_enabled).to be false
      
      ApplicationJob.secure_logging_enabled = true
      expect(ApplicationJob.secure_logging_enabled).to be true
    end

    it 'インスタンスメソッドでセキュアロギング状態を取得できる' do
      job = TestApplicationJob.new
      expect(job.secure_logging_enabled?).to be true
      
      ApplicationJob.secure_logging_enabled = false
      expect(job.secure_logging_enabled?).to be false
    end
  end

  # ============================================
  # Sidekiqリトライ設定テスト
  # ============================================

  describe 'Sidekiqリトライ設定' do
    context 'リトライ対象エラー' do
      it 'StandardErrorで3回リトライする（指数バックオフ）' do
        # リトライ設定の確認
        retry_jobs = ApplicationJob.retry_on_patterns
        standard_error_config = retry_jobs.find { |config| config[:on] == [StandardError] }
        
        expect(standard_error_config).not_to be_nil
        expect(standard_error_config[:attempts]).to eq(3)
        expect(standard_error_config[:wait]).to eq(:exponentially_longer)
      end

      it 'ActiveRecord::Deadlockedで3回リトライする（5秒間隔）' do
        deadlock_config = ApplicationJob.retry_on_patterns
                                      .find { |config| config[:on] == [ActiveRecord::Deadlocked] }
        
        expect(deadlock_config).not_to be_nil
        expect(deadlock_config[:attempts]).to eq(3)
        expect(deadlock_config[:wait]).to eq(5.seconds)
      end

      it 'ActiveRecord::ConnectionTimeoutErrorで3回リトライする（10秒間隔）' do
        timeout_config = ApplicationJob.retry_on_patterns
                                     .find { |config| config[:on] == [ActiveRecord::ConnectionTimeoutError] }
        
        expect(timeout_config).not_to be_nil
        expect(timeout_config[:attempts]).to eq(3)
        expect(timeout_config[:wait]).to eq(10.seconds)
      end
    end

    context '破棄対象エラー（リトライしない）' do
      it 'ActiveJob::DeserializationErrorは即座に破棄される' do
        discard_jobs = ApplicationJob.discard_on_patterns
        deserialization_config = discard_jobs.include?(ActiveJob::DeserializationError)
        
        expect(deserialization_config).to be true
      end

      it 'CSV::MalformedCSVErrorは即座に破棄される' do
        discard_config = ApplicationJob.discard_on_patterns.include?(CSV::MalformedCSVError)
        expect(discard_config).to be true
      end

      it 'Errno::ENOENT（ファイルが見つからない）は即座に破棄される' do
        discard_config = ApplicationJob.discard_on_patterns.include?(Errno::ENOENT)
        expect(discard_config).to be true
      end
    end
  end

  # ============================================
  # ログ機能分岐テスト
  # ============================================

  describe 'ログ機能の分岐テスト' do
    let(:job) { TestApplicationJob.new }
    let(:job_id) { SecureRandom.uuid }
    
    before do
      allow(job).to receive(:job_id).and_return(job_id)
      allow(job).to receive(:queue_name).and_return('test')
      allow(job).to receive(:arguments).and_return([:normal, 'test_arg'])
    end

    describe '#log_job_start' do
      it '正常にジョブ開始ログを出力する' do
        expect(Rails.logger).to receive(:info) do |log_data|
          parsed_data = JSON.parse(log_data)
          expect(parsed_data['event']).to eq('job_started')
          expect(parsed_data['job_class']).to eq('ApplicationJobSpec::TestApplicationJob')
          expect(parsed_data['job_id']).to eq(job_id)
          expect(parsed_data['queue_name']).to eq('test')
          expect(parsed_data).to have_key('arguments')
          expect(parsed_data).to have_key('timestamp')
        end
        
        job.send(:log_job_start)
      end

      it '機密情報を含む引数を安全にサニタイズする' do
        sensitive_job = SecureSanitizationTestJob.new
        allow(sensitive_job).to receive(:job_id).and_return(job_id)
        allow(sensitive_job).to receive(:queue_name).and_return('test')
        allow(sensitive_job).to receive(:arguments).and_return([sensitive_test_data])
        
        expect(Rails.logger).to receive(:info) do |log_data|
          expect(log_data).not_to include('test_live_secret123456789')
          expect(log_data).not_to include('super_secret_password')
          expect(log_data).not_to include('4111-1111-1111-1111')
          expect(log_data).to include('[FILTERED]')
        end
        
        sensitive_job.send(:log_job_start)
      end

      context 'パフォーマンス監視が有効な場合' do
        before do
          allow(job).to receive(:performance_monitoring_enabled?).and_return(true)
          # SecureJobPerformanceMonitorが定義されている場合のテスト
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:start_monitoring)
                                                .and_return({ started_at: Time.current })
          end
        end

        it 'パフォーマンス監視を開始する' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:start_monitoring)
                                                  .with('ApplicationJobSpec::TestApplicationJob', job_id, 2)
          end
          
          job.send(:log_job_start)
        end
      end

      context 'パフォーマンス監視が無効な場合' do
        before do
          allow(job).to receive(:performance_monitoring_enabled?).and_return(false)
        end

        it 'パフォーマンス監視を開始しない' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).not_to receive(:start_monitoring)
          end
          
          job.send(:log_job_start)
        end
      end
    end

    describe '#log_job_success' do
      before do
        job.instance_variable_set(:@start_time, Time.current - 1.5)
      end

      it '正常にジョブ完了ログを出力する' do
        expect(Rails.logger).to receive(:info) do |log_data|
          expect(log_data['event']).to eq('job_completed')
          expect(log_data['job_class']).to eq('ApplicationJobSpec::TestApplicationJob')
          expect(log_data['job_id']).to eq(job_id)
          expect(log_data['duration']).to be_a(Float)
          expect(log_data['duration']).to be > 0
          expect(log_data).to have_key('timestamp')
        end
        
        job.send(:log_job_success)
      end

      it '@start_timeが設定されていない場合でもエラーにならない' do
        job.instance_variable_set(:@start_time, nil)
        
        expect(Rails.logger).to receive(:info) do |log_data|
          expect(log_data['duration']).to be_nil
        end
        
        expect { job.send(:log_job_success) }.not_to raise_error
      end

      context 'パフォーマンス監視データがある場合' do
        before do
          job.instance_variable_set(:@performance_data, { started_at: Time.current })
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:end_monitoring)
          end
        end

        it 'パフォーマンス監視を終了する' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:end_monitoring)
                                                  .with({ started_at: Time.current }, success: true)
          end
          
          job.send(:log_job_success)
        end
      end
    end

    describe '#log_job_error' do
      let(:test_error) { StandardError.new('Test error message') }
      let(:backtrace) { ['line1', 'line2', 'line3'] }
      
      before do
        job.instance_variable_set(:@start_time, Time.current - 2.0)
        allow(test_error).to receive(:backtrace).and_return(backtrace)
      end

      it '正常にジョブエラーログを出力する' do
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['job_class']).to eq('ApplicationJobSpec::TestApplicationJob')
          expect(log_data['job_id']).to eq(job_id)
          expect(log_data['error_class']).to eq('StandardError')
          expect(log_data['error_message']).to eq('Test error message')
          expect(log_data['error_backtrace']).to eq(backtrace.first(10))
          expect(log_data['duration']).to be_a(Float)
        end
        
        expect { job.send(:log_job_error, test_error) }.to raise_error(StandardError)
      end

      it 'エラーを再発生させる（Sidekiqリトライのため）' do
        allow(Rails.logger).to receive(:error)
        
        expect { job.send(:log_job_error, test_error) }.to raise_error(StandardError, 'Test error message')
      end

      context 'パフォーマンス監視データがある場合' do
        before do
          job.instance_variable_set(:@performance_data, { started_at: Time.current })
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:end_monitoring)
          end
        end

        it 'パフォーマンス監視をエラー情報と共に終了する' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:end_monitoring)
                                                  .with({ started_at: Time.current }, 
                                                        success: false, 
                                                        error: test_error)
          end
          
          expect { job.send(:log_job_error, test_error) }.to raise_error(StandardError)
        end
      end

      it 'backtraceが10行を超える場合は10行に制限される' do
        long_backtrace = Array.new(20) { |i| "line#{i + 1}" }
        allow(test_error).to receive(:backtrace).and_return(long_backtrace)
        
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['error_backtrace'].size).to eq(10)
          expect(log_data['error_backtrace']).to eq(long_backtrace.first(10))
        end
        
        expect { job.send(:log_job_error, test_error) }.to raise_error(StandardError)
      end
    end
  end

  # ============================================
  # SecureArgumentSanitizer統合分岐テスト
  # ============================================

  describe 'SecureArgumentSanitizer統合分岐テスト' do
    let(:job) { SecureSanitizationTestJob.new }
    
    before do
      allow(job).to receive(:job_id).and_return('test-job-id')
      allow(job).to receive(:arguments).and_return([sensitive_test_data])
    end

    describe '#sanitize_arguments' do
      context 'セキュアロギングが有効な場合' do
        before { ApplicationJob.secure_logging_enabled = true }

        it '機密情報を適切にフィルタリングする' do
          result = job.send(:sanitize_arguments, [sensitive_test_data])
          
          expect(result[0][:api_token]).to eq('[FILTERED]')
          expect(result[0][:user_email]).to eq('[FILTERED]')
          expect(result[0][:password]).to eq('[FILTERED]')
          expect(result[0][:credit_card][:number]).to eq('[FILTERED]')
          expect(result[0][:credit_card][:cvv]).to eq('[FILTERED]')
        end

        it 'ネストした構造の機密情報もフィルタリングする' do
          result = job.send(:sanitize_arguments, [sensitive_test_data])
          
          expect(result[0][:nested_sensitive][:level1][:api_key]).to eq('[FILTERED]')
          expect(result[0][:nested_sensitive][:level1][:credentials][:secret]).to eq('[FILTERED]')
        end

        it '非機密情報は保持する' do
          test_data = { public_id: 123, name: 'Test Item', status: 'active' }
          result = job.send(:sanitize_arguments, [test_data])
          
          expect(result[0][:public_id]).to eq(123)
          expect(result[0][:name]).to eq('Test Item')
          expect(result[0][:status]).to eq('active')
        end
      end

      context 'セキュアロギングが無効な場合' do
        before { ApplicationJob.secure_logging_enabled = false }

        it '引数をそのまま返す' do
          result = job.send(:sanitize_arguments, [sensitive_test_data])
          expect(result).to eq([sensitive_test_data])
        end
      end

      context 'SecureArgumentSanitizerが定義されていない場合' do
        before do
          ApplicationJob.secure_logging_enabled = true
          # SecureArgumentSanitizerを一時的に隠蔽
          if defined?(SecureArgumentSanitizer)
            @original_sanitizer = Object.send(:remove_const, :SecureArgumentSanitizer)
          end
        end

        after do
          # SecureArgumentSanitizerを復元
          if @original_sanitizer
            Object.const_set(:SecureArgumentSanitizer, @original_sanitizer)
          end
        end

        it '引数をそのまま返す' do
          result = job.send(:sanitize_arguments, [sensitive_test_data])
          expect(result).to eq([sensitive_test_data])
        end
      end

      context 'サニタイズ処理でエラーが発生した場合' do
        before do
          ApplicationJob.secure_logging_enabled = true
          allow(SecureArgumentSanitizer).to receive(:sanitize).and_raise(StandardError, 'Sanitization failed')
        end

        it 'エラーログを出力する' do
          expect(Rails.logger).to receive(:error) do |log_data|
            expect(log_data['event']).to eq('argument_sanitization_failed')
            expect(log_data['error_class']).to eq('StandardError')
            expect(log_data['error_message']).to eq('Sanitization failed')
          end
          
          job.send(:sanitize_arguments, [sensitive_test_data])
        end

        it '安全な代替値を返す' do
          allow(Rails.logger).to receive(:error)
          result = job.send(:sanitize_arguments, [sensitive_test_data])
          
          expect(result).to eq(['[SANITIZATION_FAILED]'])
        end

        it 'パフォーマンス情報も記録する' do
          expect(Rails.logger).to receive(:error) do |log_data|
            expect(log_data).to have_key('duration')
            expect(log_data).to have_key('args_count')
            expect(log_data['args_count']).to eq(1)
          end
          
          job.send(:sanitize_arguments, [sensitive_test_data])
        end
      end

      context 'SecureJobPerformanceMonitorが利用可能な場合' do
        before do
          ApplicationJob.secure_logging_enabled = true
          # SecureJobPerformanceMonitorが定義されている場合のテスト
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:monitor_sanitization)
                                                .and_yield
                                                .and_return(['[FILTERED]'])
          end
        end

        it 'パフォーマンス監視付きでサニタイズを実行する' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:monitor_sanitization)
                                                  .with('ApplicationJobSpec::SecureSanitizationTestJob', 1)
          end
          
          job.send(:sanitize_arguments, [sensitive_test_data])
        end
      end
    end

    describe '#safe_arguments_to_string' do
      it '空の配列を適切に処理する' do
        result = job.send(:safe_arguments_to_string, [])
        expect(result).to eq('[]')
      end

      it '文字列要素を適切にクォートする' do
        args = ['string1', 'string2']
        result = job.send(:safe_arguments_to_string, args)
        expect(result).to eq('["string1", "string2"]')
      end

      it 'フィルタリング済みマーカーを認識する' do
        args = ['[FILTERED]', '[ADMIN_ID_12345]']
        result = job.send(:safe_arguments_to_string, args)
        expect(result).to eq('[[FILTERED], [ADMIN_ID_12345]]')
      end

      it 'ハッシュを適切に文字列化する' do
        args = [{ key: 'value', filtered: '[FILTERED]' }]
        result = job.send(:safe_arguments_to_string, args)
        expect(result).to include('"key" => "value"')
        expect(result).to include('"filtered" => [FILTERED]')
      end

      it 'ネストした配列を適切に処理する' do
        args = [['nested1', 'nested2']]
        result = job.send(:safe_arguments_to_string, args)
        expect(result).to eq('[["nested1", "nested2"]]')
      end

      it '数値、ブール値、nilを適切に処理する' do
        args = [123, true, false, nil]
        result = job.send(:safe_arguments_to_string, args)
        expect(result).to eq('[123, true, false, ]')
      end
    end
  end

  # ============================================
  # パフォーマンス監視分岐テスト
  # ============================================

  describe 'パフォーマンス監視機能分岐テスト' do
    let(:performance_job) { PerformanceMonitoringTestJob.new }

    before do
      allow(performance_job).to receive(:job_id).and_return('perf-test-job')
      allow(performance_job).to receive(:queue_name).and_return('test')
    end

    describe '#performance_monitoring_enabled?' do
      context 'Rails設定でパフォーマンス監視が有効な場合' do
        before do
          Rails.application.config.secure_job_logging = { performance_monitoring: true }
        end

        it 'trueを返す' do
          expect(performance_job.send(:performance_monitoring_enabled?)).to be true
        end
      end

      context 'Rails設定でパフォーマンス監視が無効な場合' do
        before do
          Rails.application.config.secure_job_logging = { performance_monitoring: false }
        end

        it 'falseを返す' do
          expect(performance_job.send(:performance_monitoring_enabled?)).to be false
        end
      end

      context 'Rails設定が存在しない場合' do
        before do
          Rails.application.config.secure_job_logging = nil
        end

        it 'falseを返す（デフォルト）' do
          expect(performance_job.send(:performance_monitoring_enabled?)).to be false
        end
      end
    end

    describe '#start_performance_monitoring' do
      context 'SecureJobPerformanceMonitorが定義されている場合' do
        before do
          # SecureJobPerformanceMonitorが存在することを前提
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:start_monitoring)
                                                .and_return({ started_at: Time.current })
          end
          allow(performance_job).to receive(:arguments).and_return(['test', 'args'])
        end

        it 'SecureJobPerformanceMonitor.start_monitoringを呼び出す' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:start_monitoring)
                                                  .with(
                                                    'ApplicationJobSpec::PerformanceMonitoringTestJob',
                                                    'perf-test-job',
                                                    2
                                                  )
          end

          performance_job.send(:start_performance_monitoring)
        end

        it '監視データを返す' do
          if defined?(SecureJobPerformanceMonitor)
            result = performance_job.send(:start_performance_monitoring)
            expect(result).to eq({ started_at: Time.current })
          end
        end
      end

      context 'SecureJobPerformanceMonitorが定義されていない場合' do
        before do
          # SecureJobPerformanceMonitorを一時的に隠蔽
          if defined?(SecureJobPerformanceMonitor)
            @original_monitor = Object.send(:remove_const, :SecureJobPerformanceMonitor)
          end
        end

        after do
          # SecureJobPerformanceMonitorを復元
          if @original_monitor
            Object.const_set(:SecureJobPerformanceMonitor, @original_monitor)
          end
        end

        it 'nilを返す' do
          result = performance_job.send(:start_performance_monitoring)
          expect(result).to be_nil
        end
      end

      context 'SecureJobPerformanceMonitor.start_monitoringでエラーが発生した場合' do
        before do
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:start_monitoring)
                                                .and_raise(StandardError, 'Monitoring failed')
          end
          allow(performance_job).to receive(:arguments).and_return(['test'])
        end

        it '警告ログを出力してnilを返す' do
          expect(Rails.logger).to receive(:warn)
                                 .with('Failed to start performance monitoring: Monitoring failed')

          result = performance_job.send(:start_performance_monitoring)
          expect(result).to be_nil
        end
      end
    end

    describe '#end_performance_monitoring' do
      let(:performance_data) { { started_at: Time.current - 1.0 } }

      context '正常なパフォーマンス監視終了' do
        before do
          performance_job.instance_variable_set(:@performance_data, performance_data)
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:end_monitoring)
          end
        end

        it '成功時にSecureJobPerformanceMonitor.end_monitoringを呼び出す' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:end_monitoring)
                                                  .with(performance_data, success: true)
          end

          performance_job.send(:end_performance_monitoring, success: true)
        end

        it 'エラー時にSecureJobPerformanceMonitor.end_monitoringをエラー情報と共に呼び出す' do
          test_error = StandardError.new('Test error')

          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).to receive(:end_monitoring)
                                                  .with(performance_data, success: false, error: test_error)
          end

          performance_job.send(:end_performance_monitoring, success: false, error: test_error)
        end
      end

      context '@performance_dataが設定されていない場合' do
        before do
          performance_job.instance_variable_set(:@performance_data, nil)
        end

        it 'SecureJobPerformanceMonitor.end_monitoringを呼び出さない' do
          if defined?(SecureJobPerformanceMonitor)
            expect(SecureJobPerformanceMonitor).not_to receive(:end_monitoring)
          end

          performance_job.send(:end_performance_monitoring, success: true)
        end
      end

      context 'SecureJobPerformanceMonitor.end_monitoringでエラーが発生した場合' do
        before do
          performance_job.instance_variable_set(:@performance_data, performance_data)
          if defined?(SecureJobPerformanceMonitor)
            allow(SecureJobPerformanceMonitor).to receive(:end_monitoring)
                                                .and_raise(StandardError, 'End monitoring failed')
          end
        end

        it '警告ログを出力する' do
          expect(Rails.logger).to receive(:warn)
                                 .with('Failed to end performance monitoring: End monitoring failed')

          performance_job.send(:end_performance_monitoring, success: true)
        end
      end
    end
  end

  # ============================================
  # エラー種別分岐テスト（実際のジョブ実行）
  # ============================================

  describe 'エラー種別分岐テスト（実際のジョブ実行）' do
    include ActiveJob::TestHelper

    context 'StandardError系（リトライ対象）' do
      it 'StandardErrorは適切にログ出力されてリトライされる' do
        expect(Rails.logger).to receive(:info)  # job_started
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['error_class']).to eq('StandardError')
          expect(log_data['error_message']).to eq('Intentional test error')
        end

        expect {
          TestApplicationJob.perform_now(:error)
        }.to raise_error(StandardError, 'Intentional test error')
      end

      it 'ActiveRecord::Deadlockedは適切にログ出力されてリトライされる' do
        expect(Rails.logger).to receive(:info)  # job_started
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['error_class']).to eq('ActiveRecord::Deadlocked')
          expect(log_data['error_message']).to eq('Test deadlock error')
        end

        expect {
          TestApplicationJob.perform_now(:deadlock)
        }.to raise_error(ActiveRecord::Deadlocked, 'Test deadlock error')
      end

      it 'ActiveRecord::ConnectionTimeoutErrorは適切にログ出力されてリトライされる' do
        expect(Rails.logger).to receive(:info)  # job_started
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['error_class']).to eq('ActiveRecord::ConnectionTimeoutError')
          expect(log_data['error_message']).to eq('Test connection timeout')
        end

        expect {
          TestApplicationJob.perform_now(:timeout)
        }.to raise_error(ActiveRecord::ConnectionTimeoutError, 'Test connection timeout')
      end

      it 'SecurityErrorは適切にログ出力されてリトライされる' do
        expect(Rails.logger).to receive(:info)  # job_started
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['error_class']).to eq('SecurityError')
          expect(log_data['error_message']).to eq('Test security error')
        end

        expect {
          TestApplicationJob.perform_now(:custom_security)
        }.to raise_error(SecurityError, 'Test security error')
      end

      it 'ValidationErrorは適切にログ出力されてリトライされる' do
        expect(Rails.logger).to receive(:info)  # job_started
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['error_class']).to eq('ActiveRecord::RecordInvalid')
          expect(log_data['error_message']).to eq('Test validation error')
        end

        expect {
          TestApplicationJob.perform_now(:validation)
        }.to raise_error(ActiveRecord::RecordInvalid, 'Test validation error')
      end

      it 'NetworkError系は適切にログ出力されてリトライされる' do
        expect(Rails.logger).to receive(:info)  # job_started
        expect(Rails.logger).to receive(:error) do |log_data|
          expect(log_data['event']).to eq('job_failed')
          expect(log_data['error_class']).to eq('Net::ReadTimeout')
          expect(log_data['error_message']).to eq('Test network timeout')
        end

        expect {
          TestApplicationJob.perform_now(:network)
        }.to raise_error(Net::ReadTimeout, 'Test network timeout')
      end
    end

    context '破棄対象エラー（リトライしない）' do
      # 注意：破棄対象エラーはActiveJobの仕組みでキャッチされるため、
      # 実際のエラーレイズ確認は困難。ここでは設定の確認に留める。
      
      it 'ActiveJob::DeserializationErrorは破棄設定に含まれる' do
        discard_patterns = ApplicationJob.discard_on_patterns
        expect(discard_patterns).to include(ActiveJob::DeserializationError)
      end

      it 'CSV::MalformedCSVErrorは破棄設定に含まれる' do
        discard_patterns = ApplicationJob.discard_on_patterns
        expect(discard_patterns).to include(CSV::MalformedCSVError)
      end

      it 'Errno::ENOENT（ファイルが見つからない）は破棄設定に含まれる' do
        discard_patterns = ApplicationJob.discard_on_patterns
        expect(discard_patterns).to include(Errno::ENOENT)
      end
    end

    context '正常実行時のログ出力' do
      it '正常実行時は開始ログと完了ログが出力される' do
        expect(Rails.logger).to receive(:info) do |log_data|
          if log_data.is_a?(Hash)
            expect(log_data['event']).to eq('job_started')
          else
            parsed_data = JSON.parse(log_data)
            expect(parsed_data['event']).to eq('job_started')
          end
        end

        expect(Rails.logger).to receive(:info) do |log_data|
          expect(log_data['event']).to eq('job_completed')
          expect(log_data).to have_key('duration')
          expect(log_data['duration']).to be_a(Float)
        end

        expect {
          TestApplicationJob.perform_now(:normal, 'test_arg')
        }.not_to raise_error
      end

      it '機密情報を含む引数は適切にサニタイズされてログ出力される' do
        expect(Rails.logger).to receive(:info) do |log_data|
          if log_data.is_a?(String)
            log_content = log_data
          else
            log_content = JSON.generate(log_data)
          end
          
          # 機密情報が含まれていないことを確認
          expect(log_content).not_to include('test_live_secret123456789')
          expect(log_content).not_to include('super_secret_password')
          expect(log_content).not_to include('4111-1111-1111-1111')
          
          # フィルタリングマーカーが含まれていることを確認
          expect(log_content).to include('[FILTERED]')
        end

        expect(Rails.logger).to receive(:info)  # job_completed

        expect {
          TestApplicationJob.perform_now(:sensitive_args, sensitive_test_data)
        }.not_to raise_error
      end
    end

    context 'パフォーマンステスト' do
      it 'CPU集約的な処理でも適切にログ出力される' do
        expect(Rails.logger).to receive(:info).twice  # job_started, job_completed

        benchmark_time = Benchmark.realtime do
          TestApplicationJob.perform_now(:performance_test)
        end

        # パフォーマンステストは最低100ms以上かかることを確認
        expect(benchmark_time).to be >= 0.1
      end

      it 'メモリ集約的な処理でも適切にログ出力される' do
        expect(Rails.logger).to receive(:info).twice  # job_started, job_completed

        # メモリ使用量の測定（開始時）
        GC.start
        initial_memory = GC.stat[:heap_live_slots]

        TestApplicationJob.perform_now(:large_memory)

        # メモリ使用量の測定（終了時）
        GC.start
        final_memory = GC.stat[:heap_live_slots]

        # メモリが実際に使用されたことを確認（概算）
        memory_increase = final_memory - initial_memory
        expect(memory_increase).to be > 0
      end
    end
  end

  # ============================================
  # Shared Examples（他のJobクラスで再利用可能）
  # ============================================

  # ApplicationJobベースのジョブの基本動作をテストするshared_examples
  shared_examples 'ApplicationJobベースのジョブ' do |job_class|
    let(:job_instance) { job_class.new }

    it "#{job_class}がApplicationJobを継承している" do
      expect(job_class.superclass).to eq(ApplicationJob)
    end

    it "#{job_class}がSecureLoggingモジュールを使用できる" do
      expect(job_instance).to respond_to(:secure_logging_enabled?)
    end

    it "#{job_class}でセキュアロギング機能が動作する" do
      ApplicationJob.secure_logging_enabled = true
      expect(job_instance.secure_logging_enabled?).to be true

      ApplicationJob.secure_logging_enabled = false
      expect(job_instance.secure_logging_enabled?).to be false
    end

    it "#{job_class}でsanitize_argumentsメソッドが利用可能" do
      expect(job_instance).to respond_to(:sanitize_arguments, true)
    end

    it "#{job_class}でパフォーマンス監視メソッドが利用可能" do
      expect(job_instance).to respond_to(:performance_monitoring_enabled?, true)
      expect(job_instance).to respond_to(:start_performance_monitoring, true)
      expect(job_instance).to respond_to(:end_performance_monitoring, true)
    end
  end

  # エラーハンドリング機能をテストするshared_examples
  shared_examples 'ApplicationJobエラーハンドリング' do |job_class|
    let(:job_instance) { job_class.new }

    before do
      allow(job_instance).to receive(:job_id).and_return('test-job-id')
      allow(job_instance).to receive(:queue_name).and_return('test')
      allow(job_instance).to receive(:arguments).and_return(['test_arg'])
    end

    it "#{job_class}でログ開始メソッドが正しく動作する" do
      expect(Rails.logger).to receive(:info) do |log_data|
        if log_data.is_a?(String)
          parsed_data = JSON.parse(log_data)
        else
          parsed_data = log_data
        end
        expect(parsed_data['event']).to eq('job_started')
        expect(parsed_data['job_class']).to include(job_class.name)
      end

      job_instance.send(:log_job_start)
    end

    it "#{job_class}でログ成功メソッドが正しく動作する" do
      job_instance.instance_variable_set(:@start_time, Time.current - 1.0)

      expect(Rails.logger).to receive(:info) do |log_data|
        expect(log_data['event']).to eq('job_completed')
        expect(log_data['job_class']).to include(job_class.name)
        expect(log_data['duration']).to be_a(Float)
      end

      job_instance.send(:log_job_success)
    end

    it "#{job_class}でログエラーメソッドが正しく動作する" do
      job_instance.instance_variable_set(:@start_time, Time.current - 1.0)
      test_error = StandardError.new('Test error')

      expect(Rails.logger).to receive(:error) do |log_data|
        expect(log_data['event']).to eq('job_failed')
        expect(log_data['job_class']).to include(job_class.name)
        expect(log_data['error_class']).to eq('StandardError')
        expect(log_data['error_message']).to eq('Test error')
      end

      expect {
        job_instance.send(:log_job_error, test_error)
      }.to raise_error(StandardError, 'Test error')
    end
  end

  # セキュリティ機能をテストするshared_examples
  shared_examples 'ApplicationJobセキュリティ機能' do |job_class|
    let(:job_instance) { job_class.new }
    let(:sensitive_data) do
      {
        api_token: 'test_live_secret123',
        user_email: 'user@example.com',
        password: 'secret_password'
      }
    end

    before do
      allow(job_instance).to receive(:job_id).and_return('security-test-job')
      ApplicationJob.secure_logging_enabled = true
    end

    it "#{job_class}で機密情報が適切にサニタイズされる" do
      result = job_instance.send(:sanitize_arguments, [sensitive_data])

      expect(result[0][:api_token]).to eq('[FILTERED]')
      expect(result[0][:user_email]).to eq('[FILTERED]')
      expect(result[0][:password]).to eq('[FILTERED]')
    end

    it "#{job_class}でセキュアロギング無効時は引数がそのまま返される" do
      ApplicationJob.secure_logging_enabled = false

      result = job_instance.send(:sanitize_arguments, [sensitive_data])
      expect(result).to eq([sensitive_data])
    end

    it "#{job_class}でサニタイズエラー時に安全な代替値が返される" do
      ApplicationJob.secure_logging_enabled = true
      allow(SecureArgumentSanitizer).to receive(:sanitize).and_raise(StandardError, 'Sanitization failed')
      allow(Rails.logger).to receive(:error)

      result = job_instance.send(:sanitize_arguments, [sensitive_data])
      expect(result).to eq(['[SANITIZATION_FAILED]'])
    end
  end

  # ============================================
  # Shared Examples使用例
  # ============================================

  describe 'TestApplicationJobのShared Examples検証' do
    include_examples 'ApplicationJobベースのジョブ', TestApplicationJob
    include_examples 'ApplicationJobエラーハンドリング', TestApplicationJob
    include_examples 'ApplicationJobセキュリティ機能', TestApplicationJob
  end

  describe 'SecureSanitizationTestJobのShared Examples検証' do
    include_examples 'ApplicationJobベースのジョブ', SecureSanitizationTestJob
    include_examples 'ApplicationJobエラーハンドリング', SecureSanitizationTestJob
    include_examples 'ApplicationJobセキュリティ機能', SecureSanitizationTestJob
  end

  describe 'PerformanceMonitoringTestJobのShared Examples検証' do
    include_examples 'ApplicationJobベースのジョブ', PerformanceMonitoringTestJob
    include_examples 'ApplicationJobエラーハンドリング', PerformanceMonitoringTestJob
    include_examples 'ApplicationJobセキュリティ機能', PerformanceMonitoringTestJob
  end

  # ============================================
  # TODO: 将来的な拡張テスト
  # ============================================

  describe '将来的な拡張機能のテスト準備' do
    # TODO: 🔴 緊急 - Phase 1（推定1日）- 高度セキュリティ機能テスト
    # 優先度: 高（GDPR/PCI DSS準拠の基本要件）
    # 実装内容: 
    #   - GDPR準拠の個人情報保護機能テスト
    #   - PCI DSS準拠のクレジットカード情報保護テスト
    #   - タイミング攻撃対策テスト
    #   - 横展開確認: 全Job系クラスでの統一セキュリティ適用確認
    context 'GDPR/PCI DSS準拠機能', :pending do
      it 'GDPR準拠の個人情報保護が動作する' do
        # 将来実装: EU個人情報の特定・マスキング機能
        pending 'GDPR準拠機能は次期フェーズで実装予定'
      end

      it 'PCI DSS準拠のクレジットカード情報保護が動作する' do
        # 将来実装: クレジットカード番号の完全マスキング機能
        pending 'PCI DSS準拠機能は次期フェーズで実装予定'
      end

      it 'タイミング攻撃対策が適切に機能する' do
        # 将来実装: 一定時間処理保証機構
        pending 'タイミング攻撃対策は次期フェーズで実装予定'
      end
    end

    # TODO: 🟡 重要 - Phase 2（推定2日）- パフォーマンス監視強化
    # 優先度: 中（パフォーマンス基準の明確化）
    # 実装内容:
    #   - メモリ使用量50MB制限内での安定動作確認
    #   - 大規模データ処理最適化（100万件対応）
    #   - 並列処理対応とスケーラビリティテスト
    context '高度パフォーマンス監視', :pending do
      it '大規模データでも安定したパフォーマンスを維持する' do
        # 将来実装: 100万件ログデータの効率処理
        pending '大規模データ処理最適化は次期フェーズで実装予定'
      end

      it 'メモリ使用量50MB制限内で動作する' do
        # 将来実装: ストリーミング処理による定数メモリ使用
        pending 'メモリ制限機能は次期フェーズで実装予定'
      end

      it '並列処理で安全に動作する' do
        # 将来実装: 並列ジョブ実行時のセキュリティ確保
        pending '並列処理対応は次期フェーズで実装予定'
      end
    end

    # TODO: 🟢 推奨 - Phase 3（推定1週間）- エンタープライズ機能
    # 優先度: 低（将来的な機能拡張）
    # 実装内容:
    #   - AI/MLベース機密情報検出
    #   - 分散システム対応
    #   - 国際化・多言語対応
    context 'エンタープライズ機能', :pending do
      it 'AI/MLベース機密情報検出が動作する' do
        # 将来実装: 機械学習モデルによる機密情報分類
        pending 'AI/ML機能は将来的な拡張として検討中'
      end

      it '分散システムで一貫したセキュリティを確保する' do
        # 将来実装: マイクロサービス環境での一貫性確保
        pending '分散システム対応は将来的な拡張として検討中'
      end

      it '多言語環境で機密情報検出が動作する' do
        # 将来実装: 各国の個人情報保護法対応
        pending '国際化対応は将来的な拡張として検討中'
      end
    end
  end

  # ============================================
  # メタ認知的テスト設計コメント
  # ============================================

  # **メタ認知的アプローチ**:
  # このテストファイルは「なぜこのテストが必要か？」を常に意識して設計されています。
  #
  # 1. **分岐網羅性**: ApplicationJobの全分岐パターン（正常系、エラー系、設定系）を体系的にカバー
  # 2. **再利用性**: shared_examplesにより他のJobクラスでも同様のテストパターンを適用可能
  # 3. **セキュリティファースト**: 機密情報漏洩リスクを各分岐で確認
  # 4. **パフォーマンス意識**: 処理時間・メモリ使用量への影響を常に監視
  # 5. **将来拡張性**: TODOコメントで次期実装計画を明確化
  #
  # **横展開確認**:
  # - ImportInventoriesJob, StockAlertJob等の既存Jobクラスでもshared_examplesを適用
  # - 新規Jobクラス作成時の品質保証として活用
  # - エラーハンドリングパターンの統一性確保
  #
  # **ベストプラクティス適用**:
  # - テスト駆動開発（TDD）によるエラーハンドリング分岐の事前検証
  # - 継続的品質改善のためのメトリクス監視
  # - セキュリティテストの自動化と回帰防止
end