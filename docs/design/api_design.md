# API設計書

**最終更新**: 2025年5月28日  
**バージョン**: 1.0  
**ステータス**: 実装中（v1稼働中、v2計画中）

## 1. 概要

StockRx APIは、在庫管理システムの機能を外部システムやモバイルアプリケーションに提供するRESTful APIです。JSON API仕様に準拠し、高いセキュリティと拡張性を持つ設計となっています。

### 設計原則
- **RESTful**: リソース指向のURL設計
- **JSON API**: 標準化されたレスポンス形式
- **バージョニング**: URLベースのバージョン管理
- **認証・認可**: トークンベースの認証
- **レート制限**: APIの安定性確保
- **HATEOAS**: ハイパーメディア対応

## 2. API仕様

### 2.1 基本情報

```yaml
base_url: https://api.stockrx.com
version: v1
content_type: application/vnd.api+json
authentication: Bearer Token
rate_limit: 1000 requests/hour
```

### 2.2 認証

```ruby
# app/controllers/api/v1/auth_controller.rb
module Api
  module V1
    class AuthController < ApiController
      skip_before_action :authenticate_request!, only: [:login]
      
      # POST /api/v1/auth/login
      def login
        admin = Admin.find_by(email: params[:email])
        
        if admin&.valid_password?(params[:password])
          token = generate_jwt_token(admin)
          
          render json: {
            data: {
              type: 'auth_token',
              attributes: {
                token: token,
                expires_at: 24.hours.from_now
              },
              relationships: {
                admin: {
                  data: { type: 'admin', id: admin.id }
                }
              }
            }
          }
        else
          render_error(401, 'Invalid credentials')
        end
      end
      
      # POST /api/v1/auth/refresh
      def refresh
        new_token = refresh_jwt_token(current_admin)
        
        render json: {
          data: {
            type: 'auth_token',
            attributes: {
              token: new_token,
              expires_at: 24.hours.from_now
            }
          }
        }
      end
      
      # DELETE /api/v1/auth/logout
      def logout
        invalidate_token(current_token)
        head :no_content
      end
      
      private
      
      def generate_jwt_token(admin)
        JWT.encode(
          {
            admin_id: admin.id,
            exp: 24.hours.from_now.to_i,
            iat: Time.current.to_i,
            jti: SecureRandom.uuid
          },
          Rails.application.credentials.secret_key_base,
          'HS256'
        )
      end
    end
  end
end
```

### 2.3 エラーレスポンス

```json
{
  "errors": [
    {
      "status": "422",
      "code": "validation_error",
      "title": "Validation Failed",
      "detail": "価格は0以上で入力してください",
      "source": {
        "pointer": "/data/attributes/price"
      },
      "meta": {
        "field": "price",
        "value": -100
      }
    }
  ],
  "meta": {
    "request_id": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": "2025-05-28T10:30:00Z"
  }
}
```

## 3. エンドポイント設計

### 3.1 在庫管理

#### 在庫一覧取得
```
GET /api/v1/inventories
```

**パラメータ:**
```
?filter[status]=active
&filter[category]=medicine
&filter[low_stock]=true
&sort=-updated_at,name
&page[number]=1
&page[size]=20
&include=batches,latest_logs
```

**レスポンス:**
```json
{
  "data": [
    {
      "id": "1",
      "type": "inventory",
      "attributes": {
        "sku": "MED-001",
        "name": "アスピリン 100mg",
        "description": "解熱鎮痛剤",
        "quantity": 500,
        "unit": "錠",
        "price": 10.5,
        "reorder_point": 100,
        "maximum_stock": 1000,
        "status": "active",
        "created_at": "2025-01-01T00:00:00Z",
        "updated_at": "2025-05-28T10:00:00Z"
      },
      "relationships": {
        "batches": {
          "data": [
            { "type": "batch", "id": "10" },
            { "type": "batch", "id": "11" }
          ]
        },
        "category": {
          "data": { "type": "category", "id": "1" }
        }
      },
      "links": {
        "self": "/api/v1/inventories/1"
      }
    }
  ],
  "included": [
    {
      "id": "10",
      "type": "batch",
      "attributes": {
        "lot_number": "LOT-2024-001",
        "quantity": 200,
        "expiry_date": "2025-12-31",
        "manufactured_date": "2024-01-15"
      }
    }
  ],
  "meta": {
    "total_count": 150,
    "total_pages": 8,
    "current_page": 1,
    "filters_applied": ["status", "category"]
  },
  "links": {
    "self": "/api/v1/inventories?page[number]=1",
    "first": "/api/v1/inventories?page[number]=1",
    "last": "/api/v1/inventories?page[number]=8",
    "next": "/api/v1/inventories?page[number]=2"
  }
}
```

