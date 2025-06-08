# Struct実装設計書：SearchResult & ApiResponse

**最終更新**: 2025年1月27日  
**バージョン**: 1.0  
**ステータス**: 設計完了・実装準備中

## 概要

### 目的
StockRxシステムにおいて、検索機能とAPI応答の型安全性・保守性・拡張性を向上させるため、RubyのStructを活用した構造化オブジェクトを導入する。

### 対象範囲
1. **SearchResult**: 検索結果の構造化と型安全性向上
2. **ApiResponse**: API応答の統一化とエラーハンドリング改善

### 設計原則
- **型安全性**: コンパイル時エラー検出の向上
- **可読性**: 明確な属性アクセスとメソッド定義
- **拡張性**: 将来的な機能追加への対応
- **パフォーマンス**: 軽量オブジェクトによる効率性確保
- **セキュリティ**: データ漏洩防止と入力検証強化

## 現状分析（ビフォー）

### 1. SearchQueryBuilder の課題

**問題点:**
```ruby
# 現在の実装（app/services/search_query_builder.rb）
def results
  apply_distinct if @distinct_applied || joins_applied.any?
  @scope
end

def count
  apply_distinct if @distinct_applied || joins_applied.any?
  @scope.count
end

def conditions_summary
  @conditions.empty? ? "すべて" : @conditions.join(", ")
end
```

**課題:**
- 戻り値の型が不統一（ActiveRecord::Relation、Integer、String）
- メタデータ（検索条件、実行時間、ページネーション情報）の散在
- 検索結果の追加属性計算が各コントローラーで重複
- テスト時の期待値検証が困難

### 2. API応答の課題

**問題点:**
```ruby
# 現在の実装（各コントローラー）
def index
  # ... 検索処理 ...
  render json: {
    success: true,
    data: inventories,
    message: "検索が完了しました",
    total: total_count
  }
rescue => e
  render json: {
    success: false,
    error: e.message
  }, status: 422
end
```

**課題:**
- API応答形式の非統一
- エラーハンドリングの重複
- レスポンスメタデータの不足
- セキュリティヘッダーの不統一

## 設計解決策（アフター）

### 1. SearchResult Struct の設計

#### 基本構造
```ruby
# app/lib/search_result.rb
SearchResult = Struct.new(
  :records,           # ActiveRecord::Relation | Array
  :total_count,       # Integer
  :current_page,      # Integer  
  :per_page,          # Integer
  :conditions_summary,# String
  :query_metadata,    # Hash
  :execution_time,    # Float (seconds)
  :search_params,     # Hash (original parameters)
  keyword_init: true
) do
  # ============================================
  # ページネーション関連メソッド
  # ============================================
  
  def total_pages
    return 0 if total_count <= 0 || per_page <= 0
    (total_count.to_f / per_page).ceil
  end

  def has_next_page?
    current_page < total_pages
  end

  def has_prev_page?
    current_page > 1
  end

  def next_page
    has_next_page? ? current_page + 1 : nil
  end

  def prev_page
    has_prev_page? ? current_page - 1 : nil
  end

  # ============================================
  # メタデータ関連メソッド
  # ============================================
  
  def pagination_info
    {
      current_page: current_page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: has_next_page?,
      has_prev: has_prev_page?
    }
  end

  def search_metadata
    {
      conditions: conditions_summary,
      execution_time: execution_time,
      query_complexity: query_metadata[:joins_count] || 0,
      **query_metadata
    }
  end

  # ============================================
  # セキュリティ関連メソッド
  # ============================================
  
  def sanitized_records
    # 機密情報を除外したレコードを返す
    case records
    when ActiveRecord::Relation
      records.select(safe_attributes)
    when Array
      records.map { |record| sanitize_record(record) }
    else
      records
    end
  end

  # ============================================
  # API出力用メソッド
  # ============================================
  
  def to_api_hash
    {
      data: sanitized_records,
      pagination: pagination_info,
      metadata: search_metadata,
      timestamp: Time.current.iso8601
    }
  end

  def to_json(*args)
    to_api_hash.to_json(*args)
  end

  # ============================================
  # デバッグ・開発支援メソッド
  # ============================================
  
  def debug_info
    return {} unless Rails.env.development?
    
    {
      sql_query: records.respond_to?(:to_sql) ? records.to_sql : nil,
      search_params: search_params,
      performance: {
        execution_time: execution_time,
        record_count: total_count,
        query_complexity: query_metadata[:joins_count] || 0
      }
    }
  end

  private

  def safe_attributes
    # モデルに応じて安全な属性のみを選択
    %w[id name status price quantity created_at updated_at]
  end

  def sanitize_record(record)
    # レコードから機密情報を除外
    case record
    when Hash
      record.slice(*safe_attributes)
    when ActiveRecord::Base
      record.attributes.slice(*safe_attributes)
    else
      record
    end
  end
end
```

