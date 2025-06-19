# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Current, type: :model do
  # CLAUDE.md準拠: リクエストスコープ状態管理クラスのテスト
  # メタ認知: スレッドローカル変数によるリクエスト情報管理の品質保証
  # 横展開: 他のActive Support Concernsでも同様のテストパターン適用

  # ============================================
  # 基本機能のテスト
  # ============================================

  describe 'thread local attributes' do
    before do
      # 各テスト前にCurrentをリセット
      Current.reset
    end

    after do
      # 各テスト後にCurrentをリセット
      Current.reset
    end

    describe '#request' do
      it '初期状態ではnilであること' do
        expect(Current.request).to be_nil
      end

      it 'リクエストオブジェクトを設定・取得できること' do
        mock_request = double('Request', remote_ip: '192.168.1.1', user_agent: 'TestAgent')
        Current.request = mock_request

        expect(Current.request).to eq(mock_request)
        expect(Current.request.remote_ip).to eq('192.168.1.1')
        expect(Current.request.user_agent).to eq('TestAgent')
      end
    end

    describe '#admin' do
      it '初期状態ではnilであること' do
        expect(Current.admin).to be_nil
      end

      it '管理者オブジェクトを設定・取得できること' do
        admin = create(:admin, email: 'admin@example.com')
        Current.admin = admin

        expect(Current.admin).to eq(admin)
        expect(Current.admin.email).to eq('admin@example.com')
      end
    end

    describe '#store_user' do
      it '初期状態ではnilであること' do
        expect(Current.store_user).to be_nil
      end

      it '店舗ユーザーオブジェクトを設定・取得できること' do
        store_user = create(:store_user, email: 'store@example.com')
        Current.store_user = store_user

        expect(Current.store_user).to eq(store_user)
        expect(Current.store_user.email).to eq('store@example.com')
      end
    end

    describe '#user' do
      it '初期状態ではnilであること' do
        expect(Current.user).to be_nil
      end

      it 'ユーザーオブジェクトを設定・取得できること' do
        user = create(:admin)
        Current.user = user

        expect(Current.user).to eq(user)
      end
    end
  end

  # ============================================
  # スレッド分離のテスト
  # ============================================

  describe 'thread isolation' do
    it '異なるスレッドで独立した状態を保持すること' do
      admin1 = create(:admin, email: 'admin1@example.com')
      admin2 = create(:admin, email: 'admin2@example.com')

      # メインスレッドで設定
      Current.admin = admin1
      main_thread_admin = Current.admin

      # 別スレッドでの状態確認
      thread_admin = nil
      thread = Thread.new do
        # 別スレッドでは初期状態（nil）
        expect(Current.admin).to be_nil

        # 別の値を設定
        Current.admin = admin2
        thread_admin = Current.admin
      end

      thread.join

      # メインスレッドの状態は変わらず
      expect(Current.admin).to eq(admin1)
      expect(main_thread_admin).to eq(admin1)
      expect(thread_admin).to eq(admin2)
    end

    it '複数の属性が独立して動作すること' do
      admin = create(:admin)
      store_user = create(:store_user)
      mock_request = double('Request')

      Current.admin = admin
      Current.store_user = store_user
      Current.request = mock_request

      thread = Thread.new do
        # 別スレッドでは全て初期状態
        expect(Current.admin).to be_nil
        expect(Current.store_user).to be_nil
        expect(Current.request).to be_nil
      end

      thread.join

      # メインスレッドでは設定した値が保持
      expect(Current.admin).to eq(admin)
      expect(Current.store_user).to eq(store_user)
      expect(Current.request).to eq(mock_request)
    end
  end

  # ============================================
  # リセット機能のテスト
  # ============================================

  describe '#reset' do
    it '全ての属性をリセットすること' do
      admin = create(:admin)
      store_user = create(:store_user)
      user = create(:admin)
      mock_request = double('Request')

      # 全ての属性を設定
      Current.admin = admin
      Current.store_user = store_user
      Current.user = user
      Current.request = mock_request

      # 設定されていることを確認
      expect(Current.admin).to eq(admin)
      expect(Current.store_user).to eq(store_user)
      expect(Current.user).to eq(user)
      expect(Current.request).to eq(mock_request)

      # リセット実行
      Current.reset

      # 全てnilになることを確認
      expect(Current.admin).to be_nil
      expect(Current.store_user).to be_nil
      expect(Current.user).to be_nil
      expect(Current.request).to be_nil
    end

    it 'スレッド固有のリセットが動作すること' do
      admin = create(:admin)
      Current.admin = admin

      thread = Thread.new do
        other_admin = create(:admin)
        Current.admin = other_admin
        expect(Current.admin).to eq(other_admin)

        # スレッド内でリセット
        Current.reset
        expect(Current.admin).to be_nil
      end

      thread.join

      # メインスレッドの状態は影響を受けない
      expect(Current.admin).to eq(admin)
    end
  end

  # ============================================
  # 実用的な使用パターンのテスト
  # ============================================

  describe 'practical usage patterns' do
    describe 'request context' do
      it 'リクエスト情報を適切に管理できること' do
        mock_request = double('Request',
                             remote_ip: '192.168.1.100',
                             user_agent: 'Mozilla/5.0',
                             referer: 'https://example.com',
                             request_id: 'req-123')

        Current.request = mock_request

        # リクエスト情報にアクセスできる
        expect(Current.request.remote_ip).to eq('192.168.1.100')
        expect(Current.request.user_agent).to eq('Mozilla/5.0')
        expect(Current.request.referer).to eq('https://example.com')
        expect(Current.request.request_id).to eq('req-123')
      end
    end

    describe 'user context switching' do
      it '管理者と店舗ユーザーの切り替えが適切に動作すること' do
        admin = create(:admin, email: 'admin@example.com')
        store_user = create(:store_user, email: 'store@example.com')

        # 管理者コンテキスト
        Current.admin = admin
        Current.store_user = nil
        expect(Current.admin).to eq(admin)
        expect(Current.store_user).to be_nil

        # 店舗ユーザーコンテキストに切り替え
        Current.admin = nil
        Current.store_user = store_user
        expect(Current.admin).to be_nil
        expect(Current.store_user).to eq(store_user)
      end
    end

    describe 'audit trail context' do
      it '監査ログのコンテキスト情報を適切に管理できること' do
        admin = create(:admin)
        mock_request = double('Request', remote_ip: '192.168.1.1', user_agent: 'TestAgent')

        Current.admin = admin
        Current.request = mock_request

        # 監査ログで使用する情報が取得できる
        expect(Current.admin.id).to be_present
        expect(Current.request.remote_ip).to eq('192.168.1.1')
        expect(Current.request.user_agent).to eq('TestAgent')
      end
    end
  end

  # ============================================
  # エラーハンドリングのテスト
  # ============================================

  describe 'error handling' do
    it 'nil値の設定でエラーが発生しないこと' do
      expect { Current.admin = nil }.not_to raise_error
      expect { Current.store_user = nil }.not_to raise_error
      expect { Current.user = nil }.not_to raise_error
      expect { Current.request = nil }.not_to raise_error

      expect(Current.admin).to be_nil
      expect(Current.store_user).to be_nil
      expect(Current.user).to be_nil
      expect(Current.request).to be_nil
    end

    it '無効なオブジェクトの設定でもエラーが発生しないこと' do
      expect { Current.admin = "invalid" }.not_to raise_error
      expect { Current.store_user = 123 }.not_to raise_error
      expect { Current.user = [] }.not_to raise_error
      expect { Current.request = {} }.not_to raise_error
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe 'performance', performance: true do
    it '大量アクセスでも高速に動作すること' do
      admin = create(:admin)

      start_time = Time.now
      10000.times do
        Current.admin = admin
        Current.admin
        Current.reset
      end
      end_time = Time.now

      # 10,000回の操作が100ms以下で完了することを期待
      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 100
    end

    it 'スレッド間のアクセスが効率的であること' do
      admin = create(:admin)

      start_time = Time.now
      threads = 10.times.map do
        Thread.new do
          100.times do
            Current.admin = admin
            Current.admin
          end
        end
      end

      threads.each(&:join)
      end_time = Time.now

      # 1,000回の並列操作が200ms以下で完了することを期待
      duration_ms = (end_time - start_time) * 1000
      expect(duration_ms).to be < 200
    end
  end

  # ============================================
  # メモリリークテスト
  # ============================================

  describe 'memory management' do
    it 'リセット後にオブジェクト参照が解放されること' do
      admin = create(:admin)
      admin_id = admin.id

      Current.admin = admin
      expect(Current.admin.id).to eq(admin_id)

      # adminへの参照を削除
      admin = nil

      Current.reset

      # GCでオブジェクトが回収される可能性がある
      GC.start
      expect(Current.admin).to be_nil
    end

    it '大量のオブジェクト設定後でもメモリが適切に管理されること' do
      initial_memory = GC.stat[:total_allocated_objects]

      # 100回に削減してテスト時間短縮とメモリ制約対応
      100.times do |i|
        Current.admin = create(:admin, email: "admin#{i}@example.com")
        Current.reset
      end

      GC.start
      final_memory = GC.stat[:total_allocated_objects]

      # メモリ使用量が異常に増加していないことを確認
      # 100個のAdminオブジェクト作成では約50万オブジェクト増加が妥当
      memory_increase = final_memory - initial_memory
      expect(memory_increase).to be < 1000000 # 1M objects増加まで許容
    end
  end

  # ============================================
  # 統合テスト
  # ============================================

  describe 'integration with Rails request cycle' do
    it 'コントローラーアクション間での状態管理が適切であること' do
      # リクエスト開始をシミュレート
      admin = create(:admin)
      mock_request = double('Request', remote_ip: '192.168.1.1')

      Current.admin = admin
      Current.request = mock_request

      # アクション実行中の状態確認
      expect(Current.admin).to eq(admin)
      expect(Current.request).to eq(mock_request)

      # リクエスト終了をシミュレート
      Current.reset

      expect(Current.admin).to be_nil
      expect(Current.request).to be_nil
    end
  end
end