#### 在庫作成
```
POST /api/v1/inventories
```

**リクエスト:**
```json
{
  "data": {
    "type": "inventory",
    "attributes": {
      "sku": "MED-002",
      "name": "イブプロフェン 200mg",
      "description": "消炎鎮痛剤",
      "unit": "錠",
      "price": 15.0,
      "reorder_point": 200,
      "maximum_stock": 2000
    },
    "relationships": {
      "category": {
        "data": { "type": "category", "id": "1" }
      }
    }
  }
}
```

### 3.2 在庫操作

#### 在庫受入
```
POST /api/v1/inventories/:id/receive
```

**リクエスト:**
```json
{
  "data": {
    "type": "stock_receipt",
    "attributes": {
      "quantity": 1000,
      "lot_number": "LOT-2025-001",
      "expiry_date": "2027-12-31",
      "manufactured_date": "2025-01-01",
      "supplier": "医薬品卸A社",
      "invoice_number": "INV-2025-0001",
      "unit_cost": 8.5
    }
  }
}
```

#### 在庫払出
```
POST /api/v1/inventories/:id/ship
```

**リクエスト:**
```json
{
  "data": {
    "type": "stock_shipment",
    "attributes": {
      "quantity": 100,
      "destination": "外来薬局",
      "purpose": "処方",
      "reference_number": "RX-2025-0001"
    }
  }
}
```

### 3.3 レポート

#### 在庫サマリー
```
GET /api/v1/reports/inventory_summary
```

**レスポンス:**
```json
{
  "data": {
    "type": "inventory_summary",
    "attributes": {
      "total_items": 250,
      "total_value": 1500000,
      "low_stock_items": 15,
      "expired_items": 3,
      "expiring_soon_items": 12,
      "categories": [
        {
          "name": "医薬品",
          "item_count": 180,
          "value": 1200000
        },
        {
          "name": "医療機器",
          "item_count": 70,
          "value": 300000
        }
      ],
      "top_moving_items": [
        {
          "sku": "MED-001",
          "name": "アスピリン 100mg",
          "movement_count": 500,
          "turnover_rate": 12.5
        }
      ]
    },
    "meta": {
      "generated_at": "2025-05-28T10:30:00Z",
      "period": {
        "from": "2025-05-01",
        "to": "2025-05-28"
      }
    }
  }
}
```

## 4. API実装

### 4.1 基底コントローラ

```ruby
# app/controllers/api/api_controller.rb
module Api
  class ApiController < ActionController::API
    include ErrorHandlers
    include ApiAuthentication
    include ApiPagination
    include ApiFiltering
    include ApiSorting
    
    before_action :authenticate_request!
    before_action :check_api_version
    before_action :set_locale
    
    # レート制限
    before_action :check_rate_limit
    
    private
    
    def authenticate_request!
      token = extract_token_from_header
      
      begin
        decoded = JWT.decode(
          token,
          Rails.application.credentials.secret_key_base,
          true,
          algorithm: 'HS256'
        )
        
        @current_admin = Admin.find(decoded[0]['admin_id'])
        @current_token = token
      rescue JWT::DecodeError, ActiveRecord::RecordNotFound
        render_error(401, 'Unauthorized')
      end
    end
    
    def extract_token_from_header
      authorization = request.headers['Authorization']
      return nil unless authorization.present?
      
      authorization.split(' ').last
    end
    
    def check_api_version
      requested_version = request.headers['API-Version'] || 'v1'
      
      unless supported_versions.include?(requested_version)
        render_error(400, "Unsupported API version: #{requested_version}")
      end
    end
    
    def supported_versions
      %w[v1 v2]
    end
    
    def check_rate_limit
      # TODO: Rack::Attack統合
      # 簡易実装
      key = "api_rate_limit:#{@current_admin.id}"
      count = Rails.cache.increment(key, 1, expires_in: 1.hour)
      
      if count > rate_limit_threshold
        render_error(429, 'Rate limit exceeded')
      end
    end
    
    def rate_limit_threshold
      1000 # requests per hour
    end
  end
end
```

