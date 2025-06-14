# frozen_string_literal: true

# ============================================================================
# データパッチ・バッチ処理 Rake タスク
# ============================================================================
# 目的: 本番環境での安全なデータパッチ実行とリリース作業自動化
# 機能: 検証・実行・ロールバック・通知・監査ログ
#
# 設計思想:
#   - セキュリティバイデザイン: 全操作の監査ログ
#   - フェイルセーフ: エラー時の自動ロールバック
#   - スケーラビリティ: メモリ効率とバッチ処理
#   - 可観測性: 詳細な実行ログと進捗通知

namespace :data_patch do
  # ============================================================================
  # 基本実行タスク
  # ============================================================================

  desc "データパッチを実行します（必須: patch_name）"
  task :execute, [ :patch_name ] => :environment do |task, args|
    if args[:patch_name].blank?
      puts "エラー: patch_name が必要です"
      puts "使用例: bundle exec rake data_patch:execute[inventory_price_adjustment]"
      next
    end

    options = parse_execution_options
    dry_run = ENV["DRY_RUN"] == "true"

    puts "=" * 80
    puts "データパッチ実行: #{args[:patch_name]}"
    puts "DRY RUN: #{dry_run ? 'YES' : 'NO'}"
    puts "実行環境: #{Rails.env}"
    puts "実行者: #{Current.admin&.email || 'system'}"
    puts "=" * 80

    begin
      executor = DataPatchExecutor.new(args[:patch_name], options.merge(dry_run: dry_run))
      result = executor.execute

      puts "\n実行完了!"
      puts "処理件数: #{result[:processed_count]}"
      puts "実行時間: #{result[:execution_time].round(2)}秒" if result[:execution_time]
      puts "成功: #{result[:success] ? 'YES' : 'NO'}"

      if dry_run
        puts "\nDRY RUN実行のため、実際のデータ変更は行われていません。"
        puts "本番実行時は DRY_RUN=false を指定してください。"
      end

    rescue DataPatchExecutor::DataPatchError => error
      puts "\nデータパッチエラー: #{error.message}"
      exit 1
    rescue => error
      puts "\n予期しないエラー: #{error.message}"
      puts error.backtrace if ENV["VERBOSE"] == "true"
      exit 1
    end
  end

  # ============================================================================
  # 管理・確認タスク
  # ============================================================================

  desc "利用可能なデータパッチ一覧を表示します"
  task list: :environment do
    puts "利用可能なデータパッチ一覧:"
    puts "=" * 80

    # パッチレジストリの再読み込み（Rake環境用）
    DataPatchRegistry.reload_patches
    patches = DataPatchRegistry.list_patches
    if patches.empty?
      puts "登録されているパッチがありません。"
    else
      patches.each do |patch|
        metadata = patch[:metadata]
        puts "\n📦 #{patch[:name]}"
        puts "   説明: #{metadata[:description]}"
        puts "   カテゴリ: #{metadata[:category]}"
        puts "   対象テーブル: #{metadata[:target_tables].join(', ')}"
        puts "   推定レコード数: #{metadata[:estimated_records].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
        puts "   メモリ制限: #{metadata[:memory_limit]}MB"
        puts "   バッチサイズ: #{metadata[:batch_size]}"
        puts "   ステータス: #{metadata[:status]}"
      end
    end

    puts "\n使用例:"
    puts "  bundle exec rake data_patch:execute[inventory_price_adjustment] DRY_RUN=true"
    puts "  bundle exec rake data_patch:execute[batch_expiry_update] BATCH_SIZE=500"
  end

  desc "データパッチの詳細情報を表示します"
  task :info, [ :patch_name ] => :environment do |task, args|
    if args[:patch_name].blank?
      puts "エラー: patch_name が必要です"
      puts "使用例: bundle exec rake data_patch:info[inventory_price_adjustment]"
      next
    end

    begin
      metadata = DataPatchRegistry.patch_metadata(args[:patch_name])
      patch_class = DataPatchRegistry.find_patch(args[:patch_name])

      puts "データパッチ詳細情報: #{args[:patch_name]}"
      puts "=" * 80
      puts "クラス名: #{patch_class.name}"
      puts "説明: #{metadata[:description]}"
      puts "カテゴリ: #{metadata[:category]}"
      puts "ステータス: #{metadata[:status]}"
      puts "登録日時: #{metadata[:registered_at]}"
      puts "登録元: #{metadata[:source]}"
      puts ""
      puts "技術仕様:"
      puts "  対象テーブル: #{metadata[:target_tables].join(', ')}"
      puts "  推定レコード数: #{metadata[:estimated_records].to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
      puts "  推奨メモリ制限: #{metadata[:memory_limit]}MB"
      puts "  推奨バッチサイズ: #{metadata[:batch_size]}"
      puts ""

      # 実際の対象件数を確認
      sample_options = parse_execution_options
      target_count = patch_class.estimate_target_count(sample_options)
      puts "現在の対象レコード数: #{target_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"

      if metadata[:file_path]
        puts "ファイルパス: #{metadata[:file_path]}"
      end

    rescue DataPatchRegistry::PatchNotFoundError => error
      puts "エラー: #{error.message}"
      puts "\n利用可能なパッチ一覧:"
      Rake::Task["data_patch:list"].invoke
    end
  end

  desc "データパッチレジストリの統計情報を表示します"
  task stats: :environment do
    stats = DataPatchRegistry.registry_statistics

    puts "データパッチレジストリ統計情報"
    puts "=" * 80
    puts "総パッチ数: #{stats[:total_patches]}"
    puts "レジストリ読み込み日時: #{stats[:registry_loaded_at]}"
    puts "最終パッチ登録日時: #{stats[:last_registered] || 'なし'}"
    puts ""

    if stats[:by_category].any?
      puts "カテゴリ別内訳:"
      stats[:by_category].each do |category, count|
        puts "  #{category}: #{count}件"
      end
      puts ""
    end

    if stats[:by_status].any?
      puts "ステータス別内訳:"
      stats[:by_status].each do |status, count|
        puts "  #{status}: #{count}件"
      end
    end
  end

  # ============================================================================
  # 保守・管理タスク
  # ============================================================================

  desc "データパッチレジストリをリロードします"
  task reload: :environment do
    puts "データパッチレジストリをリロードしています..."
    DataPatchRegistry.reload_patches

    stats = DataPatchRegistry.registry_statistics
    puts "リロード完了: #{stats[:total_patches]}個のパッチが読み込まれました"
  end

  desc "データパッチの設定ファイル例を生成します"
  task generate_config: :environment do
    config_path = Rails.root.join("config", "data_patches.yml")

    if config_path.exist?
      puts "設定ファイルが既に存在します: #{config_path}"
      puts "上書きする場合は FORCE=true を指定してください"
      next unless ENV["FORCE"] == "true"
    end

    sample_config = {
      "patches" => {
        "inventory_price_adjustment" => {
          "description" => "在庫アイテムの価格一括調整",
          "category" => "inventory",
          "target_tables" => [ "inventories" ],
          "estimated_records" => 100000,
          "memory_limit" => 1024,
          "batch_size" => 2000
        },
        "batch_expiry_update" => {
          "description" => "期限切れバッチの状態更新",
          "category" => "maintenance",
          "target_tables" => [ "batches", "inventory_logs" ],
          "estimated_records" => 50000,
          "memory_limit" => 512,
          "batch_size" => 1000
        }
      },
      "security" => {
        "log_encryption" => true,
        "audit_retention_days" => 90,
        "notification_channels" => [ "slack", "email" ]
      },
      "scheduling" => {
        "default_timezone" => "Asia/Tokyo",
        "maintenance_windows" => [
          {
            "start" => "02:00",
            "end" => "04:00",
            "days" => [ "sunday", "wednesday" ]
          }
        ]
      }
    }

    File.write(config_path, sample_config.to_yaml)
    puts "設定ファイルを生成しました: #{config_path}"
    puts "必要に応じて内容を編集してください。"
  end

  desc "DRY RUNですべてのパッチの影響範囲を確認します"
  task check_all: :environment do
    puts "全データパッチの影響範囲確認"
    puts "=" * 80

    patches = DataPatchRegistry.list_patches
    sample_options = parse_execution_options

    patches.each do |patch|
      begin
        patch_class = DataPatchRegistry.find_patch(patch[:name])
        target_count = patch_class.estimate_target_count(sample_options)

        puts "#{patch[:name]}:"
        puts "  対象レコード数: #{target_count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
        puts "  カテゴリ: #{patch[:metadata][:category]}"
        puts "  対象テーブル: #{patch[:metadata][:target_tables].join(', ')}"
        puts ""
      rescue => error
        puts "#{patch[:name]}: エラー - #{error.message}"
        puts ""
      end
    end
  end

  # ============================================================================
  # スケジューリング対応タスク
  # ============================================================================

  desc "スケジュール実行: 期限切れバッチの定期更新"
  task scheduled_expiry_update: :environment do
    puts "スケジュール実行: 期限切れバッチ更新"

    options = {
      grace_period: 3,
      include_expiring_soon: true,
      warning_days: 30,
      update_inventory_status: true,
      create_notification: true,
      dry_run: false
    }

    begin
      executor = DataPatchExecutor.new("batch_expiry_update", options)
      result = executor.execute

      puts "スケジュール実行完了: #{result[:processed_count]}件処理"
    rescue => error
      puts "スケジュール実行エラー: #{error.message}"
      # TODO: 🟡 Phase 3（中）- エラー通知システムとの統合
      raise error
    end
  end

  # ============================================================================
  # ユーティリティメソッド
  # ============================================================================

  private

  def parse_execution_options
    options = {}

    # 基本オプション
    options[:batch_size] = ENV["BATCH_SIZE"].to_i if ENV["BATCH_SIZE"]
    options[:memory_limit] = ENV["MEMORY_LIMIT"].to_i if ENV["MEMORY_LIMIT"]
    options[:timeout_seconds] = ENV["TIMEOUT"].to_i if ENV["TIMEOUT"]

    # パッチ固有オプション（inventory_price_adjustment用）
    options[:adjustment_type] = ENV["ADJUSTMENT_TYPE"] if ENV["ADJUSTMENT_TYPE"]
    options[:adjustment_value] = ENV["ADJUSTMENT_VALUE"].to_f if ENV["ADJUSTMENT_VALUE"]
    options[:category] = ENV["CATEGORY"] if ENV["CATEGORY"]
    options[:min_price] = ENV["MIN_PRICE"].to_i if ENV["MIN_PRICE"]
    options[:max_price] = ENV["MAX_PRICE"].to_i if ENV["MAX_PRICE"]

    # パッチ固有オプション（batch_expiry_update用）
    options[:grace_period] = ENV["GRACE_PERIOD"].to_i if ENV["GRACE_PERIOD"]
    options[:include_expiring_soon] = ENV["INCLUDE_EXPIRING_SOON"] == "true" if ENV["INCLUDE_EXPIRING_SOON"]
    options[:warning_days] = ENV["WARNING_DAYS"].to_i if ENV["WARNING_DAYS"]

    # 日付オプション
    options[:expiry_date] = Date.parse(ENV["EXPIRY_DATE"]) if ENV["EXPIRY_DATE"]
    options[:before_date] = Date.parse(ENV["BEFORE_DATE"]) if ENV["BEFORE_DATE"]

    # 通知・ログオプション
    options[:notification_enabled] = ENV["NOTIFICATION"] != "false"
    options[:audit_enabled] = ENV["AUDIT"] != "false"

    options.compact
  end
