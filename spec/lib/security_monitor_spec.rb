# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SecurityMonitor do
  # CLAUDE.md準拠: セキュリティ監視システムの包括的テスト
  # メタ認知: セキュリティ機能は障害が許されないため最高水準のテスト品質が必要
  # 横展開: 他のセキュリティ関連クラスでも同様の厳密なテストパターン適用

  let(:monitor) { described_class.instance }
  let(:mock_redis) { instance_double(Redis) }
  let(:client_ip) { '192.168.1.100' }
  let(:user_agent) { 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36' }
  let(:mock_request) do
    instance_double(ActionDispatch::Request,
      remote_ip: client_ip,
      user_agent: user_agent,
      path: '/admin/login',
      query_string: '',
      request_method: 'POST',
      referer: 'https://example.com',
      content_length: 1024,
      body: StringIO.new('{"email":"test@example.com","password":"secret"}'),
      env: {
        'HTTP_X_FORWARDED_FOR' => nil,
        'HTTP_X_REAL_IP' => nil
      }
    )
  end

  before do
    allow(monitor).to receive(:get_redis_connection).and_return(mock_redis)
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(mock_redis).to receive(:incr).and_return(1)
    allow(mock_redis).to receive(:expire)
    allow(mock_redis).to receive(:del)
    allow(mock_redis).to receive(:setex)
    allow(mock_redis).to receive(:keys).and_return([])
    allow(mock_redis).to receive(:exists?).and_return(false)
  end

  # ============================================
  # analyze_request メソッドのテスト
  # ============================================

  describe '#analyze_request' do
    context '正常なリクエスト' do
      it '異常パターンを検出しない' do
        allow(monitor).to receive(:rapid_requests_detected?).and_return(false)
        allow(monitor).to receive(:suspicious_user_agent?).and_return(false)
        allow(monitor).to receive(:path_traversal_attempt?).and_return(false)
        allow(monitor).to receive(:sql_injection_attempt?).and_return(false)
        allow(monitor).to receive(:large_request?).and_return(false)

        patterns = monitor.analyze_request(mock_request)

        expect(patterns).to be_empty
      end

      it 'リクエスト統計を更新する' do
        expect(monitor).to receive(:update_request_statistics)
          .with(client_ip, user_agent, '/admin/login')

        monitor.analyze_request(mock_request)
      end
    end

    context '異常なリクエスト' do
      it '複数の異常パターンを検出する' do
        allow(monitor).to receive(:rapid_requests_detected?).and_return(true)
        allow(monitor).to receive(:suspicious_user_agent?).and_return(true)
        allow(monitor).to receive(:path_traversal_attempt?).and_return(false)
        allow(monitor).to receive(:sql_injection_attempt?).and_return(false)
        allow(monitor).to receive(:large_request?).and_return(false)

        expect(monitor).to receive(:handle_suspicious_activity)
          .with(client_ip, [ :rapid_requests, :suspicious_user_agent ], anything)

        patterns = monitor.analyze_request(mock_request)

        expect(patterns).to include(:rapid_requests, :suspicious_user_agent)
      end

      it 'クリティカルなパターンを検出する' do
        allow(monitor).to receive(:rapid_requests_detected?).and_return(false)
        allow(monitor).to receive(:suspicious_user_agent?).and_return(false)
        allow(monitor).to receive(:path_traversal_attempt?).and_return(true)
        allow(monitor).to receive(:sql_injection_attempt?).and_return(true)
        allow(monitor).to receive(:large_request?).and_return(false)

        patterns = monitor.analyze_request(mock_request)

        expect(patterns).to include(:path_traversal, :sql_injection)
      end
    end

    context 'クラスメソッドから呼び出し' do
      it 'インスタンスメソッドに委譲する' do
        expect(monitor).to receive(:analyze_request)
          .with(mock_request, nil)

        described_class.analyze_request(mock_request)
      end
    end
  end

  # ============================================
  # track_login_attempt メソッドのテスト
  # ============================================

  describe '#track_login_attempt' do
    let(:email) { 'test@example.com' }

    context 'ログイン成功時' do
      it '失敗カウントをリセットする' do
        expect(mock_redis).to receive(:del)
          .with("failed_logins:#{client_ip}:#{email}")

        monitor.track_login_attempt(client_ip, email, success: true, user_agent: user_agent)
      end

      it '成功イベントをログに記録する' do
        expect(monitor).to receive(:log_security_event)
          .with(:successful_login, hash_including(
            ip_address: client_ip,
            email: email,
            user_agent: user_agent
          ))

        monitor.track_login_attempt(client_ip, email, success: true, user_agent: user_agent)
      end
    end

    context 'ログイン失敗時' do
      it '失敗カウントを増加させる' do
        expect(mock_redis).to receive(:incr)
          .with("failed_logins:#{client_ip}:#{email}")
          .and_return(3)

        expect(mock_redis).to receive(:expire)
          .with("failed_logins:#{client_ip}:#{email}", 3600)

        monitor.track_login_attempt(client_ip, email, success: false, user_agent: user_agent)
      end

      it '失敗イベントをログに記録する' do
        allow(mock_redis).to receive(:incr).and_return(3)

        expect(monitor).to receive(:log_security_event)
          .with(:failed_login, hash_including(
            ip_address: client_ip,
            email: email,
            failed_count: 3,
            user_agent: user_agent
          ))

        monitor.track_login_attempt(client_ip, email, success: false, user_agent: user_agent)
      end

      it 'ブルートフォース攻撃を検出する' do
        allow(mock_redis).to receive(:incr).and_return(6) # 閾値を超える

        expect(monitor).to receive(:handle_brute_force_attack)
          .with(client_ip, email, 6, user_agent)

        monitor.track_login_attempt(client_ip, email, success: false, user_agent: user_agent)
      end
    end

    context 'Redis接続なし' do
      before do
        allow(monitor).to receive(:get_redis_connection).and_return(nil)
      end

      it 'エラーなく処理を完了する' do
        expect {
          monitor.track_login_attempt(client_ip, email, success: false)
        }.not_to raise_error
      end
    end

    context 'クラスメソッドから呼び出し' do
      it 'インスタンスメソッドに委譲する' do
        expect(monitor).to receive(:track_login_attempt)
          .with(client_ip, email, success: true, user_agent: user_agent)

        described_class.track_login_attempt(client_ip, email, success: true, user_agent: user_agent)
      end
    end
  end

  # ============================================
  # ブロック機能のテスト
  # ============================================

  describe 'IP blocking functionality' do
    describe '#is_blocked?' do
      context 'ブロックされているIP' do
        it 'trueを返す' do
          allow(mock_redis).to receive(:keys)
            .with("blocked:*:#{client_ip}")
            .and_return([ "blocked:brute_force:#{client_ip}" ])

          allow(mock_redis).to receive(:exists?)
            .with("blocked:brute_force:#{client_ip}")
            .and_return(true)

          expect(monitor.is_blocked?(client_ip)).to be true
        end
      end

      context 'ブロックされていないIP' do
        it 'falseを返す' do
          allow(mock_redis).to receive(:keys)
            .with("blocked:*:#{client_ip}")
            .and_return([])

          expect(monitor.is_blocked?(client_ip)).to be false
        end
      end

      context 'Redis接続なし' do
        before do
          allow(monitor).to receive(:get_redis_connection).and_return(nil)
        end

        it 'falseを返す' do
          expect(monitor.is_blocked?(client_ip)).to be false
        end
      end

      context 'クラスメソッドから呼び出し' do
        it 'インスタンスメソッドに委譲する' do
          expect(monitor).to receive(:is_blocked?).with(client_ip)

          described_class.is_blocked?(client_ip)
        end
      end
    end

    describe '#block_ip' do
      it 'IPをブロックする' do
        block_data = {
          blocked_at: Time.current.iso8601,
          reason: :brute_force,
          duration_minutes: 120
        }

        expect(mock_redis).to receive(:setex)
          .with("blocked:brute_force:#{client_ip}", 7200, hash_including(:blocked_at, :reason, :duration_minutes))

        monitor.block_ip(client_ip, :brute_force)
      end

      it 'ブロック通知を送信する' do
        expect(monitor).to receive(:notify_security_event)
          .with(:ip_blocked, hash_including(
            ip_address: client_ip,
            reason: :brute_force,
            duration_minutes: 120
          ))

        monitor.block_ip(client_ip, :brute_force)
      end

      it 'ログにブロック情報を記録する' do
        expect(Rails.logger).to receive(:warn)
          .with(/IP blocked: #{Regexp.escape(client_ip)}/)

        monitor.block_ip(client_ip, :brute_force)
      end

      it 'カスタム期間でブロックする' do
        expect(mock_redis).to receive(:setex)
          .with("blocked:custom_reason:#{client_ip}", 1800, anything) # 30分

        monitor.block_ip(client_ip, :custom_reason, 30)
      end

      context 'Redis接続なし' do
        before do
          allow(monitor).to receive(:get_redis_connection).and_return(nil)
        end

        it 'エラーなく処理を完了する' do
          expect {
            monitor.block_ip(client_ip, :brute_force)
          }.not_to raise_error
        end
      end
    end
  end

  # ============================================
  # 異常検出ロジックのテスト
  # ============================================

  describe 'detection logic' do
    describe '#rapid_requests_detected?' do
      it '閾値を超えたリクエストを検出する' do
        allow(mock_redis).to receive(:incr)
          .with("request_count:#{client_ip}")
          .and_return(101) # 閾値100を超える

        expect(monitor.send(:rapid_requests_detected?, client_ip)).to be true
      end

      it '閾値以下のリクエストは検出しない' do
        allow(mock_redis).to receive(:incr)
          .with("request_count:#{client_ip}")
          .and_return(50)

        expect(monitor.send(:rapid_requests_detected?, client_ip)).to be false
      end

      it '初回リクエストに有効期限を設定する' do
        allow(mock_redis).to receive(:incr).and_return(1)

        expect(mock_redis).to receive(:expire)
          .with("request_count:#{client_ip}", 60)

        monitor.send(:rapid_requests_detected?, client_ip)
      end
    end

    describe '#suspicious_user_agent?' do
      it '空のUser-Agentを検出する' do
        expect(monitor.send(:suspicious_user_agent?, nil)).to be true
        expect(monitor.send(:suspicious_user_agent?, '')).to be true
      end

      it '攻撃ツールのUser-Agentを検出する' do
        suspicious_agents = [
          'sqlmap/1.0',
          'Nikto/2.1.6',
          'python-requests/2.25.1 (bot)',
          'Mozilla/5.0 <script>alert(1)</script>',
          "' OR 1=1--"
        ]

        suspicious_agents.each do |agent|
          expect(monitor.send(:suspicious_user_agent?, agent)).to be true
        end
      end

      it '正常なUser-Agentは検出しない' do
        normal_agents = [
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15'
        ]

        normal_agents.each do |agent|
          expect(monitor.send(:suspicious_user_agent?, agent)).to be false
        end
      end
    end

    describe '#path_traversal_attempt?' do
      it 'パストラバーサル攻撃を検出する' do
        malicious_paths = [
          '/admin/../../../etc/passwd',
          '/files/%2e%2e%2fetc%2fpasswd',
          '/admin/../../windows/system32',
          '/config.conf',
          '/etc/shadow'
        ]

        malicious_paths.each do |path|
          expect(monitor.send(:path_traversal_attempt?, path)).to be true
        end
      end

      it '正常なパスは検出しない' do
        normal_paths = [
          '/admin/dashboard',
          '/api/v1/inventories',
          '/users/profile'
        ]

        normal_paths.each do |path|
          expect(monitor.send(:path_traversal_attempt?, path)).to be false
        end
      end
    end

    describe '#sql_injection_attempt?' do
      let(:mock_request_with_payload) do
        instance_double(ActionDispatch::Request,
          query_string: query,
          path: path,
          body: StringIO.new(body)
        )
      end

      context 'SQLインジェクション攻撃を検出する' do
        let(:query) { "id=1' OR 1=1--" }
        let(:path) { '/search' }
        let(:body) { '{"name":"test"}' }

        before do
          allow(monitor).to receive(:extract_request_body).and_return(body)
        end

        it 'クエリパラメータの攻撃を検出する' do
          expect(monitor.send(:sql_injection_attempt?, mock_request_with_payload)).to be true
        end
      end

      context 'UNION攻撃を検出する' do
        let(:query) { "id=1 UNION SELECT password FROM users" }
        let(:path) { '/api/items' }
        let(:body) { '' }

        before do
          allow(monitor).to receive(:extract_request_body).and_return(body)
        end

        it 'UNION攻撃を検出する' do
          expect(monitor.send(:sql_injection_attempt?, mock_request_with_payload)).to be true
        end
      end

      context '正常なリクエスト' do
        let(:query) { 'name=product&category=electronics' }
        let(:path) { '/products' }
        let(:body) { '{"email":"user@example.com"}' }

        before do
          allow(monitor).to receive(:extract_request_body).and_return(body)
        end

        it '正常なリクエストは検出しない' do
          expect(monitor.send(:sql_injection_attempt?, mock_request_with_payload)).to be false
        end
      end
    end

    describe '#large_request?' do
      it '大きなリクエストを検出する' do
        large_request = instance_double(ActionDispatch::Request,
          content_length: 15.megabytes # 閾値10MBを超える
        )

        expect(monitor.send(:large_request?, large_request)).to be true
      end

      it '正常なサイズのリクエストは検出しない' do
        normal_request = instance_double(ActionDispatch::Request,
          content_length: 1.megabyte
        )

        expect(monitor.send(:large_request?, normal_request)).to be false
      end

      it 'content_lengthがない場合は検出しない' do
        no_length_request = instance_double(ActionDispatch::Request,
          content_length: nil
        )

        expect(monitor.send(:large_request?, no_length_request)).to be false
      end
    end
  end

  # ============================================
  # 対応処理のテスト
  # ============================================

  describe 'response handling' do
    describe '#handle_suspicious_activity' do
      let(:patterns) { [ :rapid_requests, :suspicious_user_agent ] }
      let(:request_details) do
        {
          request_path: '/admin/login',
          user_agent: user_agent,
          referer: 'https://example.com',
          request_method: 'POST'
        }
      end

      context 'クリティカルな脅威' do
        it 'IPをブロックする' do
          critical_patterns = [ :sql_injection ]

          expect(monitor).to receive(:block_ip)
            .with(client_ip, :critical_threat, described_class::BLOCK_DURATIONS[:sql_injection])

          monitor.send(:handle_suspicious_activity, client_ip, critical_patterns, request_details)
        end
      end

      context '高リスクな脅威' do
        it 'IPをブロックする' do
          high_patterns = [ :rapid_requests, :suspicious_user_agent ]

          expect(monitor).to receive(:block_ip)
            .with(client_ip, :high_threat, described_class::BLOCK_DURATIONS[:brute_force])

          monitor.send(:handle_suspicious_activity, client_ip, high_patterns, request_details)
        end
      end

      context '中リスクな脅威' do
        it 'ログ記録のみ行う' do
          medium_patterns = [ :rapid_requests ]

          expect(monitor).to receive(:log_security_event)
            .with(:suspicious_activity, hash_including(
              ip_address: client_ip,
              patterns: medium_patterns,
              severity: :medium
            ))

          expect(monitor).not_to receive(:block_ip)

          monitor.send(:handle_suspicious_activity, client_ip, medium_patterns, request_details)
        end
      end

      it 'セキュリティ通知を送信する' do
        expect(monitor).to receive(:notify_security_event)
          .with(:suspicious_activity_detected, hash_including(
            ip_address: client_ip,
            patterns: patterns,
            severity: :high,
            action_taken: 'blocked'
          ))

        monitor.send(:handle_suspicious_activity, client_ip, patterns, request_details)
      end
    end

    describe '#handle_brute_force_attack' do
      let(:email) { 'test@example.com' }
      let(:failed_count) { 7 }

      it 'IPをブロックする' do
        expect(monitor).to receive(:block_ip)
          .with(client_ip, :brute_force, described_class::BLOCK_DURATIONS[:brute_force])

        monitor.send(:handle_brute_force_attack, client_ip, email, failed_count, user_agent)
      end

      it 'ブルートフォース通知を送信する' do
        expect(monitor).to receive(:notify_security_event)
          .with(:brute_force_detected, hash_including(
            ip_address: client_ip,
            email: email,
            failed_count: failed_count,
            user_agent: user_agent,
            blocked_duration: described_class::BLOCK_DURATIONS[:brute_force]
          ))

        monitor.send(:handle_brute_force_attack, client_ip, email, failed_count, user_agent)
      end
    end

    describe '#determine_severity' do
      it 'クリティカルパターンでクリティカル判定' do
        patterns = [ :sql_injection, :rapid_requests ]
        expect(monitor.send(:determine_severity, patterns)).to eq(:critical)
      end

      it 'パストラバーサルでクリティカル判定' do
        patterns = [ :path_traversal ]
        expect(monitor.send(:determine_severity, patterns)).to eq(:critical)
      end

      it '複数パターンで高リスク判定' do
        patterns = [ :rapid_requests, :suspicious_user_agent ]
        expect(monitor.send(:determine_severity, patterns)).to eq(:high)
      end

      it '単一パターンで中リスク判定' do
        patterns = [ :rapid_requests ]
        expect(monitor.send(:determine_severity, patterns)).to eq(:medium)
      end
    end
  end

  # ============================================
  # ユーティリティメソッドのテスト
  # ============================================

  describe 'utility methods' do
    describe '#extract_client_ip' do
      it 'X-Forwarded-Forヘッダーから取得する' do
        request_with_proxy = instance_double(ActionDispatch::Request,
          env: {
            'HTTP_X_FORWARDED_FOR' => '203.0.113.1, 192.168.1.1',
            'HTTP_X_REAL_IP' => '10.0.0.1'
          },
          remote_ip: '127.0.0.1'
        )

        expect(monitor.send(:extract_client_ip, request_with_proxy)).to eq('203.0.113.1')
      end

      it 'X-Real-IPヘッダーから取得する' do
        request_with_real_ip = instance_double(ActionDispatch::Request,
          env: {
            'HTTP_X_FORWARDED_FOR' => nil,
            'HTTP_X_REAL_IP' => '203.0.113.2'
          },
          remote_ip: '127.0.0.1'
        )

        expect(monitor.send(:extract_client_ip, request_with_real_ip)).to eq('203.0.113.2')
      end

      it 'remote_ipから取得する' do
        request_direct = instance_double(ActionDispatch::Request,
          env: {
            'HTTP_X_FORWARDED_FOR' => nil,
            'HTTP_X_REAL_IP' => nil
          },
          remote_ip: '203.0.113.3'
        )

        expect(monitor.send(:extract_client_ip, request_direct)).to eq('203.0.113.3')
      end
    end

    describe '#extract_request_body' do
      it 'リクエストボディを読み取る' do
        body_content = '{"test": "data"}'
        request_with_body = instance_double(ActionDispatch::Request,
          content_length: body_content.length,
          body: StringIO.new(body_content)
        )

        result = monitor.send(:extract_request_body, request_with_body)
        expect(result).to eq(body_content)
      end

      it 'content_lengthがない場合はnilを返す' do
        request_no_length = instance_double(ActionDispatch::Request,
          content_length: nil
        )

        result = monitor.send(:extract_request_body, request_no_length)
        expect(result).to be_nil
      end

      it '大きすぎるリクエストはスキップする' do
        request_too_large = instance_double(ActionDispatch::Request,
          content_length: 2.megabytes
        )

        result = monitor.send(:extract_request_body, request_too_large)
        expect(result).to be_nil
      end

      it 'ボディ読み取りエラーを処理する' do
        failing_body = instance_double(StringIO)
        allow(failing_body).to receive(:read).and_raise(StandardError, "Read error")
        allow(failing_body).to receive(:rewind)

        request_with_error = instance_double(ActionDispatch::Request,
          content_length: 100,
          body: failing_body
        )

        expect(Rails.logger).to receive(:warn).with(/Failed to read request body/)

        result = monitor.send(:extract_request_body, request_with_error)
        expect(result).to be_nil
      end
    end

    describe '#update_request_statistics' do
      it '時間別統計を更新する' do
        current_hour = Time.current.strftime('%Y%m%d%H')
        hour_key = "stats:requests:#{current_hour}"

        expect(mock_redis).to receive(:incr).with(hour_key)
        expect(mock_redis).to receive(:expire).with(hour_key, 25.hours.to_i)

        monitor.send(:update_request_statistics, client_ip, user_agent, '/test')
      end

      it 'IP別統計を更新する' do
        current_date = Date.current.strftime('%Y%m%d')
        ip_key = "stats:ip:#{client_ip}:#{current_date}"

        expect(mock_redis).to receive(:incr).with(ip_key)
        expect(mock_redis).to receive(:expire).with(ip_key, 2.days.to_i)

        monitor.send(:update_request_statistics, client_ip, user_agent, '/test')
      end
    end

    describe '#get_redis_connection' do
      context 'テスト環境' do
        before do
          allow(Rails.env).to receive(:test?).and_return(true)
        end

        it 'Redis利用可能時は接続を返す' do
          mock_redis_instance = instance_double(Redis)
          allow(Redis).to receive(:current).and_return(mock_redis_instance)
          allow(mock_redis_instance).to receive(:ping)

          result = monitor.send(:get_redis_connection)
          expect(result).to eq(mock_redis_instance)
        end

        it 'Redis利用不可時はnilを返す' do
          allow(Redis).to receive(:current).and_raise(Redis::CannotConnectError)

          expect(Rails.logger).to receive(:warn).with(/Redis not available/)

          result = monitor.send(:get_redis_connection)
          expect(result).to be_nil
        end

        it 'Redisが未定義の場合はnilを返す' do
          hide_const('Redis')

          result = monitor.send(:get_redis_connection)
          expect(result).to be_nil
        end
      end

      context '非テスト環境' do
        before do
          allow(Rails.env).to receive(:test?).and_return(false)
        end

        it 'Sidekiq経由でRedis接続を取得する' do
          mock_sidekiq_redis = instance_double(Redis)
          mock_pool = instance_double('Sidekiq::RedisPool')

          stub_const('Sidekiq', double)
          allow(Sidekiq).to receive(:redis_pool).and_return(mock_pool)
          allow(Sidekiq).to receive(:redis).and_yield(mock_sidekiq_redis)

          result = monitor.send(:get_redis_connection)
          expect(result).to eq(mock_sidekiq_redis)
        end

        it 'Sidekiq利用不可時はRedis.currentを使用' do
          mock_redis_instance = instance_double(Redis)
          allow(Redis).to receive(:current).and_return(mock_redis_instance)

          result = monitor.send(:get_redis_connection)
          expect(result).to eq(mock_redis_instance)
        end

        it 'Redis接続失敗時はnilを返す' do
          allow(Redis).to receive(:current).and_raise(Redis::CannotConnectError)

          expect(Rails.logger).to receive(:warn).with(/Redis connection failed/)

          result = monitor.send(:get_redis_connection)
          expect(result).to be_nil
        end
      end
    end
  end

  # ============================================
  # ログ・通知機能のテスト
  # ============================================

  describe 'logging and notification' do
    describe '#log_security_event' do
      it 'セキュリティイベントをJSONでログ出力する' do
        event_details = {
          ip_address: client_ip,
          user_agent: user_agent
        }

        expected_log = {
          event: 'security_test_event',
          timestamp: kind_of(String),
          ip_address: client_ip,
          user_agent: user_agent
        }

        expect(Rails.logger).to receive(:info) do |log_data|
          parsed_log = JSON.parse(log_data)
          expect(parsed_log).to include('event' => 'security_test_event')
          expect(parsed_log).to include('ip_address' => client_ip)
          expect(parsed_log).to include('user_agent' => user_agent)
          expect(parsed_log).to have_key('timestamp')
        end

        monitor.send(:log_security_event, :test_event, event_details)
      end
    end

    describe '#notify_security_event' do
      it 'セキュリティ通知をログ出力する' do
        notification_details = {
          ip_address: client_ip,
          severity: :high
        }

        expect(Rails.logger).to receive(:warn) do |log_data|
          parsed_log = JSON.parse(log_data)
          expect(parsed_log).to include('event' => 'security_notification')
          expect(parsed_log).to include('notification_type' => 'ip_blocked')
          expect(parsed_log).to include('ip_address' => client_ip)
          expect(parsed_log).to include('severity' => 'high')
          expect(parsed_log).to have_key('timestamp')
        end

        monitor.send(:notify_security_event, :ip_blocked, notification_details)
      end
    end
  end

  # ============================================
  # エッジケース・統合テスト
  # ============================================

  describe 'edge cases' do
    context 'Redis接続が途中で失われる' do
      it 'エラーなく処理を継続する' do
        allow(monitor).to receive(:get_redis_connection).and_return(nil)

        expect {
          monitor.analyze_request(mock_request)
          monitor.track_login_attempt(client_ip, 'test@example.com', success: false)
          monitor.is_blocked?(client_ip)
        }.not_to raise_error
      end
    end

    context '異常なリクエストデータ' do
      it 'nil値を安全に処理する' do
        broken_request = instance_double(ActionDispatch::Request,
          remote_ip: nil,
          user_agent: nil,
          path: nil,
          query_string: nil,
          request_method: nil,
          referer: nil,
          content_length: nil,
          body: nil,
          env: {}
        )

        expect {
          monitor.analyze_request(broken_request)
        }.not_to raise_error
      end
    end

    context 'システムリソース不足' do
      it 'メモリ不足でも基本機能を維持する' do
        allow(monitor).to receive(:extract_request_body).and_raise(NoMemoryError)

        expect {
          monitor.analyze_request(mock_request)
        }.not_to raise_error
      end
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it '大量のリクエスト分析が高速に実行される' do
      start_time = Time.current

      100.times do
        monitor.analyze_request(mock_request)
      end

      elapsed_time = (Time.current - start_time) * 1000
      expect(elapsed_time).to be < 500 # 500ms以内
    end

    it 'ログイン試行追跡が高速に実行される' do
      start_time = Time.current

      100.times do |i|
        monitor.track_login_attempt("192.168.1.#{i}", 'test@example.com', success: false)
      end

      elapsed_time = (Time.current - start_time) * 1000
      expect(elapsed_time).to be < 300 # 300ms以内
    end
  end

  # ============================================
  # セキュリティ統合テスト
  # ============================================

  describe 'security integration' do
    it '実際の攻撃シナリオを適切に処理する' do
      # ブルートフォース攻撃のシミュレーション
      attack_ip = '203.0.113.100'
      target_email = 'admin@example.com'

      # 複数回のログイン失敗
      6.times do |i|
        allow(mock_redis).to receive(:incr)
          .with("failed_logins:#{attack_ip}:#{target_email}")
          .and_return(i + 1)

        monitor.track_login_attempt(attack_ip, target_email, success: false)
      end

      # 最後の試行でブルートフォース検出・ブロックされることを確認
      expect(monitor).to have_received(:notify_security_event)
        .with(:brute_force_detected, anything)
    end

    it 'SQLインジェクション攻撃を即座にブロックする' do
      malicious_request = instance_double(ActionDispatch::Request,
        remote_ip: '203.0.113.200',
        user_agent: 'sqlmap/1.0',
        path: "/admin/users?id=1' OR 1=1--",
        query_string: "id=1' OR 1=1--",
        request_method: 'GET',
        referer: nil,
        content_length: 0,
        body: StringIO.new(''),
        env: {}
      )

      allow(monitor).to receive(:extract_request_body).and_return('')

      patterns = monitor.analyze_request(malicious_request)

      expect(patterns).to include(:sql_injection, :suspicious_user_agent)
      expect(monitor).to have_received(:notify_security_event)
        .with(:suspicious_activity_detected, hash_including(severity: :critical))
    end
  end
end
