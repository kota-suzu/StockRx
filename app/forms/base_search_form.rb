# frozen_string_literal: true

# TODO: 横展開確認 - 基底検索フォームの設計パターンをすべての検索機能に適用
# アーキテクチャ設計原則：
# 1. 抽象化レベルの統一
# 2. 共通機能の基底クラス集約
# 3. ページネーション・ソート機能の標準化
# 4. メタデータ管理（キャッシュキー、クエリパラメータ等）

class BaseSearchForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  include ActiveModel::Serialization

  # TODO: パフォーマンス最適化 - ページネーション設定の動的調整
  # 共通属性
  attribute :page, :integer, default: 1
  attribute :per_page, :integer, default: 20
  attribute :sort_field, :string, default: "updated_at"
  attribute :sort_direction, :string, default: "desc"

  # TODO: バリデーション標準化 - 全検索フォームで共通の基本バリデーション
  # 共通バリデーション
  validates :page, numericality: { greater_than: 0 }
  validates :per_page, inclusion: { in: [ 10, 20, 50, 100 ] }
  validates :sort_direction, inclusion: { in: %w[asc desc] }
  validate :validate_sort_field

  # TODO: セキュリティ強化 - CSRFトークン管理とセッション連携
  # キャッシュキー生成（検索条件のハッシュ化）
  def cache_key
    require "digest/md5"
    Digest::MD5.hexdigest(to_params.to_json)
  end

  # TODO: API統合 - GraphQLとRESTful両対応のパラメータ変換
  # URLクエリ文字列用のパラメータ変換
  def to_params
    attributes.reject { |_, v| v.blank? }
  end

  # クエリパラメータ文字列の生成
  def to_query_params
    to_params.to_query
  end

  # TODO: メソッド実装必須化 - 抽象メソッドの強制実装確認機能
  # 抽象メソッド（サブクラスで実装必須）
  def search
    raise NotImplementedError, "Subclass must implement #search method"
  end

  def has_search_conditions?
    raise NotImplementedError, "Subclass must implement #has_search_conditions? method"
  end

  def conditions_summary
    raise NotImplementedError, "Subclass must implement #conditions_summary method"
  end

  protected

  # ソート可能フィールドの定義（サブクラスでオーバーライド）
  def sortable_fields
    %w[updated_at created_at]
  end

  private

  # ソートフィールドのバリデーション
  def validate_sort_field
    return if sort_field.blank? || sortable_fields.include?(sort_field)

    errors.add(:sort_field, I18n.t("errors.messages.invalid"))
  end
end