### 4.2 シリアライザ

```ruby
# app/serializers/inventory_serializer.rb
class InventorySerializer
  include JSONAPI::Serializer
  
  set_type :inventory
  set_id :id
  
  attributes :sku, :name, :description, :quantity, :unit,
             :price, :reorder_point, :maximum_stock, :status,
             :created_at, :updated_at
  
  # 関連
  has_many :batches
  has_many :inventory_logs
  belongs_to :category
  
  # カスタム属性
  attribute :stock_level do |inventory|
    case
    when inventory.quantity <= 0
      'out_of_stock'
    when inventory.quantity <= inventory.reorder_point
      'low_stock'
    when inventory.quantity >= inventory.maximum_stock
      'overstocked'
    else
      'normal'
    end
  end
  
  attribute :total_value do |inventory|
    inventory.quantity * inventory.price
  end
  
  # 条件付き属性
  attribute :sensitive_data, if: Proc.new { |record, params|
    params[:current_admin]&.has_permission?(:view_sensitive_data)
  }
  
  # リンク
  link :self do |inventory|
    "/api/v1/inventories/#{inventory.id}"
  end
  
  # メタ情報
  meta do |inventory|
    {
      last_movement: inventory.inventory_logs.last&.created_at,
      days_until_expiry: inventory.nearest_expiry_days
    }
  end
end
```

### 4.3 フィルタリング・ソート

```ruby
# app/controllers/concerns/api_filtering.rb
module ApiFiltering
  extend ActiveSupport::Concern
  
  def apply_filters(scope)
    return scope unless params[:filter].present?
    
    params[:filter].each do |key, value|
      scope = case key
      when 'status'
        scope.where(status: value)
      when 'category'
        scope.joins(:category).where(categories: { slug: value })
      when 'low_stock'
        value == 'true' ? scope.low_stock : scope
      when 'expiring_soon'
        days = value.to_i > 0 ? value.to_i : 30
        scope.expiring_soon(days)
      when 'search'
        scope.search(value)
      else
        scope
      end
    end
    
    scope
  end
end

# app/controllers/concerns/api_sorting.rb
module ApiSorting
  extend ActiveSupport::Concern
  
  SORTABLE_FIELDS = %w[name sku quantity price updated_at created_at].freeze
  
  def apply_sorting(scope)
    return scope.order(updated_at: :desc) unless params[:sort].present?
    
    sort_fields = params[:sort].split(',')
    
    sort_fields.each do |field|
      direction = field.start_with?('-') ? :desc : :asc
      column = field.delete_prefix('-')
      
      if SORTABLE_FIELDS.include?(column)
        scope = scope.order(column => direction)
      end
    end
    
    scope
  end
end
```

## 5. セキュリティ

### 5.1 認証・認可

```ruby
# app/services/api_authorization_service.rb
class ApiAuthorizationService
  def initialize(admin, resource, action)
    @admin = admin
    @resource = resource
    @action = action
  end
  
  def authorized?
    # スーパー管理者は全権限
    return true if @admin.super_admin?
    
    # リソース別の権限チェック
    case @resource
    when Inventory
      check_inventory_permission
    when Batch
      check_batch_permission
    when Report
      check_report_permission
    else
      false
    end
  end
  
  private
  
  def check_inventory_permission
    case @action
    when :index, :show
      @admin.has_permission?(:view_inventory)
    when :create, :update
      @admin.has_permission?(:manage_inventory)
    when :destroy
      @admin.has_permission?(:delete_inventory)
    when :receive, :ship
      @admin.has_permission?(:move_inventory)
    else
      false
    end
  end
  
  def check_batch_permission
    # バッチは在庫権限に従う
    check_inventory_permission
  end
  
  def check_report_permission
    @admin.has_permission?(:view_reports)
  end
end
```

