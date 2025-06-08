# Type Safety Enhancement Design Document

## Overview

This document outlines the implementation of improved type safety for the StockRx Rails application, focusing on three key areas:
1. **FormField** - Type-safe form field definitions with validation
2. **SearchResult** - Type-safe search functionality and result handling  
3. **ApiResponse** - Unified API response structure with error handling

## Architecture Goals

### Core Principles
- **Type Safety**: Strict typing to prevent runtime errors
- **Developer Experience**: Clear APIs with auto-completion support
- **Backward Compatibility**: Smooth migration from existing patterns
- **Performance**: Minimal overhead while adding safety
- **Maintainability**: Clear separation of concerns and testable components

### Design Philosophy
Following Google L8-level engineering principles:
- **Fail Fast**: Early detection of type mismatches
- **Explicit Over Implicit**: Clear type definitions over magic
- **Composability**: Reusable components across the application
- **Observability**: Built-in logging and monitoring capabilities

## 1. FormField Type Safety Enhancement

### Current State Analysis
The existing form system uses `ActiveModel::Attributes` with basic type coercion:
```ruby
# Current approach in BaseSearchForm
class BaseSearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  attribute :name, :string
  attribute :status, :string
  attribute :min_price, :decimal
  # Basic validation without type constraints
end
```

### Target Architecture

#### 1.1 FormField Value Objects
Create strongly-typed value objects for form fields:

```ruby
# app/lib/form_fields/base_field.rb
module FormFields
  class BaseField
    include ActiveModel::Model
    include ActiveModel::Validations
    include ActiveModel::Serialization
    
    attr_reader :value, :name, :type, :options
    
    def initialize(name:, value: nil, **options)
      @name = name.to_s
      @value = value
      @type = self.class.field_type
      @options = options.freeze
      validate_type_constraints!
    end
    
    def self.field_type
      raise NotImplementedError, "Subclasses must define field_type"
    end
    
    def serializable_hash
      {
        name: name,
        value: formatted_value,
        type: type,
        valid: valid?,
        errors: errors.full_messages
      }
    end
    
    private
    
    def validate_type_constraints!
      return if value.nil?
      raise TypeError, type_error_message unless value_valid_for_type?
    end
    
    def value_valid_for_type?
      raise NotImplementedError, "Subclasses must implement value_valid_for_type?"
    end
    
    def type_error_message
      "Invalid value '#{value}' for field '#{name}' of type #{type}"
    end
  end
end
```

#### 1.2 Specific Field Types

```ruby
# app/lib/form_fields/string_field.rb
module FormFields
  class StringField < BaseField
    validates :value, length: { maximum: 255 }, allow_blank: true
    
    def self.field_type
      :string
    end
    
    def formatted_value
      value&.to_s&.strip
    end
    
    private
    
    def value_valid_for_type?
      value.is_a?(String) || value.respond_to?(:to_s)
    end
  end
end

# app/lib/form_fields/decimal_field.rb
module FormFields
  class DecimalField < BaseField
    validates :value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
    
    def self.field_type
      :decimal
    end
    
    def formatted_value
      value&.to_d
    end
    
    private
    
    def value_valid_for_type?
      value.is_a?(Numeric) || 
      (value.is_a?(String) && value.match?(/\A\d*\.?\d+\z/))
    end
  end
end

# app/lib/form_fields/enum_field.rb
module FormFields
  class EnumField < BaseField
    validates :value, inclusion: { in: :allowed_values }, allow_nil: true
    
    def self.field_type
      :enum
    end
    
    def initialize(name:, value: nil, allowed_values:, **options)
      @allowed_values = Array(allowed_values).map(&:to_s).freeze
      super(name: name, value: value, **options)
    end
    
    def formatted_value
      value&.to_s
    end
    
    private
    
    attr_reader :allowed_values
    
    def value_valid_for_type?
      value.nil? || allowed_values.include?(value.to_s)
    end
  end
end

# app/lib/form_fields/date_range_field.rb
module FormFields
  class DateRangeField < BaseField
    validates :start_date, :end_date, 
              presence: { if: :range_specified? },
              comparison: { less_than_or_equal_to: :end_date, 
                          if: :both_dates_present? }
    
    def self.field_type
      :date_range
    end
    
    def initialize(name:, start_date: nil, end_date: nil, **options)
      @start_date = parse_date(start_date)
      @end_date = parse_date(end_date)
      super(name: name, value: { start_date: @start_date, end_date: @end_date }, **options)
    end
    
    def formatted_value
      {
        start_date: @start_date&.iso8601,
        end_date: @end_date&.iso8601,
        formatted_range: formatted_range
      }
    end
    
    private
    
    attr_reader :start_date, :end_date
    
    def value_valid_for_type?
      (start_date.nil? || start_date.is_a?(Date)) &&
      (end_date.nil? || end_date.is_a?(Date))
    end
    
    def range_specified?
      start_date.present? || end_date.present?
    end
    
    def both_dates_present?
      start_date.present? && end_date.present?
    end
    
    def formatted_range
      return nil unless range_specified?
      
      if both_dates_present?
        "#{start_date.strftime('%Y-%m-%d')} - #{end_date.strftime('%Y-%m-%d')}"
      elsif start_date.present?
        "#{start_date.strftime('%Y-%m-%d')} -"
      else
        "- #{end_date.strftime('%Y-%m-%d')}"
      end
    end
    
    def parse_date(date_input)
      return nil if date_input.blank?
      return date_input if date_input.is_a?(Date)
      
      Date.parse(date_input.to_s)
    rescue ArgumentError
      raise TypeError, "Invalid date format: #{date_input}"
    end
  end
end
```