end

# ============================================================================
# 使用例とドキュメント
# ============================================================================

=begin

# 基本的な使用例

# 1. パッチ一覧確認
bundle exec rake data_patch:list

# 2. パッチ詳細確認
bundle exec rake data_patch:info[inventory_price_adjustment]

# 3. Dry-run実行（推奨）
bundle exec rake data_patch:execute[inventory_price_adjustment] DRY_RUN=true ADJUSTMENT_TYPE=percentage ADJUSTMENT_VALUE=10

# 4. 本番実行
bundle exec rake data_patch:execute[inventory_price_adjustment] DRY_RUN=false ADJUSTMENT_TYPE=percentage ADJUSTMENT_VALUE=10

# 5. カスタムオプション付き実行
bundle exec rake data_patch:execute[batch_expiry_update] GRACE_PERIOD=7 INCLUDE_EXPIRING_SOON=true

# 6. バッチサイズ・メモリ制限のカスタマイズ
bundle exec rake data_patch:execute[inventory_price_adjustment] BATCH_SIZE=500 MEMORY_LIMIT=1024

# 7. 影響範囲事前確認
bundle exec rake data_patch:check_all

# 環境変数オプション一覧:
# - DRY_RUN: true/false (default: false)
# - BATCH_SIZE: 数値 (default: 1000)
# - MEMORY_LIMIT: MB単位 (default: 500)
# - TIMEOUT: 秒単位 (default: 3600)
# - NOTIFICATION: true/false (default: true)
# - AUDIT: true/false (default: true)
# - VERBOSE: true/false (エラー詳細表示)

=end
