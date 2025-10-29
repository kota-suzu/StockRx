# frozen_string_literal: true

# CLAUDE.md準拠: パラメータサニタイゼーション基盤
# セキュリティファーストアプローチによるパラメータ処理の統一化
# OWASP Top 10準拠 - A03:2021 Injection対策
module ParameterSanitization
  extend ActiveSupport::Concern

  # パラメータ処理時の共通エラーハンドリング
  included do
    rescue_from ActionController::ParameterMissing do |exception|
      respond_to do |format|
        format.html {
          redirect_back(fallback_location: root_path,
                       alert: "必須パラメータが不足しています: #{exception.param}")
        }
        format.json {
          render json: {
            code: "parameter_missing",
            message: "必須パラメータが不足しています",
            details: { missing_param: exception.param }
          }, status: :bad_request
        }
      end
    end

    rescue_from ActionController::UnpermittedParameters do |exception|
      Rails.logger.warn "Unpermitted parameters detected: #{exception.params}"

      respond_to do |format|
        format.html {
          redirect_back(fallback_location: root_path,
                       alert: "許可されていないパラメータが含まれています")
        }
        format.json {
          render json: {
            code: "unpermitted_parameters",
            message: "許可されていないパラメータが含まれています",
            details: { unpermitted: exception.params }
          }, status: :bad_request
        }
      end
    end
  end

  private

  # ============================================
  # 共通サニタイゼーションメソッド
  # ============================================

  # 文字列のサニタイズ（XSS対策）
  # @param value [String] 入力値
  # @param options [Hash] オプション
  # @return [String] サニタイズ済み文字列
  def sanitize_string(value, options = {})
    return nil if value.blank?

    # 基本的なサニタイゼーション
    sanitized = value.to_s.strip

    # HTMLエスケープ（デフォルトで有効）
    if options.fetch(:escape_html, true)
      sanitized = ERB::Util.html_escape(sanitized)
    end

    # SQLインジェクション対策
    if options[:sql_safe]
      sanitized = ActiveRecord::Base.sanitize_sql_like(sanitized)
    end

    # 長さ制限
    if options[:max_length]
      sanitized = sanitized.truncate(options[:max_length])
    end

    # 改行・タブの正規化
    if options[:normalize_whitespace]
      sanitized = sanitized.gsub(/[\r\n\t]+/, " ").squeeze(" ")
    end

    sanitized
  end

  # 数値のサニタイズと検証
  # @param value [String, Numeric] 入力値
  # @param options [Hash] オプション
  # @return [Integer, Float, nil] サニタイズ済み数値
  def sanitize_numeric(value, options = {})
    return nil if value.blank?

    # 数値変換
    numeric_value = if options[:float]
                     value.to_f
    else
                     value.to_i
    end

    # 範囲検証
    if options[:min] && numeric_value < options[:min]
      raise ArgumentError, "値が最小値（#{options[:min]}）を下回っています"
    end

    if options[:max] && numeric_value > options[:max]
      raise ArgumentError, "値が最大値（#{options[:max]}）を超えています"
    end

    # ゼロ・負数チェック
    if options[:positive] && numeric_value <= 0
      raise ArgumentError, "正の数を入力してください"
    end

    if options[:non_negative] && numeric_value < 0
      raise ArgumentError, "負の数は入力できません"
    end

    numeric_value
  end

  # 日付のサニタイズと検証
  # @param value [String, Date] 入力値
  # @param options [Hash] オプション
  # @return [Date, DateTime, nil] サニタイズ済み日付
  def sanitize_date(value, options = {})
    return nil if value.blank?

    begin
      # 日付パース
      date_value = if options[:datetime]
                    DateTime.parse(value.to_s)
      else
                    Date.parse(value.to_s)
      end

      # 範囲検証
      if options[:after] && date_value <= options[:after]
        raise ArgumentError, "#{options[:after]}より後の日付を指定してください"
      end

      if options[:before] && date_value >= options[:before]
        raise ArgumentError, "#{options[:before]}より前の日付を指定してください"
      end

      # 未来日付チェック
      if options[:no_future] && date_value > Date.current
        raise ArgumentError, "未来の日付は指定できません"
      end

      date_value
    rescue Date::Error => e
      raise ArgumentError, "有効な日付形式で入力してください"
    end
  end

  # 配列のサニタイズ
  # @param value [Array] 入力値
  # @param options [Hash] オプション
  # @return [Array] サニタイズ済み配列
  def sanitize_array(value, options = {})
    return [] if value.blank?

    # 配列変換
    array_value = Array(value).compact

    # 重複除去
    if options[:unique]
      array_value = array_value.uniq
    end

    # 要素数制限
    if options[:max_size] && array_value.size > options[:max_size]
      raise ArgumentError, "最大#{options[:max_size]}個まで指定可能です"
    end

    # 各要素のサニタイズ
    if options[:element_type]
      array_value = array_value.map do |element|
        case options[:element_type]
        when :string
          sanitize_string(element, options[:element_options] || {})
        when :numeric
          sanitize_numeric(element, options[:element_options] || {})
        when :id
          element.to_i if element.to_i > 0
        else
          element
        end
      end.compact
    end

    array_value
  end

  # ファイル名のサニタイズ（パストラバーサル対策）
  # @param filename [String] ファイル名
  # @return [String] サニタイズ済みファイル名
  def sanitize_filename(filename)
    return nil if filename.blank?

    # パストラバーサル攻撃対策
    sanitized = File.basename(filename)

    # 危険な文字の除去
    sanitized = sanitized.gsub(/[^0-9A-Za-z.\-_]/, "_")

    # 拡張子の検証
    extension = File.extname(sanitized).downcase
    allowed_extensions = %w[.csv .xlsx .xls .pdf .png .jpg .jpeg]

    unless allowed_extensions.include?(extension)
      raise ArgumentError, "許可されていないファイル形式です"
    end

    sanitized
  end

  # ============================================
  # 検索パラメータのサニタイズ
  # ============================================

  # 検索クエリのサニタイズ
  # @param query [String] 検索クエリ
  # @return [String] サニタイズ済みクエリ
  def sanitize_search_query(query)
    return nil if query.blank?

    # SQLインジェクション対策
    sanitized = ActiveRecord::Base.sanitize_sql_like(query.to_s.strip)

    # 特殊文字のエスケープ
    sanitized = sanitized.gsub(/[%_]/, '\\\\\0')

    # 長さ制限（検索クエリは100文字まで）
    sanitized.truncate(100)
  end

  # ソートパラメータのサニタイズ
  # @param column [String] ソートカラム
  # @param allowed_columns [Array<String>] 許可されたカラム
  # @return [String] サニタイズ済みカラム名
  def sanitize_sort_column(column, allowed_columns)
    column = column.to_s.downcase

    # ホワイトリスト方式で検証
    if allowed_columns.include?(column)
      column
    else
      allowed_columns.first # デフォルトカラム
    end
  end

  # ソート順のサニタイズ
  # @param direction [String] ソート順
  # @return [String] 'asc' または 'desc'
  def sanitize_sort_direction(direction)
    %w[asc desc].include?(direction.to_s.downcase) ? direction.to_s.downcase : "asc"
  end

  # ページネーションパラメータのサニタイズ
  # @param page [String, Integer] ページ番号
  # @param per_page [String, Integer] 1ページあたりの件数
  # @return [Hash] サニタイズ済みページネーション情報
  def sanitize_pagination_params(page, per_page = nil)
    result = {}

    # ページ番号
    result[:page] = [ sanitize_numeric(page, min: 1, non_negative: true) || 1, 1 ].max

    # 1ページあたりの件数
    if per_page
      allowed_per_page = [ 10, 20, 50, 100, 200 ]
      per_page_value = sanitize_numeric(per_page, min: 1, max: 200, non_negative: true)

      # 最も近い許可された値を選択
      result[:per_page] = allowed_per_page.min_by { |v| (v - per_page_value).abs }
    end

    result
  end

  # ============================================
  # Strong Parameters ヘルパー
  # ============================================

  # 在庫パラメータの標準化
  # @param params [ActionController::Parameters] パラメータ
  # @return [ActionController::Parameters] 許可されたパラメータ
  def inventory_params_with_sanitization(params)
    # 必須パラメータの確認
    params.require(:inventory)

    # 許可とサニタイゼーション
    permitted = params.require(:inventory).permit(
      :name, :quantity, :price, :status, :sku, :manufacturer, :unit,
      :description, :minimum_stock, :maximum_stock
    )

    # 各フィールドのサニタイゼーション
    if permitted[:name].present?
      permitted[:name] = sanitize_string(permitted[:name], max_length: 255)
    end

    if permitted[:quantity].present?
      permitted[:quantity] = sanitize_numeric(permitted[:quantity], non_negative: true)
    end

    if permitted[:price].present?
      permitted[:price] = sanitize_numeric(permitted[:price], float: true, non_negative: true)
    end

    if permitted[:sku].present?
      permitted[:sku] = sanitize_string(permitted[:sku], max_length: 50, normalize_whitespace: true)
    end

    if permitted[:manufacturer].present?
      permitted[:manufacturer] = sanitize_string(permitted[:manufacturer], max_length: 100)
    end

    permitted
  end

  # CSVインポートパラメータの標準化
  # @param params [ActionController::Parameters] パラメータ
  # @return [Hash] サニタイズ済みオプション
  def csv_import_params_with_sanitization(params)
    options = {}

    # ファイルの検証
    if params[:csv_file].present?
      uploaded_file = params[:csv_file]

      # ファイルサイズチェック（10MB制限）
      if uploaded_file.size > 10.megabytes
        raise ArgumentError, "ファイルサイズが大きすぎます（最大10MB）"
      end

      # MIMEタイプチェック
      unless uploaded_file.content_type&.include?("csv") ||
             uploaded_file.original_filename&.end_with?(".csv")
        raise ArgumentError, "CSVファイルを選択してください"
      end

      options[:file] = uploaded_file
      options[:filename] = sanitize_filename(uploaded_file.original_filename)
    end

    # インポートオプション
    options[:skip_invalid] = params[:skip_invalid].present?
    options[:update_existing] = params[:update_existing].present?
    options[:batch_size] = sanitize_numeric(params[:batch_size],
                                           min: 100, max: 5000, non_negative: true) || 1000

    options
  end

  # ============================================
  # セキュリティログ
  # ============================================

  # 不正なパラメータアクセスのログ記録
  # @param controller [String] コントローラー名
  # @param action [String] アクション名
  # @param params [Hash] 疑わしいパラメータ
  def log_suspicious_params(controller, action, params)
    Rails.logger.warn "[SECURITY] Suspicious parameter access detected: " \
                     "controller=#{controller}, action=#{action}, " \
                     "params=#{params.inspect}, " \
                     "ip=#{request.remote_ip}, " \
                     "user_agent=#{request.user_agent}"

    # TODO: SecurityComplianceManagerとの統合
    # SecurityComplianceManager.instance.log_security_event(
    #   "suspicious_params",
    #   current_user,
    #   { controller: controller, action: action, params: params }
    # )
  end
end
