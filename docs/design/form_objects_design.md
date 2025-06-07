# フォームオブジェクト設計書 - 複雑な検索フォームの管理

## 1. 概要

### 1.1 現状と課題

StockRxの検索機能は高度な機能を持つが、以下の課題を抱えている：

#### 現状の優位性
- **AdvancedSearchQuery**: 419行の包括的な検索サービス
- **複雑な条件構築**: AND/OR組み合わせ、関連テーブル横断検索
- **高いカバレッジ**: 15以上の検索パラメータをサポート
- **パフォーマンス配慮**: DISTINCT自動適用、ページネーション対応

#### 主要な課題
1. **パラメータ管理の複雑性**: 20以上のパラメータが手動管理されている
2. **バリデーション不足**: 検索パラメータの型・範囲チェックがない
3. **セキュリティリスク**: 直接的なパラメータ渡しによるSQLインジェクション可能性
4. **コード重複**: 複数のコントローラーで似た処理の反復
5. **状態管理の欠如**: フォーム状態の永続化や復元機能がない

### 1.2 目的

本設計書では、以下を実現するフォームオブジェクトパターンを提案する：

- 検索パラメータの一元的なバリデーション
- 型安全性の確保とセキュリティ強化
- フォーム状態の適切な管理
- コードの再利用性向上
- テスタビリティの向上

## 🎯 背景と課題

### 現状の問題点

#### Before（現在の実装）
```ruby
# app/views/inventories/_advanced_search_form.html.erb
<%= form_with url: inventories_path, method: :get do |f| %>
  <%= f.text_field :q, value: params[:q] %>
  <%= f.select :status, options_for_select(...) %>
  <%= f.number_field :min_price, value: params[:min_price] %>
  <!-- 15以上のフィールドが散在 -->
<% end %>

# app/controllers/inventories_controller.rb
def index
  if complex_search_required?(params)
    @inventories = SearchQuery.new.advanced_search(params)
  else
    @inventories = SearchQuery.new.simple_search(params)
  end
end
```

**課題**：
- ビューに検索ロジックが散在
- パラメータバリデーションが不十分
- 検索条件の永続化困難
- 複雑な条件組み合わせの管理が困難
- テスタビリティの低下

#### After（フォームオブジェクト導入後）
```ruby
# app/forms/inventory_search_form.rb
class InventorySearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  # 検索ロジックとバリデーションを集約
end

# app/controllers/inventories_controller.rb
def index
  @search_form = InventorySearchForm.new(search_params)
  @inventories = @search_form.search if @search_form.valid?
end
```

**改善点**：
- 検索ロジックの集約化
- 強固なバリデーション
- 検索条件の永続化対応
- テスト容易性の向上

## 🏗️ アーキテクチャ設計

### 設計方針の比較検討

#### アプローチ1: シンプルフォームオブジェクト
```ruby
class InventorySearchForm
  include ActiveModel::Model
  # 基本的な検索フィールドのみ
end
```
**利点**: 実装が簡単、理解しやすい
**欠点**: 複雑な検索には限界、拡張性に課題

#### アプローチ2: 階層化フォームオブジェクト（推奨）
```ruby
class InventorySearchForm < BaseSearchForm
  # 基本検索
  has_many :advanced_conditions, class_name: 'SearchCondition'
end
```
**利点**: 拡張性、再利用性、保守性が高い
**欠点**: 初期実装コストが高い

#### アプローチ3: Compositeパターン
```ruby
class SearchFormComposite
  def initialize(*forms)
    @forms = forms
  end
end
```
**利点**: 柔軟性が最も高い
**欠点**: 複雑すぎる、過剰設計のリスク

**採用決定**: アプローチ2（階層化）を選択
**理由**: 拡張性と実装コストのバランスが最適

### システム構成図