### 5.2 レート制限

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  # APIレート制限
  throttle('api/ip', limit: 1000, period: 1.hour) do |req|
    req.ip if req.path.start_with?('/api/')
  end
  
  # 認証エンドポイントの制限
  throttle('api/auth', limit: 5, period: 1.minute) do |req|
    req.ip if req.path == '/api/v1/auth/login' && req.post?
  end
  
  # トークン別の制限
  throttle('api/token', limit: 5000, period: 1.hour) do |req|
    if req.path.start_with?('/api/') && req.env['HTTP_AUTHORIZATION']
      # トークンからユーザーIDを抽出
      token = req.env['HTTP_AUTHORIZATION'].split(' ').last
      decoded = JWT.decode(token, Rails.application.credentials.secret_key_base, false)
      decoded[0]['admin_id']
    end
  rescue
    nil
  end
  
  # カスタムレスポンス
  self.throttled_response = lambda do |env|
    [
      429,
      {
        'Content-Type' => 'application/vnd.api+json',
        'Retry-After' => (env['rack.attack.match_data'] || {})[:period]
      },
      [{
        errors: [{
          status: '429',
          code: 'rate_limit_exceeded',
          title: 'Too Many Requests',
          detail: 'Rate limit exceeded. Please try again later.'
        }]
      }.to_json]
    ]
  end
end
```

### 5.3 入力検証

```ruby
# app/validators/api_input_validator.rb
class ApiInputValidator
  include ActiveModel::Model
  
  def self.validate_inventory_params(params)
    validator = new(params)
    validator.validate_inventory
    validator.errors.empty? ? params : validator.errors
  end
  
  def validate_inventory
    # 必須フィールド
    validates_presence_of :sku, :name, :unit
    
    # 数値検証
    validates_numericality_of :price, greater_than_or_equal_to: 0
    validates_numericality_of :quantity, greater_than_or_equal_to: 0, only_integer: true
    
    # 文字列長
    validates_length_of :sku, maximum: 50
    validates_length_of :name, maximum: 255
    
    # フォーマット
    validates_format_of :sku, with: /\A[A-Z0-9\-]+\z/
    
    # カスタム検証
    validate :reorder_point_logic
  end
  
  private
  
  def reorder_point_logic
    return unless reorder_point.present? && maximum_stock.present?
    
    if reorder_point >= maximum_stock
      errors.add(:reorder_point, 'must be less than maximum stock')
    end
  end
end
```

## 6. パフォーマンス最適化

### 6.1 クエリ最適化

```ruby
# app/controllers/api/v1/inventories_controller.rb
module Api
  module V1
    class InventoriesController < ApiController
      def index
        # N+1問題の回避
        inventories = Inventory
          .includes(:batches, :category, latest_logs: :admin)
          .preload(:recent_movements)
        
        # フィルタリング
        inventories = apply_filters(inventories)
        
        # ソート
        inventories = apply_sorting(inventories)
        
        # ページネーション
        inventories = paginate(inventories)
        
        # キャッシュ
        cache_key = [
          'api/v1/inventories',
          inventories.cache_key_with_version,
          params.to_unsafe_h.sort
        ].join('/')
        
        json = Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
          InventorySerializer.new(
            inventories,
            include: included_resources,
            meta: collection_meta(inventories)
          ).serializable_hash.to_json
        end
        
        render json: json
      end
      
      private
      
      def included_resources
        return [] unless params[:include].present?
        
        params[:include].split(',').select do |resource|
          %w[batches category logs].include?(resource)
        end
      end
    end
  end
end
```

### 6.2 レスポンス圧縮

```ruby
# config/application.rb
config.middleware.use Rack::Deflater

