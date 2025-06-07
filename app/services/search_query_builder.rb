# frozen_string_literal: true

class SearchQueryBuilder
  attr_reader :scope, :joins_applied, :distinct_applied, :conditions
  
  def initialize(scope = Inventory.all)
    @scope = scope
    @joins_applied = Set.new
    @distinct_applied = false
    @conditions = []
  end
  
  # ファクトリーメソッド
  def self.build(scope = Inventory.all)
    new(scope)
  end
  
  # 名前での検索
  def filter_by_name(name)
    return self if name.blank?
    
    sanitized_name = sanitize_like_parameter(name)
    @scope = @scope.where("inventories.name LIKE ?", "%#{sanitized_name}%")
    @conditions << "名前: #{name}"
    self
  end
  
  # ステータスでの検索
  def filter_by_status(status)
    return self if status.blank?
    
    if Inventory::STATUSES.include?(status)
      @scope = @scope.where(status: status)
      @conditions << "ステータス: #{status}"
    end
    self
  end
  
  # 価格範囲での検索
  def filter_by_price_range(min_price, max_price)
    return self if min_price.blank? && max_price.blank?
    
    if min_price.present? && max_price.present?
      @scope = @scope.where(price: min_price..max_price)
      @conditions << "価格: #{min_price}円〜#{max_price}円"
    elsif min_price.present?
      @scope = @scope.where("inventories.price >= ?", min_price)
      @conditions << "価格: #{min_price}円以上"
    elsif max_price.present?
      @scope = @scope.where("inventories.price <= ?", max_price)
      @conditions << "価格: #{max_price}円以下"
    end
    self
  end
  
  # 数量範囲での検索
  def filter_by_quantity_range(min_quantity, max_quantity)
    return self if min_quantity.blank? && max_quantity.blank?
    
    if min_quantity.present? && max_quantity.present?
      @scope = @scope.where(quantity: min_quantity..max_quantity)
      @conditions << "数量: #{min_quantity}〜#{max_quantity}"
    elsif min_quantity.present?
      @scope = @scope.where("inventories.quantity >= ?", min_quantity)
      @conditions << "数量: #{min_quantity}以上"
    elsif max_quantity.present?
      @scope = @scope.where("inventories.quantity <= ?", max_quantity)
      @conditions << "数量: #{max_quantity}以下"
    end
    self
  end
  
  # 在庫状態での検索
  def filter_by_stock_status(stock_filter, threshold = 10)
    return self if stock_filter.blank?
    
    case stock_filter
    when 'out_of_stock'
      @scope = @scope.where("inventories.quantity <= 0")
      @conditions << "在庫切れ"
    when 'low_stock'
      @scope = @scope.where("inventories.quantity > 0 AND inventories.quantity <= ?", threshold)
      @conditions << "在庫少 (#{threshold}以下)"
    when 'in_stock'
      @scope = @scope.where("inventories.quantity > ?", threshold)
      @conditions << "在庫あり (#{threshold}超)"
    end
    self
  end
  
  # 日付範囲での検索
  def filter_by_date_range(field, from_date, to_date)
    return self if from_date.blank? && to_date.blank?
    
    field_name = sanitize_field_name(field)
    
    if from_date.present? && to_date.present?
      @scope = @scope.where("#{field_name} BETWEEN ? AND ?", from_date, to_date)
      @conditions << "#{field.humanize}: #{from_date}〜#{to_date}"
    elsif from_date.present?
      @scope = @scope.where("#{field_name} >= ?", from_date)
      @conditions << "#{field.humanize}: #{from_date}以降"
    elsif to_date.present?
      @scope = @scope.where("#{field_name} <= ?", to_date)
      @conditions << "#{field.humanize}: #{to_date}以前"
    end
    self
  end
  
  # バッチ関連での検索
  def filter_by_batch_conditions(lot_code: nil, expires_before: nil, expires_after: nil)
    return self if lot_code.blank? && expires_before.blank? && expires_after.blank?
    
    ensure_batch_join
    
    if lot_code.present?
      sanitized_lot_code = sanitize_like_parameter(lot_code)
      @scope = @scope.where("batches.lot_code LIKE ?", "%#{sanitized_lot_code}%")
      @conditions << "ロット: #{lot_code}"
    end
    
    if expires_before.present?
      @scope = @scope.where("batches.expires_on <= ?", expires_before)
      @conditions << "期限: #{expires_before}以前"
    end
    
    if expires_after.present?
      @scope = @scope.where("batches.expires_on >= ?", expires_after)
      @conditions << "期限: #{expires_after}以降"
    end
    
    self
  end
  
  # 期限切れ間近での検索
  def filter_by_expiring_soon(days = 30)
    return self if days.blank? || days <= 0
    
    ensure_batch_join
    expiry_date = Date.current + days.days
    @scope = @scope.where("batches.expires_on <= ?", expiry_date)
    @conditions << "期限切れ間近 (#{days}日以内)"
    self
  end
  
  # 最近更新されたものでの検索
  def filter_by_recently_updated(days = 7)
    return self if days.blank? || days <= 0
    
    update_date = Date.current - days.days
    @scope = @scope.where("inventories.updated_at >= ?", update_date)
    @conditions << "最近更新 (#{days}日以内)"
    self
  end
  
  # 出荷関連での検索
  def filter_by_shipment_conditions(status: nil, destination: nil)
    return self if status.blank? && destination.blank?
    
    ensure_shipment_join
    
    if status.present?
      @scope = @scope.where(shipments: { status: status })
      @conditions << "出荷ステータス: #{status}"
    end
    
    if destination.present?
      sanitized_destination = sanitize_like_parameter(destination)
      @scope = @scope.where("shipments.destination LIKE ?", "%#{sanitized_destination}%")
      @conditions << "出荷先: #{destination}"
    end
    
    self
  end
  
  # 入荷関連での検索
  def filter_by_receipt_conditions(status: nil, source: nil)
    return self if status.blank? && source.blank?
    
    ensure_receipt_join
    
    if status.present?
      @scope = @scope.where(receipts: { status: status })
      @conditions << "入荷ステータス: #{status}"
    end
    
    if source.present?
      sanitized_source = sanitize_like_parameter(source)
      @scope = @scope.where("receipts.source LIKE ?", "%#{sanitized_source}%")
      @conditions << "入荷元: #{source}"
    end
    
    self
  end
  
  # カスタム検索条件の適用
  def apply_search_condition(search_condition)
    return self unless search_condition.is_a?(SearchCondition) && search_condition.valid?
    
    sql_condition = search_condition.to_sql_condition
    return self unless sql_condition
    
    # JOINが必要な場合の処理
    ensure_join_for_field(search_condition.field)
    
    if sql_condition.is_a?(Array)
      @scope = @scope.where(sql_condition.first, *sql_condition[1..-1])
    else
      @scope = @scope.where(sql_condition)
    end
    
    @conditions << search_condition.description
    self
  end
  
  # 複数の検索条件を一括適用（AND条件）
  def apply_search_conditions(search_conditions)
    search_conditions.each do |condition|
      apply_search_condition(condition)
    end
    self
  end
  
  # OR条件での検索
  def apply_or_conditions(conditions_array)
    return self if conditions_array.empty?
    
    or_scopes = conditions_array.map do |condition_params|
      if condition_params.is_a?(SearchCondition)
        build_scope_from_search_condition(condition_params)
      else
        Inventory.where(condition_params)
      end
    end.compact
    
    return self if or_scopes.empty?
    
    combined_scope = or_scopes.reduce { |result, scope| result.or(scope) }
    @scope = @scope.merge(combined_scope)
    @conditions << "OR条件 (#{conditions_array.size}個)"
    self
  end
  
  # ソート
  def order_by(field, direction = :desc)
    return self if field.blank?
    
    sanitized_field = sanitize_field_name(field)
    direction = direction.to_s.downcase == 'asc' ? 'ASC' : 'DESC'
    
    @scope = @scope.order("#{sanitized_field} #{direction}")
    self
  end
  
  # ページネーション
  def paginate(page: 1, per_page: 20)
    @scope = @scope.page(page).per(per_page)
    self
  end
  
  # 結果の取得
  def results
    apply_distinct if @distinct_applied || joins_applied.any?
    @scope
  end
  
  # カウント取得
  def count
    apply_distinct if @distinct_applied || joins_applied.any?
    @scope.count
  end
  
  # 検索条件のサマリー
  def conditions_summary
    @conditions.empty? ? "すべて" : @conditions.join(', ')
  end
  
  # デバッグ用のSQL表示
  def to_sql
    results.to_sql
  end
  
  private
  
  # DISTINCT の適用
  def apply_distinct
    @scope = @scope.distinct unless @distinct_applied
    @distinct_applied = true
  end
  
  # バッチテーブルのJOIN
  def ensure_batch_join
    return if @joins_applied.include?(:batches)
    
    @scope = @scope.left_joins(:batches)
    @joins_applied << :batches
    @distinct_applied = true
  end
  
  # 出荷テーブルのJOIN
  def ensure_shipment_join
    return if @joins_applied.include?(:shipments)
    
    @scope = @scope.left_joins(:shipments)
    @joins_applied << :shipments
    @distinct_applied = true
  end
  
  # 入荷テーブルのJOIN
  def ensure_receipt_join
    return if @joins_applied.include?(:receipts)
    
    @scope = @scope.left_joins(:receipts)
    @joins_applied << :receipts
    @distinct_applied = true
  end
  
  # フィールドに応じたJOINの確保
  def ensure_join_for_field(field)
    case field
    when /^batches\./
      ensure_batch_join
    when /^shipments\./
      ensure_shipment_join
    when /^receipts\./
      ensure_receipt_join
    end
  end
  
  # フィールド名のサニタイズ
  def sanitize_field_name(field)
    # ホワイトリストによる検証
    allowed_fields = %w[
      name status price quantity created_at updated_at
      batches.lot_code batches.expires_on
      shipments.destination shipments.status
      receipts.source receipts.status
    ]
    
    return 'inventories.updated_at' unless allowed_fields.include?(field)
    
    if field.include?('.')
      field
    else
      "inventories.#{field}"
    end
  end
  
  # LIKE パラメータのサニタイズ
  def sanitize_like_parameter(value)
    # SQLインジェクション対策: エスケープ文字の処理
    value.to_s.gsub(/[%_\\]/) { |match| "\\#{match}" }
  end
  
  # SearchConditionからスコープを構築
  def build_scope_from_search_condition(search_condition)
    return Inventory.none unless search_condition.valid?
    
    builder = SearchQueryBuilder.new
    builder.apply_search_condition(search_condition)
    builder.scope
  end
end