```
┌─────────────────────────────────────────────────────────────┐
│                     View Layer                              │
├─────────────────────────────────────────────────────────────┤
│  inventory_search_form.html.erb                            │
│  ├─ BasicSearchForm (名前、ステータス、価格範囲)              │
│  ├─ AdvancedSearchForm (日付範囲、バッチ条件)                │
│  └─ CustomConditionsForm (OR/AND条件組み合わせ)              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  Form Objects Layer                         │
├─────────────────────────────────────────────────────────────┤
│  InventorySearchForm (メインフォーム)                        │
│  ├─ include ActiveModel::Model                             │
│  ├─ include ActiveModel::Attributes                        │
│  ├─ include SearchFormValidations                          │
│  └─ include SearchFormPersistence                          │
│                                                             │
│  SearchCondition (個別条件)                                 │
│  ├─ field: string                                          │
│  ├─ operator: enum                                         │
│  ├─ value: polymorphic                                     │
│  └─ logic_type: enum (AND/OR)                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                Service Objects Layer                        │
├─────────────────────────────────────────────────────────────┤
│  SearchQueryBuilder                                         │
│  ├─ FormToQueryConverter                                    │
│  ├─ AdvancedSearchQuery (既存)                             │
│  └─ QueryOptimizer                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Data Layer                               │
├─────────────────────────────────────────────────────────────┤
│  Inventory, Batch, InventoryLog, etc.                      │
└─────────────────────────────────────────────────────────────┘
```

## 📊 詳細設計

### 1. ベースフォームオブジェクト

```ruby
# app/forms/base_search_form.rb
class BaseSearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  include ActiveModel::Serialization
  
  # 共通属性
  attribute :page, :integer, default: 1
  attribute :per_page, :integer, default: 20
  attribute :sort_field, :string, default: 'updated_at'
  attribute :sort_direction, :string, default: 'desc'
  
  # バリデーション
  validates :page, numericality: { greater_than: 0 }
  validates :per_page, inclusion: { in: [10, 20, 50, 100] }
  validates :sort_direction, inclusion: { in: %w[asc desc] }
  
  # 抽象メソッド
  def search
    raise NotImplementedError, "#{self.class.name}#search must be implemented"
  end
  
  # 検索結果のキャッシュキー生成
  def cache_key
    Digest::MD5.hexdigest(serializable_hash.to_json)
  end
end
```

### 2. メインフォームオブジェクト

```ruby
# app/forms/inventory_search_form.rb
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
  
  # カスタム条件
  attribute :custom_conditions, :array, default: []
  
  # バリデーション
  validates :name, length: { maximum: 255 }
  validates :min_price, :max_price, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
  validates :min_quantity, :max_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_blank: true
  validates :search_type, inclusion: { in: %w[basic advanced custom] }
  validates :stock_filter, inclusion: { in: %w[out_of_stock low_stock in_stock all] }, allow_blank: true
  
  validate :price_range_consistency
  validate :quantity_range_consistency
  validate :date_range_consistency
  
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
      basic_search
    end
  end
  
  # 検索実行前の条件チェック
  def has_search_conditions?
    basic_conditions? || advanced_conditions? || custom_conditions?
  end
  
  # 検索条件のサマリー生成
  def conditions_summary
    conditions = []
    conditions << "名前: #{name}" if name.present?
    conditions << "ステータス: #{status}" if status.present?
    conditions << "価格: #{min_price}円〜#{max_price}円" if price_range_specified?
    conditions << "数量: #{min_quantity}〜#{max_quantity}" if quantity_range_specified?
    conditions << "作成日: #{created_from}〜#{created_to}" if created_date_range_specified?
    conditions << "期限: #{expires_before}日前〜#{expires_after}日後" if expiry_conditions?
    conditions.join(', ')
  end
  
  # 永続化用のハッシュ
  def to_params
    attributes.reject { |_, v| v.blank? }
  end
  
  # URL用のクエリパラメータ
  def to_query_params
    to_params.to_query
  end
  
  private
  
  def basic_search
    query = SearchQueryBuilder.new(base_scope)
    
    query.filter_by_name(name) if name.present?
    query.filter_by_status(status) if status.present?
    query.filter_by_price_range(min_price, max_price) if price_range_specified?
    query.filter_by_quantity_range(min_quantity, max_quantity) if quantity_range_specified?
    query.filter_by_stock_status(stock_filter) if stock_filter.present?
    
    query.paginate(page: page, per_page: per_page)
         .order_by(sort_field, sort_direction)
         .results
  end
  
  def advanced_search
    query = AdvancedSearchQuery.build(base_scope)
    
    # 基本条件を適用
    query = apply_basic_conditions(query)
    
    # 高度な条件を適用
    query = apply_advanced_conditions(query)
    
    query.paginate(page: page, per_page: per_page)
         .order_by(sort_field, sort_direction)
         .results
  end
  
  def custom_search
    query = AdvancedSearchQuery.build(base_scope)
    
    # カスタム条件を適用
    custom_conditions.each do |condition|
      query = apply_custom_condition(query, condition)
    end
    
    query.results
  end
  
  def base_scope
    scope = Inventory.all
    scope = scope.where.not(status: :archived) unless include_archived
    scope
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
  
  # 条件チェックヘルパー
  def basic_conditions?
    name.present? || status.present? || price_range_specified? || quantity_range_specified?
  end
  
  def advanced_conditions?
    created_date_range_specified? || updated_date_range_specified? || expiry_conditions?
  end
  
  def custom_conditions?
    custom_conditions.any?
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
    lot_code.present? || expires_before.present? || expires_after.present? || expiring_days.present?
  end
end
```

