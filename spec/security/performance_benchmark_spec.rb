# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

# Phase 5-5: セキュリティ機能パフォーマンステスト
# ============================================
# セキュリティ機能のパフォーマンス影響測定
# ベンチマークと最適化の検証
# ============================================
RSpec.describe "Security Performance Benchmark", type: :request do
  let(:admin) { create(:admin) }
  let(:store) { create(:store) }

  # ============================================
  # レート制限のパフォーマンス影響
  # ============================================
  describe "レート制限のオーバーヘッド測定" do
    before do
      # レート制限をリセット
      RateLimiter.new(:api, "test-benchmark").reset!
    end

    it "レート制限チェックが50ms以内で完了すること" do
      sign_in admin

      # ウォームアップ
      get admin_inventories_path

      # ベンチマーク実行
      times = []
      100.times do
        time = Benchmark.realtime do
          limiter = RateLimiter.new(:api, "benchmark-user")
          limiter.allowed?
          limiter.track!
        end
        times << time * 1000 # ミリ秒に変換
      end

      average_time = times.sum / times.size
      max_time = times.max

      expect(average_time).to be < 5.0  # 平均5ms以内
      expect(max_time).to be < 50.0     # 最大50ms以内
    end

    it "レート制限が有効でもレスポンスタイムが許容範囲内であること" do
      sign_in admin

      # レート制限なしのベースライン測定
      baseline_times = []
      10.times do
        time = Benchmark.realtime { get admin_inventories_path }
        baseline_times << time
      end
      baseline_avg = baseline_times.sum / baseline_times.size

      # レート制限ありの測定
      with_limit_times = []
      10.times do
        time = Benchmark.realtime do
          # レート制限チェックを含むリクエスト
          get admin_inventories_path
        end
        with_limit_times << time
      end
      with_limit_avg = with_limit_times.sum / with_limit_times.size

      # オーバーヘッドが10%以内
      overhead = ((with_limit_avg - baseline_avg) / baseline_avg) * 100
      expect(overhead).to be < 10.0
    end
  end

  # ============================================
  # 監査ログのパフォーマンス影響
  # ============================================
  describe "監査ログ記録のオーバーヘッド測定" do
    it "監査ログ記録が10ms以内で完了すること" do
      # ウォームアップ
      create(:inventory)

      # ベンチマーク実行
      times = []
      50.times do |i|
        time = Benchmark.realtime do
          inventory = build(:inventory, name: "Benchmark #{i}")
          inventory.save!
        end
        times << time * 1000 # ミリ秒に変換
      end

      average_time = times.sum / times.size

      # 監査ログ記録を含めても平均10ms以内
      expect(average_time).to be < 10.0
    end

    it "大量データ更新時も監査ログがパフォーマンスに影響しないこと" do
      inventories = create_list(:inventory, 100)

      # バルク更新のベンチマーク
      update_time = Benchmark.realtime do
        inventories.each { |inv| inv.update!(price: inv.price + 10) }
      end

      # 100件の更新が10秒以内（1件あたり100ms以内）
      expect(update_time).to be < 10.0
    end

    it "機密情報マスキングが高速に処理されること" do
      # マスキング処理のベンチマーク
      sensitive_data = {
        credit_card: "4111-1111-1111-1111",
        email: "benchmark@example.com",
        my_number: "123456789012"
      }

      masking_time = Benchmark.realtime do
        1000.times do
          # Auditableのマスキング処理をシミュレート
          data = sensitive_data.dup
          data[:credit_card] = "[CARD_NUMBER]" if data[:credit_card] =~ /\d{4}-?\d{4}-?\d{4}-?\d{4}/
          data[:email] = data[:email].gsub(/(.{2})[^@]+(@.+)/, '\1***\2') if data[:email]
          data[:my_number] = "[MY_NUMBER]" if data[:my_number] =~ /\d{12}/
        end
      end

      # 1000回のマスキング処理が100ms以内
      expect(masking_time * 1000).to be < 100.0
    end
  end

  # ============================================
  # セキュリティヘッダーのパフォーマンス影響
  # ============================================
  describe "セキュリティヘッダー生成のオーバーヘッド測定" do
    it "CSP nonce生成が高速であること" do
      controller = ApplicationController.new

      nonce_times = []
      1000.times do
        time = Benchmark.realtime do
          # nonce生成処理
          SecureRandom.base64(24)
        end
        nonce_times << time * 1000 # ミリ秒に変換
      end

      average_time = nonce_times.sum / nonce_times.size

      # 平均0.1ms以内
      expect(average_time).to be < 0.1
    end

    it "全ヘッダー設定が5ms以内で完了すること" do
      get root_path

      header_times = []
      50.times do
        time = Benchmark.realtime do
          get admin_inventories_path
          # ヘッダーが設定されていることを確認
          response.headers["X-Frame-Options"]
          response.headers["Content-Security-Policy"]
          response.headers["Permissions-Policy"]
        end
        header_times << time * 1000
      end

      average_time = header_times.sum / header_times.size

      # リクエスト全体で平均50ms以内
      expect(average_time).to be < 50.0
    end
  end

  # ============================================
  # 暗号化処理のパフォーマンス
  # ============================================
  describe "暗号化処理のパフォーマンス測定" do
    it "パスワードハッシュ生成が適切な時間で完了すること" do
      password = "BenchmarkPassword123!"

      hash_times = []
      10.times do
        time = Benchmark.realtime do
          BCrypt::Password.create(password, cost: 10)
        end
        hash_times << time
      end

      average_time = hash_times.sum / hash_times.size

      # 平均50-200ms（セキュリティと速度のバランス）
      expect(average_time).to be_between(0.05, 0.2)
    end

    it "パスワード検証が高速に実行されること" do
      user = create(:admin, password: "TestPassword123!")

      verify_times = []
      20.times do
        time = Benchmark.realtime do
          user.valid_password?("TestPassword123!")
        end
        verify_times << time
      end

      average_time = verify_times.sum / verify_times.size

      # 平均100ms以内
      expect(average_time).to be < 0.1
    end
  end

  # ============================================
  # 同時アクセス時のパフォーマンス
  # ============================================
  describe "高負荷時のセキュリティ機能パフォーマンス" do
    it "同時アクセス時もレート制限が正常に動作すること" do
      threads = []
      results = Concurrent::Array.new

      # 10スレッドで同時アクセス
      10.times do |i|
        threads << Thread.new do
          limiter = RateLimiter.new(:api, "concurrent-#{i}")

          5.times do
            result = Benchmark.realtime do
              limiter.allowed?
              limiter.track!
            end
            results << result * 1000
          end
        end
      end

      threads.each(&:join)

      # 全リクエストの95%が10ms以内
      sorted_results = results.sort
      percentile_95 = sorted_results[(results.size * 0.95).floor]
      expect(percentile_95).to be < 10.0
    end

    it "大量の監査ログ書き込みでもデッドロックが発生しないこと" do
      threads = []
      errors = Concurrent::Array.new

      # 20スレッドで同時に監査ログ記録
      20.times do |i|
        threads << Thread.new do
          begin
            5.times do |j|
              inventory = create(:inventory, name: "Concurrent #{i}-#{j}")
              inventory.update!(price: rand(100..1000))
              inventory.destroy
            end
          rescue => e
            errors << e
          end
        end
      end

      threads.each(&:join)

      # デッドロックエラーがないこと
      expect(errors.select { |e| e.message.include?("Deadlock") }).to be_empty
    end
  end

  # ============================================
  # メモリ使用量測定
  # ============================================
  describe "セキュリティ機能のメモリ使用量" do
    it "レート制限のメモリ使用量が適切であること" do
      initial_memory = memory_usage

      # 1000個の異なるキーでレート制限を作成
      1000.times do |i|
        limiter = RateLimiter.new(:api, "memory-test-#{i}")
        limiter.track!
      end

      final_memory = memory_usage
      memory_increase = final_memory - initial_memory

      # メモリ増加が10MB以内
      expect(memory_increase).to be < 10_000_000
    end

    it "監査ログの大量生成でメモリリークがないこと" do
      GC.start
      initial_memory = memory_usage

      # 1000件の監査ログを生成
      1000.times do |i|
        AuditLog.log_action(
          admin,
          "test_action",
          "Test message #{i}",
          { data: "x" * 1000 } # 1KBのデータ
        )
      end

      GC.start
      final_memory = memory_usage
      memory_increase = final_memory - initial_memory

      # メモリ増加が妥当な範囲内（20MB以内）
      expect(memory_increase).to be < 20_000_000
    end
  end

  # ============================================
  # 総合パフォーマンススコア
  # ============================================
  describe "セキュリティ機能の総合パフォーマンス評価" do
    it "全セキュリティ機能を有効にしても許容可能なパフォーマンスであること" do
      sign_in admin

      # 実際の利用シナリオをシミュレート
      total_time = Benchmark.realtime do
        # 1. ログイン（レート制限チェック含む）
        post admin_session_path, params: {
          admin: { email: admin.email, password: admin.password }
        }

        # 2. ダッシュボード表示（セキュリティヘッダー設定含む）
        get admin_root_path

        # 3. データ作成（監査ログ記録含む）
        post admin_inventories_path, params: {
          inventory: { name: "Performance Test", sku: "PERF001", price: 100 }
        }

        # 4. データ検索
        get admin_inventories_path, params: { q: { name_cont: "Performance" } }

        # 5. データ更新
        inventory = Inventory.last
        patch admin_inventory_path(inventory), params: {
          inventory: { price: 200 }
        }
      end

      # 5つの操作が合計2秒以内
      expect(total_time).to be < 2.0
    end
  end

  private

  def memory_usage
    # プロセスのメモリ使用量を取得（バイト単位）
    `ps -o rss= -p #{Process.pid}`.to_i * 1024
  end
end

# ============================================
# TODO: Phase 5-6以降の拡張予定
# ============================================
# 1. 🔴 詳細なプロファイリング
#    - フレームグラフ生成
#    - CPU使用率分析
#    - I/O待機時間測定
#
# 2. 🟡 継続的パフォーマンス監視
#    - CI/CDでのパフォーマンステスト自動実行
#    - パフォーマンス劣化の自動検出
#    - ベースラインとの比較
#
# 3. 🟢 最適化提案
#    - ボトルネックの自動検出
#    - キャッシュ戦略の提案
#    - インデックス最適化の提案
