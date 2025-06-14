# frozen_string_literal: true

# ============================================================================
# BatchExpiryUpdatePatch
# ============================================================================
# 目的: 期限切れバッチの状態更新とクリーンアップ
# 利用場面: 月次・四半期メンテナンス、期限管理の自動化
#
# 実装例: 月次レポート自動化システムのデータパッチ機能
# 設計思想: データ整合性・監査ログ・段階的処理

class BatchExpiryUpdatePatch < DataPatch
  include DataPatchHelper

  # ============================================================================
  # クラスレベル設定とメタデータ
  # ============================================================================

  # TODO: ✅ Rails 8.0対応 - パッチ登録を config/initializers/data_patch_registration.rb に移動
  # 理由: eager loading時の DataPatch基底クラス読み込み順序問題の回避
  # 登録情報は data_patch_registration.rb で管理

  # ============================================================================
  # クラスメソッド
  # ============================================================================

  def self.estimate_target_count(options = {})
    expiry_date = options[:expiry_date] || Date.current
    grace_period = options[:grace_period] || 0
    target_date = expiry_date - grace_period.days

    expired_count = Batch.where("expiry_date <= ?", target_date).count
    expiring_soon_count = if options[:include_expiring_soon]
      warning_days = options[:warning_days] || 30
      Batch.where(
        expiry_date: (target_date + 1.day)..(target_date + warning_days.days)
      ).count
    else
      0
    end

    expired_count + expiring_soon_count
  end

  # ============================================================================
  # 初期化
  # ============================================================================

  def initialize(options = {})
    super(options)

    @expiry_date = options[:expiry_date] || Date.current
    @grace_period = options[:grace_period] || 0
    @include_expiring_soon = options[:include_expiring_soon] || false
    @warning_days = options[:warning_days] || 30
    @update_inventory_status = options[:update_inventory_status] || true
    @create_notification = options[:create_notification] || true

    @statistics = {
      expired_batches: 0,
      expiring_soon_batches: 0,
      updated_inventories: 0,
      created_logs: 0,
      errors: []
    }
  end

  # ============================================================================
  # バッチ実行
  # ============================================================================

  def execute_batch(batch_size, offset)
    log_info "期限切れバッチ更新開始: batch_size=#{batch_size}, offset=#{offset}"

    # 対象バッチ取得
    target_batches = build_target_query
                      .limit(batch_size)
                      .offset(offset)
                      .includes(:inventory)

    return { count: 0, finished: true } if target_batches.empty?

    # バッチ処理実行
    processed_count = 0
    target_batches.each do |batch|
      if process_single_batch(batch)
        processed_count += 1
      end
    end

    log_info "期限切れバッチ更新完了: 処理件数=#{processed_count}/#{target_batches.size}"

    {
      count: processed_count,
      finished: target_batches.size < batch_size,
      statistics: @statistics.dup
    }
  end

  # ============================================================================
  # 単一バッチ処理
  # ============================================================================

  private

  def process_single_batch(batch)
    expiry_status = determine_expiry_status(batch)
    return false unless expiry_status

    if dry_run?
      log_dry_run_action(batch, expiry_status)
      update_statistics(expiry_status)
      return true
    end

    begin
      # バッチ状態更新
      update_batch_status(batch, expiry_status)

      # 関連在庫の状態更新
      update_related_inventory(batch) if @update_inventory_status

      # 監査ログ作成
      create_audit_log(batch, expiry_status)

      # 通知作成（必要に応じて）
      create_expiry_notification(batch, expiry_status) if @create_notification

      update_statistics(expiry_status)
      log_info "バッチ更新完了: #{batch.batch_number} (#{expiry_status})"

      true
    rescue => error
      @statistics[:errors] << {
        batch_id: batch.id,
        batch_number: batch.batch_number,
        error: error.message
      }
      log_error "バッチ更新エラー: #{batch.batch_number} - #{error.message}"
      false
    end
  end

  def determine_expiry_status(batch)
    target_date = @expiry_date - @grace_period.days

    if batch.expiry_date <= target_date
      "expired"
    elsif @include_expiring_soon && batch.expiry_date <= target_date + @warning_days.days
      "expiring_soon"
    else
      nil # 処理対象外
    end
  end

  def update_batch_status(batch, expiry_status)
    case expiry_status
    when "expired"
      batch.update!(
        status: "expired",
        updated_at: Time.current
      )
    when "expiring_soon"
      batch.update!(
        status: "expiring_soon",
        updated_at: Time.current
      )
    end
  end

  def update_related_inventory(batch)
    inventory = batch.inventory
    return unless inventory

    # 在庫の有効バッチ数を再計算
    active_batches_count = inventory.batches.where.not(status: [ "expired", "consumed" ]).count

    # 在庫ステータス更新判定
    if active_batches_count == 0
      inventory.update!(status: "out_of_stock")
      @statistics[:updated_inventories] += 1
    elsif inventory.batches.where(status: "expiring_soon").exists?
      inventory.update!(status: "expiring_soon") unless inventory.status == "expired"
      @statistics[:updated_inventories] += 1
    end
  end

  def create_audit_log(batch, expiry_status)
    InventoryLog.create!(
      inventory: batch.inventory,
      admin: Current.admin,
      action: "batch_expiry_update",
      details: {
        batch_id: batch.id,
        batch_number: batch.batch_number,
        old_status: batch.status_was,
        new_status: batch.status,
        expiry_date: batch.expiry_date,
        expiry_status: expiry_status,
        patch_execution_id: @options[:execution_id],
        grace_period: @grace_period
      }.to_json,
      created_at: Time.current
    )

    @statistics[:created_logs] += 1
  end

  def create_expiry_notification(batch, expiry_status)
    # TODO: 🟡 Phase 3（中）- 通知システムとの統合
    # 実装予定: Slack/メール通知、管理者ダッシュボード更新
    # 現在はログ出力のみ

    case expiry_status
    when "expired"
      log_info "期限切れ通知: #{batch.inventory.name} - バッチ #{batch.batch_number}"
    when "expiring_soon"
      log_info "期限切れ警告: #{batch.inventory.name} - バッチ #{batch.batch_number}"
    end
  end

  def build_target_query
    target_date = @expiry_date - @grace_period.days

    query = Batch.where("expiry_date <= ?", target_date)

    if @include_expiring_soon
      expiring_date = target_date + @warning_days.days
      query = query.or(
        Batch.where(
          expiry_date: (target_date + 1.day)..expiring_date
        )
      )
    end

    # 既に処理済みのバッチを除外
    query = query.where.not(status: [ "expired" ]) unless @include_expiring_soon

    query.order(:expiry_date)
  end

  def update_statistics(expiry_status)
    case expiry_status
    when "expired"
      @statistics[:expired_batches] += 1
    when "expiring_soon"
      @statistics[:expiring_soon_batches] += 1
    end
  end

  def log_dry_run_action(batch, expiry_status)
    case expiry_status
    when "expired"
      log_info "DRY RUN: バッチ期限切れ設定 - #{batch.batch_number} (期限: #{batch.expiry_date})"
    when "expiring_soon"
      log_info "DRY RUN: バッチ期限切れ警告設定 - #{batch.batch_number} (期限: #{batch.expiry_date})"
    end
  end

  # ============================================================================
  # 統計情報とレポート
  # ============================================================================

  public

  def execution_summary
    total_processed = @statistics[:expired_batches] + @statistics[:expiring_soon_batches]

    summary = []
    summary << "=== 期限切れバッチ更新 実行結果 ==="
    summary << "処理対象期間: #{@expiry_date - @grace_period.days} 以前"
    summary << "猶予期間: #{@grace_period}日"
    summary << ""
    summary << "処理結果:"
    summary << "- 期限切れバッチ: #{@statistics[:expired_batches]}件"
    summary << "- 期限切れ警告バッチ: #{@statistics[:expiring_soon_batches]}件" if @include_expiring_soon
    summary << "- 更新された在庫: #{@statistics[:updated_inventories]}件"
    summary << "- 作成された監査ログ: #{@statistics[:created_logs]}件"
    summary << "- エラー件数: #{@statistics[:errors].size}件"
    summary << ""

    if @statistics[:errors].any?
      summary << "エラー詳細:"
      @statistics[:errors].each do |error|
        summary << "- バッチ #{error[:batch_number]}: #{error[:error]}"
      end
      summary << ""
    end

    summary << "=" * 50
    summary.join("\n")
  end

  def detailed_statistics
    {
      processing_date: @expiry_date,
      grace_period: @grace_period,
      include_expiring_soon: @include_expiring_soon,
      warning_days: @warning_days,
      statistics: @statistics,
      dry_run: dry_run?
    }
  end
end

# ============================================================================
# 使用例とドキュメント
# ============================================================================

=begin

# 基本的な使用例

# 1. 標準的な期限切れバッチ更新
executor = DataPatchExecutor.new('batch_expiry_update', {
  expiry_date: Date.current,
  grace_period: 0,
  dry_run: true
})

# 2. 猶予期間付き更新（7日猶予）
executor = DataPatchExecutor.new('batch_expiry_update', {
  expiry_date: Date.current,
  grace_period: 7,
  update_inventory_status: true,
  dry_run: false
})

# 3. 期限切れ警告も含む包括的更新
executor = DataPatchExecutor.new('batch_expiry_update', {
  include_expiring_soon: true,
  warning_days: 30,
  create_notification: true,
  dry_run: false
})

# 実行
result = executor.execute

=end
