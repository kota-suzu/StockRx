class ApplicationJob < ActiveJob::Base
  # ============================================
  # セキュリティモジュール
  # ============================================
  include SecureLogging

  # ============================================
  # セキュアロギング設定（クラス変数）
  # ============================================

  # セキュアロギング機能の有効/無効を制御
  # @note デフォルトはtrue（セキュリティファースト）
  @@secure_logging_enabled = true

  # クラスメソッド: セキュアロギング有効状態の取得
  # @return [Boolean] セキュアロギングが有効かどうか
  def self.secure_logging_enabled
    @@secure_logging_enabled
  end

  # クラスメソッド: セキュアロギング有効状態の設定
  # @param value [Boolean] セキュアロギングの有効/無効
  def self.secure_logging_enabled=(value)
    @@secure_logging_enabled = !!value  # 真偽値に強制変換
  end

  # インスタンスメソッド: セキュアロギング有効状態の取得
  # @return [Boolean] セキュアロギングが有効かどうか
  def secure_logging_enabled?
    self.class.secure_logging_enabled
  end

  # ============================================
  # Sidekiq Configuration for Background Jobs
  # ============================================
  # 要求仕様：3回リトライでエラーハンドリング強化

  # Sidekiq specific retry configuration
  # 指数バックオフによる自動復旧（1回目:即座、2回目:3秒、3回目:18秒）
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  retry_on ActiveRecord::Deadlocked, wait: 5.seconds, attempts: 3
  retry_on ActiveRecord::ConnectionTimeoutError, wait: 10.seconds, attempts: 3

  # 回復不可能なエラーは即座に破棄
  discard_on ActiveJob::DeserializationError
  discard_on CSV::MalformedCSVError
  discard_on Errno::ENOENT  # ファイルが見つからない

  # TODO: 将来的な拡張エラーハンドリング
  # discard_on ActiveStorage::FileNotFoundError
  # retry_on Timeout::Error, wait: 30.seconds, attempts: 5
  # retry_on Net::ReadTimeout, wait: 30.seconds, attempts: 5
  # retry_on Net::WriteTimeout, wait: 30.seconds, attempts: 5

  # ============================================
  # Logging and Monitoring
  # ============================================
  # ジョブの可観測性向上のためのログ機能

  before_perform :log_job_start
  after_perform :log_job_success
  rescue_from StandardError, with: :log_job_error

  private

  def log_job_start
    @start_time = Time.current

    # パフォーマンス監視の開始
    @performance_data = start_performance_monitoring if performance_monitoring_enabled?

    # 引数のサニタイズと安全な文字列化
    sanitized_args = sanitize_arguments(arguments)
    safe_args_string = safe_arguments_to_string(sanitized_args)

    Rails.logger.info({
      event: "job_started",
      job_class: self.class.name,
      job_id: job_id,
      queue_name: queue_name,
      arguments: safe_args_string,
      timestamp: @start_time.iso8601
    }.to_json)
  end

  def log_job_success
    duration = Time.current - @start_time if @start_time

    # パフォーマンス監視の終了
    end_performance_monitoring(success: true) if @performance_data

    Rails.logger.info({
      event: "job_completed",
      job_class: self.class.name,
      job_id: job_id,
      duration: duration&.round(2),
      queue_name: queue_name,
      timestamp: Time.current.iso8601
    })
  end

  def log_job_error(exception)
    duration = Time.current - @start_time if @start_time

    # パフォーマンス監視の終了（エラー時）
    end_performance_monitoring(success: false, error: exception) if @performance_data

    Rails.logger.error({
      event: "job_failed",
      job_class: self.class.name,
      job_id: job_id,
      duration: duration&.round(2),
      queue_name: queue_name,
      error_class: exception.class.name,
      error_message: exception.message,
      error_backtrace: exception.backtrace&.first(10),
      timestamp: Time.current.iso8601
    })

    # エラーを再発生させてSidekiqのリトライ機能を働かせる
    raise exception
  end

  # ============================================
  # セキュリティ関連メソッド
  # ============================================

  # ジョブ引数の機密情報をサニタイズ
  #
  # @param args [Array] ジョブの引数配列
  # @return [Array] サニタイズ済み引数配列
  def sanitize_arguments(args)
    # セキュアロギングが無効な場合は元の引数をそのまま返す
    return args unless secure_logging_enabled?
    return args unless defined?(SecureArgumentSanitizer)

    # パフォーマンス監視開始
    start_time = Time.current

    begin
      # メモリ使用量監視
      if defined?(SecureJobPerformanceMonitor)
        SecureJobPerformanceMonitor.monitor_sanitization(self.class.name, args.size) do
          SecureArgumentSanitizer.sanitize(args, self.class.name)
        end
      else
        SecureArgumentSanitizer.sanitize(args, self.class.name)
      end
    rescue => e
      # サニタイズ失敗時はエラーログを記録し、安全な代替値を返す
      duration = Time.current - start_time

      Rails.logger.error({
        event: "argument_sanitization_failed",
        job_class: self.class.name,
        job_id: job_id,
        error_class: e.class.name,
        error_message: e.message,
        duration: duration.round(4),
        args_count: args.size,
        timestamp: Time.current.iso8601
      })

      # フォールバック: 全引数を安全な値に置換
      Array.new(args.size, "[SANITIZATION_FAILED]")
    end
  end

  # 開発環境での機密情報フィルタリングデバッグ
  #
  # @param original [Array] 元の引数
  # @param sanitized [Array] サニタイズ済み引数
  def debug_argument_filtering(original, sanitized)
    return unless Rails.env.development? && original != sanitized

    Rails.logger.debug({
      event: "argument_filtering_applied",
      job_class: self.class.name,
      job_id: job_id,
      original_arg_count: original.size,
      sanitized_arg_count: sanitized.size,
      filtering_applied: true,
      timestamp: Time.current.iso8601
    })
  end

  # 引数を安全な文字列に変換（inspect使用を避ける）
  def safe_arguments_to_string(args)
    return "[]" if args.empty?

    safe_elements = args.map do |arg|
      case arg
      when String
        # フィルタリング済みのマーカーか確認
        if arg.start_with?("[") && arg.end_with?("]") &&
           (arg.include?("FILTERED") || arg.include?("ADMIN_ID") || arg.include?("CVV") || arg.include?("DATE"))
          arg
        else
          "\"#{arg}\""
        end
      when Hash
        safe_hash_to_string(arg)
      when Array
        safe_array_to_string(arg)
      when Numeric, TrueClass, FalseClass, NilClass
        arg.to_s
      else
        arg_str = arg.to_s
        if arg_str.start_with?("[") && arg_str.end_with?("]") &&
           (arg_str.include?("FILTERED") || arg_str.include?("ADMIN_ID") || arg_str.include?("CVV") || arg_str.include?("DATE"))
          arg_str
        else
          "\"#{arg_str}\""
        end
      end
    end

    "[#{safe_elements.join(', ')}]"
  end

  # ハッシュの安全な文字列化
  def safe_hash_to_string(hash)
    return "{}" if hash.empty?

    safe_pairs = hash.map do |key, value|
      safe_key = key.to_s
      safe_value = case value
      when String
                     if value.start_with?("[") && value.end_with?("]") &&
                        (value.include?("FILTERED") || value.include?("ADMIN_ID") || value.include?("CVV") || value.include?("DATE"))
                       value
                     else
                       "\"#{value}\""
                     end
      when Hash
                     safe_hash_to_string(value)
      when Array
                     safe_array_to_string(value)
      else
                     value.to_s
      end
      "\"#{safe_key}\" => #{safe_value}"
    end

    "{#{safe_pairs.join(', ')}}"
  end

  # 配列の安全な文字列化
  def safe_array_to_string(array)
    return "[]" if array.empty?

    safe_elements = array.map do |item|
      case item
      when String
        if item.start_with?("[") && item.end_with?("]") &&
           (item.include?("FILTERED") || item.include?("ADMIN_ID") || item.include?("CVV") || item.include?("DATE"))
          item
        else
          "\"#{item}\""
        end
      when Hash
        safe_hash_to_string(item)
      when Array
        safe_array_to_string(item)
      else
        item.to_s
      end
    end

    "[#{safe_elements.join(', ')}]"
  end

  # ============================================
  # パフォーマンス監視関連メソッド
  # ============================================

  def performance_monitoring_enabled?
    Rails.application.config.secure_job_logging&.dig(:performance_monitoring) || false
  end

  def start_performance_monitoring
    return unless defined?(SecureJobPerformanceMonitor)

    SecureJobPerformanceMonitor.start_monitoring(
      self.class.name,
      job_id,
      arguments.size
    )
  rescue => e
    Rails.logger.warn "Failed to start performance monitoring: #{e.message}"
    nil
  end

  def end_performance_monitoring(success:, error: nil)
    return unless @performance_data && defined?(SecureJobPerformanceMonitor)

    SecureJobPerformanceMonitor.end_monitoring(
      @performance_data,
      success: success,
      error: error
    )
  rescue => e
    Rails.logger.warn "Failed to end performance monitoring: #{e.message}"
  end

  # ============================================================================
  # ✅ 完了済み修正（2025年6月14日）
  # ============================================================================

  # ✅ Phase 1: secure_logging機能実装完了
  # - ApplicationJob.secure_logging_enabled クラスメソッド実装
  # - secure_logging_enabled? インスタンスメソッド実装
  # - sanitize_arguments メソッドでのフラグベース制御
  # - GitHub Actions CI での NoMethodError 解消確認済み

  # ============================================================================
  # 残課題TODO - セキュアロギング統合機能（優先度別・更新版）
  # ============================================================================

  # 🔴 緊急 - Phase 1（推定2-3日） - 高度セキュリティ機能実装
  # TODO: GDPR準拠の個人情報保護機能
  # 場所: spec/security/secure_job_logging_security_spec.rb:89-93
  # 状態: PENDING（実装待ち）
  # 実装内容:
  #   - EU個人情報の特定・マスキング
  #   - データ処理履歴の適切な記録
  #   - 忘れられる権利への対応
  #   - 横展開確認: 全Job系クラスでの統一実装
  #
  # TODO: PCI DSS準拠のクレジットカード情報保護
  # 場所: spec/security/secure_job_logging_security_spec.rb:99-103
  # 状態: PENDING（実装待ち）
  # 実装内容:
  #   - クレジットカード番号の完全マスキング
  #   - CVVコードの即座削除
  #   - PCI DSS Level 1 要件準拠
  #   - セキュリティ監査証跡の実装

  # 🟡 重要 - Phase 2（推定3-4日） - 高度攻撃対策・監視機能
  # TODO: 高度攻撃手法対策
  # 場所: spec/security/secure_job_logging_security_spec.rb:112-120
  # 状態: PENDING（実装待ち）
  # 実装内容:
  #   - JSON埋め込み攻撃防御
  #   - SQLインジェクション検出・無害化
  #   - スクリプト埋め込み攻撃対策
  #   - ゼロデイ攻撃パターンの検知
  #
  # TODO: セキュリティ監査・監視機能
  # 場所: spec/security/secure_job_logging_security_spec.rb:144-152
  # 状態: PENDING（実装待ち）
  # 実装内容:
  #   - セキュリティイベント記録
  #   - 異常アクセスパターン検出
  #   - 自動セキュリティレポート生成
  #   - リアルタイム脅威検知

  # 🟡 重要 - Phase 2（推定2-3日） - パフォーマンス・耐攻撃性強化
  # TODO: タイミング攻撃対策
  # 場所: spec/security/secure_job_logging_security_spec.rb:58
  # 状態: PENDING（実装待ち）
  # 実装内容:
  #   - 一定時間処理保証機構
  #   - サニタイズ処理時間の均一化
  #   - サイドチャネル攻撃耐性
  #   - メモリアクセスパターン秘匿
  #
  # TODO: 大規模データ処理最適化
  # 場所: spec/security/secure_job_logging_security_spec.rb:129
  # 状態: PENDING（実装待ち）
  # 実装内容:
  #   - 100万件ログデータの効率処理
  #   - ストリーミング処理機構
  #   - メモリ使用量最適化
  #   - 並列処理対応

  # 🟢 推奨 - Phase 3（推定1-2週間） - 将来的な拡張機能
  # TODO: エンタープライズ機能拡張
  # - Prometheus/Grafana メトリクス連携
  # - Slack/Teams/PagerDuty アラート統合
  # - NewRelic/Datadog パフォーマンス監視
  # - Vault/HSM 暗号化キー管理
  # - Kubernetes セキュリティポリシー統合
  #
  # TODO: AI・機械学習ベースセキュリティ
  # - 異常行動検知（Machine Learning）
  # - 予測的脅威分析（AI）
  # - 自動インシデント対応（Automation）
  # - 適応的セキュリティポリシー（Dynamic）
  #
  # TODO: コンプライアンス・監査機能
  # - SOX法対応監査証跡
  # - HIPAA準拠医療情報保護
  # - ISO27001 セキュリティ管理
  # - 自動コンプライアンスレポート
end
