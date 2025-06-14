# frozen_string_literal: true

# ============================================================================
# Data Patch Registration Initializer
# ============================================================================
# 目的: Rails 8.0対応 - データパッチ自動登録の初期化後処理
# 問題: eager loading時の DataPatch基底クラス読み込み順序問題
# 解決: 全クラス読み込み完了後にパッチ登録を実行

Rails.application.config.after_initialize do
  # データパッチの自動登録（Rails 8.0対応）
  Rails.logger.info "[DataPatchRegistration] データパッチ自動登録を開始"

  # 手動でパッチを登録
  begin
    # InventoryPriceAdjustmentPatch登録
    if defined?(InventoryPriceAdjustmentPatch)
      DataPatchRegistry.register_patch("inventory_price_adjustment", InventoryPriceAdjustmentPatch, {
        description: "在庫商品の価格一括調整（消費税率変更・仕入れ価格変動・キャンペーン対応）",
        category: "inventory",
        target_tables: %w[inventories inventory_logs],
        estimated_records: 1000,
        memory_limit: 256,
        batch_size: 100,
        tags: %w[price adjustment inventory bulk_update],
        risk_level: "medium",
        rollback_strategy: "automatic",
        supported_adjustments: %w[percentage fixed_amount multiply set_value],
        filter_options: %w[min_price max_price before_date]
      })
      Rails.logger.info "[DataPatchRegistration] InventoryPriceAdjustmentPatch 登録完了"
    end

    # BatchExpiryUpdatePatch登録
    if defined?(BatchExpiryUpdatePatch)
      DataPatchRegistry.register_patch("batch_expiry_update", BatchExpiryUpdatePatch, {
        description: "期限切れバッチの状態更新とクリーンアップ処理",
        category: "maintenance",
        target_tables: %w[batches inventory_logs],
        estimated_records: 500,
        memory_limit: 128,
        batch_size: 50,
        tags: %w[batch expiry maintenance cleanup],
        risk_level: "low",
        rollback_strategy: "manual",
        cleanup_strategies: %w[archive soft_delete status_update notification]
      })
      Rails.logger.info "[DataPatchRegistration] BatchExpiryUpdatePatch 登録完了"
    end

    Rails.logger.info "[DataPatchRegistration] データパッチ自動登録完了"

  rescue => error
    Rails.logger.error "[DataPatchRegistration] データパッチ登録エラー: #{error.message}"
    Rails.logger.error error.backtrace.join("\n")
  end
end