#### 1.3 Enhanced Form Base Class

```ruby
# app/forms/type_safe_form.rb
class TypeSafeForm
  include ActiveModel::Model
  include ActiveModel::Validations
  include ActiveModel::Serialization
  
  class_attribute :field_definitions, default: {}
  
  def self.field(name, type, **options)
    field_definitions[name] = { type: type, options: options }
    
    define_method(name) do
      field_value = instance_variable_get("@#{name}")
      return field_value if field_value.is_a?(FormFields::BaseField)
      
      field_class = field_class_for_type(type)
      field_value = field_class.new(
        name: name,
        value: field_value,
        **field_definitions[name][:options]
      )
      instance_variable_set("@#{name}", field_value)
      field_value
    end
    
    define_method("#{name}=") do |value|
      instance_variable_set("@#{name}", value)
    end
    
    define_method("#{name}_value") do
      public_send(name).value
    end
  end
  
  def initialize(params = {})
    assign_attributes(params)
  end
  
  def assign_attributes(params)
    params.each do |key, value|
      public_send("#{key}=", value) if respond_to?("#{key}=")
    end
  end
  
  def serializable_hash
    field_definitions.keys.each_with_object({}) do |field_name, hash|
      field = public_send(field_name)
      hash[field_name] = field.serializable_hash
    end
  end
  
  def valid?
    super && all_fields_valid?
  end
  
  private
  
  def field_class_for_type(type)
    case type
    when :string then FormFields::StringField
    when :decimal then FormFields::DecimalField
    when :enum then FormFields::EnumField
    when :date_range then FormFields::DateRangeField
    else
      raise ArgumentError, "Unknown field type: #{type}"
    end
  end
  
  def all_fields_valid?
    field_definitions.keys.all? do |field_name|
      field = public_send(field_name)
      field.valid?.tap do |valid|
        field.errors.full_messages.each do |error|
          errors.add(field_name, error)
        end unless valid
      end
    end
  end
end
```

#### 1.4 Enhanced InventorySearchForm

```ruby
# app/forms/inventory_search_form.rb
class InventorySearchForm < TypeSafeForm
  # Basic search fields
  field :name, :string
  field :status, :enum, allowed_values: Inventory::STATUSES
  field :min_price, :decimal
  field :max_price, :decimal
  
  # Advanced search fields  
  field :created_date_range, :date_range
  field :updated_date_range, :date_range
  field :expiry_date_range, :date_range
  
  # Pagination and sorting
  field :page, :decimal, default: 1
  field :per_page, :decimal, default: 25
  field :sort_field, :enum, allowed_values: %w[name status price created_at updated_at]
  field :sort_direction, :enum, allowed_values: %w[asc desc]
  
  validates :min_price, :max_price, numericality: { greater_than_or_equal_to: 0 }
  validate :price_range_consistency
  validate :pagination_bounds
  
  def search_type
    return :advanced if advanced_search?
    return :basic if basic_search?
    :empty
  end
  
  def to_query_params
    serializable_hash.transform_values { |field_data| field_data[:value] }
                    .compact
  end
  
  private
  
  def price_range_consistency
    return unless min_price_value.present? && max_price_value.present?
    
    if min_price_value > max_price_value
      errors.add(:max_price, I18n.t('errors.price_range.max_less_than_min'))
    end
  end
  
  def pagination_bounds
    errors.add(:page, 'must be positive') if page_value.present? && page_value < 1
    errors.add(:per_page, 'must be between 1 and 100') if per_page_value.present? && !per_page_value.between?(1, 100)
  end
  
  def advanced_search?
    [created_date_range, updated_date_range, expiry_date_range].any? { |field| field.value.present? }
  end
  
  def basic_search?
    [name, status, min_price, max_price].any? { |field| field.value.present? }
  end
end
```