# app/controllers/api/api_controller.rb
class ApiController < ActionController::API
  # 大きなレスポンスの圧縮
  after_action :compress_response
  
  private
  
  def compress_response
    return unless response.body.size > 1.kilobyte
    
    request.env['HTTP_ACCEPT_ENCODING'] =~ /gzip/ &&
      response.headers['Content-Encoding'] = 'gzip'
  end
end
```

## 7. API バージョニング

### 7.1 バージョン管理戦略

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    # v1 (現行版)
    namespace :v1 do
      resources :inventories do
        member do
          post :receive
          post :ship
        end
      end
      
      resources :batches, only: [:index, :show]
      resources :reports, only: [:index, :show]
    end
    
    # v2 (開発中)
    namespace :v2 do
      # GraphQL対応
      post '/graphql', to: 'graphql#execute'
      
      # 新機能
      resources :inventories do
        resources :forecasts
        resources :analytics
      end
    end
  end
  
  # デフォルトバージョンへのリダイレクト
  get '/api/inventories', to: redirect('/api/v1/inventories')
end
```

### 7.2 下位互換性

```ruby
# app/serializers/v2/inventory_serializer.rb
module V2
  class InventorySerializer < ::InventorySerializer
    # v1の全機能を継承
    
    # v2の新機能
    attribute :forecast_data do |inventory|
      {
        next_month_demand: inventory.forecast_demand(1.month),
        recommended_order_quantity: inventory.recommended_order_quantity,
        stockout_probability: inventory.stockout_probability
      }
    end
    
    # 非推奨フィールドの警告
    attribute :deprecated_field do |inventory|
      {
        value: inventory.old_field,
        warning: 'This field is deprecated and will be removed in v3'
      }
    end
  end
end
```

## 8. ドキュメント生成

### 8.1 OpenAPI (Swagger) 定義

```yaml
# swagger/v1/swagger.yaml
openapi: 3.0.0
info:
  title: StockRx API
  version: 1.0.0
  description: 在庫管理システムAPI
  contact:
    name: API Support
    email: api@stockrx.com
  
servers:
  - url: https://api.stockrx.com/v1
    description: Production server
  - url: https://staging-api.stockrx.com/v1
    description: Staging server
    
security:
  - bearerAuth: []
  
paths:
  /inventories:
    get:
      summary: List inventories
      tags:
        - Inventories
      parameters:
        - name: filter[status]
          in: query
          schema:
            type: string
            enum: [active, inactive]
        - name: page[number]
          in: query
          schema:
            type: integer
      responses:
        '200':
          description: Successful response
          content:
            application/vnd.api+json:
              schema:
                $ref: '#/components/schemas/InventoriesResponse'
```

### 8.2 APIドキュメント自動生成

```ruby
# spec/swagger_helper.rb
require 'rails_helper'

RSpec.configure do |config|
  config.swagger_root = Rails.root.join('swagger').to_s
  
  config.swagger_docs = {
    'v1/swagger.yaml' => {
      openapi: '3.0.0',
      info: {
        title: 'StockRx API V1',
        version: 'v1'
      },
      paths: {},
      servers: [
        {
          url: 'https://api.stockrx.com',
          variables: {
            defaultHost: {
              default: 'api.stockrx.com'
            }
          }
        }
      ]
    }
  }
end

# spec/requests/api/v1/inventories_spec.rb
require 'swagger_helper'

RSpec.describe 'api/v1/inventories', type: :request do
  path '/api/v1/inventories' do
    get('List inventories') do
      tags 'Inventories'
      produces 'application/vnd.api+json'
      parameter name: 'Authorization', in: :header, type: :string
      
      response(200, 'successful') do
        let(:Authorization) { "Bearer #{generate_token}" }
        
        after do |example|
          example.metadata[:response][:content] = {
            'application/vnd.api+json' => {
              example: JSON.parse(response.body, symbolize_names: true)
            }
          }
        end
        
        run_test!
      end
    end
  end
end
```

## 9. テスト戦略

### 9.1 APIテスト

