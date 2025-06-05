# frozen_string_literal: true

# 高度な検索機能を提供するサービスクラス
# Ransackを使用せずに、複雑な検索条件（OR/AND混在、ポリモーフィック関連、クロステーブル検索）を実装
class AdvancedSearchQuery
  attr_reader :base_scope, :joins_applied, :distinct_applied

  def initialize(scope = Inventory.all)
    @base_scope = scope
    @joins_applied = Set.new
    @distinct_applied = false
  end

  # メソッドチェーンで検索条件を構築
  def self.build(scope = Inventory.all)
    new(scope)
  end

  # AND条件での検索
  def where(*args)
    @base_scope = @base_scope.where(*args)
    self
  end

  # OR条件での検索
  def or_where(conditions)
    @base_scope = @base_scope.or(Inventory.where(conditions))
    self
  end

  # 複数のOR条件を組み合わせる
  def where_any(conditions_array)
    return self if conditions_array.empty?

    combined_scope = nil
    conditions_array.each do |conditions|
      scope = Inventory.where(conditions)
      combined_scope = combined_scope ? combined_scope.or(scope) : scope
    end

    @base_scope = @base_scope.merge(combined_scope) if combined_scope
    self
  end

  # 複数のAND条件を組み合わせる
  def where_all(conditions_array)
    conditions_array.each do |conditions|
      @base_scope = @base_scope.where(conditions)
    end
    self
  end

  # カスタム条件でのグループ化（AND/ORの複雑な組み合わせ）
  def complex_where(&block)
    builder = ComplexConditionBuilder.new(@base_scope)
    yield(builder) if block_given?
    @base_scope = builder.base_scope
    self
  end

  # キーワード検索（複数フィールドを対象）
  def search_keywords(keyword, fields: [ :name, :description ])
    return self if keyword.blank?

    conditions = fields.map do |field|
      "#{field} LIKE :keyword"
    end.join(" OR ")

    where("(#{conditions})", keyword: "%#{keyword}%")
  end

  # 日付範囲検索
  def between_dates(field, from, to)
    return self if from.blank? && to.blank?

    if from.present? && to.present?
      where("#{field} BETWEEN ? AND ?", from, to)
    elsif from.present?
      where("#{field} >= ?", from)
    else
      where("#{field} <= ?", to)
    end
  end

  # 数値範囲検索
  def in_range(field, min, max)
    return self if min.blank? && max.blank?

    if min.present? && max.present?
      where("#{field} BETWEEN ? AND ?", min, max)
    elsif min.present?
      where("#{field} >= ?", min)
    else
      where("#{field} <= ?", max)
    end
  end

  # Enumフィールドでの検索
  def with_status(status)
    return self unless status.present?

    if status.is_a?(Array)
      where(status: status)
    else
      where(status: status)
    end
  end

  # バッチ（ロット）関連の検索
  def with_batch_conditions(&block)
    ensure_join(:batches)
    builder = BatchConditionBuilder.new
    builder.instance_eval(&block)
    @base_scope = builder.apply_to(@base_scope)
    self
  end

  # 在庫ログ関連の検索
  def with_inventory_log_conditions(&block)
    ensure_join(:inventory_logs)
    builder = InventoryLogConditionBuilder.new
    builder.instance_eval(&block)
    @base_scope = builder.apply_to(@base_scope)
    self
  end

  # 出荷関連の検索
  def with_shipment_conditions(&block)
    ensure_join(:shipments)
    builder = ShipmentConditionBuilder.new
    builder.instance_eval(&block)
    @base_scope = builder.apply_to(@base_scope)
    self
  end

  # 入荷関連の検索
  def with_receipt_conditions(&block)
    ensure_join(:receipts)
    builder = ReceiptConditionBuilder.new
    builder.instance_eval(&block)
    @base_scope = builder.apply_to(@base_scope)
    self
  end

  # ポリモーフィック関連（監査ログ）の検索
  def with_audit_conditions(&block)
    ensure_join(:audit_logs)
    builder = AuditConditionBuilder.new
    builder.instance_eval(&block)
    @base_scope = builder.apply_to(@base_scope)
    self
  end

  # 期限切れ間近の商品検索
  def expiring_soon(days = 30)
    ensure_join(:batches)
    where("batches.expires_on BETWEEN ? AND ?", Date.current, days.days.from_now)
  end

  # 在庫切れ商品の検索
  def out_of_stock
    where("inventories.quantity <= 0")
  end

  # 低在庫商品の検索（カスタム閾値）
  def low_stock(threshold = 10)
    where("inventories.quantity > 0 AND inventories.quantity <= ?", threshold)
  end

  # 最近更新された商品
  def recently_updated(days = 7)
    where("inventories.updated_at >= ?", days.days.ago)
  end

  # 特定ユーザーが操作した商品
  def modified_by_user(user_id)
    ensure_join(:inventory_logs)
    where("inventory_logs.user_id = ?", user_id)
  end

  # ソート
  def order_by(field, direction = :asc)
    @base_scope = @base_scope.order(field => direction)
    self
  end

  # 複数条件でのソート
  def order_by_multiple(orders)
    @base_scope = @base_scope.order(orders)
    self
  end

  # 重複を除外
  def distinct
    unless @distinct_applied
      @base_scope = @base_scope.distinct
      @distinct_applied = true
    end
    self
  end

  # ページネーション
  def paginate(page: 1, per_page: 20)
    @base_scope = @base_scope.page(page).per(per_page)
    self
  end

  # 結果を取得
  def results
    @base_scope
  end

  # カウントを取得
  def count
    @base_scope.count
  end

  # SQLプレビュー（デバッグ用）
  def to_sql
    @base_scope.to_sql
  end

  private

  # 必要に応じてJOINを追加
  def ensure_join(association)
    unless @joins_applied.include?(association)
      @base_scope = @base_scope.joins(association)
      @joins_applied.add(association)
      # JOINによる重複を防ぐため、常にdistinctを適用
      apply_distinct
    end
  end

  # distinctを安全に適用
  def apply_distinct
    unless @distinct_applied
      @base_scope = @base_scope.distinct
      @distinct_applied = true
    end
  end

  # 複雑な条件を構築するビルダークラス
  class ComplexConditionBuilder
    attr_reader :base_scope

    def initialize(scope)
      @base_scope = scope
    end

    def and_group(&block)
      sub_builder = ComplexConditionBuilder.new(@base_scope)
      yield(sub_builder) if block_given?
      @base_scope = @base_scope.merge(sub_builder.base_scope)
      self
    end

    def or_group(&block)
      sub_builder = ComplexConditionBuilder.new(Inventory.all)
      yield(sub_builder) if block_given?
      @base_scope = @base_scope.or(sub_builder.base_scope)
      self
    end

    def where(conditions)
      @base_scope = @base_scope.where(conditions)
      self
    end
  end

  # バッチ条件ビルダー
  class BatchConditionBuilder
    def initialize
      @scope = Inventory.all
    end

    def lot_code(code)
      @scope = @scope.where("batches.lot_code LIKE ?", "%#{code}%")
    end

    def expires_before(date)
      @scope = @scope.where("batches.expires_on < ?", date)
    end

    def expires_after(date)
      @scope = @scope.where("batches.expires_on > ?", date)
    end

    def quantity_greater_than(quantity)
      @scope = @scope.where("batches.quantity > ?", quantity)
    end

    def apply_to(base_scope)
      base_scope.merge(@scope)
    end
  end

  # 在庫ログ条件ビルダー
  class InventoryLogConditionBuilder
    def initialize
      @scope = Inventory.all
    end

    def action_type(type)
      @scope = @scope.where("inventory_logs.action = ?", type)
    end

    def quantity_changed_by(amount)
      @scope = @scope.where("inventory_logs.quantity_change = ?", amount)
    end

    def changed_after(date)
      @scope = @scope.where("inventory_logs.created_at > ?", date)
    end

    def by_user(user_id)
      @scope = @scope.where("inventory_logs.user_id = ?", user_id)
    end

    def apply_to(base_scope)
      base_scope.merge(@scope)
    end
  end

  # 出荷条件ビルダー
  class ShipmentConditionBuilder
    def initialize
      @scope = Inventory.all
    end

    def status(status)
      @scope = @scope.where("shipments.status = ?", status)
    end

    def destination_like(destination)
      @scope = @scope.where("shipments.destination LIKE ?", "%#{destination}%")
    end

    def scheduled_after(date)
      @scope = @scope.where("shipments.scheduled_date > ?", date)
    end

    def tracking_number(number)
      @scope = @scope.where("shipments.tracking_number = ?", number)
    end

    def apply_to(base_scope)
      base_scope.merge(@scope)
    end
  end

  # 入荷条件ビルダー
  class ReceiptConditionBuilder
    def initialize
      @scope = Inventory.all
    end

    def status(status)
      @scope = @scope.where("receipts.status = ?", status)
    end

    def source_like(source)
      @scope = @scope.where("receipts.source LIKE ?", "%#{source}%")
    end

    def received_after(date)
      @scope = @scope.where("receipts.receipt_date > ?", date)
    end

    def cost_range(min, max)
      @scope = @scope.where("receipts.cost BETWEEN ? AND ?", min, max)
    end

    def apply_to(base_scope)
      base_scope.merge(@scope)
    end
  end

  # 監査ログ条件ビルダー
  class AuditConditionBuilder
    def initialize
      @scope = Inventory.all
    end

    def action(action)
      @scope = @scope.where("audit_logs.action = ?", action)
    end

    def changed_fields_include(field)
      @scope = @scope.where("audit_logs.changed_fields LIKE ?", "%#{field}%")
    end

    def created_after(date)
      @scope = @scope.where("audit_logs.created_at > ?", date)
    end

    def by_user(user_id)
      @scope = @scope.where("audit_logs.user_id = ?", user_id)
    end

    def apply_to(base_scope)
      base_scope.merge(@scope)
    end
  end
end