## 2. SearchResult Type Safety Enhancement

### Current State Analysis
Search results are currently handled through service classes with basic result objects:
```ruby
# Current approach in SearchQueryBuilder
class SearchQueryBuilder
  def call
    # Returns ActiveRecord::Relation directly
    query = base_query
    apply_conditions(query)
    query.distinct
  end
end
```

### Target Architecture

#### 2.1 SearchResult Value Object

```ruby
# app/lib/search_results/search_result.rb
module SearchResults
  class SearchResult
    include ActiveModel::Model
    include ActiveModel::Serialization
    
    attr_reader :records, :metadata, :form, :query_info
    
    def initialize(records:, form:, query_info: {})
      @records = records
      @form = form
      @query_info = query_info.freeze
      @metadata = build_metadata
      
      validate_result_consistency!
    end
    
    def serializable_hash
      {
        records: records.map(&:serializable_hash),
        metadata: metadata,
        form: form.serializable_hash,
        query_info: query_info
      }
    end
    
    def success?
      form.valid? && query_info[:errors].blank?
    end
    
    def total_count
      metadata[:total_count]
    end
    
    def total_pages
      metadata[:total_pages]
    end
    
    def current_page
      metadata[:current_page]
    end
    
    def has_next_page?
      current_page < total_pages
    end
    
    def has_previous_page?
      current_page > 1
    end
    
    # Enumerable interface for compatibility
    delegate :each, :map, :select, :reject, :size, :length, :count, 
             :empty?, :present?, :first, :last, to: :records
    
    private
    
    def build_metadata
      if records.respond_to?(:total_count)
        # Kaminari pagination
        {
          total_count: records.total_count,
          current_page: records.current_page,
          total_pages: records.total_pages,
          per_page: records.limit_value,
          offset: records.offset_value,
          search_type: form.search_type,
          execution_time_ms: query_info[:execution_time_ms],
          cache_hit: query_info[:cache_hit] || false
        }
      else
        # Regular array or relation
        {
          total_count: records.size,
          current_page: 1,
          total_pages: 1,
          per_page: records.size,
          offset: 0,
          search_type: form.search_type,
          execution_time_ms: query_info[:execution_time_ms],
          cache_hit: query_info[:cache_hit] || false
        }
      end
    end
    
    def validate_result_consistency!
      unless records.respond_to?(:each)
        raise TypeError, "Records must be enumerable, got #{records.class}"
      end
      
      unless form.respond_to?(:valid?)
        raise TypeError, "Form must respond to valid?, got #{form.class}"
      end
    end
  end
end
```

#### 2.2 Search Service Enhancement

