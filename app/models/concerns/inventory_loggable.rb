# frozen_string_literal: true

module InventoryLoggable
  extend ActiveSupport::Concern

  included do
    # CLAUDE.md準拠: 監査ログの完全性保護（削除禁止）
    # メタ認知: 監査証跡は永続保存が必要なため、親レコードの削除時も保護
    # TODO: Phase 2 - 削除時の適切なエラーメッセージのi18n対応
    has_many :inventory_logs, dependent: :restrict_with_error

    after_save :log_inventory_changes, if: :saved_change_to_quantity?
  end

  # インスタンスメソッド
  def log_operation(operation_type, delta, note = nil, user_id = nil)
    previous_quantity = quantity - delta

    inventory_logs.create!(
      delta: delta,
      operation_type: operation_type,
      previous_quantity: previous_quantity,
      current_quantity: quantity,
      user_id: user_id || (defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil),
      note: note || "手動記録: #{operation_type}"
    )
  end

  def adjust_quantity(new_quantity, note = nil, user_id = nil)
    delta = new_quantity - quantity
    return if delta.zero?

    operation_type = delta.positive? ? "add" : "remove"

    with_transaction do
      update!(quantity: new_quantity)
      log_operation(operation_type, delta, note, user_id)
    end
  end

  def add_stock(amount, note = nil, user_id = nil)
    return false if amount <= 0

    with_transaction do
      update!(quantity: quantity + amount)
      log_operation("add", amount, note || "入庫処理", user_id)
    end

    true
  end

  def remove_stock(amount, note = nil, user_id = nil)
    return false if amount <= 0 || amount > quantity

    with_transaction do
      update!(quantity: quantity - amount)
      log_operation("remove", -amount, note || "出庫処理", user_id)
    end

    true
  end

  private

  def log_inventory_changes
    return unless saved_change_to_quantity?

    previous_quantity = saved_change_to_quantity.first || 0
    current_quantity = quantity
    delta = current_quantity - previous_quantity

    return if delta.zero?

    inventory_logs.create!(
      delta: delta,
      operation_type: determine_operation_type(delta),
      previous_quantity: previous_quantity,
      current_quantity: current_quantity,
      user_id: defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil,
      note: "自動記録：数量変更"
    )
  rescue => e
    Rails.logger.error("在庫ログ記録エラー: #{e.message}")
  end

  def determine_operation_type(delta)
    case
    when delta > 0 then "add"
    when delta < 0 then "remove"
    else "adjust"
    end
  end

  def with_transaction(&block)
    self.class.transaction(&block)
  end

  # クラスメソッド
  module ClassMethods
    def recent_operations(limit = 50)
      includes(:inventory_logs)
        .joins(:inventory_logs)
        .order("inventory_logs.created_at DESC")
        .limit(limit)
    end

    def operation_summary(start_date = 30.days.ago, end_date = Time.current)
      joins(:inventory_logs)
        .where("inventory_logs.created_at BETWEEN ? AND ?", start_date, end_date)
        .group("inventory_logs.operation_type")
        .select("inventory_logs.operation_type, COUNT(*) as count, SUM(ABS(inventory_logs.delta)) as total_quantity")
    end

    # バルクインサート後のログ一括作成
    def create_bulk_inventory_logs(records, inserted_ids)
      return if records.blank? || inserted_ids.blank?

      log_entries = []

      records.each_with_index do |record, index|
        # Handle both formats: array of arrays (PostgreSQL style) or simple array (MySQL style)
        inventory_id = inserted_ids[index].is_a?(Array) ? inserted_ids[index][0] : inserted_ids[index]

        log_entries << {
          inventory_id: inventory_id,
          delta: record.quantity,
          operation_type: "add",
          previous_quantity: 0,
          current_quantity: record.quantity,
          note: "CSVインポートによる登録"
        }
      end

      InventoryLog.insert_all(log_entries, record_timestamps: true) if log_entries.present?
    end

    # バルクインサート後の在庫ログ一括作成
    # @param records [Array<Inventory>] インサートしたInventoryオブジェクト
    # @param inserted_ids [Array<Array>] insert_allの戻り値（主キーの配列）
    def create_bulk_logs(records, inserted_ids)
      create_bulk_inventory_logs(records, inserted_ids)
    end

    # ============================================
    # TODO: 在庫ログ機能の拡張（CLAUDE.md準拠）
    # ============================================
    #
    # 🔴 Phase 2: データ完全性強化（優先度: 高、推定2日）
    # 1. 削除戦略の改善
    #    - 在庫の論理削除（ソフトデリート）実装
    #    - 削除済み在庫の監査ログ永続保存
    #    - アーカイブ機能によるデータ保持
    #    - 横展開: 他の重要モデルへの適用検討
    #
    # 2. 監査証跡の強化
    #    - ログの完全性チェック機能
    #    - 改ざん防止のためのハッシュチェーン実装
    #    - デジタル署名によるログ認証
    #    - GDPR/PCI DSS準拠の保存期間管理
    #
    # 🟡 Phase 3: 分析機能拡張（優先度: 中、推定3日）
    # 1. ログの詳細分析機能
    #    - 操作頻度の可視化とトレンド分析
    #    - 異常操作の検出と警告システム
    #    - ユーザー別操作統計の生成
    #    - 在庫回転率・適正在庫分析
    #
    # 🟢 Phase 4: パフォーマンス最適化（優先度: 低、推定2日）
    # 1. 大規模データ対応
    #    - ログテーブルのパーティショニング
    #    - アーカイブ機能の実装
    #    - 非同期ログ処理の導入
    #    - インデックス最適化
    #
    # ============================================
    # メタ認知的改善ポイント（今回の問題から得た教訓）
    # ============================================
    # 1. **依存関係の慎重な設計**: dependent オプションの選択が重要
    #    - :destroy → 監査ログには不適切
    #    - :restrict_with_error → 現在の選択（保護優先）
    #    - :nullify → 将来の論理削除実装時に検討
    #
    # 2. **エラーハンドリングの重要性**:
    #    - ユーザーへの明確なフィードバック
    #    - 適切なログ記録
    #    - 例外の分類と個別対応
    #
    # 3. **横展開チェックリスト**:
    #    - [ ] 全ログ系モデルのdependent確認
    #    - [ ] 削除制限の一貫性確保
    #    - [ ] エラーメッセージのi18n対応
    #    - [ ] 論理削除の段階的導入計画
  end
end