### 3. 検索条件オブジェクト

```ruby
# app/forms/search_condition.rb
class SearchCondition
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  # フィールド定義
  attribute :field, :string
  attribute :operator, :string
  attribute :value, :string
  attribute :logic_type, :string, default: 'AND'
  attribute :data_type, :string, default: 'string'
  
  # 演算子の定義
  OPERATORS = {
    'equals' => '=',
    'not_equals' => '!=',
    'contains' => 'LIKE',
    'not_contains' => 'NOT LIKE',
    'starts_with' => 'LIKE',
    'ends_with' => 'LIKE',
    'greater_than' => '>',
    'greater_than_or_equal' => '>=',
    'less_than' => '<',
    'less_than_or_equal' => '<=',
    'between' => 'BETWEEN',
    'in' => 'IN',
    'not_in' => 'NOT IN',
    'is_null' => 'IS NULL',
    'is_not_null' => 'IS NOT NULL'
  }.freeze
  
  DATA_TYPES = %w[string integer decimal date boolean].freeze
  LOGIC_TYPES = %w[AND OR].freeze
  
  # バリデーション
  validates :field, presence: true
  validates :operator, inclusion: { in: OPERATORS.keys }
  validates :logic_type, inclusion: { in: LOGIC_TYPES }
  validates :data_type, inclusion: { in: DATA_TYPES }
  validate :value_presence_for_operator
  validate :value_type_consistency
  
  # SQL条件生成
  def to_sql_condition
    return nil unless valid?
    
    case operator
    when 'contains'
      ["#{field} LIKE ?", "%#{value}%"]
    when 'not_contains'
      ["#{field} NOT LIKE ?", "%#{value}%"]
    when 'starts_with'
      ["#{field} LIKE ?", "#{value}%"]
    when 'ends_with'
      ["#{field} LIKE ?", "%#{value}"]
    when 'between'
      values = value.split(',').map(&:strip)
      ["#{field} BETWEEN ? AND ?", values[0], values[1]]
    when 'in', 'not_in'
      values = value.split(',').map(&:strip)
      placeholders = Array.new(values.size, '?').join(',')
      ["#{field} #{OPERATORS[operator]} (#{placeholders})", *values]
    when 'is_null', 'is_not_null'
      "#{field} #{OPERATORS[operator]}"
    else
      ["#{field} #{OPERATORS[operator]} ?", converted_value]
    end
  end
  
  private
  
  def value_presence_for_operator
    null_operators = %w[is_null is_not_null]
    return if null_operators.include?(operator)
    
    errors.add(:value, 'を入力してください') if value.blank?
  end
  
  def value_type_consistency
    return if value.blank? || data_type == 'string'
    
    case data_type
    when 'integer'
      errors.add(:value, '数値を入力してください') unless value =~ /^\d+$/
    when 'decimal'
      errors.add(:value, '数値を入力してください') unless value =~ /^\d+(\.\d+)?$/
    when 'date'
      begin
        Date.parse(value)
      rescue ArgumentError
        errors.add(:value, '有効な日付を入力してください')
      end
    when 'boolean'
      errors.add(:value, 'true/falseを入力してください') unless %w[true false].include?(value.downcase)
    end
  end
  
  def converted_value
    case data_type
    when 'integer'
      value.to_i
    when 'decimal'
      value.to_f
    when 'date'
      Date.parse(value)
    when 'boolean'
      value.downcase == 'true'
    else
      value
    end
  end
end
```