```ruby
# app/services/type_safe_search_service.rb
class TypeSafeSearchService
  include ActiveModel::Model
  
  attr_reader :form_class, :base_relation
  
  def initialize(form_class:, base_relation:)
    @form_class = form_class
    @base_relation = base_relation
  end
  
  def call(params = {})
    form = form_class.new(params)
    
    execution_start = Time.current
    
    if form.valid?
      records = execute_search(form)
      query_info = {
        execution_time_ms: ((Time.current - execution_start) * 1000).round(2),
        sql_queries: query_counter.count,
        cache_hit: cache_hit_for_form?(form)
      }
    else
      records = base_relation.none
      query_info = {
        execution_time_ms: 0,
        errors: form.errors.full_messages
      }
    end
    
    SearchResults::SearchResult.new(
      records: records,
      form: form,
      query_info: query_info
    )
  end
  
  private
  
  def execute_search(form)
    case form.search_type
    when :basic
      basic_search(form)
    when :advanced
      advanced_search(form)
    when :empty
      base_relation.page(form.page_value).per(form.per_page_value)
    else
      raise ArgumentError, "Unknown search type: #{form.search_type}"
    end
  end
  
  def basic_search(form)
    query = base_relation
    
    query = query.where('name ILIKE ?', "%#{form.name_value}%") if form.name_value.present?
    query = query.where(status: form.status_value) if form.status_value.present?
    
    if form.min_price_value.present? || form.max_price_value.present?
      query = apply_price_range(query, form.min_price_value, form.max_price_value)
    end
    
    apply_sorting_and_pagination(query, form)
  end
  
  def advanced_search(form)
    # Start with basic search
    query = basic_search(form)
    
    # Apply date range filters
    if form.created_date_range.value.present?
      query = apply_date_range(query, :created_at, form.created_date_range)
    end
    
    if form.updated_date_range.value.present?
      query = apply_date_range(query, :updated_at, form.updated_date_range)
    end
    
    if form.expiry_date_range.value.present?
      query = query.joins(:batches)
      query = apply_date_range(query, 'batches.expiry_date', form.expiry_date_range)
    end
    
    query.distinct
  end
  
  def apply_price_range(query, min_price, max_price)
    if min_price.present? && max_price.present?
      query.where(price: min_price..max_price)
    elsif min_price.present?
      query.where('price >= ?', min_price)
    elsif max_price.present?
      query.where('price <= ?', max_price)
    else
      query
    end
  end
  
  def apply_date_range(query, field, date_range_field)
    range_value = date_range_field.value
    start_date = range_value[:start_date]
    end_date = range_value[:end_date]
    
    if start_date.present? && end_date.present?
      query.where(field => start_date..end_date)
    elsif start_date.present?
      query.where("#{field} >= ?", start_date)
    elsif end_date.present?
      query.where("#{field} <= ?", end_date)
    else
      query
    end
  end
  
  def apply_sorting_and_pagination(query, form)
    if form.sort_field_value.present?
      direction = form.sort_direction_value || 'asc'
      query = query.order("#{form.sort_field_value} #{direction}")
    end
    
    query.page(form.page_value || 1).per(form.per_page_value || 25)
  end
  
  def query_counter
    @query_counter ||= ActiveRecord::QueryCounter.new
  end
  
  def cache_hit_for_form?(form)
    # Implement cache checking logic
    false
  end
end
```

#### 2.3 Controller Integration

```ruby
# app/controllers/inventories_controller.rb
class InventoriesController < ApplicationController
  def index
    search_service = TypeSafeSearchService.new(
      form_class: InventorySearchForm,
      base_relation: Inventory.includes(:batches)
    )
    
    @search_result = search_service.call(search_params)
    @inventories = @search_result.records
    @form = @search_result.form
    
    respond_to do |format|
      format.html
      format.json { render json: @search_result.serializable_hash }
      format.turbo_stream { render 'inventories/search_results' }
    end
  end
  
  private
  
  def search_params
    params.permit(:name, :status, :min_price, :max_price, :page, :per_page,
                  :sort_field, :sort_direction,
                  created_date_range: [:start_date, :end_date],
                  updated_date_range: [:start_date, :end_date],
                  expiry_date_range: [:start_date, :end_date])
  end
end
```

## 3. ApiResponse Type Safety Enhancement

### Current State Analysis
API responses currently use individual controller logic with JBuilder templates:
```ruby
# Current approach in Api::V1::InventoriesController
def show
  @inventory = Inventory.find(params[:id]).decorate
  render :show # Uses JBuilder template
rescue ActiveRecord::RecordNotFound
  render json: { error: 'Not found' }, status: :not_found
end
```

### Target Architecture

#### 3.1 ApiResponse Value Object

