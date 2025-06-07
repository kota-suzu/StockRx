# frozen_string_literal: true

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
  
  # 検索実行前の条件チェック
  def has_search_conditions?
    raise NotImplementedError, "#{self.class.name}#has_search_conditions? must be implemented"
  end
  
  # 検索条件のサマリー生成
  def conditions_summary
    raise NotImplementedError, "#{self.class.name}#conditions_summary must be implemented"
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
  
  # ソート可能フィールドの定義（サブクラスでオーバーライド）
  def sortable_fields
    %w[updated_at created_at]
  end
  
  # ソートフィールドのバリデーション
  def validate_sort_field
    return if sort_field.blank? || sortable_fields.include?(sort_field)
    
    errors.add(:sort_field, "無効なソートフィールドです: #{sort_field}")
  end
end