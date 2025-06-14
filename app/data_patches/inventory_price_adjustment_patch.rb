# frozen_string_literal: true

# ============================================================================
# InventoryPriceAdjustmentPatch
# ============================================================================
# 目的: 在庫商品の価格一括調整データパッチ
# 利用場面: 消費税率変更、仕入れ価格変動、キャンペーン価格設定
#
# 実装例: 月次レポート自動化システムのデータパッチ機能
# 設計思想: 安全性・トレーサビリティ・ロールバック対応

class InventoryPriceAdjustmentPatch < DataPatch
  include DataPatchHelper
  include ActionView::Helpers::NumberHelper

  # ============================================================================
  # クラスレベル設定とメタデータ
  # ============================================================================

  # TODO: ✅ Rails 8.0対応 - パッチ登録を config/initializers/data_patch_registration.rb に移動
  # 理由: eager loading時の DataPatch基底クラス読み込み順序問題の回避
  # 登録情報は data_patch_registration.rb で管理

  # ============================================================================
  # クラスメソッド（DataPatchRegistry用）
  # ============================================================================

  def self.estimate_target_count(options = {})
    conditions = build_target_conditions(options)
    Inventory.where(conditions).count
  end

  def self.build_target_conditions(options)
    conditions = {}

    # TODO: ✅ 修正済み - Inventoryモデルにcategoryカラム未存在のため削除
    # 将来的にcategoryカラムが追加された場合は以下のコードを有効化:
    # if options[:category].present?
    #   conditions[:category] = options[:category]
    # end

    # 価格範囲フィルタ
    if options[:min_price].present?
      conditions[:price] = (options[:min_price]..)
    end

    if options[:max_price].present?
      range = conditions[:price] || (0..)
      conditions[:price] = (range.begin..options[:max_price])
    end

    # 更新日時フィルタ（古いデータのみ対象）
    if options[:before_date].present?
      conditions[:updated_at] = (..options[:before_date])
    end

    conditions
  end

  # ============================================================================
  # 初期化
  # ============================================================================

  def initialize(options = {})
    super(options)

    @adjustment_type = options[:adjustment_type] || "percentage"
    @adjustment_value = options[:adjustment_value] || 0
    @target_conditions = self.class.build_target_conditions(options)
    @dry_run_results = []

    validate_adjustment_parameters!
  end

  # ============================================================================
  # バッチ実行（DataPatchExecutor用）
  # ============================================================================

  def execute_batch(batch_size, offset)
    log_info "バッチ実行開始: batch_size=#{batch_size}, offset=#{offset}"

    # 対象レコード取得
    inventories = Inventory.where(@target_conditions)
                           .limit(batch_size)
                           .offset(offset)
                           .includes(:batches, :inventory_logs)

    return { count: 0, records: [], finished: true } if inventories.empty?

    # バッチ処理実行
    processed_records = []
    inventories.each do |inventory|
      result = process_single_inventory(inventory)
      processed_records << result if result
    end

    log_info "バッチ処理完了: 処理件数=#{processed_records.size}/#{inventories.size}"

    {
      count: processed_records.size,
      records: processed_records,
      finished: inventories.size < batch_size
    }
  end

  # ============================================================================
  # 単一レコード処理
  # ============================================================================

  private

  def process_single_inventory(inventory)
    old_price = inventory.price
    new_price = calculate_new_price(old_price)

    # 価格変更ログの準備
    change_log = {
      inventory_id: inventory.id,
      name: inventory.name,
      old_price: old_price,
      new_price: new_price,
      adjustment_type: @adjustment_type,
      adjustment_value: @adjustment_value,
      processed_at: Time.current
    }

    if dry_run?
      # Dry-runモード: 実際の更新は行わない
      @dry_run_results << change_log
      log_info "DRY RUN: #{inventory.name} - #{old_price}円 → #{new_price}円"
      return change_log
    end

    # 実際の価格更新
    begin
      inventory.update!(
        price: new_price,
        updated_at: Time.current
      )

      # 変更履歴をInventoryLogに記録
      create_inventory_log(inventory, old_price, new_price)

      log_info "価格更新完了: #{inventory.name} - #{old_price}円 → #{new_price}円"
      change_log[:success] = true
      change_log

    rescue => error
      log_error "価格更新エラー: #{inventory.name} - #{error.message}"
      change_log[:success] = false
      change_log[:error] = error.message
      change_log
    end
  end

  def calculate_new_price(current_price)
    case @adjustment_type
    when "percentage"
      # パーセンテージ調整: 10% → adjustment_value = 10
      (current_price * (1 + @adjustment_value / 100.0)).round
    when "fixed_amount"
      # 固定金額調整: +100円 → adjustment_value = 100
      [ current_price + @adjustment_value, 0 ].max
    when "multiply"
      # 倍率調整: 1.08倍（消費税） → adjustment_value = 1.08
      (current_price * @adjustment_value).round
    when "set_value"
      # 固定価格設定 → adjustment_value = 新価格
      @adjustment_value
    else
      raise ArgumentError, "未対応の調整タイプ: #{@adjustment_type}"
    end
  end

  def create_inventory_log(inventory, old_price, new_price)
    # InventoryLogは在庫数量の変化を記録するため、価格変更では数量変化なし
    InventoryLog.create!(
      inventory: inventory,
      user_id: Current.admin&.id,
      operation_type: "adjust",  # OPERATION_TYPESに存在する値を使用
      delta: 0,  # 価格変更では数量変化なし
      previous_quantity: inventory.quantity,
      current_quantity: inventory.quantity,
      note: "価格調整: #{old_price}円 → #{new_price}円 (#{@adjustment_type}:#{@adjustment_value})"
    )
  rescue => error
    log_error "InventoryLog作成エラー: #{error.message}"
    # ログ作成エラーは処理を停止しない（データ更新は成功しているため）
  end

  def validate_adjustment_parameters!
    unless %w[percentage fixed_amount multiply set_value].include?(@adjustment_type)
      raise ArgumentError, "adjustment_typeが無効です: #{@adjustment_type}"
    end

    unless @adjustment_value.is_a?(Numeric)
      raise ArgumentError, "adjustment_valueは数値である必要があります: #{@adjustment_value}"
    end

    case @adjustment_type
    when "percentage"
      unless @adjustment_value.between?(-100, 1000)
        raise ArgumentError, "percentage調整値は-100〜1000の範囲である必要があります: #{@adjustment_value}"
      end
    when "multiply"
      unless @adjustment_value > 0
        raise ArgumentError, "multiply調整値は正の数である必要があります: #{@adjustment_value}"
      end
    when "set_value"
      unless @adjustment_value >= 0
        raise ArgumentError, "set_value調整値は0以上である必要があります: #{@adjustment_value}"
      end
    end
  end

  # ============================================================================
  # ユーティリティメソッド
  # ============================================================================

  public

  def dry_run_summary
    return "Dry-runが実行されていません" unless dry_run? && @dry_run_results.any?

    total_count = @dry_run_results.size
    total_old_amount = @dry_run_results.sum { |r| r[:old_price] }
    total_new_amount = @dry_run_results.sum { |r| r[:new_price] }
    difference = total_new_amount - total_old_amount

    summary = []
    summary << "=== 価格調整 Dry-run 結果サマリー ==="
    summary << "対象商品数: #{total_count}件"
    summary << "調整前合計金額: #{number_with_delimiter(total_old_amount)}円"
    summary << "調整後合計金額: #{number_with_delimiter(total_new_amount)}円"
    summary << "差額: #{difference >= 0 ? '+' : ''}#{number_with_delimiter(difference)}円"
    summary << "調整タイプ: #{@adjustment_type}"
    summary << "調整値: #{@adjustment_value}"
    summary << "=" * 50

    summary.join("\n")
  end

  def execution_statistics
    return {} unless @dry_run_results.any?

    {
      total_processed: @dry_run_results.size,
      adjustment_type: @adjustment_type,
      adjustment_value: @adjustment_value,
      total_price_before: @dry_run_results.sum { |r| r[:old_price] },
      total_price_after: @dry_run_results.sum { |r| r[:new_price] },
      average_price_before: (@dry_run_results.sum { |r| r[:old_price] } / @dry_run_results.size.to_f).round(2),
      average_price_after: (@dry_run_results.sum { |r| r[:new_price] } / @dry_run_results.size.to_f).round(2)
    }
  end
end

# ============================================================================
# 使用例とドキュメント
# ============================================================================

=begin

# 基本的な使用例

# 1. 消費税率変更（8% → 10%）
executor = DataPatchExecutor.new('inventory_price_adjustment', {
  adjustment_type: 'multiply',
  adjustment_value: 1.025,  # 2.5%増（8% → 10%の差分）
  dry_run: true
})

# 2. カテゴリ別価格調整（10%値上げ）
executor = DataPatchExecutor.new('inventory_price_adjustment', {
  adjustment_type: 'percentage',
  adjustment_value: 10,
  category: 'medicine',
  dry_run: false
})

# 3. 特定価格帯の一律調整（1000円以下商品を100円値上げ）
executor = DataPatchExecutor.new('inventory_price_adjustment', {
  adjustment_type: 'fixed_amount',
  adjustment_value: 100,
  max_price: 1000,
  dry_run: false
})

# 実行
result = executor.execute

=end
