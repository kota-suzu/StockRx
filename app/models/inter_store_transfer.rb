# frozen_string_literal: true

class InterStoreTransfer < ApplicationRecord
  # アソシエーション
  belongs_to :source_store, class_name: "Store"
  belongs_to :destination_store, class_name: "Store"
  belongs_to :inventory
  belongs_to :requested_by, class_name: "Admin"
  belongs_to :approved_by, class_name: "Admin", optional: true

  # ============================================
  # enum定義
  # ============================================
  enum :status, {
    pending: 0,      # 承認待ち
    approved: 1,     # 承認済み
    rejected: 2,     # 却下
    in_transit: 3,   # 移動中
    completed: 4,    # 完了
    cancelled: 5     # キャンセル
  }

  enum :priority, {
    normal: 0,       # 通常
    urgent: 1,       # 緊急
    emergency: 2     # 非常時
  }

  # ============================================
  # バリデーション
  # ============================================
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :reason, presence: true, length: { maximum: 1000 }
  # requested_atはbefore_validationコールバックで自動設定されるため、バリデーション不要
  validate :different_stores
  validate :sufficient_source_stock, on: :create
  validate :valid_status_transition, on: :update

  # ============================================
  # callbacks
  # ============================================
  before_validation :set_requested_at, on: :create
  after_create :reserve_source_stock
  after_update :handle_status_change
  before_destroy :release_reserved_stock, if: :can_be_cancelled?
  after_commit :update_store_pending_counts

  # ============================================
  # スコープ
  # ============================================
  scope :by_source_store, ->(store) { where(source_store: store) }
  scope :by_destination_store, ->(store) { where(destination_store: store) }
  scope :by_store, ->(store) { where("source_store_id = ? OR destination_store_id = ?", store.id, store.id) }
  scope :by_inventory, ->(inventory) { where(inventory: inventory) }
  scope :by_requestor, ->(admin) { where(requested_by: admin) }
  scope :by_approver, ->(admin) { where(approved_by: admin) }
  scope :recent, -> { order(requested_at: :desc) }
  scope :by_priority, ->(priority) { where(priority: priority) }
  scope :active, -> { where(status: [ :pending, :approved, :in_transit ]) }
  scope :completed_transfers, -> { where(status: [ :completed, :cancelled, :rejected ]) }

  # ============================================
  # インスタンスメソッド
  # ============================================

  # ステータス表示用
  def status_text
    case status
    when "pending" then "承認待ち"
    when "approved" then "承認済み"
    when "rejected" then "却下"
    when "in_transit" then "移動中"
    when "completed" then "完了"
    when "cancelled" then "キャンセル"
    end
  end

  # 優先度表示用
  def priority_text
    case priority
    when "normal" then "通常"
    when "urgent" then "緊急"
    when "emergency" then "非常時"
    end
  end

  # 移動先確認用の表示テキスト
  def transfer_summary
    "#{source_store.display_name} → #{destination_store.display_name}: #{inventory.name} × #{quantity}"
  end

  # 処理時間計算
  def processing_time
    return nil unless completed_at && requested_at

    completed_at - requested_at
  end

  # 承認可能かどうか
  def approvable?
    pending? && sufficient_stock_available?
  end

  # 却下可能かどうか
  def rejectable?
    pending?
  end

  # キャンセル可能かどうか
  def can_be_cancelled?
    pending? || approved?
  end

  # 完了処理可能かどうか
  def completable?
    approved? || in_transit?
  end

  # 移動元の利用可能在庫が十分かどうか
  def sufficient_stock_available?
    source_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)
    return false unless source_inventory

    source_inventory.available_quantity >= quantity
  end

  # 承認処理
  def approve!(approver, notes = nil)
    return false unless approvable?

    transaction do
      update!(
        status: :approved,
        approved_by: approver,
        approved_at: Time.current
      )

      # 承認通知（Phase 2で実装予定）
      # NotificationService.send_approval_notification(self)

      true
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  # 却下処理
  def reject!(approver, reason)
    return false unless rejectable?

    transaction do
      update!(
        status: :rejected,
        approved_by: approver,
        approved_at: Time.current,
        reason: "#{self.reason}\n\n【却下理由】\n#{reason}"
      )

      release_reserved_stock

      # 却下通知（Phase 2で実装予定）
      # NotificationService.send_rejection_notification(self, reason)

      true
    end
  rescue ActiveRecord::RecordInvalid
    false
  end

  # 移動実行処理
  def execute_transfer!
    return false unless completable?

    transaction do
      source_inventory = StoreInventory.find_by!(store: source_store, inventory: inventory)
      destination_inventory = StoreInventory.find_or_create_by!(
        store: destination_store,
        inventory: inventory
      ) do |si|
        si.quantity = 0
        si.reserved_quantity = 0
        si.safety_stock_level = 5  # デフォルト値
      end

      # 在庫移動実行
      source_inventory.quantity -= quantity
      source_inventory.reserved_quantity -= quantity
      destination_inventory.quantity += quantity

      source_inventory.save!
      destination_inventory.save!

      # 移動完了
      update!(
        status: :completed,
        completed_at: Time.current
      )

      # 完了通知（Phase 2で実装予定）
      # NotificationService.send_completion_notification(self)

      true
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "移動実行エラー: #{e.message}"
    false
  end

  # ============================================
  # クラスメソッド
  # ============================================

  # 管理者がアクセス可能な移動申請のみを取得
  def self.accessible_to_admin(admin)
    if admin.headquarters_admin?
      all
    else
      accessible_store_ids = admin.accessible_store_ids
      where(
        "source_store_id IN (?) OR destination_store_id IN (?)",
        accessible_store_ids, accessible_store_ids
      )
    end
  end

  # 店舗の移動統計
  def self.store_transfer_stats(store, period = 30.days.ago..)
    outgoing = where(source_store: store, requested_at: period)
    incoming = where(destination_store: store, requested_at: period)

    {
      outgoing_count: outgoing.count,
      incoming_count: incoming.count,
      outgoing_completed: outgoing.completed.count,
      incoming_completed: incoming.completed.count,
      pending_approvals: outgoing.pending.count,
      average_processing_time: calculate_average_processing_time(outgoing.completed)
    }
  end

  # 移動申請の分析データ
  def self.transfer_analytics(period = 30.days.ago..)
    transfers = where(requested_at: period)

    {
      total_requests: transfers.count,
      approval_rate: calculate_approval_rate(transfers),
      average_quantity: transfers.average(:quantity),
      by_priority: transfers.group(:priority).count,
      by_status: transfers.group(:status).count,
      top_requested_items: top_requested_inventories(transfers, limit: 10)
    }
  end

  # ============================================
  # TODO: Phase 2以降で実装予定の機能
  # ============================================
  # 1. 自動承認機能
  #    - 承認ルールエンジンの実装
  #    - 金額・数量・優先度による自動判定
  #    - エスカレーション機能
  #
  # 2. 配送追跡機能
  #    - 配送業者との連携
  #    - リアルタイム配送状況更新
  #    - 配送完了の自動通知
  #
  # 3. バッチ移動機能
  #    - 複数商品の一括移動申請
  #    - 定期移動スケジュール
  #    - テンプレート機能
  #
  # 4. 高度な分析機能
  #    - 移動パターン分析
  #    - 店舗間効率性分析
  #    - 予測的移動提案

  private

  # 申請日時の自動設定
  def set_requested_at
    self.requested_at ||= Time.current
  end

  # 異なる店舗間での移動であることを検証
  def different_stores
    if source_store_id == destination_store_id
      errors.add(:destination_store, "移動元と移動先は異なる店舗である必要があります")
    end
  end

  # 移動元の在庫が十分であることを検証
  def sufficient_source_stock
    return unless source_store && inventory && quantity

    source_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)
    unless source_inventory&.available_quantity&.>= quantity
      errors.add(:quantity, "移動元の利用可能在庫が不足しています")
    end
  end

  # ステータス変更の妥当性検証
  def valid_status_transition
    return unless status_changed?

    valid_transitions = {
      "pending" => %w[approved rejected cancelled],
      "approved" => %w[in_transit cancelled completed],
      "in_transit" => %w[completed],
      "rejected" => [],
      "completed" => [],
      "cancelled" => []
    }

    old_status = status_was
    new_status = status

    unless valid_transitions[old_status]&.include?(new_status)
      errors.add(:status, "無効なステータス変更です: #{old_status} → #{new_status}")
    end
  end

  # 移動元在庫の予約処理
  def reserve_source_stock
    source_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)
    return unless source_inventory

    source_inventory.increment!(:reserved_quantity, quantity)
  end

  # 予約在庫の解放
  def release_reserved_stock
    source_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)
    return unless source_inventory

    source_inventory.decrement!(:reserved_quantity, [ quantity, source_inventory.reserved_quantity ].min)
  end

  # ステータス変更時の処理
  def handle_status_change
    return unless saved_change_to_status?

    case status
    when "approved"
      # 承認時の処理（通知など）
      Rails.logger.info "移動申請が承認されました: #{id}"
    when "rejected", "cancelled"
      release_reserved_stock
    when "completed"
      # 完了通知など
      Rails.logger.info "移動が完了しました: #{id}"
    end
  end

  # クラスメソッド用のヘルパー
  def self.calculate_approval_rate(transfers)
    return 0.0 if transfers.count.zero?

    approved_count = transfers.where(status: [ :approved, :completed ]).count
    (approved_count.to_f / transfers.count * 100).round(2)
  end

  def self.calculate_average_processing_time(completed_transfers)
    times = completed_transfers.where.not(completed_at: nil)
                              .pluck(:requested_at, :completed_at)
                              .map { |req, comp| comp - req }

    return 0.0 if times.empty?

    times.sum / times.size
  end

  def self.top_requested_inventories(transfers, limit: 5)
    transfers.joins(:inventory)
            .group("inventories.name")
            .order(Arel.sql("COUNT(*) DESC"))
            .limit(limit)
            .count
  end

  # 店舗のpending状態のカウンタを更新
  def update_store_pending_counts
    # ステータスの変更またはレコードの作成・削除時に更新
    if saved_change_to_status? || destroyed? || (previous_changes.key?(:id) && persisted?)
      # 移動元の店舗のカウンタを更新
      if source_store
        source_store.update_column(:pending_outgoing_transfers_count,
                                   source_store.outgoing_transfers.pending.count)
      end

      # 移動先の店舗のカウンタを更新
      if destination_store
        destination_store.update_column(:pending_incoming_transfers_count,
                                        destination_store.incoming_transfers.pending.count)
      end
    end
  end
end