## 🔒 セキュリティ考慮事項

### 1. SQLインジェクション対策
```ruby
# パラメータ化クエリの使用
def safe_query_build(conditions)
  where_clauses = []
  values = []
  
  conditions.each do |condition|
    sql_condition = condition.to_sql_condition
    if sql_condition.is_a?(Array)
      where_clauses << sql_condition.first
      values.concat(sql_condition[1..-1])
    else
      where_clauses << sql_condition
    end
  end
  
  base_scope.where(where_clauses.join(' AND '), *values)
end
```

### 2. 許可フィールドの制限
```ruby
# ホワイトリスト方式
ALLOWED_SEARCH_FIELDS = %w[
  name status price quantity created_at updated_at
  batches.lot_code batches.expires_on
].freeze

validates :field, inclusion: { in: ALLOWED_SEARCH_FIELDS }
```

### 3. 入力値サニタイゼーション
```ruby
def sanitize_input(value)
  return value if value.blank?
  
  # HTMLタグの除去
  ActionController::Base.helpers.sanitize(value, tags: [])
end
```

## ⚡ パフォーマンス最適化

### 1. クエリ最適化
```ruby
# N+1問題の回避
def optimized_search
  query = base_query
  query = query.includes(:batches, :inventory_logs) if include_relations?
  query = query.select(select_fields) if specific_fields_only?
  query
end

# インデックス推奨
# ALTER TABLE inventories ADD INDEX idx_search_common (name, status, price, quantity);
# ALTER TABLE batches ADD INDEX idx_batch_search (lot_code, expires_on);
```

### 2. キャッシュ戦略
```ruby
# 検索結果のキャッシュ
def cached_search
  cache_key = "inventory_search:#{self.cache_key}"
  
  Rails.cache.fetch(cache_key, expires_in: 15.minutes) do
    search.to_a
  end
end

# カウントクエリの最適化
def total_count
  @total_count ||= search.except(:limit, :offset).count
end
```

## 🧪 テスト戦略

### 1. ユニットテスト
```ruby
# spec/forms/inventory_search_form_spec.rb
RSpec.describe InventorySearchForm, type: :model do
  describe 'validations' do
    it { should validate_numericality_of(:min_price).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:max_price).is_greater_than_or_equal_to(0) }
    
    context 'price range consistency' do
      let(:form) { described_class.new(min_price: 100, max_price: 50) }
      
      it 'adds error when max_price is less than min_price' do
        expect(form).not_to be_valid
        expect(form.errors[:max_price]).to include('最高価格は最低価格以上である必要があります')
      end
    end
  end
  
  describe '#search' do
    let!(:inventory1) { create(:inventory, name: 'テスト商品A', price: 100) }
    let!(:inventory2) { create(:inventory, name: 'テスト商品B', price: 200) }
    
    context 'basic search' do
      let(:form) { described_class.new(name: 'テスト', search_type: 'basic') }
      
      it 'returns matching inventories' do
        results = form.search
        expect(results).to include(inventory1, inventory2)
      end
    end
    
    context 'price range search' do
      let(:form) { described_class.new(min_price: 150, max_price: 250, search_type: 'basic') }
      
      it 'returns inventories within price range' do
        results = form.search
        expect(results).to include(inventory2)
        expect(results).not_to include(inventory1)
      end
    end
  end
end
```

