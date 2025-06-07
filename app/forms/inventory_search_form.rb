# frozen_string_literal: true

class InventorySearchForm < BaseSearchForm
  # 基本検索フィールド
  attribute :name, :string
  attribute :status, :string
  attribute :min_price, :decimal
  attribute :max_price, :decimal
  attribute :min_quantity, :integer
  attribute :max_quantity, :integer
  
  # 日付関連
  attribute :created_from, :date
  attribute :created_to, :date
  attribute :updated_from, :date
  attribute :updated_to, :date
  
  # バッチ関連
  attribute :lot_code, :string
  attribute :expires_before, :date
  attribute :expires_after, :date
  attribute :expiring_days, :integer
  
  # 高度な検索オプション
  attribute :search_type, :string, default: 'basic' # basic/advanced/custom
  attribute :include_archived, :boolean, default: false
  attribute :stock_filter, :string # out_of_stock/low_stock/in_stock
  attribute :low_stock_threshold, :integer, default: 10
  
  # 従来の互換性パラメータ
  attribute :q, :string # name の alias
  attribute :low_stock, :boolean, default: false
  attribute :advanced_search, :boolean, default: false
  
  # 出荷・入荷関連
  attribute :shipment_status, :string
  attribute :destination, :string
  attribute :receipt_status, :string
  attribute :source, :string
  
  # 新機能
  attribute :expiring_soon, :boolean, default: false
  attribute :recently_updated, :boolean, default: false
  attribute :updated_days, :integer, default: 7
  
  # カスタム条件（将来拡張用）
  # Note: ActiveModel::Attributes doesn't support :array type, so we use attr_accessor
  attr_accessor :custom_conditions, :or_conditions, :complex_condition
  
  def initialize(attributes = {})
    self.custom_conditions = []
    self.or_conditions = []
    self.complex_condition = {}
    super(attributes)
  end
  
  # バリデーション
  validates :name, length: { maximum: 255 }
  validates :min_price, :max_price, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
  validates :min_quantity, :max_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
  validates :search_type, inclusion: { in: %w[basic advanced custom] }
  validates :stock_filter, inclusion: { in: %w[out_of_stock low_stock in_stock] }, allow_blank: true
  validates :status, inclusion: { in: -> { Inventory::STATUSES } }, allow_blank: true
  validates :low_stock_threshold, numericality: { greater_than: 0 }, allow_blank: true
  validates :expiring_days, numericality: { greater_than: 0 }, allow_blank: true
  validates :updated_days, numericality: { greater_than: 0 }, allow_blank: true
  
  validate :price_range_consistency
  validate :quantity_range_consistency
  validate :date_range_consistency
  validate :validate_sort_field
  
  # メイン検索メソッド
  def search
    return Inventory.none unless valid?
    
    case search_type
    when 'basic'
      basic_search
    when 'advanced'
      advanced_search
    when 'custom'
      custom_search
    else
      determine_search_type_and_execute
    end
  end
  
  # 検索実行前の条件チェック
  def has_search_conditions?
    basic_conditions? || advanced_conditions? || custom_conditions?
  end
  
  # 検索条件のサマリー生成
  def conditions_summary
    conditions = []
    
    # 基本条件
    conditions << "名前: #{effective_name}" if effective_name.present?
    conditions << "ステータス: #{status_display}" if status.present?
    conditions << "価格: #{price_range_display}" if price_range_specified?
    conditions << "数量: #{quantity_range_display}" if quantity_range_specified?
    
    # 日付条件
    conditions << "作成日: #{date_range_display(created_from, created_to)}" if created_date_range_specified?
    conditions << "更新日: #{date_range_display(updated_from, updated_to)}" if updated_date_range_specified?
    
    # バッチ条件
    conditions << "ロット: #{lot_code}" if lot_code.present?
    conditions << "期限: #{expiry_display}" if expiry_conditions?
    
    # 在庫条件
    conditions << "在庫状態: #{stock_filter_display}" if stock_filter.present?
    conditions << "在庫切れのみ" if low_stock
    
    # 特殊条件
    conditions << "期限切れ間近 (#{expiring_days}日以内)" if expiring_soon
    conditions << "最近更新 (#{updated_days}日以内)" if recently_updated
    
    conditions.empty? ? "すべて" : conditions.join(', ')
  end
  
  # 永続化用のハッシュ（空の値を除去）
  def to_params
    attributes.reject { |_, v| v.blank? }
  end
  
  # 従来のsearch_paramsとの互換性
  def to_search_params
    params = {}
    
    # 基本パラメータ
    params[:q] = effective_name if effective_name.present?
    params[:status] = status if status.present?
    params[:low_stock] = "true" if low_stock
    params[:advanced_search] = "true" if advanced_search || advanced_conditions?
    
    # 価格範囲
    params[:min_price] = min_price if min_price.present?
    params[:max_price] = max_price if max_price.present?
    
    # 日付範囲
    params[:created_from] = created_from if created_from.present?
    params[:created_to] = created_to if created_to.present?
    
    # バッチ条件
    params[:lot_code] = lot_code if lot_code.present?
    params[:expires_before] = expires_before if expires_before.present?
    params[:expires_after] = expires_after if expires_after.present?
    
    # 新しい条件
    params[:stock_filter] = stock_filter if stock_filter.present?
    params[:low_stock_threshold] = low_stock_threshold if low_stock_threshold.present?
    params[:expiring_soon] = "true" if expiring_soon
    params[:expiring_days] = expiring_days if expiring_days.present?
    params[:recently_updated] = "true" if recently_updated
    params[:updated_days] = updated_days if updated_days.present?
    
    # 出荷・入荷
    params[:shipment_status] = shipment_status if shipment_status.present?
    params[:destination] = destination if destination.present?
    params[:receipt_status] = receipt_status if receipt_status.present?
    params[:source] = source if source.present?
    
    # カスタム条件
    params[:or_conditions] = or_conditions if or_conditions.any?
    params[:complex_condition] = complex_condition if complex_condition.any?
    
    # ページング・ソート
    params[:page] = page if page != 1
    params[:per_page] = per_page if per_page != 20
    params[:sort] = sort_field if sort_field != 'updated_at'
    params[:direction] = sort_direction if sort_direction != 'desc'
    
    params
  end
  
  private
  
  # 実際の名前検索値（qとnameの統合）
  def effective_name
    name.presence || q.presence
  end
  
  # 検索タイプを自動判定して実行
  def determine_search_type_and_execute
    if complex_search_required?
      advanced_search
    else
      basic_search
    end
  end
  
  # 基本検索の実行
  def basic_search
    # 従来のSearchQuery.simple_searchと同等の処理
    query = base_scope
    
    # キーワード検索
    if effective_name.present?
      query = query.where("name LIKE ?", "%#{effective_name}%")
    end
    
    # ステータスでフィルタリング
    if status.present?
      query = query.where(status: status)
    end
    
    # 在庫量でフィルタリング
    if low_stock || stock_filter == 'out_of_stock'
      query = query.where("quantity <= 0")
    elsif stock_filter == 'low_stock'
      query = query.where("quantity > 0 AND quantity <= ?", low_stock_threshold)
    elsif stock_filter == 'in_stock'
      query = query.where("quantity > ?", low_stock_threshold)
    end
    
    # 価格範囲
    if price_range_specified?
      query = apply_price_range(query)
    end
    
    # 数量範囲
    if quantity_range_specified?
      query = apply_quantity_range(query)
    end
    
    apply_ordering_and_pagination(query)
  end
  
  # 高度な検索の実行
  def advanced_search
    # 基本的なActive Recordクエリを使用
    query = base_scope
    
    # 基本条件を適用
    query = apply_basic_conditions_to_standard(query)
    
    # 高度な条件を適用
    query = apply_advanced_conditions_to_standard(query)
    
    # ソート・ページング
    query = apply_ordering_and_pagination(query)
    
    query
  end
  
  # カスタム検索の実行（将来拡張）
  def custom_search
    query = AdvancedSearchQuery.build(base_scope)
    
    # カスタム条件を適用
    custom_conditions.each do |condition|
      query = apply_custom_condition(query, condition)
    end
    
    # OR条件
    if or_conditions.any?
      query = query.where_any(or_conditions)
    end
    
    # 複雑な条件
    if complex_condition.any?
      query = build_complex_condition(query, complex_condition)
    end
    
    query.results
  end
  
  # ベーススコープ
  def base_scope
    scope = Inventory.all
    scope = scope.where.not(status: :archived) unless include_archived
    scope
  end
  
  # 基本条件を標準的なクエリに適用
  def apply_basic_conditions_to_standard(query)
    # キーワード検索
    if effective_name.present?
      query = query.where("inventories.name LIKE ?", "%#{effective_name}%")
    end
    
    # ステータス
    if status.present?
      query = query.where(status: status)
    end
    
    # 在庫状態
    case stock_filter
    when "out_of_stock"
      query = query.where("inventories.quantity <= 0")
    when "low_stock"
      query = query.where("inventories.quantity > 0 AND inventories.quantity <= ?", low_stock_threshold)
    when "in_stock"
      query = query.where("inventories.quantity > ?", low_stock_threshold)
    else
      if low_stock
        query = query.where("inventories.quantity <= 0")
      end
    end
    
    # 価格範囲
    if price_range_specified?
      query = apply_price_range(query)
    end
    
    # 数量範囲
    if quantity_range_specified?
      query = apply_quantity_range(query)
    end
    
    query
  end

  # 基本条件をAdvancedSearchQueryに適用
  def apply_basic_conditions_to_advanced(query)
    if effective_name.present?
      query = query.search_keywords(effective_name, fields: [:name, :description])
    end
    
    if status.present?
      query = query.with_status(status)
    end
    
    # 在庫状態
    case stock_filter
    when "out_of_stock"
      query = query.out_of_stock
    when "low_stock"
      query = query.low_stock(low_stock_threshold)
    when "in_stock"
      query = query.where("quantity > ?", low_stock_threshold)
    else
      if low_stock
        query = query.out_of_stock
      end
    end
    
    # 価格範囲
    if price_range_specified?
      query = query.in_range("price", min_price, max_price)
    end
    
    # 数量範囲
    if quantity_range_specified?
      query = query.in_range("quantity", min_quantity, max_quantity)
    end
    
    query
  end
  
  # 高度な条件を標準的なクエリに適用
  def apply_advanced_conditions_to_standard(query)
    # 日付範囲
    if created_date_range_specified?
      if created_from.present? && created_to.present?
        query = query.where(created_at: created_from..created_to)
      elsif created_from.present?
        query = query.where("inventories.created_at >= ?", created_from)
      elsif created_to.present?
        query = query.where("inventories.created_at <= ?", created_to)
      end
    end
    
    if updated_date_range_specified?
      if updated_from.present? && updated_to.present?
        query = query.where(updated_at: updated_from..updated_to)
      elsif updated_from.present?
        query = query.where("inventories.updated_at >= ?", updated_from)
      elsif updated_to.present?
        query = query.where("inventories.updated_at <= ?", updated_to)
      end
    end
    
    # バッチ関連（簡単な実装）
    if lot_code.present?
      query = query.joins(:batches).where("batches.lot_code LIKE ?", "%#{lot_code}%")
    end
    
    if expires_before.present?
      query = query.joins(:batches).where("batches.expires_on <= ?", expires_before)
    end
    
    if expires_after.present?
      query = query.joins(:batches).where("batches.expires_on >= ?", expires_after)
    end
    
    # 期限切れ間近
    if expiring_soon && expiring_days.present?
      expiry_date = Date.current + expiring_days.days
      query = query.joins(:batches).where("batches.expires_on <= ?", expiry_date)
    end
    
    # 最近の更新
    if recently_updated && updated_days.present?
      update_date = Date.current - updated_days.days
      query = query.where("inventories.updated_at >= ?", update_date)
    end
    
    # 出荷関連（簡単な実装）
    if shipment_status.present?
      query = query.joins(:shipments).where(shipments: { status: shipment_status })
    end
    
    if destination.present?
      query = query.joins(:shipments).where("shipments.destination LIKE ?", "%#{destination}%")
    end
    
    # 入荷関連（簡単な実装）
    if receipt_status.present?
      query = query.joins(:receipts).where(receipts: { status: receipt_status })
    end
    
    if source.present?
      query = query.joins(:receipts).where("receipts.source LIKE ?", "%#{source}%")
    end
    
    query
  end

  
  # 価格範囲の適用
  def apply_price_range(query)
    if min_price.present? && max_price.present?
      query.where(price: min_price..max_price)
    elsif min_price.present?
      query.where("price >= ?", min_price)
    elsif max_price.present?
      query.where("price <= ?", max_price)
    else
      query
    end
  end
  
  # 数量範囲の適用
  def apply_quantity_range(query)
    if min_quantity.present? && max_quantity.present?
      query.where(quantity: min_quantity..max_quantity)
    elsif min_quantity.present?
      query.where("quantity >= ?", min_quantity)
    elsif max_quantity.present?
      query.where("quantity <= ?", max_quantity)
    else
      query
    end
  end
  
  # ソート・ページングの適用
  def apply_ordering_and_pagination(query)
    # ソート
    order_column = sortable_fields.include?(sort_field) ? sort_field : 'updated_at'
    order_direction = sort_direction.upcase
    query = query.order("#{order_column} #{order_direction}")
    
    # ページング（Kaminariを使用している場合）
    if page.present?
      query = query.page(page).per(per_page)
    end
    
    query
  end
  
  # 複雑な検索が必要かどうかの判定
  def complex_search_required?
    [
      min_price.present?,
      max_price.present?,
      created_from.present?,
      created_to.present?,
      updated_from.present?,
      updated_to.present?,
      lot_code.present?,
      expires_before.present?,
      expires_after.present?,
      expiring_soon,
      recently_updated,
      shipment_status.present?,
      destination.present?,
      receipt_status.present?,
      source.present?,
      or_conditions.any?,
      complex_condition.any?,
      stock_filter.present?
    ].any?
  end
  
  # バリデーションメソッド
  def price_range_consistency
    return unless min_price.present? && max_price.present?
    
    if min_price > max_price
      errors.add(:max_price, '最高価格は最低価格以上である必要があります')
    end
  end
  
  def quantity_range_consistency
    return unless min_quantity.present? && max_quantity.present?
    
    if min_quantity > max_quantity
      errors.add(:max_quantity, '最大数量は最小数量以上である必要があります')
    end
  end
  
  def date_range_consistency
    check_date_range(:created_from, :created_to, '作成日')
    check_date_range(:updated_from, :updated_to, '更新日')
  end
  
  def check_date_range(from_field, to_field, field_name)
    from_date = send(from_field)
    to_date = send(to_field)
    
    return unless from_date.present? && to_date.present?
    
    if from_date > to_date
      errors.add(to_field, "#{field_name}の終了日は開始日以降である必要があります")
    end
  end
  
  # ソート可能フィールドの定義
  def sortable_fields
    %w[name price quantity created_at updated_at status]
  end
  
  # 条件チェックヘルパー
  def basic_conditions?
    effective_name.present? || status.present? || price_range_specified? || 
    quantity_range_specified? || low_stock || stock_filter.present?
  end
  
  def advanced_conditions?
    created_date_range_specified? || updated_date_range_specified? || 
    expiry_conditions? || expiring_soon || recently_updated ||
    shipment_status.present? || destination.present? ||
    receipt_status.present? || source.present?
  end
  
  def custom_conditions?
    custom_conditions.any? || or_conditions.any? || complex_condition.any?
  end
  
  def price_range_specified?
    min_price.present? || max_price.present?
  end
  
  def quantity_range_specified?
    min_quantity.present? || max_quantity.present?
  end
  
  def created_date_range_specified?
    created_from.present? || created_to.present?
  end
  
  def updated_date_range_specified?
    updated_from.present? || updated_to.present?
  end
  
  def expiry_conditions?
    lot_code.present? || expires_before.present? || expires_after.present?
  end
  
  # 表示用ヘルパー
  def status_display
    return '' unless status.present?
    I18n.t("activerecord.attributes.inventory.statuses.#{status}", default: status.humanize)
  end
  
  def price_range_display
    if min_price.present? && max_price.present?
      "#{min_price}円〜#{max_price}円"
    elsif min_price.present?
      "#{min_price}円以上"
    elsif max_price.present?
      "#{max_price}円以下"
    end
  end
  
  def quantity_range_display
    if min_quantity.present? && max_quantity.present?
      "#{min_quantity}〜#{max_quantity}"
    elsif min_quantity.present?
      "#{min_quantity}以上"
    elsif max_quantity.present?
      "#{max_quantity}以下"
    end
  end
  
  def date_range_display(from_date, to_date)
    if from_date.present? && to_date.present?
      "#{from_date}〜#{to_date}"
    elsif from_date.present?
      "#{from_date}以降"
    elsif to_date.present?
      "#{to_date}以前"
    end
  end
  
  def expiry_display
    conditions = []
    conditions << "ロット: #{lot_code}" if lot_code.present?
    conditions << "期限前: #{expires_before}" if expires_before.present?
    conditions << "期限後: #{expires_after}" if expires_after.present?
    conditions.join(', ')
  end
  
  def stock_filter_display
    case stock_filter
    when 'out_of_stock'
      '在庫切れ'
    when 'low_stock'
      "在庫少 (#{low_stock_threshold}以下)"
    when 'in_stock'
      "在庫あり (#{low_stock_threshold}超)"
    else
      stock_filter
    end
  end
  
  # カスタム条件の適用（将来拡張用）
  def apply_custom_condition(query, condition)
    # SearchConditionオブジェクトを使用する場合
    if condition.respond_to?(:to_sql_condition)
      sql_condition = condition.to_sql_condition
      query = query.where(sql_condition) if sql_condition
    end
    
    query
  end
  
  # 複雑な条件を構築（SearchQueryからの移植）
  def build_complex_condition(query, condition)
    return query unless condition.is_a?(Hash)
    
    condition.each do |type, sub_conditions|
      case type.to_s
      when "and"
        query = query.where_all(sub_conditions)
      when "or"
        query = query.where_any(sub_conditions)
      end
    end
    
    query
  end
end