```ruby
# app/lib/api_responses/base_response.rb
module ApiResponses
  class BaseResponse
    include ActiveModel::Model
    include ActiveModel::Serialization
    
    attr_reader :data, :status, :headers, :metadata, :errors
    
    def initialize(data: nil, status: :ok, headers: {}, metadata: {}, errors: [])
      @data = data
      @status = normalize_status(status)
      @headers = default_headers.merge(headers)
      @metadata = default_metadata.merge(metadata)
      @errors = Array(errors)
      
      validate_response_structure!
    end
    
    def success?
      @status >= 200 && @status < 300
    end
    
    def client_error?
      @status >= 400 && @status < 500
    end
    
    def server_error?
      @status >= 500
    end
    
    def serializable_hash
      {
        data: serialize_data,
        success: success?,
        status: status,
        metadata: metadata,
        errors: serialize_errors,
        timestamp: Time.current.iso8601
      }.compact
    end
    
    def to_rack_response
      [status, headers, [serializable_hash.to_json]]
    end
    
    protected
    
    def serialize_data
      return nil if data.nil?
      
      case data
      when ActiveRecord::Base, Draper::Decorator
        data.serializable_hash
      when ActiveRecord::Relation, Array
        data.map(&:serializable_hash)
      when SearchResults::SearchResult
        data.serializable_hash
      when Hash
        data
      else
        data.respond_to?(:serializable_hash) ? data.serializable_hash : data
      end
    end
    
    def serialize_errors
      errors.map do |error|
        case error
        when String
          { message: error }
        when ActiveModel::Error
          { field: error.attribute, message: error.message, code: error.type }
        when Hash
          error
        else
          { message: error.to_s }
        end
      end
    end
    
    private
    
    def normalize_status(status)
      case status
      when Symbol
        Rack::Utils::SYMBOL_TO_STATUS_CODE[status] || 
          raise(ArgumentError, "Unknown status symbol: #{status}")
      when Integer
        status
      else
        raise ArgumentError, "Status must be Symbol or Integer, got #{status.class}"
      end
    end
    
    def default_headers
      {
        'Content-Type' => 'application/json',
        'X-API-Version' => 'v1',
        'X-Response-Time' => Time.current.iso8601
      }
    end
    
    def default_metadata
      {
        api_version: 'v1',
        response_id: SecureRandom.uuid
      }
    end
    
    def validate_response_structure!
      unless status.is_a?(Integer) && status.between?(100, 599)
        raise ArgumentError, "Invalid HTTP status: #{status}"
      end
      
      unless headers.is_a?(Hash)
        raise ArgumentError, "Headers must be a Hash"
      end
    end
  end
end
```

#### 3.2 Specialized Response Types

```ruby
# app/lib/api_responses/success_response.rb
module ApiResponses
  class SuccessResponse < BaseResponse
    def initialize(data: nil, status: :ok, **options)
      super(data: data, status: status, **options)
    end
    
    def self.ok(data = nil, **options)
      new(data: data, status: :ok, **options)
    end
    
    def self.created(data = nil, **options)
      new(data: data, status: :created, **options)
    end
    
    def self.no_content(**options)
      new(data: nil, status: :no_content, **options)
    end
  end
end

# app/lib/api_responses/error_response.rb
module ApiResponses
  class ErrorResponse < BaseResponse
    def initialize(errors:, status: :bad_request, **options)
      super(data: nil, status: status, errors: errors, **options)
    end
    
    def self.bad_request(errors, **options)
      new(errors: errors, status: :bad_request, **options)
    end
    
    def self.unauthorized(message = 'Unauthorized', **options)
      new(errors: [message], status: :unauthorized, **options)
    end
    
    def self.forbidden(message = 'Forbidden', **options)
      new(errors: [message], status: :forbidden, **options)
    end
    
    def self.not_found(message = 'Resource not found', **options)
      new(errors: [message], status: :not_found, **options)
    end
    
    def self.unprocessable_entity(errors, **options)
      new(errors: errors, status: :unprocessable_entity, **options)
    end
    
    def self.internal_server_error(message = 'Internal server error', **options)
      new(errors: [message], status: :internal_server_error, **options)
    end
    
    def self.from_exception(exception, **options)
      case exception
      when ActiveRecord::RecordNotFound
        not_found("#{exception.model} not found", **options)
      when ActiveRecord::RecordInvalid
        unprocessable_entity(exception.record.errors, **options)
      when ActiveRecord::StaleObjectError
        ErrorResponse.new(
          errors: ['Resource has been modified by another user'],
          status: :conflict,
          **options
        )
      when CustomError::ResourceConflict
        ErrorResponse.new(
          errors: [exception.message],
          status: :conflict,
          metadata: { code: exception.code },
          **options
        )
      when CustomError::RateLimitExceeded
        ErrorResponse.new(
          errors: [exception.message],
          status: :too_many_requests,
          headers: { 'Retry-After' => '60' },
          **options
        )
      else
        internal_server_error(
          Rails.env.production? ? 'An error occurred' : exception.message,
          **options
        )
      end
    end
  end
end

# app/lib/api_responses/paginated_response.rb
module ApiResponses
  class PaginatedResponse < SuccessResponse
    def initialize(search_result:, **options)
      pagination_metadata = {
        pagination: {
          current_page: search_result.current_page,
          total_pages: search_result.total_pages,
          total_count: search_result.total_count,
          per_page: search_result.metadata[:per_page],
          has_next_page: search_result.has_next_page?,
          has_previous_page: search_result.has_previous_page?
        },
        search: {
          type: search_result.form.search_type,
          execution_time_ms: search_result.query_info[:execution_time_ms],
          cache_hit: search_result.query_info[:cache_hit]
        }
      }
      
      merged_metadata = options[:metadata]&.merge(pagination_metadata) || pagination_metadata
      
      super(
        data: search_result.records,
        metadata: merged_metadata,
        **options
      )
    end
  end
end
```