### 2. 統合テスト
```ruby
# spec/features/inventory_search_spec.rb
RSpec.feature 'Inventory Search', type: :feature do
  scenario 'User performs advanced search' do
    visit inventories_path
    
    click_link '高度な検索'
    
    fill_in '商品名', with: 'テスト'
    select 'アクティブ', from: 'ステータス'
    fill_in '最低価格', with: '100'
    fill_in '最高価格', with: '500'
    
    click_button '検索'
    
    expect(page).to have_content('検索結果')
    expect(page).to have_css('.inventory-item')
  end
end
```

## 🌍 国際化対応

### 1. 多言語フィールドラベル
```yaml
# config/locales/ja.yml
ja:
  forms:
    inventory_search:
      name: "商品名"
      status: "ステータス"
      min_price: "最低価格"
      max_price: "最高価格"
      search_type: "検索タイプ"
      
  search_operators:
    equals: "等しい"
    contains: "含む"
    greater_than: "より大きい"
    less_than: "より小さい"
```

### 2. 動的ローカライゼーション
```ruby
def localized_field_options
  ALLOWED_SEARCH_FIELDS.map do |field|
    [I18n.t("forms.inventory_search.#{field}"), field]
  end
end
```

## 🔄 拡張性設計

### 1. プラガブル検索条件
```ruby
# app/forms/concerns/pluggable_search.rb
module PluggableSearch
  extend ActiveSupport::Concern
  
  included do
    class_attribute :search_plugins, default: []
  end
  
  class_methods do
    def register_plugin(plugin_class)
      self.search_plugins += [plugin_class]
    end
  end
  
  def apply_plugins(query)
    search_plugins.each do |plugin_class|
      plugin = plugin_class.new(self)
      query = plugin.apply(query) if plugin.applicable?
    end
    query
  end
end
```

### 2. カスタムフィールド対応
```ruby
# 将来の拡張：カスタムフィールド検索
class CustomFieldSearchCondition < SearchCondition
  belongs_to :custom_field
  
  def to_sql_condition
    case custom_field.field_type
    when 'json'
      build_json_condition
    when 'array'
      build_array_condition
    else
      super
    end
  end
end
```

## 📈 運用・保守

### 1. ログ・監視
```ruby
# 検索パフォーマンスの監視
def search_with_monitoring
  start_time = Time.current
  result = search
  duration = Time.current - start_time
  
  Rails.logger.info({
    event: 'inventory_search',
    duration: duration,
    conditions: conditions_summary,
    result_count: result.size
  }.to_json)
  
  result
end
```

### 2. メトリクス収集
```ruby
# 検索パターンの分析
def track_search_metrics
  SearchMetrics.increment('inventory_search.total')
  SearchMetrics.increment("inventory_search.type.#{search_type}")
  SearchMetrics.timing('inventory_search.duration', search_duration)
end
```

## 📚 実装ロードマップ

### Phase 1: 基盤実装（1-2週間）
- [ ] BaseSearchForm の実装
- [ ] InventorySearchForm の基本機能
- [ ] 基本的なバリデーション
- [ ] ユニットテストの作成

### Phase 2: 高度な機能（2-3週間）
- [ ] SearchCondition の実装
- [ ] カスタム検索条件の対応
- [ ] パフォーマンス最適化
- [ ] 統合テストの追加

### Phase 3: UI/UX改善（1-2週間）
- [ ] フロントエンド実装
- [ ] Ajax対応
- [ ] 検索履歴機能
- [ ] エクスポート機能

### Phase 4: 運用機能（1週間）
- [ ] 監視・ログ機能
- [ ] メトリクス収集
- [ ] ドキュメント整備
- [ ] 本番デプロイ

## 🎯 成功指標

### パフォーマンス指標
- 検索レスポンス時間: < 500ms (95th percentile)
- データベースクエリ数: N+1問題の完全排除
- メモリ使用量: 現状維持

### 品質指標
- テストカバレッジ: > 95%
- コード複雑度: < 10 (cyclomatic complexity)
- 保守性指数: > 80

### ビジネス指標
- 検索機能の利用率向上: +30%
- 検索精度の向上: ユーザーフィードバック
- 開発効率: 新しい検索条件追加時間の短縮

---

**更新履歴**
- 2024年: 初版作成
- TODO: 実装進捗に応じて更新予定 