```ruby
# spec/requests/api/v1/inventories_spec.rb
require 'rails_helper'

RSpec.describe "Api::V1::Inventories", type: :request do
  let(:admin) { create(:admin) }
  let(:token) { generate_jwt_token(admin) }
  let(:headers) {
    {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/vnd.api+json',
      'Accept' => 'application/vnd.api+json'
    }
  }
  
  describe "GET /api/v1/inventories" do
    let!(:inventories) { create_list(:inventory, 25) }
    
    it "returns paginated inventories" do
      get '/api/v1/inventories', headers: headers
      
      expect(response).to have_http_status(:ok)
      
      json = JSON.parse(response.body)
      expect(json['data']).to be_an(Array)
      expect(json['data'].size).to eq(20) # default page size
      expect(json['meta']['total_count']).to eq(25)
      expect(json['links']).to include('next')
    end
    
    it "filters inventories by status" do
      active = create_list(:inventory, 5, status: :active)
      inactive = create_list(:inventory, 3, status: :inactive)
      
      get '/api/v1/inventories', 
          params: { filter: { status: 'active' } },
          headers: headers
      
      json = JSON.parse(response.body)
      expect(json['data'].size).to eq(5)
      expect(json['data'].pluck('id')).to match_array(active.map(&:id).map(&:to_s))
    end
    
    it "includes related resources" do
      inventory = create(:inventory)
      create_list(:batch, 3, inventory: inventory)
      
      get "/api/v1/inventories/#{inventory.id}",
          params: { include: 'batches' },
          headers: headers
      
      json = JSON.parse(response.body)
      expect(json['included']).to be_present
      expect(json['included'].size).to eq(3)
      expect(json['included'].first['type']).to eq('batch')
    end
  end
  
  describe "POST /api/v1/inventories" do
    let(:valid_params) {
      {
        data: {
          type: 'inventory',
          attributes: {
            sku: 'TEST-001',
            name: 'Test Product',
            unit: 'pcs',
            price: 100
          }
        }
      }
    }
    
    it "creates a new inventory" do
      expect {
        post '/api/v1/inventories', 
             params: valid_params.to_json,
             headers: headers
      }.to change(Inventory, :count).by(1)
      
      expect(response).to have_http_status(:created)
      expect(response.headers['Location']).to be_present
    end
    
    it "returns errors for invalid data" do
      invalid_params = valid_params.deep_merge(
        data: { attributes: { price: -100 } }
      )
      
      post '/api/v1/inventories',
           params: invalid_params.to_json,
           headers: headers
      
      expect(response).to have_http_status(:unprocessable_entity)
      
      json = JSON.parse(response.body)
      expect(json['errors']).to be_present
      expect(json['errors'].first['source']['pointer']).to eq('/data/attributes/price')
    end
  end
end
```

### 9.2 統合テスト

```ruby
# spec/integration/api_workflow_spec.rb
require 'rails_helper'

RSpec.describe "API Workflow", type: :request do
  it "completes full inventory lifecycle" do
    admin = create(:admin)
    token = generate_jwt_token(admin)
    headers = api_headers(token)
    
    # 1. 在庫作成
    post '/api/v1/inventories',
         params: inventory_params.to_json,
         headers: headers
    
    expect(response).to have_http_status(:created)
    inventory_id = JSON.parse(response.body)['data']['id']
    
    # 2. 在庫受入
    post "/api/v1/inventories/#{inventory_id}/receive",
         params: receipt_params.to_json,
         headers: headers
    
    expect(response).to have_http_status(:ok)
    
    # 3. 在庫確認
    get "/api/v1/inventories/#{inventory_id}",
        headers: headers
    
    json = JSON.parse(response.body)
    expect(json['data']['attributes']['quantity']).to eq(1000)
    
    # 4. 在庫払出
    post "/api/v1/inventories/#{inventory_id}/ship",
         params: shipment_params.to_json,
         headers: headers
    
    expect(response).to have_http_status(:ok)
    
    # 5. 履歴確認
    get "/api/v1/inventories/#{inventory_id}/history",
        headers: headers
    
    json = JSON.parse(response.body)
    expect(json['data'].size).to eq(3) # created, received, shipped
  end
end
```

## 10. 運用・監視

### 10.1 APIメトリクス