#### 3.3 Enhanced API Controller Base

```ruby
# app/controllers/api/api_controller.rb
class Api::ApiController < ApplicationController
  include ApiResponseHelper
  
  skip_before_action :verify_authenticity_token
  before_action :set_api_headers
  before_action :enforce_json_format
  
  rescue_from StandardError, with: :handle_api_error
  
  private
  
  def set_api_headers
    response.headers['X-API-Version'] = 'v1'
    response.headers['X-API-Client'] = request.headers['X-API-Client'] || 'unknown'
  end
  
  def enforce_json_format
    request.format = :json unless request.format.json?
  end
  
  def handle_api_error(exception)
    error_response = ApiResponses::ErrorResponse.from_exception(
      exception,
      metadata: {
        request_id: request.request_id,
        timestamp: Time.current.iso8601
      }
    )
    
    log_api_error(exception, error_response)
    render_api_response(error_response)
  end
  
  def log_api_error(exception, error_response)
    Rails.logger.error(
      message: 'API Error',
      exception: exception.class.name,
      exception_message: exception.message,
      status: error_response.status,
      request_id: request.request_id,
      user_id: current_admin&.id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      endpoint: "#{request.method} #{request.path}",
      backtrace: Rails.env.development? ? exception.backtrace : nil
    )
  end
end

# app/controllers/concerns/api_response_helper.rb
module ApiResponseHelper
  extend ActiveSupport::Concern
  
  private
  
  def render_api_response(response)
    render json: response.serializable_hash, 
           status: response.status, 
           headers: response.headers
  end
  
  def success_response(data = nil, **options)
    ApiResponses::SuccessResponse.ok(data, **options)
  end
  
  def created_response(data = nil, **options)
    ApiResponses::SuccessResponse.created(data, **options)
  end
  
  def no_content_response(**options)
    ApiResponses::SuccessResponse.no_content(**options)
  end
  
  def paginated_response(search_result, **options)
    ApiResponses::PaginatedResponse.new(search_result: search_result, **options)
  end
  
  def error_response(errors, status = :bad_request, **options)
    ApiResponses::ErrorResponse.new(errors: errors, status: status, **options)
  end
  
  def validation_error_response(model, **options)
    ApiResponses::ErrorResponse.unprocessable_entity(model.errors, **options)
  end
end
```

#### 3.4 Enhanced API Controllers

```ruby
# app/controllers/api/v1/inventories_controller.rb
class Api::V1::InventoriesController < Api::ApiController
  before_action :set_inventory, only: [:show, :update, :destroy]
  
  def index
    search_service = TypeSafeSearchService.new(
      form_class: InventorySearchForm,
      base_relation: Inventory.includes(:batches).with_attached_image
    )
    
    search_result = search_service.call(search_params)
    
    if search_result.success?
      response = paginated_response(search_result)
    else
      response = error_response(
        search_result.form.errors.full_messages,
        :unprocessable_entity
      )
    end
    
    render_api_response(response)
  end
  
  def show
    response = success_response(@inventory.decorate)
    render_api_response(response)
  end
  
  def create
    @inventory = Inventory.new(inventory_params)
    
    if @inventory.save
      response = created_response(
        @inventory.decorate,
        headers: { 'Location' => api_v1_inventory_url(@inventory) }
      )
    else
      response = validation_error_response(@inventory)
    end
    
    render_api_response(response)
  end
  
  def update
    if @inventory.update(inventory_params)
      response = success_response(@inventory.reload.decorate)
    else
      response = validation_error_response(@inventory)
    end
    
    render_api_response(response)
  end
  
  def destroy
    @inventory.destroy!
    response = no_content_response
    render_api_response(response)
  rescue ActiveRecord::RecordNotDestroyed => e
    response = error_response([e.message], :unprocessable_entity)
    render_api_response(response)
  end
  
  private
  
  def set_inventory
    @inventory = Inventory.find(params[:id])
  end
  
  def inventory_params
    params.require(:inventory).permit(:name, :quantity, :price, :status, :lock_version)
  end
  
  def search_params
    params.permit(:name, :status, :min_price, :max_price, :page, :per_page,
                  :sort_field, :sort_direction,
                  created_date_range: [:start_date, :end_date],
                  updated_date_range: [:start_date, :end_date],
                  expiry_date_range: [:start_date, :end_date])
  end
end
```

## 4. Integration and Testing Strategy

### 4.1 RSpec Testing Patterns

