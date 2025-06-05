# frozen_string_literal: true

require_relative 'security/security_config'
require_relative 'security/threat_detector'
require_relative 'security/security_storage'
require_relative 'security/security_event_handler'
require_relative 'security/login_tracker'

# ============================================
# Security Monitor System - Refactored
# ============================================
# セキュリティ監視・異常検知システム（リファクタリング済み）
# REF: doc/remaining_tasks.md - エラー追跡・分析（優先度：高）

class SecurityMonitor
  attr_reader :detector, :storage, :event_handler, :login_tracker, :config

  def initialize(
    detector: nil,
    storage: nil,
    event_handler: nil,
    login_tracker: nil,
    config: nil
  )
    @config = config || Security::SecurityConfig.instance
    @storage = storage || Security::SecurityStorage.new(@config)
    @detector = detector || Security::ThreatDetector.new(config: @config, storage: @storage)
    @event_handler = event_handler || Security::SecurityEventHandler.new(config: @config, storage: @storage)
    @login_tracker = login_tracker || Security::LoginTracker.new(
      config: @config,
      storage: @storage,
      event_handler: @event_handler
    )
  end

  # ============================================
  # 異常アクセスパターンの検出
  # ============================================

  def self.analyze_request(request, response = nil)
    instance.analyze_request(request, response)
  end

  def analyze_request(request, response = nil)
    return [] if storage.is_blocked?(extract_client_ip(request))

    threats = detector.detect_threats(request)

    if threats.any?
      severity = detector.determine_severity(threats)
      client_ip = extract_client_ip(request)
      
      context = {
        ip: client_ip,
        threats: threats,
        severity: severity,
        request_path: request.path,
        user_agent: request.user_agent,
        referer: request.referer,
        request_method: request.request_method
      }

      event_handler.handle_threat(severity, context)
    end

    # リクエスト統計の更新
    storage.update_statistics(
      extract_client_ip(request),
      request.user_agent,
      request.path
    )

    threats
  end

  # ============================================
  # ログイン試行の監視
  # ============================================

  def self.track_login_attempt(ip_address, email, success:, user_agent: nil)
    instance.track_login_attempt(ip_address, email, success: success, user_agent: user_agent)
  end

  def track_login_attempt(ip_address, email, success:, user_agent: nil)
    login_tracker.track_login_attempt(ip_address, email, success: success, user_agent: user_agent)
  end

  # ============================================
  # 自動ブロック機能
  # ============================================

  def self.is_blocked?(ip_address)
    instance.is_blocked?(ip_address)
  end

  def is_blocked?(ip_address)
    storage.is_blocked?(ip_address)
  end

  def block_ip(ip_address, reason, duration_minutes = nil)
    duration = duration_minutes || config.block_durations[reason] || 60
    storage.block_ip(ip_address, reason, duration)
  end

  # ============================================
  # Singleton 互換性メソッド（既存コードとの互換性のため）
  # ============================================

  def self.instance
    @instance ||= new
  end

  private

  # ============================================
  # 内部メソッド - ユーティリティ
  # ============================================

  def extract_client_ip(request)
    # リバースプロキシ経由の場合のIPアドレス取得
    request.env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first&.strip ||
      request.env["HTTP_X_REAL_IP"] ||
      request.remote_ip
  end
end

# ============================================
# TODO: セキュリティ監視システムの拡張計画（優先度：高）
# REF: doc/remaining_tasks.md - エラー追跡・分析
# ============================================
# 1. 機械学習による異常検知（優先度：中）
#    - 正常なアクセスパターンの学習
#    - 異常スコアの自動計算
#    - 偽陽性の削減
#
# 2. 脅威インテリジェンス連携（優先度：高）
#    - 既知の悪意あるIPリストとの照合
#    - 外部脅威データベースとの連携
#    - リアルタイム脅威情報の取得
#
# 3. 可視化・ダッシュボード（優先度：中）
#    - セキュリティ状況のリアルタイム表示
#    - 攻撃マップの可視化
#    - トレンド分析とレポート生成
#
# 4. 自動対応・隔離機能（優先度：高）
#    - 段階的な対応レベル
#    - 自動隔離とエスカレーション
#    - 復旧手順の自動化
#
# 5. コンプライアンス対応（優先度：中）
#    - セキュリティログの長期保存
#    - 監査レポートの自動生成
#    - 規制要件への準拠確認
