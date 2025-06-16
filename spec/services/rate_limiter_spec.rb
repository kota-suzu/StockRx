# frozen_string_literal: true

require 'rails_helper'

# Phase 5-4: レート制限サービステスト
# ============================================
# RateLimiterサービスの単体テスト
# ============================================
RSpec.describe RateLimiter do
  let(:redis) { Redis.new }
  
  before do
    # テスト前にRedisをクリーンアップ
    redis.flushdb
  end
  
  after do
    # テスト後もクリーンアップ
    redis.flushdb
  end
  
  describe "#initialize" do
    it "有効なキータイプで初期化できること" do
      expect { described_class.new(:login, "test-id") }.not_to raise_error
    end
    
    it "無効なキータイプでエラーが発生すること" do
      expect { described_class.new(:invalid, "test-id") }.to raise_error(ArgumentError)
    end
  end
  
  describe "#allowed?" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    context "制限内の場合" do
      it "trueを返すこと" do
        4.times { limiter.track! }
        expect(limiter.allowed?).to be true
      end
    end
    
    context "制限に達した場合" do
      it "falseを返すこと" do
        5.times { limiter.track! }
        expect(limiter.allowed?).to be false
      end
    end
    
    context "ブロックされている場合" do
      it "falseを返すこと" do
        5.times { limiter.track! } # ブロックをトリガー
        
        # カウンターをリセットしてもブロック中はfalse
        redis.del("rate_limit:login:test-user:count")
        expect(limiter.allowed?).to be false
      end
    end
  end
  
  describe "#track!" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    it "カウンターが増加すること" do
      expect { limiter.track! }.to change { limiter.current_count }.from(0).to(1)
    end
    
    it "制限に達するとブロックされること" do
      5.times { limiter.track! }
      expect(limiter.blocked?).to be true
    end
    
    it "ブロック時に監査ログが記録されること" do
      allow(AuditLog).to receive(:log_action)
      
      5.times { limiter.track! }
      
      expect(AuditLog).to have_received(:log_action).with(
        nil,
        "security_event",
        "レート制限超過: login",
        hash_including(event_type: "rate_limit_exceeded")
      )
    end
  end
  
  describe "#current_count" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    it "現在のカウント数を返すこと" do
      expect(limiter.current_count).to eq(0)
      
      3.times { limiter.track! }
      expect(limiter.current_count).to eq(3)
    end
  end
  
  describe "#remaining_attempts" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    it "残り試行回数を返すこと" do
      expect(limiter.remaining_attempts).to eq(5)
      
      2.times { limiter.track! }
      expect(limiter.remaining_attempts).to eq(3)
      
      3.times { limiter.track! }
      expect(limiter.remaining_attempts).to eq(0)
    end
  end
  
  describe "#blocked?" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    it "ブロック状態を正しく判定すること" do
      expect(limiter.blocked?).to be false
      
      5.times { limiter.track! }
      expect(limiter.blocked?).to be true
    end
  end
  
  describe "#time_until_unblock" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    context "ブロックされていない場合" do
      it "0を返すこと" do
        expect(limiter.time_until_unblock).to eq(0)
      end
    end
    
    context "ブロックされている場合" do
      it "残り時間を秒単位で返すこと" do
        5.times { limiter.track! }
        
        # ブロック期間は30分（1800秒）
        expect(limiter.time_until_unblock).to be_between(1, 1800)
      end
    end
  end
  
  describe "#reset!" do
    let(:limiter) { described_class.new(:login, "test-user") }
    
    it "カウンターとブロックをリセットすること" do
      5.times { limiter.track! }
      expect(limiter.blocked?).to be true
      
      limiter.reset!
      
      expect(limiter.current_count).to eq(0)
      expect(limiter.blocked?).to be false
    end
  end
  
  describe "異なるレート制限タイプ" do
    it "ログイン制限が正しく設定されること" do
      limiter = described_class.new(:login, "test")
      config = limiter.instance_variable_get(:@config)
      
      expect(config[:limit]).to eq(5)
      expect(config[:period]).to eq(15.minutes)
      expect(config[:block_duration]).to eq(30.minutes)
    end
    
    it "API制限が正しく設定されること" do
      limiter = described_class.new(:api, "test")
      config = limiter.instance_variable_get(:@config)
      
      expect(config[:limit]).to eq(100)
      expect(config[:period]).to eq(1.hour)
      expect(config[:block_duration]).to eq(1.hour)
    end
    
    it "パスワードリセット制限が正しく設定されること" do
      limiter = described_class.new(:password_reset, "test")
      config = limiter.instance_variable_get(:@config)
      
      expect(config[:limit]).to eq(3)
      expect(config[:period]).to eq(1.hour)
      expect(config[:block_duration]).to eq(1.hour)
    end
  end
  
  describe "異なる識別子での独立性" do
    it "異なる識別子で独立してカウントされること" do
      limiter1 = described_class.new(:login, "user1")
      limiter2 = described_class.new(:login, "user2")
      
      3.times { limiter1.track! }
      expect(limiter1.current_count).to eq(3)
      expect(limiter2.current_count).to eq(0)
    end
  end
  
  describe "期間経過後の自動リセット" do
    it "期間経過後にカウンターがリセットされること" do
      # 短い期間のテスト用設定
      allow_any_instance_of(described_class).to receive(:increment_counter!) do |instance|
        redis = instance.send(:redis)
        key = instance.send(:counter_key)
        redis.multi do |r|
          r.incr(key)
          r.expire(key, 2) # 2秒で期限切れ
        end
      end
      
      limiter = described_class.new(:login, "test-expire")
      
      2.times { limiter.track! }
      expect(limiter.current_count).to eq(2)
      
      sleep 3 # 期限切れを待つ
      
      expect(limiter.current_count).to eq(0)
    end
  end
  
  describe "エラーハンドリング" do
    context "Redis接続エラー" do
      it "エラーをログに記録すること" do
        limiter = described_class.new(:login, "test-error")
        
        # Redis接続をモック
        allow(limiter).to receive(:redis).and_raise(Redis::ConnectionError)
        allow(Rails.logger).to receive(:error)
        
        # エラーが発生してもクラッシュしない
        expect { limiter.allowed? }.to raise_error(Redis::ConnectionError)
      end
    end
  end
end

# ============================================
# TODO: Phase 5-5以降の拡張予定
# ============================================
# 1. 🔴 分散環境でのテスト
#    - Redis Clusterでの動作確認
#    - 複数アプリケーションサーバーでの同期
#
# 2. 🟡 パフォーマンステスト
#    - 大量リクエスト時の応答時間
#    - Redisの負荷テスト
#
# 3. 🟢 カスタム制限ルール
#    - 動的な制限値の変更
#    - ユーザーグループ別の制限