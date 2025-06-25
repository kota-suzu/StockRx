# frozen_string_literal: true

require "csv"

# CSV出力サービス
# ============================================
# 責務: 在庫データのCSV出力機能
# 分離元: StoreControllers::InventoriesController
# ============================================
class CsvExportService
  include ActiveModel::Model

  # Phase 1: 緊急分離 - CSV出力ロジックの専用サービス化
  # メタ認知: 出力フォーマット変更時の影響範囲限定化

  def initialize(store: nil, current_user: nil)
    @store = store
    @current_user = current_user
  end

  # 在庫CSVの生成
  def generate_inventory_csv(store_inventories)
    csv_data = CSV.generate(
      encoding: "UTF-8",
      headers: true,
      write_headers: true,
      col_sep: ","
    ) do |csv|
      # ヘッダー行
      csv << csv_headers

      # データ行
      store_inventories.each do |store_inventory|
        csv << build_csv_row(store_inventory)
      end
    end

    # 監査ログの記録
    log_export_event(store_inventories.count)

    csv_data
  end

  # CSVファイル名の生成
  def generate_filename(prefix: "inventory_export")
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    store_suffix = @store ? "_store_#{@store.id}" : "_all_stores"
    "#{prefix}#{store_suffix}_#{timestamp}.csv"
  end

  private

  # CSVヘッダーの定義
  def csv_headers
    [
      "店舗名",
      "商品ID",
      "商品名",
      "カテゴリ",
      "現在在庫",
      "予約済み在庫",
      "利用可能在庫",
      "発注点",
      "在庫状態",
      "回転日数",
      "最終更新日",
      "備考"
    ]
  end

  # CSV行データの構築
  def build_csv_row(store_inventory)
    inventory = store_inventory.inventory

    [
      store_inventory.store.name,
      inventory.id,
      inventory.name,
      categorize_by_name(inventory.name),
      store_inventory.quantity,
      store_inventory.reserved_quantity || 0,
      calculate_available_quantity(store_inventory),
      store_inventory.reorder_level || 0,
      extract_stock_status_text(store_inventory),
      calculate_turnover_days(store_inventory),
      store_inventory.updated_at.strftime("%Y-%m-%d %H:%M"),
      format_notes(store_inventory)
    ]
  end

  # 利用可能在庫の計算
  def calculate_available_quantity(store_inventory)
    quantity = store_inventory.quantity || 0
    reserved = store_inventory.reserved_quantity || 0
    [ quantity - reserved, 0 ].max
  end

  # 商品名からカテゴリを推定
  def categorize_by_name(product_name)
    return "その他" if product_name.blank?

    category_patterns = {
      "医薬品" => /(薬|錠|カプセル|シロップ|軟膏|目薬|点鼻|吸入|注射|輸液)/,
      "医療機器" => /(器具|機器|装置|測定|検査|手術|治療|診断)/,
      "消耗品" => /(ガーゼ|包帯|綿|手袋|マスク|注射器|針|カテーテル|チューブ)/,
      "衛生用品" => /(消毒|洗浄|清拭|石鹸|アルコール|ワイプ|タオル)/
    }

    category_patterns.each do |category, pattern|
      return category if product_name.match?(pattern)
    end

    "その他"
  end

  # 在庫状態のテキスト化
  def extract_stock_status_text(store_inventory)
    quantity = store_inventory.quantity || 0
    reorder_level = store_inventory.reorder_level || 0

    if quantity <= 0
      "在庫切れ"
    elsif quantity <= reorder_level
      "在庫不足"
    else
      "適正在庫"
    end
  end

  # 回転日数の計算
  def calculate_turnover_days(store_inventory)
    # 簡易計算: 実際の運用では売上データとの連携が必要
    quantity = store_inventory.quantity || 0
    return "N/A" if quantity <= 0

    # 仮定: 週間平均消費量を基に計算
    weekly_consumption = estimate_weekly_consumption(store_inventory)
    return "N/A" if weekly_consumption <= 0

    days = (quantity.to_f / weekly_consumption * 7).round
    "約#{days}日"
  end

  # 週間消費量の推定
  def estimate_weekly_consumption(store_inventory)
    # 簡易実装: 実際はInventoryLogからの実績ベース計算が望ましい
    reorder_level = store_inventory.reorder_level || 0
    [ reorder_level / 2.0, 1.0 ].max
  end

  # 備考欄の整形
  def format_notes(store_inventory)
    notes = []

    # 期限切れバッチの警告
    if inventory_has_expired_batches?(store_inventory)
      notes << "期限切れ商品あり"
    end

    # 長期在庫の警告
    if long_term_stock?(store_inventory)
      notes << "長期在庫"
    end

    notes.join(", ")
  end

  # 期限切れバッチの存在確認
  def inventory_has_expired_batches?(store_inventory)
    # バッチ情報へのアクセスが可能な場合の実装
    return false unless store_inventory.inventory.respond_to?(:batches)

    store_inventory.inventory.batches.any? { |batch|
      batch.expiration_date && batch.expiration_date < Date.current
    }
  end

  # 長期在庫の判定
  def long_term_stock?(store_inventory)
    # 90日以上更新がない場合を長期在庫とする
    store_inventory.updated_at < 90.days.ago
  end

  # エクスポートイベントのログ記録
  def log_export_event(record_count)
    return unless @current_user

    Rails.logger.info({
      event: "csv_export",
      user_id: @current_user.id,
      user_email: @current_user.email,
      store_id: @store&.id,
      store_name: @store&.name,
      record_count: record_count,
      timestamp: Time.current.iso8601
    }.to_json)

    # AuditLogへの記録
    create_audit_log(record_count) if defined?(AuditLog)
  end

  # 監査ログの作成
  def create_audit_log(record_count)
    AuditLog.create!(
      user: @current_user,
      action: "csv_export",
      details: {
        store_id: @store&.id,
        store_name: @store&.name,
        record_count: record_count,
        export_type: "inventory_list"
      },
      ip_address: Current.request&.remote_ip,
      user_agent: Current.request&.user_agent
    )
  rescue StandardError => e
    Rails.logger.error("Failed to create audit log for CSV export: #{e.message}")
    # エクスポート処理は継続（監査ログ失敗でユーザー操作を阻害しない）
  end
end
