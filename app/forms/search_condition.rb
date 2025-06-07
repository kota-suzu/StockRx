# frozen_string_literal: true

# TODO: 横展開確認 - 動的検索条件の設計パターンを他の検索機能に適用
# セキュリティ設計原則：
# 1. SQLインジェクション対策（ホワイトリストベース）
# 2. 入力値のサニタイゼーション
# 3. データ型別バリデーション
# 4. エラーハンドリングの統一

class SearchCondition
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations

  # フィールド定義
  attribute :field, :string
  attribute :operator, :string
  attribute :value, :string
  attribute :logic_type, :string, default: "AND"
  attribute :data_type, :string, default: "string"

  # TODO: セキュリティ強化 - より細かい権限ベースのフィールドアクセス制御
  # 演算子の定義
  OPERATORS = {
    "equals" => "=",
    "not_equals" => "!=",
    "contains" => "LIKE",
    "not_contains" => "NOT LIKE",
    "starts_with" => "LIKE",
    "ends_with" => "LIKE",
    "greater_than" => ">",
    "greater_than_or_equal" => ">=",
    "less_than" => "<",
    "less_than_or_equal" => "<=",
    "between" => "BETWEEN",
    "in" => "IN",
    "not_in" => "NOT IN",
    "is_null" => "IS NULL",
    "is_not_null" => "IS NOT NULL"
  }.freeze

  DATA_TYPES = %w[string integer decimal date boolean].freeze
  LOGIC_TYPES = %w[AND OR].freeze

  # TODO: 動的フィールド拡張 - 設定ベースでの検索可能フィールド管理
  # 検索可能フィールドの定義（セキュリティ対策）
  ALLOWED_SEARCH_FIELDS = %w[
    name status price quantity created_at updated_at
    batches.lot_code batches.expires_on
    shipments.destination shipments.status
    receipts.source receipts.status
  ].freeze

  # TODO: バリデーション強化 - 業務ルールベースの複合バリデーション
  # バリデーション
  validates :field, presence: true, inclusion: { in: ALLOWED_SEARCH_FIELDS }
  validates :operator, inclusion: { in: OPERATORS.keys }
  validates :logic_type, inclusion: { in: LOGIC_TYPES }
  validates :data_type, inclusion: { in: DATA_TYPES }
  validate :value_presence_for_operator
  validate :value_type_consistency

  # TODO: SQLビルダー最適化 - クエリパフォーマンスの向上
  # SQL条件生成
  def to_sql_condition
    return nil unless valid?

    sanitized_field = sanitize_field_name(field)

    case operator
    when "contains"
      [ "#{sanitized_field} LIKE ?", "%#{sanitize_value}%" ]
    when "not_contains"
      [ "#{sanitized_field} NOT LIKE ?", "%#{sanitize_value}%" ]
    when "starts_with"
      [ "#{sanitized_field} LIKE ?", "#{sanitize_value}%" ]
    when "ends_with"
      [ "#{sanitized_field} LIKE ?", "%#{sanitize_value}" ]
    when "between"
      values = parse_between_values
      return nil if values.length != 2
      [ "#{sanitized_field} BETWEEN ? AND ?", converted_value(values[0]), converted_value(values[1]) ]
    when "in", "not_in"
      values = parse_array_values
      return nil if values.empty?
      placeholders = Array.new(values.size, "?").join(",")
      converted_values = values.map { |v| converted_value(v) }
      [ "#{sanitized_field} #{OPERATORS[operator]} (#{placeholders})", *converted_values ]
    when "is_null", "is_not_null"
      "#{sanitized_field} #{OPERATORS[operator]}"
    else
      [ "#{sanitized_field} #{OPERATORS[operator]} ?", converted_value ]
    end
  end

  # TODO: UX改善 - より直感的な条件説明の生成
  # 条件の説明テキスト生成
  def description
    return "無効な条件" unless valid?

    field_name = field_display_name
    operator_name = operator_display_name
    value_text = value_display_text

    "#{field_name} #{operator_name} #{value_text}"
  end

  # TODO: 国際化対応 - 動的な言語切り替え対応
  # フィールドの表示名
  def field_display_name
    I18n.t("search_conditions.fields.#{field.gsub('.', '_')}", default: field.humanize)
  end

  # 演算子の表示名
  def operator_display_name
    I18n.t("search_conditions.operators.#{operator}", default: operator.humanize)
  end

  # 値の表示テキスト
  def value_display_text
    case operator
    when "is_null", "is_not_null"
      ""
    when "between"
      values = parse_between_values
      if values.length == 2
        "#{values[0]} 〜 #{values[1]}"
      else
        value
      end
    when "in", "not_in"
      values = parse_array_values
      values.join(", ")
    else
      value
    end
  end

  private

  # フィールド名のサニタイズ
  def sanitize_field_name(field_name)
    # ホワイトリストによる検証済みなので、基本的な確認のみ
    if field_name.include?(".")
      # 関連テーブルの場合、ActiveRecordのjoin構文に適合するかチェック
      table, column = field_name.split(".", 2)
      "#{table}.#{column}"
    else
      "inventories.#{field_name}"
    end
  end

  # 値のサニタイズ
  def sanitize_value
    return value if value.blank?

    # HTMLタグの除去
    ActionController::Base.helpers.sanitize(value, tags: [])
  end

  # BETWEEN用の値解析
  def parse_between_values
    return [] if value.blank?

    value.split(",").map(&:strip).reject(&:blank?)
  end

  # IN/NOT IN用の値解析
  def parse_array_values
    return [] if value.blank?

    value.split(",").map(&:strip).reject(&:blank?)
  end

  # バリデーション: 演算子に応じた値の存在チェック
  def value_presence_for_operator
    null_operators = %w[is_null is_not_null]
    return if null_operators.include?(operator)

    errors.add(:value, I18n.t("errors.messages.blank")) if value.blank?
  end

  # バリデーション: データ型の整合性チェック
  def value_type_consistency
    return if value.blank? || data_type == "string"

    case data_type
    when "integer"
      validate_integer_value
    when "decimal"
      validate_decimal_value
    when "date"
      validate_date_value
    when "boolean"
      validate_boolean_value
    end
  end

  def validate_integer_value
    case operator
    when "between"
      values = parse_between_values
      values.each do |v|
        unless v =~ /^\d+$/
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    when "in", "not_in"
      values = parse_array_values
      values.each do |v|
        unless v =~ /^\d+$/
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    else
      errors.add(:value, I18n.t("errors.messages.invalid")) unless value =~ /^\d+$/
    end
  end

  def validate_decimal_value
    case operator
    when "between"
      values = parse_between_values
      values.each do |v|
        unless v =~ /^\d+(\.\d+)?$/
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    when "in", "not_in"
      values = parse_array_values
      values.each do |v|
        unless v =~ /^\d+(\.\d+)?$/
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    else
      errors.add(:value, I18n.t("errors.messages.invalid")) unless value =~ /^\d+(\.\d+)?$/
    end
  end

  def validate_date_value
    case operator
    when "between"
      values = parse_between_values
      values.each do |v|
        begin
          Date.parse(v)
        rescue ArgumentError
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    when "in", "not_in"
      values = parse_array_values
      values.each do |v|
        begin
          Date.parse(v)
        rescue ArgumentError
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    else
      begin
        Date.parse(value)
      rescue ArgumentError
        errors.add(:value, I18n.t("errors.messages.invalid"))
      end
    end
  end

  def validate_boolean_value
    valid_boolean_values = %w[true false 1 0 yes no]
    case operator
    when "in", "not_in"
      values = parse_array_values
      values.each do |v|
        unless valid_boolean_values.include?(v.downcase)
          errors.add(:value, I18n.t("errors.messages.invalid"))
          break
        end
      end
    else
      unless valid_boolean_values.include?(value.downcase)
        errors.add(:value, I18n.t("errors.messages.invalid"))
      end
    end
  end

  # 値の型変換
  def converted_value(val = value)
    case data_type
    when "integer"
      val.to_i
    when "decimal"
      val.to_f
    when "date"
      Date.parse(val)
    when "boolean"
      convert_to_boolean(val)
    else
      val
    end
  rescue StandardError
    val # 変換に失敗した場合は元の値を返す
  end

  def convert_to_boolean(val)
    case val.to_s.downcase
    when "true", "1", "yes"
      true
    when "false", "0", "no"
      false
    else
      val
    end
  end
end
