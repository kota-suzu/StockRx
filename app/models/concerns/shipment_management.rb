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
  
  # クラスメソッド
  module ClassMethods
    # 指定期間内の出荷データを取得
    def shipments_by_period(start_date, end_date)
      joins(:shipments)
        .where('shipments.scheduled_date BETWEEN ? AND ?', start_date, end_date)
        .group('inventories.id')
        .select('inventories.*, COUNT(shipments.id) as shipment_count, SUM(shipments.quantity) as total_shipped')
    end
    
    # 指定期間内の入荷データを取得
    def receipts_by_period(start_date, end_date)
      joins(:receipts)
        .where('receipts.receipt_date BETWEEN ? AND ?', start_date, end_date)
        .group('inventories.id')
        .select('inventories.*, COUNT(receipts.id) as receipt_count, SUM(receipts.quantity) as total_received')
    end
    
    # 入出荷レポートの生成
    def movement_report(start_date = 30.days.ago, end_date = Date.current)
      shipped = shipments_by_period(start_date, end_date)
      received = receipts_by_period(start_date, end_date)
      
      # 在庫ID別に集計データを結合
      all_ids = (shipped.pluck(:id) + received.pluck(:id)).uniq
      
      report_data = all_ids.map do |id|
        inventory = find(id)
        ship_data = shipped.find { |s| s.id == id }
        rcpt_data = received.find { |r| r.id == id }
        
        {
          id: id,
          name: inventory.name,
          current_quantity: inventory.quantity,
          shipped_quantity: ship_data&.total_shipped || 0,
          received_quantity: rcpt_data&.total_received || 0,
          net_change: (rcpt_data&.total_received || 0) - (ship_data&.total_shipped || 0)
        }
      end
      
      report_data
    end
  end
end