#### 使用例
```ruby
# SearchQueryBuilder での使用
class SearchQueryBuilder
  def execute
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    
    paginated_scope = @scope.page(current_page).per(per_page)
    total = @scope.count
    
    execution_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    
    SearchResult.new(
      records: paginated_scope,
      total_count: total,
      current_page: current_page,
      per_page: per_page,
      conditions_summary: conditions_summary,
      query_metadata: {
        joins_count: @joins_applied.size,
        distinct_applied: @distinct_applied,
        conditions_count: @conditions.size
      },
      execution_time: execution_time,
      search_params: original_params
    )
  end
end
```

### 2. ApiResponse Struct の設計

#### 基本構造
```ruby
# app/lib/api_response.rb
ApiResponse = Struct.new(
  :success,      # Boolean
  :data,         # Any (主要データ)
  :message,      # String (ユーザー向けメッセージ)
  :errors,       # Array<String> (エラー詳細)
  :metadata,     # Hash (追加情報)
  :status_code,  # Integer (HTTPステータスコード)
  keyword_init: true
) do
  # ============================================
  # ファクトリーメソッド
  # ============================================
  
  def self.success(data = nil, message = nil, metadata = {})
    new(
      success: true,
      data: data,
      message: message || default_success_message(data),
      errors: [],
      metadata: base_metadata.merge(metadata),
      status_code: 200
    )
  end

  def self.created(data = nil, message = nil, metadata = {})
    new(
      success: true,
      data: data,
      message: message || "リソースが正常に作成されました",
      errors: [],
      metadata: base_metadata.merge(metadata),
      status_code: 201
    )
  end

  def self.error(message, errors = [], status_code = 422, metadata = {})
    new(
      success: false,
      data: nil,
      message: message,
      errors: normalize_errors(errors),
      metadata: base_metadata.merge(metadata),
      status_code: status_code
    )
  end

  def self.validation_error(errors, message = "入力データに問題があります")
    error(message, errors, 422, { type: "validation_error" })
  end

  def self.not_found(resource = "リソース", message = nil)
    message ||= "#{resource}が見つかりません"
    error(message, [], 404, { type: "not_found" })
  end

  def self.forbidden(message = "この操作を行う権限がありません")
    error(message, [], 403, { type: "forbidden" })
  end

  def self.internal_error(message = "内部エラーが発生しました")
    error(message, [], 500, { type: "internal_error" })
  end

  # ============================================
  # インスタンスメソッド
  # ============================================
  
  def successful?
    success == true
  end

  def failed?
    !successful?
  end

  def has_errors?
    errors.any?
  end

  def client_error?
    status_code >= 400 && status_code < 500
  end

  def server_error?
    status_code >= 500
  end

  # ============================================
  # 出力関連メソッド
  # ============================================
  
  def to_h
    {
      success: success,
      data: data,
      message: message,
      errors: errors,
      metadata: metadata
    }
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  def headers
    base_headers = {
      'Content-Type' => 'application/json; charset=utf-8',
      'X-Response-Time' => metadata[:response_time]&.to_s,
      'X-Request-ID' => metadata[:request_id]
    }

    # セキュリティヘッダーの追加
    security_headers = {
      'X-Content-Type-Options' => 'nosniff',
      'X-Frame-Options' => 'DENY',
      'X-XSS-Protection' => '1; mode=block'
    }

    base_headers.merge(security_headers).compact
  end

  # ============================================
  # Rails統合メソッド
  # ============================================
  
  def render_options
    {
      json: to_h,
      status: status_code,
      headers: headers
    }
  end

  # ============================================
  # デバッグ・ログ出力用メソッド
  # ============================================
  
  def log_summary
    {
      success: success,
      status_code: status_code,
      message: message,
      error_count: errors.size,
      data_type: data.class.name,
      request_id: metadata[:request_id]
    }
  end

  private

  def self.base_metadata
    {
      timestamp: Time.current.iso8601,
      request_id: Thread.current[:request_id] || SecureRandom.uuid,
      version: "v1"
    }
  end

  def self.normalize_errors(errors)
    case errors
    when String
      [errors]
    when Hash
      errors.flat_map { |key, messages| Array(messages).map { |msg| "#{key}: #{msg}" } }
    when ActiveModel::Errors
      errors.full_messages
    when Array
      errors.flatten.map(&:to_s)
    else
      [errors.to_s]
    end
  end

  def self.default_success_message(data)
    case data
    when ActiveRecord::Relation, Array
      "データを#{data.respond_to?(:count) ? data.count : data.size}件取得しました"
    when ActiveRecord::Base
      "データを取得しました"
    else
      "処理が正常に完了しました"
    end
  end
end
```