```ruby
# spec/lib/form_fields/string_field_spec.rb
RSpec.describe FormFields::StringField do
  describe '#initialize' do
    it 'creates valid string field' do
      field = described_class.new(name: 'test_field', value: 'test value')
      
      expect(field.name).to eq('test_field')
      expect(field.value).to eq('test value')
      expect(field.type).to eq(:string)
      expect(field.formatted_value).to eq('test value')
    end
    
    it 'raises TypeError for invalid value type' do
      expect {
        described_class.new(name: 'test', value: { invalid: 'hash' })
      }.to raise_error(TypeError, /Invalid value/)
    end
  end
  
  describe '#valid?' do
    it 'validates string length' do
      long_value = 'a' * 256
      field = described_class.new(name: 'test', value: long_value)
      
      expect(field).not_to be_valid
      expect(field.errors[:value]).to include('is too long')
    end
  end
end

# spec/lib/search_results/search_result_spec.rb
RSpec.describe SearchResults::SearchResult do
  let(:form) { instance_double(InventorySearchForm, valid?: true, search_type: :basic) }
  let(:records) { [create(:inventory), create(:inventory)] }
  
  describe '#initialize' do
    it 'creates valid search result' do
      result = described_class.new(records: records, form: form)
      
      expect(result.records).to eq(records)
      expect(result.form).to eq(form)
      expect(result.success?).to be true
    end
    
    it 'builds correct metadata' do
      result = described_class.new(records: records, form: form)
      
      expect(result.metadata[:total_count]).to eq(2)
      expect(result.metadata[:search_type]).to eq(:basic)
    end
  end
end

# spec/lib/api_responses/success_response_spec.rb
RSpec.describe ApiResponses::SuccessResponse do
  describe '.ok' do
    it 'creates successful response' do
      data = { id: 1, name: 'Test' }
      response = described_class.ok(data)
      
      expect(response.success?).to be true
      expect(response.status).to eq(200)
      expect(response.data).to eq(data)
    end
  end
  
  describe '#serializable_hash' do
    it 'includes all required fields' do
      response = described_class.ok({ test: 'data' })
      hash = response.serializable_hash
      
      expect(hash).to include(
        :data, :success, :status, :metadata, :errors, :timestamp
      )
      expect(hash[:success]).to be true
      expect(hash[:status]).to eq(200)
    end
  end
end
```

### 4.2 Controller Testing

```ruby
# spec/requests/api/v1/inventories_spec.rb
RSpec.describe 'Api::V1::Inventories', type: :request do
  describe 'GET /api/v1/inventories' do
    let!(:inventories) { create_list(:inventory, 3) }
    
    context 'with valid search parameters' do
      it 'returns paginated response' do
        get '/api/v1/inventories', params: { name: 'test', page: 1, per_page: 2 }
        
        expect(response).to have_http_status(:ok)
        
        json = JSON.parse(response.body)
        expect(json['success']).to be true
        expect(json['data']).to be_an(Array)
        expect(json['metadata']['pagination']).to include(
          'current_page', 'total_pages', 'total_count'
        )
      end
    end
    
    context 'with invalid search parameters' do
      it 'returns validation errors' do
        get '/api/v1/inventories', params: { min_price: -1 }
        
        expect(response).to have_http_status(:unprocessable_entity)
        
        json = JSON.parse(response.body)
        expect(json['success']).to be false
        expect(json['errors']).not_to be_empty
      end
    end
  end
end
```

## 5. Migration Strategy

### 5.1 Gradual Migration Plan

#### Phase 1: Foundation (Week 1-2)
1. Implement base FormField classes
2. Create basic field types (String, Decimal, Enum)
3. Add comprehensive unit tests
4. Update documentation

#### Phase 2: Forms Enhancement (Week 3-4)
1. Migrate InventorySearchForm to TypeSafeForm
2. Implement date range fields
3. Add form validation tests
4. Update search controllers

#### Phase 3: Search Results (Week 5-6)
1. Implement SearchResult value object
2. Enhance search services with type safety
3. Add search result tests
4. Update view integration

#### Phase 4: API Responses (Week 7-8)
1. Implement ApiResponse classes
2. Migrate API controllers
3. Add comprehensive API tests
4. Update API documentation

#### Phase 5: Integration & Optimization (Week 9-10)
1. Performance optimization
2. Error handling refinement
3. Monitoring and logging enhancement
4. Final testing and documentation

### 5.2 Backward Compatibility

