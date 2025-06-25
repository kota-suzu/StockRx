# frozen_string_literal: true

# ============================================================================
# Security::KeyProvider - Enterprise-Grade Key Management Service
# ============================================================================
# 目的:
#   - 全セキュリティレイヤーでの統一的なキー管理
#   - KMS/HSM対応の準備（AWS KMS, Google Cloud KMS, Azure Key Vault）
#   - キーローテーション・バージョン管理
#   - 依存注入（DI）による疎結合設計
#
# 使用例:
#   key = Security::KeyProvider.current_key(:database_encryption)
#   Security::Encryptor.new(key).encrypt(data)
#
# TODOs (Phase 2: 5-7日):
#   [ ] AWS KMS統合 (app/lib/security/kms/aws_provider.rb)
#   [ ] Google Cloud KMS統合 (app/lib/security/kms/gcp_provider.rb)
#   [ ] Azure Key Vault統合 (app/lib/security/kms/azure_provider.rb)
#   [ ] Redis/Memcached キーキャッシュ機能
#   [ ] キーローテーションワーカー (app/jobs/security/key_rotation_job.rb)
#   [ ] 監査ログ統合 (app/models/security/key_audit_log.rb)
#
# メタ認知的改善点:
#   - キー生成ロジックの中央集約化
#   - 各暗号化層での重複削除
#   - パフォーマンス最適化（キーキャッシュ）
#   - エラーハンドリングの標準化
# ============================================================================