```ruby
# app/middleware/api_metrics_middleware.rb
class ApiMetricsMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    start_time = Time.current
    
    status, headers, response = @app.call(env)
    
    # メトリクス記録
    if env['PATH_INFO'].start_with?('/api/')
      record_metrics(env, status, Time.current - start_time)
    end
    
    [status, headers, response]
  end
  
  private
  
  def record_metrics(env, status, duration)
    Rails.logger.info({
      api_metrics: {
        path: env['PATH_INFO'],
        method: env['REQUEST_METHOD'],
        status: status,
        duration_ms: (duration * 1000).round(2),
        ip: env['REMOTE_ADDR'],
        user_agent: env['HTTP_USER_AGENT'],
        api_version: extract_version(env['PATH_INFO'])
      }
    }.to_json)
    
    # TODO: Prometheus/DataDog等への送信
  end
  
  def extract_version(path)
    match = path.match(/\/api\/(v\d+)\//)
    match ? match[1] : 'unknown'
  end
end
```

### 10.2 APIヘルスチェック

```ruby
# app/controllers/api/health_controller.rb
module Api
  class HealthController < ApplicationController
    skip_before_action :authenticate_request!
    
    def show
      checks = {
        database: check_database,
        redis: check_redis,
        sidekiq: check_sidekiq
      }
      
      status = checks.values.all? ? :ok : :service_unavailable
      
      render json: {
        status: status,
        timestamp: Time.current.iso8601,
        checks: checks,
        version: {
          api: 'v1',
          app: Rails.application.config.version
        }
      }, status: status
    end
    
    private
    
    def check_database
      ActiveRecord::Base.connection.active?
      { status: 'healthy', response_time_ms: measure_time { Inventory.first } }
    rescue => e
      { status: 'unhealthy', error: e.message }
    end
    
    def check_redis
      Redis.current.ping == 'PONG'
      { status: 'healthy', response_time_ms: measure_time { Redis.current.ping } }
    rescue => e
      { status: 'unhealthy', error: e.message }
    end
    
    def check_sidekiq
      Sidekiq::ProcessSet.new.size > 0
      { status: 'healthy', workers: Sidekiq::ProcessSet.new.size }
    rescue => e
      { status: 'unhealthy', error: e.message }
    end
    
    def measure_time
      start = Time.current
      yield
      ((Time.current - start) * 1000).round(2)
    end
  end
end
```

## 11. ベストプラクティス

### 11.1 API設計原則

1. **一貫性**: 全エンドポイントで統一されたパターン
2. **予測可能性**: RESTfulな命名規則
3. **拡張性**: バージョニングによる後方互換性
4. **性能**: 適切なキャッシュとページネーション
5. **セキュリティ**: 認証・認可・レート制限

### 11.2 実装チェックリスト

- [ ] エンドポイントはRESTfulか
- [ ] レスポンスはJSON API仕様準拠か
- [ ] 適切なHTTPステータスコードを返すか
- [ ] エラーレスポンスは統一されているか
- [ ] 認証・認可は実装されているか
- [ ] レート制限は設定されているか
- [ ] N+1問題は解決されているか
- [ ] キャッシュは適切に実装されているか
- [ ] ドキュメントは更新されているか
- [ ] テストは網羅的か

## 12. 今後の拡張計画

### v2 計画（実装中）
- [ ] GraphQL対応
- [ ] WebSocket対応（リアルタイム更新）
- [ ] バッチ操作API
- [ ] 高度な検索・フィルタリング
- [ ] 予測分析API

### v3 構想（将来）
- [ ] gRPC対応
- [ ] マイクロサービス化
- [ ] イベントドリブンAPI
- [ ] AI/ML統合
- [ ] ブロックチェーン統合

## 13. 参考資料

- [JSON:API Specification](https://jsonapi.org/)
- [RESTful API Design Best Practices](https://www.vinaysahni.com/best-practices-for-a-pragmatic-restful-api)
- [API Security Checklist](https://github.com/shieldfy/API-Security-Checklist)
- [Rails API Documentation](https://api.rubyonrails.org/)