```ruby
# app/forms/legacy_form_adapter.rb
class LegacyFormAdapter
  def self.wrap(legacy_form)
    return legacy_form if legacy_form.is_a?(TypeSafeForm)
    
    # Create adapter for legacy forms
    LegacyFormWrapper.new(legacy_form)
  end
end

class LegacyFormWrapper
  delegate_missing_to :@legacy_form
  
  def initialize(legacy_form)
    @legacy_form = legacy_form
  end
  
  def serializable_hash
    # Convert legacy form to new format
    @legacy_form.attributes.transform_values do |value|
      { name: nil, value: value, type: :unknown, valid: true, errors: [] }
    end
  end
end
```

## 6. Monitoring and Observability

### 6.1 Performance Monitoring

```ruby
# app/lib/monitoring/type_safety_monitor.rb
module Monitoring
  class TypeSafetyMonitor
    def self.track_form_validation(form_class, execution_time_ms, errors = [])
      Rails.logger.info(
        event: 'form_validation',
        form_class: form_class.name,
        execution_time_ms: execution_time_ms,
        errors_count: errors.size,
        has_errors: errors.any?
      )
    end
    
    def self.track_search_execution(search_result)
      Rails.logger.info(
        event: 'search_execution',
        search_type: search_result.form.search_type,
        records_count: search_result.records.size,
        execution_time_ms: search_result.query_info[:execution_time_ms],
        cache_hit: search_result.query_info[:cache_hit],
        sql_queries: search_result.query_info[:sql_queries]
      )
    end
    
    def self.track_api_response(response, controller_action)
      Rails.logger.info(
        event: 'api_response',
        controller_action: controller_action,
        status: response.status,
        success: response.success?,
        response_size_bytes: response.serializable_hash.to_json.bytesize,
        has_errors: response.errors.any?
      )
    end
  end
end
```

### 6.2 Error Tracking

```ruby
# app/lib/monitoring/error_tracker.rb
module Monitoring
  class ErrorTracker
    def self.track_type_error(error, context = {})
      Rails.logger.error(
        event: 'type_safety_error',
        error_class: error.class.name,
        error_message: error.message,
        context: context,
        backtrace: error.backtrace&.first(10)
      )
      
      # Send to external monitoring (Sentry, etc.)
      # Sentry.capture_exception(error, extra: context)
    end
    
    def self.track_validation_failure(form, field_errors)
      Rails.logger.warn(
        event: 'validation_failure',
        form_class: form.class.name,
        field_errors: field_errors,
        form_data: form.serializable_hash
      )
    end
  end
end
```

## 7. Documentation and Developer Experience

### 7.1 Code Documentation

```ruby
# Add comprehensive YARD documentation
class FormFields::BaseField
  # Base class for type-safe form fields
  #
  # @abstract Subclass and override {#value_valid_for_type?} to implement
  #   type-specific validation
  #
  # @example Creating a custom field type
  #   class PhoneNumberField < FormFields::BaseField
  #     def self.field_type
  #       :phone_number
  #     end
  #
  #     private
  #
  #     def value_valid_for_type?
  #       value.match?(/\A\+?[\d\s\-\(\)]+\z/)
  #     end
  #   end
  #
  # @param name [String, Symbol] the field name
  # @param value [Object] the field value
  # @param options [Hash] additional field options
  # @option options [Boolean] :required whether the field is required
  # @option options [String] :help_text help text for the field
  def initialize(name:, value: nil, **options)
    # Implementation...
  end
end
```

### 7.2 Migration Guide

```markdown
# Migration Guide: Legacy Forms to Type-Safe Forms

## Before (Legacy)
```ruby
class InventorySearchForm < BaseSearchForm
  attribute :name, :string
  attribute :min_price, :decimal
  
  validates :min_price, numericality: { greater_than_or_equal_to: 0 }
end
```

## After (Type-Safe)
```ruby
class InventorySearchForm < TypeSafeForm
  field :name, :string
  field :min_price, :decimal
  
  # Validation is built into the field type
end
```

## Benefits
- Compile-time type checking
- Better error messages
- Consistent validation logic
- Improved developer experience
```

## Conclusion

This design document provides a comprehensive approach to enhancing type safety in the StockRx Rails application. The implementation focuses on:

1. **Strong typing** through dedicated value objects
2. **Consistent interfaces** across forms, search results, and API responses
3. **Backward compatibility** to ensure smooth migration
4. **Comprehensive testing** to maintain reliability
5. **Observability** for monitoring and debugging

The gradual migration strategy ensures minimal disruption while providing immediate benefits as each component is implemented.