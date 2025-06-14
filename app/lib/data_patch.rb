# frozen_string_literal: true

# ============================================================================
# DataPatch Base Class
# ============================================================================
# 目的: データパッチクラスの基底クラス定義
# 機能: 共通メソッド・ヘルパー・インターフェース定義
#
# 設計思想:
#   - 継承性: 全データパッチの共通機能提供
#   - 拡張性: 派生クラスでの柔軟な実装
#   - 可読性: 標準的なインターフェース定義

# ============================================================================
# 便利なヘルパーメソッド
# ============================================================================

module DataPatchHelper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def register_as_data_patch(name, metadata = {})
      # DataPatchRegistryが読み込まれるまで遅延実行
      Rails.application.config.after_initialize do
        if defined?(DataPatchRegistry)
          DataPatchRegistry.register_patch(name, self, metadata)
        else
          Rails.logger.warn "[DataPatch] DataPatchRegistry未読み込み: #{name}"
        end
      end
    end
  end
end

# ============================================================================
# 基底クラス（オプション）
# ============================================================================

class DataPatch
  include DataPatchHelper

  def initialize(options = {})
    @options = options
    @logger = Rails.logger
  end

  # 派生クラスで実装必須
  def execute_batch(batch_size, offset)
    raise NotImplementedError, "execute_batch メソッドを実装してください"
  end

  def self.estimate_target_count(options = {})
    raise NotImplementedError, "estimate_target_count メソッドを実装してください"
  end

  def estimate_target_count(options = {})
    self.class.estimate_target_count(options)
  end

  protected

  attr_reader :options, :logger

  def log_info(message)
    @logger.info "[#{self.class.name}] #{message}"
  end

  def log_error(message)
    @logger.error "[#{self.class.name}] #{message}"
  end

  def dry_run?
    @options[:dry_run] == true
  end
end
