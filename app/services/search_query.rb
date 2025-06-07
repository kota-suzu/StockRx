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

      query.order("#{order_column} #{order_direction}")
    end

    # 高度な検索（AdvancedSearchQueryを使用）
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

      query.results
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
            # OR条件は単一のWHERE句として結合
            or_conditions = sub_conditions.map { |cond|
              cond.is_a?(Hash) ? cond.map { |k, v| "#{k} = #{ActiveRecord::Base.connection.quote(v)}" }.join(" AND ") : cond
            }.join(" OR ")
            q = q.where(or_conditions) if or_conditions.present?
          end
        end
      end
    end
  end
end