#### 使用例
```ruby
# コントローラーでの使用
class AdminControllers::InventoriesController < AdminControllers::BaseController
  def index
    search_result = SearchQueryBuilder
      .build(Inventory.includes(:batches))
      .filter_by_name(params[:name])
      .filter_by_status(params[:status])
      .execute

    response = ApiResponse.success(
      search_result.to_api_hash,
      "在庫データを検索しました",
      {
        search_conditions: search_result.conditions_summary,
        execution_time: search_result.execution_time
      }
    )

    render response.render_options
  end

  def create
    inventory = Inventory.new(inventory_params)
    
    if inventory.save
      response = ApiResponse.created(
        inventory,
        "在庫が正常に作成されました"
      )
      render response.render_options
    else
      response = ApiResponse.validation_error(inventory.errors)
      render response.render_options
    end
  rescue => e
    Rails.logger.error "Inventory creation failed: #{e.message}"
    response = ApiResponse.internal_error
    render response.render_options
  end
end
```

## セキュリティ考慮事項

### 1. データ漏洩防止
```ruby
# SearchResult でのセキュリティ対策
def sanitized_records
  # 管理者のみアクセス可能な属性の除外
  admin_only_attributes = %w[cost internal_notes supplier_info]
  
  case records
  when ActiveRecord::Relation
    if Current.admin&.super_admin?
      records
    else
      records.select(safe_attributes)
    end
  end
end
```

### 2. ログ出力時の機密情報保護
```ruby
# ApiResponse でのログ保護
def log_summary
  log_data = {
    success: success,
    status_code: status_code,
    message: message,
    error_count: errors.size
  }
  
  # 本番環境では機密データを除外
  unless Rails.env.production?
    log_data[:data_preview] = data.is_a?(Hash) ? data.keys : data.class.name
  end
  
  log_data
end
```

### 3. CSRFトークン統合
```ruby
# ApiResponse でのCSRF対策
def headers
  base_headers = super
  
  # CSRF トークンの追加（必要に応じて）
  if Rails.application.config.force_ssl
    base_headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
  end
  
  base_headers
end
```

## パフォーマンス最適化

### 1. メモリ効率
```ruby
# 大量データ処理時の最適化
SearchResult = Struct.new(...) do
  def records
    # レイジーローディングの実装
    @_records ||= super
  end

  def total_count
    # キャッシュによる計算量削減
    @_total_count ||= super
  end
end
```

