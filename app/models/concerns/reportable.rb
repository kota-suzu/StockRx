# frozen_string_literal: true

module Reportable
  extend ActiveSupport::Concern

  # インスタンスメソッド
  def generate_stock_report
    {
      id: id,
      name: name,
      current_quantity: quantity,
      value: quantity * price,
      status: stock_status,
      batches_count: batches.count,
      last_updated: updated_at,
      nearest_expiry: respond_to?(:nearest_expiry_date) ? nearest_expiry_date : nil
    }
  end
  
  # クラスメソッド
  module ClassMethods
    # 在庫レポートの生成
    def generate_inventory_report(options = {})
      report_data = {
        generated_at: Time.current,
        total_items: count,
        total_value: sum('quantity * price'),
        low_stock_items: low_stock.count,
        out_of_stock_items: out_of_stock.count,
        items_by_status: {
          active: active.count,
          archived: where(status: :archived).count
        }
      }
      
      # 詳細情報を含める場合
      if options[:include_details]
        report_data[:items] = all.map(&:generate_stock_report)
      end
      
      # 過去比較データを含める場合
      if options[:compare_with_previous]
        previous_period = options[:compare_days] || 30
        previous_data = get_historical_data(previous_period.days.ago)
        
        report_data[:comparison] = {
          previous_total_items: previous_data[:total_items],
          previous_total_value: previous_data[:total_value],
          items_change: count - previous_data[:total_items],
          value_change: sum('quantity * price') - previous_data[:total_value],
          change_percentage: previous_data[:total_value].zero? ? 0 : ((sum('quantity * price') - previous_data[:total_value]) / previous_data[:total_value] * 100).round(2)
        }
      end
      
      report_data
    end
    
    # 過去の在庫データを取得（既存データまたは在庫ログから再構築）
    def get_historical_data(date)
      # 理想的には過去の時点でのスナップショットデータがあれば使用
      # なければ在庫ログからその時点での状態を再構築
      {
        total_items: InventoryLog.where('created_at <= ?', date).select('DISTINCT inventory_id').count,
        total_value: InventoryLog.where('created_at <= ?', date).order('inventory_id, created_at DESC').distinct.pluck(:inventory_id).sum do |id|
          log = InventoryLog.where(inventory_id: id).where('created_at <= ?', date).order(created_at: :desc).first
          inventory = Inventory.find_by(id: id)
          log ? log.current_quantity * (inventory&.price || 0) : 0
        end
      }
    end
    
    # CSV形式で在庫レポートをエクスポート
    def export_inventory_report_csv
      CSV.generate do |csv|
        csv << ['ID', '商品名', '現在数量', '価格', '合計金額', '状態', 'バッチ数', '最終更新日', '最短期限日']
        
        all.find_each do |item|
          report = item.generate_stock_report
          csv << [
            report[:id],
            report[:name],
            report[:current_quantity],
            item.price,
            report[:value],
            report[:status],
            report[:batches_count],
            report[:last_updated].strftime('%Y-%m-%d %H:%M:%S'),
            report[:nearest_expiry]&.strftime('%Y-%m-%d')
          ]
        end
      end
    end
    
    # JSONで在庫分析データを生成
    def generate_analysis_json(options = {})
      report = generate_inventory_report(include_details: true)
      
      # APIやグラフ描画用にJSON形式で返す
      {
        summary: {
          total_items: report[:total_items],
          total_value: report[:total_value],
          low_stock_items: report[:low_stock_items],
          out_of_stock_items: report[:out_of_stock_items]
        },
        status_distribution: {
          active: report[:items_by_status][:active],
          archived: report[:items_by_status][:archived]
        },
        items: report[:items].map do |item|
          {
            id: item[:id],
            name: item[:name],
            quantity: item[:current_quantity],
            value: item[:value],
            status: item[:status]
          }
        end
      }.to_json
    end
  end
end
