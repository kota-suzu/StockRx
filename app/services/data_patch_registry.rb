# frozen_string_literal: true

# ============================================================================
# DataPatchRegistry Service
# ============================================================================
# 目的: データパッチクラスの登録・管理・検索
# 機能: パッチ登録・動的ロード・メタデータ管理
#
# 設計思想:
#   - 拡張性: 新しいパッチクラスの簡単な追加
#   - 安全性: パッチの事前検証と型安全性
#   - 可視性: 利用可能パッチの一覧と説明

class DataPatchRegistry
  include Singleton

  # ============================================================================
  # エラー定義
  # ============================================================================

  class RegistryError < StandardError; end
  class PatchNotFoundError < RegistryError; end
  class InvalidPatchClassError < RegistryError; end

  # ============================================================================
  # 初期化
  # ============================================================================

  def initialize
    @patches = {}
    @metadata = {}
    load_registered_patches
  end

  # ============================================================================
  # クラスメソッド（シングルトンアクセス）
  # ============================================================================

  class << self
    delegate :register_patch, :find_patch, :patch_exists?, :list_patches,
             :patch_metadata, :validate_patch_class, :reload_patches, to: :instance
  end

  # ============================================================================
  # パッチ登録
  # ============================================================================

  def register_patch(name, patch_class, metadata = {})
    validate_patch_class(patch_class)

    @patches[name.to_s] = patch_class
    @metadata[name.to_s] = default_metadata.merge(metadata).merge(
      registered_at: Time.current,
      class_name: patch_class.name
    )

    Rails.logger.info "[DataPatchRegistry] パッチ登録: #{name} (#{patch_class.name})"
    true
  end

  # ============================================================================
  # パッチ検索
  # ============================================================================

  def find_patch(name)
    patch_class = @patches[name.to_s]
    raise PatchNotFoundError, "パッチが見つかりません: #{name}" unless patch_class
    patch_class
  end

  def patch_exists?(name)
    @patches.key?(name.to_s)
  end

  # ============================================================================
  # パッチ一覧
  # ============================================================================

  def list_patches(category: nil, status: :active)
    filtered_patches = @patches.select do |name, patch_class|
      metadata = @metadata[name]

      # カテゴリフィルタ
      category_match = category.nil? || metadata[:category] == category.to_s

      # ステータスフィルタ
      status_match = status == :all || metadata[:status] == status.to_s

      category_match && status_match
    end

    filtered_patches.map do |name, patch_class|
      {
        name: name,
        class_name: patch_class.name,
        metadata: @metadata[name]
      }
    end
  end

  # ============================================================================
  # メタデータ管理
  # ============================================================================

  def patch_metadata(name)
    raise PatchNotFoundError, "パッチが見つかりません: #{name}" unless patch_exists?(name)
    @metadata[name.to_s].dup
  end

  def update_patch_metadata(name, new_metadata)
    raise PatchNotFoundError, "パッチが見つかりません: #{name}" unless patch_exists?(name)
    @metadata[name.to_s] = @metadata[name.to_s].merge(new_metadata)
  end

  # ============================================================================
  # パッチクラス検証
  # ============================================================================

  def validate_patch_class(patch_class)
    unless patch_class.is_a?(Class)
      raise InvalidPatchClassError, "クラスオブジェクトが必要です: #{patch_class}"
    end

    # 必須メソッドの確認
    required_methods = [ :new, :execute_batch, :estimate_target_count ]
    missing_methods = required_methods.reject { |method| patch_class.method_defined?(method) || patch_class.respond_to?(method) }

    if missing_methods.any?
      raise InvalidPatchClassError,
            "必須メソッドが不足しています: #{missing_methods.join(', ')} (クラス: #{patch_class.name})"
    end

    # DataPatch基底クラスの確認（オプション）
    if defined?(DataPatch) && !patch_class.ancestors.include?(DataPatch)
      Rails.logger.warn "[DataPatchRegistry] 警告: #{patch_class.name} は DataPatch を継承していません"
    end

    true
  end

  # ============================================================================
  # 動的ロード
  # ============================================================================

  def reload_patches
    @patches.clear
    @metadata.clear
    load_registered_patches
    Rails.logger.info "[DataPatchRegistry] パッチレジストリを再ロードしました"
  end

  # ============================================================================
  # 統計情報
  # ============================================================================

  def registry_statistics
    total_patches = @patches.size
    by_category = @metadata.group_by { |_, meta| meta[:category] }.transform_values(&:size)
    by_status = @metadata.group_by { |_, meta| meta[:status] }.transform_values(&:size)

    {
      total_patches: total_patches,
      by_category: by_category,
      by_status: by_status,
      last_registered: @metadata.values.map { |meta| meta[:registered_at] }.max,
      registry_loaded_at: @registry_loaded_at
    }
  end

  # ============================================================================
  # プライベートメソッド
  # ============================================================================

  private

  def load_registered_patches
    @registry_loaded_at = Time.current

    # 標準パッチディレクトリからの自動ロード
    load_patches_from_directory

    # 設定ファイルからの登録
    load_patches_from_config

    Rails.logger.info "[DataPatchRegistry] #{@patches.size}個のパッチを読み込みました"
  end

  def load_patches_from_directory
    patches_dir = Rails.root.join("app", "data_patches")
    return unless patches_dir.exist?

    Dir.glob(patches_dir.join("**", "*.rb")).each do |file_path|
      begin
        require file_path

        # ファイル名からクラス名を推測
        class_name = File.basename(file_path, ".rb").camelize

        # クラスの動的取得
        if Object.const_defined?(class_name)
          patch_class = Object.const_get(class_name)
          patch_name = class_name.underscore

          # 自動登録
          register_patch(patch_name, patch_class, {
            source: "auto_loaded",
            file_path: file_path,
            category: "general"
          })
        end
      rescue => error
        Rails.logger.error "[DataPatchRegistry] パッチロードエラー (#{file_path}): #{error.message}"
      end
    end
  end

  def load_patches_from_config
    config_file = Rails.root.join("config", "data_patches.yml")
    return unless config_file.exist?

    begin
      config = YAML.load_file(config_file)
      patches_config = config["patches"] || {}

      patches_config.each do |patch_name, patch_info|
        class_name = patch_info["class_name"] || patch_name.camelize

        if Object.const_defined?(class_name)
          patch_class = Object.const_get(class_name)

          metadata = {
            source: "config_file",
            description: patch_info["description"],
            category: patch_info["category"] || "general",
            target_tables: patch_info["target_tables"] || [],
            estimated_records: patch_info["estimated_records"],
            memory_limit: patch_info["memory_limit"],
            batch_size: patch_info["batch_size"]
          }

          register_patch(patch_name, patch_class, metadata)
        else
          Rails.logger.warn "[DataPatchRegistry] クラスが見つかりません: #{class_name}"
        end
      end
    rescue => error
      Rails.logger.error "[DataPatchRegistry] 設定ファイルロードエラー: #{error.message}"
    end
  end

  def default_metadata
    {
      description: "",
      category: "general",
      status: "active",
      target_tables: [],
      estimated_records: 0,
      memory_limit: 500,
      batch_size: 1000,
      source: "manual"
    }
  end
end

# ============================================================================
# 便利なヘルパーメソッド
# ============================================================================

module DataPatchHelper
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def register_as_data_patch(name, metadata = {})
      DataPatchRegistry.register_patch(name, self, metadata)
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

  def estimate_target_count(options = {})
    raise NotImplementedError, "estimate_target_count メソッドを実装してください"
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