### 2. JSON シリアライゼーション最適化
```ruby
# ApiResponse での高速JSON生成
def to_json(*args)
  # Oj gem を使用した高速JSON生成（利用可能な場合）
  if defined?(Oj)
    Oj.dump(to_h, mode: :compat)
  else
    to_h.to_json(*args)
  end
end
```

## テスト戦略

### 1. SearchResult のテスト
```ruby
# spec/lib/search_result_spec.rb
RSpec.describe SearchResult do
  let(:records) { create_list(:inventory, 25) }
  let(:search_result) do
    SearchResult.new(
      records: records.limit(10),
      total_count: 25,
      current_page: 1,
      per_page: 10,
      conditions_summary: "テスト条件",
      query_metadata: { joins_count: 2 },
      execution_time: 0.125
    )
  end

  describe "pagination methods" do
    it "calculates total pages correctly" do
      expect(search_result.total_pages).to eq(3)
    end

    it "detects next page availability" do
      expect(search_result.has_next_page?).to be true
    end
  end

  describe "API output" do
    it "generates proper API hash" do
      api_hash = search_result.to_api_hash
      expect(api_hash).to include(:data, :pagination, :metadata)
      expect(api_hash[:pagination][:total_pages]).to eq(3)
    end
  end
end
```

### 2. ApiResponse のテスト
```ruby
# spec/lib/api_response_spec.rb
RSpec.describe ApiResponse do
  describe ".success" do
    it "creates successful response" do
      response = ApiResponse.success("test data", "Success message")
      
      expect(response.successful?).to be true
      expect(response.data).to eq("test data")
      expect(response.message).to eq("Success message")
      expect(response.status_code).to eq(200)
    end
  end

  describe ".error" do
    it "creates error response" do
      response = ApiResponse.error("Error message", ["error1", "error2"])
      
      expect(response.failed?).to be true
      expect(response.errors).to eq(["error1", "error2"])
      expect(response.status_code).to eq(422)
    end
  end

  describe "Rails integration" do
    it "provides proper render options" do
      response = ApiResponse.success("data")
      options = response.render_options
      
      expect(options).to include(:json, :status, :headers)
      expect(options[:status]).to eq(200)
    end
  end
end
```

## 実装計画

### フェーズ 1: 基本構造の実装（1-2日）
1. `SearchResult` Structの基本実装
2. `ApiResponse` Structの基本実装
3. 基本的なテスト作成

### フェーズ 2: 既存システムとの統合（2-3日）
1. `SearchQueryBuilder`の`SearchResult`対応
2. 主要コントローラーの`ApiResponse`対応
3. 統合テストの実装

### フェーズ 3: 最適化と拡張（2-3日）
1. パフォーマンス最適化
2. セキュリティ強化
3. ドキュメント更新

### フェーズ 4: 横展開（継続）
1. 他の検索機能への適用
2. API v2での全面採用
3. 監視・メトリクス統合

## ベストプラクティス

### 1. 命名規則
- Structの名前は明確で直感的に
- メソッド名は動詞または述語形式
- プライベートメソッドの適切な使用

### 2. エラーハンドリング
- 例外発生時の適切なフォールバック
- ログ出力の標準化
- デバッグ情報の条件付き出力

### 3. 拡張性の確保
- 新しい属性の追加を考慮した設計
- バージョニングの仕組み
- 下位互換性の維持

## 今後の拡張計画

### 短期（1-3ヶ月）
- GraphQL対応
- キャッシュ機能統合
- メトリクス収集

### 中期（3-6ヶ月）
- マイクロサービス対応
- 非同期処理統合
- 国際化対応

### 長期（6ヶ月以上）
- Machine Learning統合
- リアルタイム更新
- 高度な分析機能

## 結論

SearchResultとApiResponseのStruct実装により、StockRxシステムの検索機能とAPI応答の**型安全性**、**保守性**、**拡張性**が大幅に向上します。段階的な実装により、既存システムへの影響を最小限に抑えながら、将来的な機能拡張に対応できる柔軟な基盤を構築できます。 