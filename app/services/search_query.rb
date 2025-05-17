# frozen_string_literal: true

# 検索クエリを処理するサービスクラス
class SearchQuery
  class << self
    def call(params)
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
  end
end