module Security
  class KeyProvider
    include ActiveSupport::Configurable

    # ============================================================================
    # Configuration & Constants
    # ============================================================================

    # キータイプの定義
    KEY_TYPES = {
      database_encryption: {
        algorithm: "AES-256-GCM",
        size: 32, # 256 bits
        rotation_interval: 30.days,
        audit_required: true
      },
      job_arguments: {
        algorithm: "AES-256-GCM",
        size: 32,
        rotation_interval: 7.days,
        audit_required: true
      },
      log_encryption: {
        algorithm: "AES-256-GCM",
        size: 32,
        rotation_interval: 1.day,
        audit_required: false
      },
      session_encryption: {
        algorithm: "AES-256-GCM", # 修正: AES-256-CBC → AES-256-GCM（padding oracle attacks対策）
        size: 32,
        rotation_interval: 1.hour,
        audit_required: false
      }
    }.freeze

    # エラークラス
    class KeyNotFoundError < StandardError; end
    class InvalidKeyTypeError < StandardError; end
    class KMSConnectionError < StandardError; end
    class KeyRotationRequiredError < StandardError; end

    # ============================================================================
    # Configuration (DI Support)
    # ============================================================================

    config_accessor :provider_strategy, default: :rails_credentials
    config_accessor :kms_provider, default: nil  # :aws, :gcp, :azure
    config_accessor :key_cache_ttl, default: 1.hour
    config_accessor :enable_key_rotation, default: false
    config_accessor :enable_audit_logging, default: Rails.env.production?
    config_accessor :fallback_to_derived_keys, default: true

    # ============================================================================
    # Public API
    # ============================================================================

    class << self
      # メインエントリーポイント - 現在の有効キーを取得
      def current_key(key_type, version: :latest)
        validate_key_type!(key_type)

        # TODO: Phase 2 - キーローテーション機能
        # check_rotation_required!(key_type) if config.enable_key_rotation

        case config.provider_strategy
        when :rails_credentials
          get_rails_credential_key(key_type, version)
        when :kms
          get_kms_key(key_type, version)
        when :derived
          get_derived_key(key_type, version)
        else
          raise InvalidKeyTypeError, "Unknown provider strategy: #{config.provider_strategy}"
        end

      rescue => e
        handle_key_retrieval_error(e, key_type, version)
      end

      # キーメタデータの取得
      def key_metadata(key_type)
        validate_key_type!(key_type)

        {
          type: key_type,
          algorithm: KEY_TYPES[key_type][:algorithm],
          size: KEY_TYPES[key_type][:size],
          rotation_interval: KEY_TYPES[key_type][:rotation_interval],
          audit_required: KEY_TYPES[key_type][:audit_required],
          current_version: get_current_version(key_type),
          last_rotated: get_last_rotation_time(key_type),
          next_rotation: get_next_rotation_time(key_type)
        }
      end

      # 利用可能なキータイプ一覧
      def available_key_types
        KEY_TYPES.keys
      end

      # キー検証（開発・テスト用）
      def validate_key(key_type, key_data)
        metadata = KEY_TYPES[key_type]

        # サイズチェック
        return false unless key_data.bytesize == metadata[:size]

        # エントロピーチェック（基本）
        return false if key_data.bytes.uniq.size < 16

        # TODO: Phase 2 - 詳細な暗号学的検証
        # - 統計的ランダム性テスト
        # - NIST SP 800-22準拠検証

        true
      end

      # ============================================================================
      # キー生成（開発・テスト・緊急時用）
      # ============================================================================

      def generate_key(key_type)
        validate_key_type!(key_type)

        metadata = KEY_TYPES[key_type]
        key_data = SecureRandom.bytes(metadata[:size])

        # TODO: Phase 2 - KMS統合時の鍵生成
        # if config.kms_provider
        #   return generate_kms_key(key_type)
        # end

        audit_key_generation(key_type) if config.enable_audit_logging

        key_data
      end

      private

      # ============================================================================
      # Rails Credentials Key Management
      # ============================================================================

      def get_rails_credential_key(key_type, version)
        credential_path = "security.encryption_keys.#{key_type}"

        # TODO: 🟠 Phase 2（重要・推定2日）- 環境変数からのキー取得実装
        # 実装内容: ENV['STOCKRX_#{key_type.upcase}_KEY']からのキー取得優先
        # 優先度: 高（プロダクション環境でのセキュリティ強化）
        # ベストプラクティス:
        #   - 環境変数 > Rails.credentials > 派生キーの優先順位
        #   - 12-factor app準拠の設定管理
        #   - Docker/Kubernetes環境でのSecret管理統合
        # 横展開確認: 全ての暗号化キー取得箇所で同様の実装

        if version == :latest
          key_data = if Rails.application.respond_to?(:safe_credentials)
                       Rails.application.safe_credentials.dig(*credential_path.split(".").map(&:to_sym))
          else
                       Rails.application.credentials.dig(*credential_path.split(".").map(&:to_sym))
          end
        else
          # TODO: Phase 2 - バージョン管理対応
          credential_path = "#{credential_path}.v#{version}"
          key_data = if Rails.application.respond_to?(:safe_credentials)
                       Rails.application.safe_credentials.dig(*credential_path.split(".").map(&:to_sym))
          else
                       Rails.application.credentials.dig(*credential_path.split(".").map(&:to_sym))
          end
        end

        if key_data.nil? && config.fallback_to_derived_keys
          Rails.logger.warn "[Security::KeyProvider] Credential key not found for #{key_type}, falling back to derived key"
          return get_derived_key(key_type, version)
        end

        raise KeyNotFoundError, "Key not found: #{key_type}" if key_data.nil?

        # Base64デコード（credentialが文字列として保存されている場合）
        if key_data.is_a?(String) && key_data.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/)
          Base64.strict_decode64(key_data)
        else
          key_data
        end
      end

      # ============================================================================
      # KMS Key Management (Phase 2)
      # ============================================================================

      def get_kms_key(key_type, version)
        # TODO: Phase 2 - KMS統合
        # case config.kms_provider
        # when :aws
        #   Security::KMS::AWSProvider.new.get_key(key_type, version)
        # when :gcp
        #   Security::KMS::GCPProvider.new.get_key(key_type, version)
        # when :azure
        #   Security::KMS::AzureProvider.new.get_key(key_type, version)
        # else
        #   raise KMSConnectionError, "Unknown KMS provider: #{config.kms_provider}"
        # end

        raise NotImplementedError, "KMS integration not yet implemented (Phase 2)"
      end

      # ============================================================================
      # Derived Key Management（フォールバック）
      # ============================================================================

      def get_derived_key(key_type, version)
        base_key = Rails.application.secret_key_base
        salt = "StockRx-Security-#{key_type}-#{version}"

        metadata = KEY_TYPES[key_type]
        key_length = metadata[:size]

        # PBKDF2による派生キー生成（SHA256使用）
        derived_key = ActiveSupport::KeyGenerator.new(base_key, hash_digest_class: OpenSSL::Digest::SHA256).generate_key(salt, key_length)

        Rails.logger.debug "[Security::KeyProvider] Generated derived key for #{key_type} (#{key_length} bytes)"

        derived_key
      end

      # ============================================================================
      # バリデーション
      # ============================================================================

      def validate_key_type!(key_type)
        unless KEY_TYPES.key?(key_type)
          raise InvalidKeyTypeError, "Invalid key type: #{key_type}. Available: #{KEY_TYPES.keys.join(', ')}"
        end
      end

      # ============================================================================
      # メタデータ管理
      # ============================================================================

      def get_current_version(key_type)
        # TODO: Phase 2 - バージョン管理実装
        :v1
      end

      def get_last_rotation_time(key_type)
        # TODO: Phase 2 - ローテーション履歴管理
        nil
      end

      def get_next_rotation_time(key_type)
        # TODO: Phase 2 - 次回ローテーション時刻計算
        nil
      end

      # ============================================================================
      # エラーハンドリング
      # ============================================================================

      def handle_key_retrieval_error(error, key_type, version)
        Rails.logger.error "[Security::KeyProvider] Key retrieval failed: #{error.message}"
        Rails.logger.error "[Security::KeyProvider] Key type: #{key_type}, Version: #{version}"
        Rails.logger.error "[Security::KeyProvider] Backtrace: #{error.backtrace.first(5).join("\n")}"

        if config.enable_audit_logging
          audit_key_error(key_type, version, error)
        end

        # フォールバック戦略
        if config.fallback_to_derived_keys && !error.is_a?(InvalidKeyTypeError)
          Rails.logger.warn "[Security::KeyProvider] Attempting fallback to derived key"
          return get_derived_key(key_type, :latest)
        end

        raise error
      end

      # ============================================================================
      # 監査ログ（Phase 2）
      # ============================================================================

      def audit_key_generation(key_type)
        # TODO: Phase 2 - 監査ログ実装
        # Security::KeyAuditLog.create!(
        #   action: 'key_generated',
        #   key_type: key_type,
        #   timestamp: Time.current,
        #   environment: Rails.env,
        #   user_agent: request&.user_agent,
        #   ip_address: request&.remote_ip
        # )
      end

      def audit_key_error(key_type, version, error)
        # TODO: Phase 2 - エラー監査ログ
        # Security::KeyAuditLog.create!(
        #   action: 'key_error',
        #   key_type: key_type,
        #   version: version,
        #   error_message: error.message,
        #   error_class: error.class.name,
        #   timestamp: Time.current,
        #   environment: Rails.env
        # )
      end
    end
  end
end

# ============================================================================
# Rails設定統合
# ============================================================================

Rails.application.configure do
  # 環境別設定
  if Rails.env.production?
    Security::KeyProvider.configure do |config|
      config.provider_strategy = :rails_credentials
      config.enable_key_rotation = true
      config.enable_audit_logging = true
      config.fallback_to_derived_keys = false
    end
  elsif Rails.env.development?
    Security::KeyProvider.configure do |config|
      config.provider_strategy = :derived
      config.enable_key_rotation = false
      config.enable_audit_logging = false
      config.fallback_to_derived_keys = true
    end
  else # test
    Security::KeyProvider.configure do |config|
      config.provider_strategy = :derived
      config.enable_key_rotation = false
      config.enable_audit_logging = false
      config.fallback_to_derived_keys = true
    end
  end
end
