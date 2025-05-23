# frozen_string_literal: true

module ShipmentManagement
  extend ActiveSupport::Concern

  included do
    has_many :shipments, dependent: :destroy
    has_many :receipts, dependent: :destroy

    # 配送ステータスの列挙型
    enum shipment_status: {
      pending: 0,      # 出荷準備中
      processing: 1,   # 処理中
      shipped: 2,      # 出荷済み
      delivered: 3,    # 配達済み
      returned: 4,     # 返品
      cancelled: 5     # キャンセル
    }

    # 入荷ステータスの列挙型
    enum receipt_status: {
      expected: 0,     # 入荷予定
      partial: 1,      # 一部入荷
      completed: 2,    # 入荷完了
      rejected: 3,     # 受入拒否
      delayed: 4       # 入荷遅延
    }
  end

  # インスタンスメソッド

  # 新規出荷の登録
  def create_shipment(quantity, destination, options = {})
    return false if quantity <= 0 || quantity > self.quantity

    shipment = shipments.new(
      quantity: quantity,
      destination: destination,
      scheduled_date: options[:scheduled_date] || Date.current,
      shipment_status: options[:status] || :pending,
      tracking_number: options[:tracking_number],
      carrier: options[:carrier],
      notes: options[:notes]
    )

    if shipment.save
      # 出荷時に在庫を減少
      remove_stock(quantity, "出荷: #{destination}向け #{options[:tracking_number]}")
      true
    else
      false
    end
  end

  # 入荷の登録
  def create_receipt(quantity, source, options = {})
    return false if quantity <= 0

    receipt = receipts.new(
      quantity: quantity,
      source: source,
      receipt_date: options[:receipt_date] || Date.current,
      receipt_status: options[:status] || :completed,
      batch_number: options[:batch_number],
      purchase_order: options[:purchase_order],
      cost_per_unit: options[:cost_per_unit],
      notes: options[:notes]
    )

    if receipt.save
      # 入荷時に在庫を増加
      add_stock(quantity, "入荷: #{source}から #{options[:purchase_order]}")

      # ロット管理を行う場合は、バッチも追加
      if respond_to?(:add_batch) && options[:expiry_date]
        add_batch(
          quantity,
          options[:expiry_date],
          options[:batch_number] || "RN-#{receipt.id}"
        )
      end

      true
    else
      false
    end
  end

  # 出荷の取り消し
  def cancel_shipment(shipment_id, reason = nil)
    shipment = shipments.find_by(id: shipment_id)
    return false unless shipment

    if shipment.pending? || shipment.processing?
      shipment.cancelled!

      # 在庫を戻す
      add_stock(shipment.quantity, "出荷取消: #{reason || '理由なし'}")
      true
    else
      false
    end
  end

  # 返品の処理
  def process_return(shipment_id, return_quantity, reason = nil, quality_check = true)
    shipment = shipments.find_by(id: shipment_id)
    return false unless shipment
    return false if return_quantity <= 0 || return_quantity > shipment.quantity

    # 出荷済みまたは配達済みのみ返品可能
    unless shipment.shipped? || shipment.delivered?
      return false
    end

    # 返品ステータスに更新
    shipment.update(
      shipment_status: :returned,
      return_quantity: return_quantity,
      return_reason: reason,
      return_date: Date.current
    )

    # 品質チェックをパスした場合のみ在庫に戻す
    if quality_check
      add_stock(return_quantity, "返品受入: #{reason || '理由なし'}")
    end

    true
  end

  class_methods do
    # 出荷処理
    def ship(inventory_id, quantity, options = {})
      inventory = find(inventory_id)

      # 在庫不足チェック
      if inventory.quantity < quantity
        raise "出荷数量が在庫数量を超えています（在庫: #{inventory.quantity}, 出荷: #{quantity}）"
      end

      # 在庫数量を減らす
      inventory.quantity -= quantity

      # ログ用のメモ設定
      note = options[:note] || "出荷処理"

      # トランザクション内で処理
      ActiveRecord::Base.transaction do
        inventory.save!

        # ログ記録
        InventoryLog.create!(
          inventory_id: inventory.id,
          delta: -quantity,
          operation_type: "ship",
          previous_quantity: inventory.quantity + quantity,
          current_quantity: inventory.quantity,
          user_id: options[:user_id],
          note: note,
          reference_number: options[:reference_number],
          destination: options[:destination]
        )
      end
    end

    # 入荷処理
    def receive(inventory_id, quantity, options = {})
      inventory = find(inventory_id)

      # 在庫数量を増やす
      inventory.quantity += quantity

      # ログ用のメモ設定
      note = options[:note] || "入荷処理"

      # トランザクション内で処理
      ActiveRecord::Base.transaction do
        inventory.save!

        # ログ記録
        InventoryLog.create!(
          inventory_id: inventory.id,
          delta: quantity,
          operation_type: "receive",
          previous_quantity: inventory.quantity - quantity,
          current_quantity: inventory.quantity,
          user_id: options[:user_id],
          note: note,
          reference_number: options[:reference_number],
          source: options[:source]
        )
      end
    end

    # 移動処理（出荷+入荷）
    def transfer(from_id, to_id, quantity, options = {})
      # 移動元、移動先の在庫確認
      from_inventory = find(from_id)
      to_inventory = find(to_id)

      # 在庫不足チェック
      if from_inventory.quantity < quantity
        raise "移動数量が在庫数量を超えています（在庫: #{from_inventory.quantity}, 移動: #{quantity}）"
      end

      # トランザクション内で処理
      logs = []
      ActiveRecord::Base.transaction do
        # 出荷処理
        ship_options = options.merge(note: "在庫移動（出庫）: #{from_inventory.name} → #{to_inventory.name}")
        logs << ship(from_id, quantity, ship_options)

        # 入荷処理
        receive_options = options.merge(note: "在庫移動（入庫）: #{from_inventory.name} → #{to_inventory.name}")
        logs << receive(to_id, quantity, receive_options)
      end

      logs
    end

    # 指定期間内の出荷データを取得
    def shipments_by_period(start_date, end_date)
      joins(:shipments)
        .where("shipments.scheduled_date BETWEEN ? AND ?", start_date, end_date)
        .group("inventories.id")
        .select("inventories.*, COUNT(shipments.id) as shipment_count, SUM(shipments.quantity) as total_shipped")
    end

    # 指定期間内の入荷データを取得
    def receipts_by_period(start_date, end_date)
      joins(:receipts)
        .where("receipts.receipt_date BETWEEN ? AND ?", start_date, end_date)
        .group("inventories.id")
        .select("inventories.*, COUNT(receipts.id) as receipt_count, SUM(receipts.quantity) as total_received")
    end

    # 在庫移動レポート生成
    def movement_report(start_date, end_date, options = {})
      # 出荷と入荷のログを取得
      shipped = joins(:inventory_logs)
                .where(inventory_logs: {
                  operation_type: "ship",
                  created_at: start_date.beginning_of_day..end_date.end_of_day
                })
                .distinct

      received = joins(:inventory_logs)
                .where(inventory_logs: {
                  operation_type: "receive",
                  created_at: start_date.beginning_of_day..end_date.end_of_day
                })
                .distinct

      # 全ての関連在庫IDを取得
      all_ids = (shipped.pluck(:id) + received.pluck(:id)).uniq

      # N+1クエリ回避のためにインベントリデータを一括取得
      inventories_hash = Inventory.where(id: all_ids).index_by(&:id)

      # 在庫ごとの出荷・入荷データを取得
      report_data = all_ids.map do |id|
        inventory = inventories_hash[id]
        next unless inventory

        # 期間内の出荷・入荷ログを取得
        ship_logs = InventoryLog.where(
          inventory_id: id,
          operation_type: "ship",
          created_at: start_date.beginning_of_day..end_date.end_of_day
        )

        receive_logs = InventoryLog.where(
          inventory_id: id,
          operation_type: "receive",
          created_at: start_date.beginning_of_day..end_date.end_of_day
        )

        # 出荷・入荷の合計
        total_shipped = ship_logs.sum(:delta).abs
        total_received = receive_logs.sum(:delta)

        {
          id: id,
          name: inventory.name,
          code: inventory.code,
          shipped_quantity: total_shipped,
          received_quantity: total_received,
          net_change: total_received - total_shipped,
          ship_count: ship_logs.count,
          receive_count: receive_logs.count
        }
      end.compact

      # ソートオプション
      if options[:sort_by]
        field = options[:sort_by].to_sym
        direction = options[:sort_direction] == :desc ? -1 : 1
        report_data.sort_by! { |item| direction * (item[field] || 0) }
      end

      {
        start_date: start_date,
        end_date: end_date,
        total_shipped: report_data.sum { |item| item[:shipped_quantity] },
        total_received: report_data.sum { |item| item[:received_quantity] },
        net_change: report_data.sum { |item| item[:net_change] },
        items: report_data
      }
    end

    # TODO: 出荷管理機能の拡張
    # 1. 配送トラッキング機能
    #    - 配送業者APIとの連携
    #    - リアルタイム配送状況の取得
    #    - 顧客への配送通知機能
    #
    # 2. 自動出荷システム
    #    - 在庫レベルに基づく自動発注
    #    - 予測需要による先行出荷
    #    - 季節性を考慮した出荷計画
    #
    # 3. 返品管理の強化
    #    - 返品理由の分析機能
    #    - 品質チェック履歴の管理
    #    - 返品コスト分析レポート
  end
end
