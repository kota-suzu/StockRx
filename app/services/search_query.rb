# frozen_string_literal: true

# 検索クエリを処理するサービスクラス
# シンプルな検索には従来の実装を使用し、複雑な検索にはAdvancedSearchQueryを使用
class SearchQuery
  class << self
    def call(params)
      # 複雑な検索条件が含まれている場合はAdvancedSearchQueryを使用
      if complex_search_required?(params)
        advanced_search(params)
      else
        simple_search(params)
      end
    end

    private

    # シンプルな検索（従来の実装）
    def simple_search(params)
      # Counter Cacheカラムを使用するため、includesは不要
      # サブクエリで取得したカウンターキャッシュは予備として保持
      query = Inventory.select('inventories.*, (SELECT COUNT(*) FROM batches WHERE batches.inventory_id = inventories.id) as batches_count_cache')

      # キーワード検索
      if params[:q].present?
        query = query.where("name LIKE ?", "%#{params[:q]}%")
      end

      # ステータスでフィルタリング
      if params[:status].present? && Inventory::STATUSES.include?(params[:status])
        query = query.where(status: params[:status])
      end

      # 在庫量でフィルタリング（在庫切れ商品のみ表示）
      if params[:low_stock] == "true"
        query = query.where("quantity <= 0")
      end

      # 並び替え
      order_column = "updated_at"
      order_direction = "DESC"

      if params[:sort].present?
        case params[:sort]
        when "name"
          order_column = "name"
        when "price"
          order_column = "price"
        when "quantity"
          order_column = "quantity"
        end
      end

      if params[:direction].present? && %w[asc desc].include?(params[:direction].downcase)
        order_direction = params[:direction].upcase
      end

      query.order("#{order_column} #{order_direction}")
    end

    # 高度な検索（AdvancedSearchQueryを使用）
    def advanced_search(params)
      query = AdvancedSearchQuery.build

      # 条件に応じて必要な関連データのみをinclude
      includes_array = []
      
      # バッチ関連の検索がある場合のみ:batchesをinclude
      if params[:lot_code].present? || params[:expires_before].present? || params[:expires_after].present? || params[:expiring_soon].present?
        includes_array << :batches
      end
      
      # 出荷関連の検索がある場合
      if params[:shipment_status].present? || params[:destination].present?
        includes_array << :shipments
      end
      
      # 入荷関連の検索がある場合
      if params[:receipt_status].present? || params[:source].present?
        includes_array << :receipts
      end
      
      # ログ関連の検索がある場合（現在は直接的な条件はないが、将来の拡張用）
      # includes_array << :inventory_logs if params[:log_search].present?
      
      # 必要な関連データがある場合のみincludesを適用
      query = query.includes(includes_array) if includes_array.any?

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
        query = query.where("quantity > ?", params[:low_stock_threshold]&.to_i || 10)
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

      # 従来の互換性のためのresults呼び出し
      query.results
    end

    # SearchResult形式での結果取得（推奨）
    def advanced_search_with_result(params)
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
        query = query.where("quantity > ?", params[:low_stock_threshold]&.to_i || 10)
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

      # SearchResult形式で結果を返す
      # TODO: AdvancedSearchQueryでもexecuteメソッドを実装予定
      # 現在は簡易版で対応
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      results = query.results
      paginated_results = results.page(params[:page] || 1).per(params[:per_page] || 20)
      total_count = results.count

      execution_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      SearchResult.new(
        records: paginated_results,
        total_count: total_count,
        current_page: (params[:page] || 1).to_i,
        per_page: (params[:per_page] || 20).to_i,
        conditions_summary: build_conditions_summary(params),
        query_metadata: {
          search_type: "advanced",
          complex_query: true,
          or_conditions_count: params[:or_conditions]&.size || 0
        },
        execution_time: execution_time,
        search_params: params.except(:controller, :action, :format)
      )
    end

    # 条件サマリーの構築
    def build_conditions_summary(params)
      conditions = []

      conditions << "キーワード: #{params[:q]}" if params[:q].present?
      conditions << "ステータス: #{params[:status]}" if params[:status].present?
      conditions << "在庫状態: #{params[:stock_filter]}" if params[:stock_filter].present?
      conditions << "価格範囲: #{params[:min_price]}〜#{params[:max_price]}円" if params[:min_price].present? || params[:max_price].present?
      conditions << "作成日: #{params[:created_from]}〜#{params[:created_to]}" if params[:created_from].present? || params[:created_to].present?
      conditions << "ロット: #{params[:lot_code]}" if params[:lot_code].present?
      conditions << "期限切れ間近" if params[:expiring_soon].present?
      conditions << "最近更新" if params[:recently_updated].present?

      conditions.empty? ? "すべて" : conditions.join(", ")
    end

    # 統一的な検索呼び出しメソッド（SearchResult対応版）
    def call_with_result(params)
      if complex_search_required?(params)
        advanced_search_with_result(params)
      else
        simple_search_with_result(params)
      end
    end

    # シンプル検索のSearchResult版
    def simple_search_with_result(params)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      query = Inventory.all

      # キーワード検索
      if params[:q].present?
        query = query.where("name LIKE ?", "%#{params[:q]}%")
      end

      # ステータスでフィルタリング
      if params[:status].present? && Inventory::STATUSES.include?(params[:status])
        query = query.where(status: params[:status])
      end

      # 在庫量でフィルタリング（在庫切れ商品のみ表示）
      if params[:low_stock] == "true"
        query = query.where("quantity <= 0")
      end

      # 並び替え
      order_column = "updated_at"
      order_direction = "DESC"

      if params[:sort].present?
        case params[:sort]
        when "name"
          order_column = "name"
        when "price"
          order_column = "price"
        when "quantity"
          order_column = "quantity"
        end
      end

      if params[:direction].present? && %w[asc desc].include?(params[:direction].downcase)
        order_direction = params[:direction].upcase
      end

      query = query.order("#{order_column} #{order_direction}")

      # ページネーション
      paginated_query = query.page(params[:page] || 1).per(params[:per_page] || 20)
      total_count = query.count

      execution_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

      SearchResult.new(
        records: paginated_query,
        total_count: total_count,
        current_page: (params[:page] || 1).to_i,
        per_page: (params[:per_page] || 20).to_i,
        conditions_summary: build_simple_conditions_summary(params),
        query_metadata: {
          search_type: "simple",
          complex_query: false
        },
        execution_time: execution_time,
        search_params: params.except(:controller, :action, :format)
      )
    end

    # シンプル検索の条件サマリー
    def build_simple_conditions_summary(params)
      conditions = []

      conditions << "キーワード: #{params[:q]}" if params[:q].present?
      conditions << "ステータス: #{params[:status]}" if params[:status].present?
      conditions << "在庫切れのみ" if params[:low_stock] == "true"

      conditions.empty? ? "すべて" : conditions.join(", ")
    end

    # 複雑な検索が必要かどうかを判定
    def complex_search_required?(params)
      # 以下のいずれかの条件がある場合は複雑な検索を使用
      [
        params[:min_price].present?,
        params[:max_price].present?,
        params[:created_from].present?,
        params[:created_to].present?,
        params[:lot_code].present?,
        params[:expires_before].present?,
        params[:expires_after].present?,
        params[:expiring_soon].present?,
        params[:recently_updated].present?,
        params[:shipment_status].present?,
        params[:destination].present?,
        params[:receipt_status].present?,
        params[:source].present?,
        params[:or_conditions].present?,
        params[:complex_condition].present?,
        params[:stock_filter].present?
      ].any?
    end

    # 複雑な条件を構築
    def build_complex_condition(query, condition)
      return query unless condition.is_a?(Hash)

      query.complex_where do |q|
        condition.each do |type, sub_conditions|
          case type.to_s
          when "and"
            sub_conditions.each { |cond| q = q.where(cond) }
          when "or"
            # OR条件を安全に構築
            if sub_conditions.is_a?(Array) && sub_conditions.any?
              # AdvancedSearchQueryのwhere_anyメソッドを使用
              q = q.where_any(sub_conditions)
            end
          end
        end
      end
    end
  end
end
