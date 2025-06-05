# frozen_string_literal: true

# 検索クエリを処理するサービスクラス
# シンプルな検索には従来の実装を使用し、複雑な検索にはAdvancedSearchQueryを使用
#
# TODO: パフォーマンス最適化
# - 検索結果のキャッシュ機能（Redis活用）
# - インデックス最適化の推奨事項
# - N+1クエリ問題の検出と改善
# - ページネーション改善（カーソルベース）
#
# TODO: 機能拡張
# - フルテキスト検索対応（ElasticsearchまたはMroonga）
# - 検索履歴機能
# - 検索結果のエクスポート機能
# - リアルタイム検索機能（WebSocket）
#
# TODO: 監視とメトリクス
# - 検索クエリのパフォーマンス監視
# - 人気検索キーワードの分析
# - 検索エラー率の追跡
class SearchQuery
  # 許可されたソートカラム（SQLインジェクション対策）
  ALLOWED_SORT_COLUMNS = %w[name price quantity updated_at created_at].freeze

  # 許可されたソート方向（SQLインジェクション対策）
  ALLOWED_SORT_DIRECTIONS = %w[asc desc].freeze

  # デフォルトのソート設定
  DEFAULT_SORT_COLUMN = "updated_at"
  DEFAULT_SORT_DIRECTION = "desc"

  class << self
    # メインの検索エントリポイント
    # @param params [Hash] 検索パラメータ
    # @return [ActiveRecord::Relation] 検索結果
    # @raise [ArgumentError] 無効なパラメータが渡された場合
    def call(params)
      # パラメータのバリデーション
      validate_params!(params)

      # TODO: 検索結果のキャッシュ機能を実装
      # cache_key = generate_cache_key(params)
      # Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      
      # 複雑な検索条件が含まれている場合はAdvancedSearchQueryを使用
      if complex_search_required?(params)
        advanced_search(params)
      else
        simple_search(params)
      end
      
      # end # キャッシュブロック終了
    rescue ArgumentError => e
      # バリデーションエラーは再発生させる
      raise e
    rescue => e
      # エラーログ出力（本番環境での詳細情報漏洩を防ぐ）
      Rails.logger.error "SearchQuery error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?

      # 安全なデフォルト結果を返す
      Inventory.none
    end

    private

    # パラメータのバリデーション
    # @param params [Hash] 検証対象のパラメータ
    # @raise [ArgumentError] 無効なパラメータが含まれている場合
    def validate_params!(params)
      return unless params.is_a?(Hash)

      # ソートカラムの検証
      if params.key?(:sort) && params[:sort].present? && !ALLOWED_SORT_COLUMNS.include?(params[:sort].to_s)
        raise ArgumentError, "Invalid sort column: #{params[:sort]}"
      end

      # ソート方向の検証
      if params.key?(:direction) && params[:direction].present? && !ALLOWED_SORT_DIRECTIONS.include?(params[:direction].to_s.downcase)
        raise ArgumentError, "Invalid sort direction: #{params[:direction]}"
      end

      # ステータスの検証
      if params.key?(:status) && params[:status].present? && !Inventory::STATUSES.include?(params[:status].to_s)
        raise ArgumentError, "Invalid status: #{params[:status]}"
      end
    end

    # シンプルな検索（従来の実装を安全化）
    # @param params [Hash] 検索パラメータ
    # @return [ActiveRecord::Relation] 検索結果
    def simple_search(params)
      query = Inventory.all

      # キーワード検索（SQLインジェクション対策済み）
      query = apply_keyword_filter(query, params[:q])

      # ステータスでフィルタリング（安全な方法）
      query = apply_status_filter(query, params[:status])

      # 在庫量でフィルタリング
      query = apply_stock_filter(query, params[:low_stock])

      # 安全な並び替え
      apply_safe_ordering(query, params[:sort], params[:direction])
    end

    # キーワード検索フィルタの適用
    # @param query [ActiveRecord::Relation] ベースクエリ
    # @param keyword [String] 検索キーワード
    # @return [ActiveRecord::Relation] フィルタリング後のクエリ
    def apply_keyword_filter(query, keyword)
      return query if keyword.blank?

      # SQLインジェクション対策：プレースホルダーを使用
      # MySQL対応：ILIKEではなくLIKEを使用（大文字小文字を区別しない検索）
      sanitized_keyword = "%#{keyword.to_s.strip}%"
      query.where("name LIKE ?", sanitized_keyword)
    end

    # ステータスフィルタの適用
    # @param query [ActiveRecord::Relation] ベースクエリ
    # @param status [String] ステータス値
    # @return [ActiveRecord::Relation] フィルタリング後のクエリ
    def apply_status_filter(query, status)
      return query if status.blank?
      return query unless Inventory::STATUSES.include?(status)

      query.where(status: status)
    end

    # 在庫フィルタの適用
    # @param query [ActiveRecord::Relation] ベースクエリ
    # @param low_stock [String] 低在庫フィルタフラグ
    # @return [ActiveRecord::Relation] フィルタリング後のクエリ
    def apply_stock_filter(query, low_stock)
      return query unless low_stock == "true"

      query.where("quantity <= ?", 0)
    end

    # 安全なソート処理
    # @param query [ActiveRecord::Relation] ベースクエリ
    # @param sort_column [String] ソートカラム
    # @param sort_direction [String] ソート方向
    # @return [ActiveRecord::Relation] ソート後のクエリ
    def apply_safe_ordering(query, sort_column, sort_direction)
      # 安全なカラム名とソート方向の決定
      safe_column = ALLOWED_SORT_COLUMNS.include?(sort_column.to_s) ? sort_column.to_s : DEFAULT_SORT_COLUMN
      safe_direction = ALLOWED_SORT_DIRECTIONS.include?(sort_direction.to_s.downcase) ? sort_direction.to_s.downcase : DEFAULT_SORT_DIRECTION

      # ハッシュ形式で安全にソート（SQLインジェクション対策）
      query.order(safe_column => safe_direction)
    end

    # 高度な検索（AdvancedSearchQueryを使用）
    # @param params [Hash] 検索パラメータ
    # @return [ActiveRecord::Relation] 検索結果
    def advanced_search(params)
      query = AdvancedSearchQuery.build

      # 基本的な検索条件
      if params[:q].present?
        query = query.search_keywords(params[:q], fields: [ :name, :description ])
      end

      if params[:status].present?
        query = query.with_status(params[:status])
      end

      # 在庫状態
      case params[:stock_filter]
      when "out_of_stock"
        query = query.out_of_stock
      when "low_stock"
        threshold = params[:low_stock_threshold]&.to_i || 10
        query = query.low_stock(threshold)
      when "in_stock"
        threshold = params[:low_stock_threshold]&.to_i || 10
        query = query.where("inventories.quantity > ?", threshold)
      else
        # 従来の互換性のため
        if params[:low_stock] == "true"
          query = query.out_of_stock
        end
      end

      # 価格範囲
      if params[:min_price].present? || params[:max_price].present?
        query = query.in_range("price", params[:min_price]&.to_f, params[:max_price]&.to_f)
      end

      # 日付範囲
      if params[:created_from].present? || params[:created_to].present?
        query = query.between_dates("created_at", params[:created_from], params[:created_to])
      end

      # バッチ関連の検索
      if params[:lot_code].present? || params[:expires_before].present? || params[:expires_after].present?
        query = query.with_batch_conditions do
          lot_code(params[:lot_code]) if params[:lot_code].present?
          expires_before(params[:expires_before]) if params[:expires_before].present?
          expires_after(params[:expires_after]) if params[:expires_after].present?
        end
      end

      # 期限切れ間近
      if params[:expiring_soon].present?
        days = params[:expiring_days]&.to_i || 30
        query = query.expiring_soon(days)
      end

      # 最近の更新
      if params[:recently_updated].present?
        days = params[:updated_days]&.to_i || 7
        query = query.recently_updated(days)
      end

      # 出荷関連
      if params[:shipment_status].present? || params[:destination].present?
        query = query.with_shipment_conditions do
          status(params[:shipment_status]) if params[:shipment_status].present?
          destination_like(params[:destination]) if params[:destination].present?
        end
      end

      # 入荷関連
      if params[:receipt_status].present? || params[:source].present?
        query = query.with_receipt_conditions do
          status(params[:receipt_status]) if params[:receipt_status].present?
          source_like(params[:source]) if params[:source].present?
        end
      end

      # OR条件の検索
      if params[:or_conditions].present? && params[:or_conditions].is_a?(Array)
        query = query.where_any(params[:or_conditions])
      end

      # 複雑な条件
      if params[:complex_condition].present?
        query = build_complex_condition(query, params[:complex_condition])
      end

      # ソート
      sort_field = params[:sort] || "updated_at"
      sort_direction = params[:direction]&.downcase&.to_sym || :desc
      query = query.order_by(sort_field, sort_direction)

      # ページネーション（必要に応じて）
      if params[:page].present?
        query = query.paginate(
          page: params[:page].to_i,
          per_page: params[:per_page]&.to_i || 20
        )
      end

      query.results
    end

    # 複雑な検索が必要かどうかを判定
    # @param params [Hash] 検索パラメータ
    # @return [Boolean] 複雑な検索が必要な場合true
    def complex_search_required?(params)
      return false unless params.is_a?(Hash)

      # 高度な検索パラメータのリスト
      ADVANCED_SEARCH_PARAMS.any? { |param| params[param].present? }
    end

    # 高度な検索パラメータの定義（不変オブジェクト）
    ADVANCED_SEARCH_PARAMS = %i[
      min_price max_price
      created_from created_to
      lot_code expires_before expires_after
      expiring_soon expiring_days
      recently_updated updated_days
      shipment_status destination
      receipt_status source
      or_conditions complex_condition
      stock_filter low_stock_threshold
    ].freeze

    # 複雑な条件を構築
    # @param query [AdvancedSearchQuery] AdvancedSearchQueryインスタンス
    # @param condition [Hash] 条件設定
    # @return [AdvancedSearchQuery] 条件適用後のクエリ
    def build_complex_condition(query, condition)
      return query unless condition.is_a?(Hash)
      return query if condition.empty?

      condition_builder = ComplexConditionBuilder.new(query)
      condition_builder.build(condition)
    end

    # 複雑な条件を構築するための専用クラス
    # AdvancedSearchQueryと連携して安全な条件構築を行う
    class ComplexConditionBuilder
      # 許可される条件タイプ（セキュリティ対策）
      ALLOWED_CONDITION_TYPES = %w[and or].freeze

      # @param query [AdvancedSearchQuery] ベースとなるクエリ
      def initialize(query)
        @query = query
      end

      # 複雑な条件を構築
      # @param condition [Hash] 条件設定
      # @return [AdvancedSearchQuery] 条件適用後のクエリ
      def build(condition)
        return @query unless condition.is_a?(Hash)

        # AdvancedSearchQueryのcomplex_whereメソッドを使用
        @query.complex_where do |builder|
          condition.each do |type, sub_conditions|
            # セキュリティ：許可されていない条件タイプは無視
            next unless ALLOWED_CONDITION_TYPES.include?(type.to_s)
            next unless sub_conditions.is_a?(Array)

            case type.to_s
            when "and"
              builder.and_group do |and_builder|
                sub_conditions.each { |cond| safely_apply_condition(and_builder, cond) }
              end
            when "or"
              builder.or_group do |or_builder|
                sub_conditions.each { |cond| safely_apply_condition(or_builder, cond) }
              end
            end
          end
        end
      end

      private

      # 安全に条件を適用
      # @param builder [Object] 条件ビルダー
      # @param condition [Hash] 適用する条件
      def safely_apply_condition(builder, condition)
        return unless condition.is_a?(Hash)
        return if condition.empty?

        # 条件のサニタイズとバリデーション
        sanitized_condition = sanitize_condition(condition)
        builder.where(sanitized_condition) if sanitized_condition.present?
      rescue => e
        # 個別の条件エラーをログに記録し、処理を継続
        Rails.logger.warn "Skipping invalid condition: #{e.message}"
      end

      # 条件のサニタイズ
      # @param condition [Hash] サニタイズ対象の条件
      # @return [Hash] サニタイズ済みの条件
      def sanitize_condition(condition)
        # TODO: より詳細な条件バリデーションとサニタイズを実装
        # 現時点では基本的なタイプチェックのみ
        # - SQLインジェクション対策の強化
        # - パラメータの型チェック（数値、日付など）
        # - 許可されたフィールド名のホワイトリスト化
        condition.select { |_key, value| !value.nil? }
      end
    end
  end
end
