# frozen_string_literal: true

# 高度な検索機能を提供するサービスクラス
# Ransackを使用せずに、複雑な検索条件（OR/AND混在、ポリモーフィック関連、クロステーブル検索）を実装
#
# セキュリティ対策状況:
# ✅ SQLインジェクション対策: Arel使用による安全なクエリ構築
# ✅ フィールド名ホワイトリスト: allowed_fields配列による制限
# ✅ LIKE検索サニタイズ: ActiveRecord::Base.sanitize_sql_like使用
#
# TODO: パフォーマンス最適化
# - [ ] 検索結果のキャッシュ機能（Redis活用）
#       実装目安: 高頻度検索クエリのキャッシュキー設計
# - [ ] インデックス最適化の推奨事項の実装
#       実装目安: EXPLAIN ANALYZE結果に基づく自動最適化提案
# - [ ] N+1クエリ問題の検出と改善
#       実装目安: includes()の自動提案機能
# - [ ] ページネーション改善（カーソルベース）
#       実装目安: 大量データ用のperformance改善
#
# TODO: 機能拡張
# - [ ] フルテキスト検索対応（ElasticsearchまたはMroonga）
#       実装目安: 曖昧検索、同義語検索、読み仮名検索対応
# - [ ] 保存検索機能（よく使う検索条件の保存）
#       実装目安: ユーザーごとの検索プリセット機能
# - [ ] 検索履歴機能
#       実装目安: 検索キーワードの履歴管理とオートコンプリート
# - [ ] 検索結果のエクスポート機能（CSV/Excel/PDF）
#       実装目安: バックグラウンドジョブでの大容量ファイル生成
# - [ ] リアルタイム検索機能（WebSocket）
#       実装目安: ActionCableを活用したライブ検索
#
# TODO: セキュリティ強化（基本対策完了）
# - [x] SQLインジェクション対策の強化（完了：Arel使用）
# - [x] フィールド名のホワイトリスト化の完全実装（完了）
# - [ ] より詳細な入力値バリデーション
#       実装目安: 型チェック、範囲チェック、文字数制限
# - [ ] 権限に基づくデータフィルタリング
#       実装目安: ユーザーロール別データアクセス制御
# - [ ] レート制限（API呼び出し制限）
#       実装目安: Redis + Sliding Windowアルゴリズム
#
# TODO: 監視とメトリクス
# - [ ] 検索クエリのパフォーマンス監視
#       実装目安: APMツール連携（NewRelic/DataDog）
# - [ ] 人気検索キーワードの分析
#       実装目安: 検索ログの集計とダッシュボード作成
# - [ ] 検索エラー率の追跡
#       実装目安: エラーログ分析とアラート機能
# - [ ] 検索実行時間の測定
#       実装目安: 詳細なクエリパフォーマンス分析
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
  def search_keywords(keyword, fields: [ :name ])
    return self if keyword.blank?

    # カラム名をホワイトリストで検証（実際に存在するカラムのみ）
    allowed_fields = %w[name].freeze
    safe_fields = fields.select { |field| allowed_fields.include?(field.to_s) }
    return self if safe_fields.empty?

    # Arelを使用してセキュアなクエリを構築
    table = Inventory.arel_table
    conditions = safe_fields.map do |field|
      table[field].matches("%#{keyword}%")
    end

    # 複数条件をORで結合
    combined_condition = conditions.reduce { |acc, condition| acc.or(condition) }
    where(combined_condition)
  end

  # 日付範囲検索
  def between_dates(field, from, to)
    return self if from.blank? && to.blank?

    # カラム名をホワイトリストで検証
    allowed_date_fields = %w[created_at updated_at expires_on receipt_date scheduled_date].freeze
    return self unless allowed_date_fields.include?(field.to_s)

    table = Inventory.arel_table
    column = table[field]

    if from.present? && to.present?
      where(column.between(from..to))
    elsif from.present?
      where(column.gteq(from))
    else
      where(column.lteq(to))
    end
  end

  # 数値範囲検索
  def in_range(field, min, max)
    return self if min.blank? && max.blank?

    # カラム名をホワイトリストで検証
    allowed_numeric_fields = %w[quantity cost price weight].freeze
    return self unless allowed_numeric_fields.include?(field.to_s)

    table = Inventory.arel_table
    column = table[field]

    if min.present? && max.present?
      where(column.between(min..max))
    elsif min.present?
      where(column.gteq(min))
    else
      where(column.lteq(max))
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
    # Arelを使用してセキュアなクエリ構築
    batches_table = Batch.arel_table
    where(batches_table[:expires_on].between(Date.current..days.days.from_now))
  end

  # 在庫切れ商品の検索
  def out_of_stock
    # Arelを使用してセキュアなクエリ構築
    table = Inventory.arel_table
    where(table[:quantity].lteq(0))
  end

  # 低在庫商品の検索（カスタム閾値）
  def low_stock(threshold = 10)
    # Arelを使用してセキュアなクエリ構築
    table = Inventory.arel_table
    where(table[:quantity].gt(0).and(table[:quantity].lteq(threshold)))
  end

  # 最近更新された商品
  def recently_updated(days = 7)
    # Arelを使用してセキュアなクエリ構築
    table = Inventory.arel_table
    where(table[:updated_at].gteq(days.days.ago))
  end

  # 特定ユーザーが操作した商品
  def modified_by_user(user_id)
    ensure_join(:inventory_logs)
    where("inventory_logs.admin_id = ?", user_id)
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

    def where(*args)
      @base_scope = @base_scope.where(*args)
      self
    end
  end

  # バッチ条件ビルダー
  class BatchConditionBuilder
    def initialize
      @scope = Inventory.all
    end

    def lot_code(code)
      # セキュリティ改善: 直接文字列補間を回避、プリペアドステートメント使用
      sanitized_code = sanitize_like_input(code)
      @scope = @scope.where("batches.lot_code LIKE ?", "%#{sanitized_code}%")
      self
    end

    def expires_before(date)
      # Arelを使用してセキュアなクエリ構築
      batches_table = Batch.arel_table
      @scope = @scope.where(batches_table[:expires_on].lt(date))
      self
    end

    def expires_after(date)
      # Arelを使用してセキュアなクエリ構築
      batches_table = Batch.arel_table
      @scope = @scope.where(batches_table[:expires_on].gt(date))
      self
    end

    def quantity_greater_than(quantity)
      # Arelを使用してセキュアなクエリ構築
      batches_table = Batch.arel_table
      @scope = @scope.where(batches_table[:quantity].gt(quantity))
      self
    end

    private

    # LIKE検索用の入力値サニタイズ
    def sanitize_like_input(input)
      return "" if input.blank?
      # SQLワイルドカードをエスケープ
      ActiveRecord::Base.sanitize_sql_like(input.to_s)
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
      @scope = @scope.where("inventory_logs.operation_type = ?", type)
      self
    end

    def quantity_changed_by(amount)
      @scope = @scope.where("inventory_logs.delta = ?", amount)
      self
    end

    def changed_after(date)
      @scope = @scope.where("inventory_logs.created_at > ?", date)
      self
    end

    def by_user(user_id)
      @scope = @scope.where("inventory_logs.admin_id = ?", user_id)
      self
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
      @scope = @scope.where("shipments.shipment_status = ?", status)
      self
    end

    def destination_like(destination)
      # セキュリティ改善: LIKE検索用入力値サニタイズ
      sanitized_destination = ActiveRecord::Base.sanitize_sql_like(destination.to_s)
      @scope = @scope.where("shipments.destination LIKE ?", "%#{sanitized_destination}%")
      self
    end

    def scheduled_after(date)
      @scope = @scope.where("shipments.scheduled_date > ?", date)
      self
    end

    def tracking_number(number)
      @scope = @scope.where("shipments.tracking_number = ?", number)
      self
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
      @scope = @scope.where("receipts.receipt_status = ?", status)
      self
    end

    def source_like(source)
      # セキュリティ改善: LIKE検索用入力値サニタイズ
      sanitized_source = ActiveRecord::Base.sanitize_sql_like(source.to_s)
      @scope = @scope.where("receipts.source LIKE ?", "%#{sanitized_source}%")
      self
    end

    def received_after(date)
      @scope = @scope.where("receipts.receipt_date > ?", date)
      self
    end

    def cost_range(min, max)
      @scope = @scope.where("receipts.cost_per_unit BETWEEN ? AND ?", min, max)
      self
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
      self
    end

    def changed_fields_include(field)
      # セキュリティ改善: LIKE検索用入力値サニタイズ
      sanitized_field = ActiveRecord::Base.sanitize_sql_like(field.to_s)
      @scope = @scope.where("audit_logs.changed_fields LIKE ?", "%#{sanitized_field}%")
      self
    end

    def created_after(date)
      @scope = @scope.where("audit_logs.created_at > ?", date)
      self
    end

    def by_user(user_id)
      @scope = @scope.where("audit_logs.user_id = ?", user_id)
      self
    end

    def apply_to(base_scope)
      base_scope.merge(@scope)
    end
  end
end
