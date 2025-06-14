# frozen_string_literal: true

# 高度な検索機能を提供するサービスクラス
# Ransackを使用せずに、複雑な検索条件（OR/AND混在、ポリモーフィック関連、クロステーブル検索）を実装
class AdvancedSearchQuery
  attr_reader :base_scope, :joins_applied, :distinct_applied

  # 許可されたフィールド名のホワイトリスト（SQLインジェクション対策）
  ALLOWED_FIELDS = %w[
    inventories.name inventories.price inventories.quantity
    inventories.status inventories.created_at inventories.updated_at
    batches.lot_code batches.expires_on batches.quantity
    inventory_logs.operation_type inventory_logs.delta inventory_logs.created_at
    shipments.shipment_status shipments.destination shipments.scheduled_date shipments.tracking_number
    receipts.receipt_status receipts.source receipts.receipt_date receipts.cost_per_unit
    audit_logs.action audit_logs.changed_fields audit_logs.created_at
  ].freeze

  # TODO: セキュリティとパフォーマンス強化（推定2-3日）
  # 1. SQLインジェクション対策の強化
  #    - 動的クエリ生成の検証強化
  #    - ユーザー入力のサニタイゼーション改善
  # 2. クエリパフォーマンス最適化
  #    - インデックス利用の最適化
  #    - N+1問題の完全解決
  #    - クエリキャッシュの活用
  # 3. 検索機能の拡張
  #    - 全文検索（PostgreSQL, Elasticsearch）
  #    - ファジー検索対応
  #    - 検索結果のランキング機能

  # 許可されたカラム名のマッピング（シンプルなフィールド名から完全なフィールド名へ）
  FIELD_MAPPING = {
    "name" => "inventories.name",
    "price" => "inventories.price",
    "quantity" => "inventories.quantity",
    "status" => "inventories.status",
    "created_at" => "inventories.created_at",
    "updated_at" => "inventories.updated_at"
  }.freeze

  def initialize(base_scope = Inventory.all)
    @base_scope = base_scope
    @joins_applied = Set.new
    @distinct_applied = false
  end

  # ファクトリーメソッド
  def self.build(base_scope = Inventory.all)
    new(base_scope)
  end

  # Eager loadingサポート（N+1クエリ対策）
  def includes(*associations)
    @base_scope = @base_scope.includes(*associations)
    self
  end

  # AND条件での検索
  def where(*args)
    @base_scope = @base_scope.where(*args)
    self
  end

  # OR条件での検索
  def or_where(*args)
    @base_scope = @base_scope.or(Inventory.where(*args))
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
    builder = ComplexConditionBuilder.new(self)
    builder.instance_eval(&block)
    @base_scope = builder.apply_to(@base_scope)
    self
  end

  # キーワード検索（複数フィールドを対象）
  def search_keywords(keyword, fields: [ :name ])
    return self if keyword.blank?

    # フィールド名の安全性を検証
    safe_fields = fields.map { |field| sanitize_field_name(field.to_s) }.compact
    return self if safe_fields.empty?

    # Arel DSLを使用してOR条件を安全に構築
    table = Inventory.arel_table
    sanitized_keyword = sanitize_like_parameter(keyword)

    or_conditions = safe_fields.map do |field|
      field_parts = field.split(".")
      if field_parts.length == 2 && field_parts[0] == "inventories"
        table[field_parts[1]].matches("%#{sanitized_keyword}%")
      else
        # 他のテーブルの場合は、対応するテーブルを使用
        next nil unless ALLOWED_FIELDS.include?(field)
        table[:name].matches("%#{sanitized_keyword}%") # デフォルトはnameフィールド
      end
    end.compact

    return self if or_conditions.empty?

    combined_condition = or_conditions.reduce { |result, condition| result.or(condition) }
    @base_scope = @base_scope.where(combined_condition)
    self
  end

  # 日付範囲検索
  def between_dates(field, from, to)
    return self if from.blank? && to.blank?

    safe_field = sanitize_field_name(field.to_s)
    return self unless safe_field

    # Arel DSLを使用して安全にクエリを構築
    table = Inventory.arel_table
    field_parts = safe_field.split(".")

    if field_parts.length == 2 && field_parts[0] == "inventories"
      column = table[field_parts[1]]

      if from.present? && to.present?
        @base_scope = @base_scope.where(column.gteq(from).and(column.lteq(to)))
      elsif from.present?
        @base_scope = @base_scope.where(column.gteq(from))
      else
        @base_scope = @base_scope.where(column.lteq(to))
      end
    end
    self
  end

  # 数値範囲検索
  def in_range(field, min, max)
    return self if min.blank? && max.blank?

    safe_field = sanitize_field_name(field.to_s)
    return self unless safe_field

    # Arel DSLを使用して安全にクエリを構築
    table = Inventory.arel_table
    field_parts = safe_field.split(".")

    if field_parts.length == 2 && field_parts[0] == "inventories"
      column = table[field_parts[1]]

      if min.present? && max.present?
        @base_scope = @base_scope.where(column.gteq(min).and(column.lteq(max)))
      elsif min.present?
        @base_scope = @base_scope.where(column.gteq(min))
      else
        @base_scope = @base_scope.where(column.lteq(max))
      end
    end
    self
  end

  # ステータスでの検索
  def with_status(status)
    return self unless status.present? && Inventory::STATUSES.include?(status)

    @base_scope = @base_scope.where(status: status)
    self
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
    @base_scope = @base_scope.where("batches.expires_on BETWEEN ? AND ?", Date.current, days.days.from_now)
    self
  end

  # 在庫切れ商品の検索
  def out_of_stock
    @base_scope = @base_scope.where("inventories.quantity <= 0")
    self
  end

  # 低在庫商品の検索（カスタム閾値）
  def low_stock(threshold = 10)
    @base_scope = @base_scope.where("inventories.quantity > 0 AND inventories.quantity <= ?", threshold)
    self
  end

  # 最近更新された商品
  def recently_updated(days = 7)
    @base_scope = @base_scope.where("inventories.updated_at >= ?", days.days.ago)
    self
  end

  # 特定ユーザーが操作した商品
  def modified_by_user(user_id)
    ensure_join(:inventory_logs)
    @base_scope = @base_scope.where("inventory_logs.user_id = ?", user_id)
    self
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
      # JOINによる重複を防ぐ
      distinct unless @distinct_applied
    end
  end

  # フィールド名のサニタイゼーション（SQLインジェクション対策）
  def sanitize_field_name(field)
    # まずフィールド名のマッピングをチェック
    mapped_field = FIELD_MAPPING[field]

    # マッピングされたフィールドまたは元のフィールドがホワイトリストに含まれているかチェック
    field_to_check = mapped_field || field

    if ALLOWED_FIELDS.include?(field_to_check)
      field_to_check
    else
      Rails.logger.warn "Potentially unsafe field name rejected: #{field}"
      nil
    end
  end

  # LIKE検索用のパラメータサニタイゼーション
  def sanitize_like_parameter(value)
    # SQLインジェクション対策: エスケープ文字の処理
    value.to_s.gsub(/[%_\\]/) { |match| "\\#{match}" }
  end

  # 複雑な条件を構築するビルダークラス
  class ComplexConditionBuilder
    # TODO: ベストプラクティス - ComplexConditionBuilderのスコープ問題を修正
    attr_reader :parent_scope

    def initialize(parent_scope = nil)
      @conditions = []
      @parent_scope = parent_scope
    end

    def and(&block)
      sub_builder = ComplexConditionBuilder.new(@parent_scope)
      sub_builder.instance_eval(&block)
      @conditions << { type: :and, builder: sub_builder }
      self
    end

    def or(&block)
      sub_builder = ComplexConditionBuilder.new(@parent_scope)
      sub_builder.instance_eval(&block)
      @conditions << { type: :or, builder: sub_builder }
      self
    end

    def where(*args)
      @conditions << { type: :where, conditions: args }
      self
    end

    # TODO: 横展開確認 - 外部変数へのアクセスを可能にするメソッド
    def method_missing(method_name, *args, &block)
      if @parent_scope && @parent_scope.respond_to?(method_name)
        @parent_scope.send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      (@parent_scope && @parent_scope.respond_to?(method_name, include_private)) || super
    end

    def apply_to(scope)
      result_scope = scope

      @conditions.each_with_index do |condition, index|
        case condition[:type]
        when :where
          if index == 0
            result_scope = result_scope.where(*condition[:conditions])
          else
            prev = @conditions[index - 1]
            if prev[:type] == :or || (prev[:type] == :where && @conditions[index - 2]&.dig(:type) == :or)
              result_scope = result_scope.or(scope.where(*condition[:conditions]))
            else
              result_scope = result_scope.where(*condition[:conditions])
            end
          end
        when :and
          result_scope = condition[:builder].apply_to(result_scope)
        when :or
          sub_scope = condition[:builder].apply_to(scope)
          result_scope = result_scope.or(sub_scope)
        end
      end

      result_scope
    end
  end

  # バッチ条件ビルダー
  class BatchConditionBuilder
    def initialize
      @conditions = []
    end

    def lot_code(code)
      @conditions << [ "batches.lot_code LIKE ?", "%#{code}%" ]
    end

    def expires_before(date)
      @conditions << [ "batches.expires_on < ?", date ]
    end

    def expires_after(date)
      @conditions << [ "batches.expires_on > ?", date ]
    end

    def quantity_greater_than(quantity)
      @conditions << [ "batches.quantity > ?", quantity ]
    end

    def apply_to(base_scope)
      @conditions.reduce(base_scope) do |scope, (condition, *values)|
        scope.where(condition, *values)
      end
    end
  end

  # 在庫ログ条件ビルダー
  class InventoryLogConditionBuilder
    def initialize
      @conditions = []
    end

    def action_type(type)
      @conditions << [ "inventory_logs.operation_type = ?", type ]
    end

    def quantity_changed_by(amount)
      @conditions << [ "inventory_logs.delta = ?", amount ]
    end

    def changed_after(date)
      @conditions << [ "inventory_logs.created_at > ?", date ]
    end

    def by_user(user_id)
      @conditions << [ "inventory_logs.user_id = ?", user_id ]
    end

    def apply_to(base_scope)
      @conditions.reduce(base_scope) do |scope, (condition, *values)|
        scope.where(condition, *values)
      end
    end
  end

  # 出荷条件ビルダー
  class ShipmentConditionBuilder
    def initialize
      @conditions = []
    end

    def status(status)
      # Enum値を適切に処理（文字列をenum整数値に変換）
      enum_value = Shipment.shipment_statuses[status.to_s]
      @conditions << [ "shipments.shipment_status = ?", enum_value ]
    end

    def destination_like(destination)
      @conditions << [ "shipments.destination LIKE ?", "%#{destination}%" ]
    end

    def scheduled_after(date)
      @conditions << [ "shipments.scheduled_date > ?", date ]
    end

    def tracking_number(number)
      @conditions << [ "shipments.tracking_number = ?", number ]
    end

    def apply_to(base_scope)
      @conditions.reduce(base_scope) do |scope, (condition, *values)|
        scope.where(condition, *values)
      end
    end
  end

  # 入荷条件ビルダー
  class ReceiptConditionBuilder
    def initialize
      @conditions = []
    end

    def status(status)
      @conditions << [ "receipts.receipt_status = ?", status ]
    end

    def source_like(source)
      @conditions << [ "receipts.source LIKE ?", "%#{source}%" ]
    end

    def received_after(date)
      @conditions << [ "receipts.receipt_date > ?", date ]
    end

    def cost_range(min, max)
      @conditions << [ "receipts.cost_per_unit BETWEEN ? AND ?", min, max ]
    end

    def apply_to(base_scope)
      @conditions.reduce(base_scope) do |scope, (condition, *values)|
        scope.where(condition, *values)
      end
    end
  end

  # 監査ログ条件ビルダー
  class AuditConditionBuilder
    def initialize
      @conditions = []
    end

    def action(action)
      @conditions << [ "audit_logs.action = ?", action ]
    end

    def changed_fields_include(field)
      @conditions << [ "audit_logs.changed_fields LIKE ?", "%#{field}%" ]
    end

    def created_after(date)
      @conditions << [ "audit_logs.created_at > ?", date ]
    end

    def by_user(user_id)
      @conditions << [ "audit_logs.user_id = ?", user_id ]
    end

    def apply_to(base_scope)
      @conditions.reduce(base_scope) do |scope, (condition, *values)|
        scope.where(condition, *values)
      end
    end
  end
end
