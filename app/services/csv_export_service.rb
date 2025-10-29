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
    # メモリ効率化: 大量データ対応のストリーミング処理
    csv_data = CSV.generate(
      encoding: "UTF-8",
      headers: true,
      write_headers: true,
      col_sep: ","
    ) do |csv|
      # ヘッダー行
      csv << csv_headers

      # データ行 - バッチ処理で メモリ使用量を制限
      process_inventories_in_batches(store_inventories, csv)
    end

    # 監査ログの記録
    log_export_event(store_inventories.count)

    csv_data
  end

  # 大容量対応のストリーミングCSV生成
  def generate_inventory_csv_stream(store_inventories, &block)
    # Enumeratorを使用したストリーミング処理
    csv_enumerator = Enumerator.new do |yielder|
      # ヘッダー行を出力
      yielder << CSV.generate_line(csv_headers)

      # データ行をバッチ処理で出力
      store_inventories.find_in_batches(batch_size: batch_size) do |batch|
        batch.each do |store_inventory|
          yielder << CSV.generate_line(build_csv_row(store_inventory))
        end

        # メモリ解放のためのガベージコレクション
        GC.start if batch.size == batch_size
      end
    end

    # 監査ログの記録
    log_export_event(store_inventories.count)

    if block_given?
      csv_enumerator.each(&block)
    else
      csv_enumerator
    end
  end

  # CSVファイル名の生成
  def generate_filename(prefix: "inventory_export")
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    store_suffix = @store ? "_store_#{@store.id}" : "_all_stores"
    "#{prefix}#{store_suffix}_#{timestamp}.csv"
  end

  private

  # バッチサイズの設定
  def batch_size
    @batch_size ||= ENV.fetch("CSV_BATCH_SIZE", 1000).to_i
  end

  # バッチ処理でメモリ効率を向上
  def process_inventories_in_batches(store_inventories, csv)
    # ActiveRecord::Relationの場合はfind_in_batchesを使用
    if store_inventories.respond_to?(:find_in_batches)
      store_inventories.find_in_batches(batch_size: batch_size) do |batch|
        batch.each { |store_inventory| csv << build_csv_row(store_inventory) }
        # バッチ処理後にメモリを解放
        GC.start if batch.size == batch_size
      end
    else
      # 配列の場合は each_slice でバッチ処理
      store_inventories.each_slice(batch_size) do |batch|
        batch.each { |store_inventory| csv << build_csv_row(store_inventory) }
        GC.start if batch.size == batch_size
      end
    end
  end

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

  # CSV行データの構築 - パフォーマンス最適化
  def build_csv_row(store_inventory)
    # nil チェックを事前に実行してエラーを回避
    return build_fallback_csv_row if store_inventory.nil?

    inventory = store_inventory.inventory
    store = store_inventory.store

    # nil チェックと安全な値取得
    return build_fallback_csv_row unless inventory && store

    [
      store.name,
      inventory.id,
      inventory.name,
      memoized_categorize_by_name(inventory.name),
      store_inventory.quantity || 0,
      store_inventory.reserved_quantity || 0,
      calculate_available_quantity(store_inventory),
      store_inventory.reorder_level || 0,
      extract_stock_status_text(store_inventory),
      calculate_turnover_days(store_inventory),
      format_datetime(store_inventory.updated_at),
      format_notes(store_inventory)
    ]
  end

  # フォールバック用のCSV行データ
  def build_fallback_csv_row
    Array.new(12, "N/A")
  end

  # 日時フォーマットの最適化
  def format_datetime(datetime)
    return "N/A" unless datetime
    datetime.strftime("%Y-%m-%d %H:%M")
  end

  # カテゴリ分類のメモ化によるパフォーマンス向上
  def memoized_categorize_by_name(product_name)
    @category_cache ||= {}
    @category_cache[product_name] ||= categorize_by_name(product_name)
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
      batch.expires_on && batch.expires_on < Date.current
    }
  end

  # 長期在庫の判定
  def long_term_stock?(store_inventory)
    # 90日以上更新がない場合を長期在庫とする
    store_inventory.updated_at < 90.days.ago
  end

  # エクスポートイベントのログ記録 - セキュリティ強化
  def log_export_event(record_count)
    return unless @current_user

    # 🛡️ セキュリティ対策: 機密情報のフィルタリング
    sanitized_log_data = {
      event: "csv_export",
      user_id: filter_sensitive_data(@current_user.id),
      user_email: mask_email(@current_user.email),
      store_id: @store&.id,
      store_name: @store&.name,
      record_count: record_count,
      timestamp: Time.current.iso8601,
      performance_metrics: capture_performance_metrics
    }

    Rails.logger.info(sanitized_log_data.to_json)

    # AuditLogへの記録 - 非同期処理で性能向上
    create_audit_log_async(record_count) if defined?(AuditLog)
  end

  # パフォーマンスメトリクスの取得
  def capture_performance_metrics
    {
      memory_usage: get_memory_usage,
      processing_time: @processing_start_time ? (Time.current - @processing_start_time) : nil,
      batch_size: batch_size
    }
  end

  # メモリ使用量の取得
  def get_memory_usage
    return nil unless defined?(ObjectSpace)
    ObjectSpace.count_objects[:TOTAL] rescue nil
  end

  # メールアドレスのマスキング
  def mask_email(email)
    return "N/A" unless email
    parts = email.split("@")
    return email if parts.length != 2

    username = parts[0]
    domain = parts[1]
    masked_username = username.length > 2 ? "#{username[0]}***#{username[-1]}" : "***"
    "#{masked_username}@#{domain}"
  end

  # 機密データのフィルタリング
  def filter_sensitive_data(data)
    return data unless data.is_a?(String)
    # 個人識別情報のマスキング処理
    data.gsub(/(\d{4})(\d{4})(\d{4})/, '\1****\3')
  end

  # 監査ログの作成 - パフォーマンス最適化
  def create_audit_log(record_count)
    AuditLog.create!(
      user: @current_user,
      action: "csv_export",
      details: {
        store_id: @store&.id,
        store_name: @store&.name,
        record_count: record_count,
        export_type: "inventory_list",
        performance_metrics: capture_performance_metrics
      },
      ip_address: Current.request&.remote_ip,
      user_agent: Current.request&.user_agent
    )
  rescue StandardError => e
    Rails.logger.error("Failed to create audit log for CSV export: #{e.message}")
    # エクスポート処理は継続（監査ログ失敗でユーザー操作を阻害しない）
  end

  # 非同期監査ログ作成 - 高性能化
  def create_audit_log_async(record_count)
    # Background Jobでの非同期処理
    CsvExportAuditJob.perform_later(
      user_id: @current_user.id,
      store_id: @store&.id,
      record_count: record_count,
      performance_metrics: capture_performance_metrics,
      request_metadata: {
        ip_address: Current.request&.remote_ip,
        user_agent: Current.request&.user_agent
      }
    )
  rescue StandardError => e
    Rails.logger.error("Failed to enqueue audit log job for CSV export: #{e.message}")
    # フォールバック: 同期処理で監査ログ作成
    create_audit_log(record_count)
  end
end
