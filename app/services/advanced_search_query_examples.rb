# frozen_string_literal: true

# AdvancedSearchQueryの使用例
# このファイルは、複雑な検索を実装する際の参考例です

class AdvancedSearchQueryExamples
  class << self
    # 例1: 基本的なAND条件での検索
    def basic_and_search
      AdvancedSearchQuery.build
        .where(status: "active")
        .where("quantity > ?", 0)
        .where("price < ?", 100)
        .results
    end

    # 例2: OR条件を使った検索
    def or_condition_search
      AdvancedSearchQuery.build
        .where(name: "Product A")
        .or_where(name: "Product B")
        .or_where(name: "Product C")
        .results
    end

    # 例3: 複数のOR条件をまとめて適用
    def multiple_or_conditions
      AdvancedSearchQuery.build
        .where_any([
          { quantity: 0 },                    # 在庫切れ
          { status: "archived" },             # アーカイブ済み
          ["price > ?", 1000],               # 高額商品
          ["updated_at < ?", 30.days.ago]    # 長期間更新なし
        ])
        .results
    end

    # 例4: 複雑なAND/ORの組み合わせ
    def complex_and_or_combination
      AdvancedSearchQuery.build
        .complex_where do
          # (status = 'active' AND (quantity < 10 OR price > 500))
          and do
            where(status: "active")
            or do
              where("quantity < ?", 10)
              where("price > ?", 500)
            end
          end
        end
        .results
    end

    # 例5: キーワード検索と範囲検索の組み合わせ
    def keyword_and_range_search(keyword, min_price, max_price)
      AdvancedSearchQuery.build
        .search_keywords(keyword, fields: [:name, :description])
        .in_range("price", min_price, max_price)
        .with_status("active")
        .results
    end

    # 例6: バッチ（ロット）関連の検索
    def batch_related_search
      AdvancedSearchQuery.build
        .with_batch_conditions do
          lot_code("LOT")                       # ロットコードに"LOT"を含む
          expires_before(30.days.from_now)     # 30日以内に期限切れ
          quantity_greater_than(0)              # 在庫あり
        end
        .results
    end

    # 例7: 期限切れ間近の商品を優先度順に取得
    def expiring_items_priority_list
      AdvancedSearchQuery.build
        .expiring_soon(14)  # 14日以内に期限切れ
        .with_status("active")
        .order_by_multiple(
          "batches.expires_on" => :asc,  # 期限が近い順
          quantity: :desc                 # 在庫量が多い順
        )
        .results
    end

    # 例8: 在庫ログを使った操作履歴検索
    def inventory_activity_search(user_id, days_ago = 7)
      AdvancedSearchQuery.build
        .with_inventory_log_conditions do
          by_user(user_id)
          changed_after(days_ago.days.ago)
          action_type("decrement")  # 出庫操作のみ
        end
        .distinct
        .results
    end

    # 例9: 出荷状況による検索
    def shipment_status_search
      AdvancedSearchQuery.build
        .with_shipment_conditions do
          status("pending")                    # 出荷待ち
          scheduled_after(Date.current)        # 本日以降の予定
          destination_like("東京")             # 東京向け
        end
        .order_by("shipments.scheduled_date", :asc)
        .results
    end

    # 例10: 入荷履歴とコスト分析
    def receipt_cost_analysis(min_cost, max_cost)
      AdvancedSearchQuery.build
        .with_receipt_conditions do
          status("received")
          cost_range(min_cost, max_cost)
          received_after(3.months.ago)
        end
        .order_by("receipts.cost", :desc)
        .results
    end

    # 例11: ポリモーフィック関連（監査ログ）を使った検索
    def audit_trail_search(user_id, action = "update")
      AdvancedSearchQuery.build
        .with_audit_conditions do
          by_user(user_id)
          action(action)
          changed_fields_include("quantity")  # 数量変更を含む
          created_after(1.week.ago)
        end
        .results
    end

    # 例12: 複数テーブルを跨いだ複合検索
    def cross_table_complex_search
      AdvancedSearchQuery.build
        # 基本条件
        .with_status("active")
        .where("inventories.quantity > ?", 0)
        
        # バッチ条件
        .with_batch_conditions do
          expires_after(Date.current)  # 期限切れでない
        end
        
        # 最近の入荷がある
        .with_receipt_conditions do
          received_after(1.month.ago)
          status("received")
        end
        
        # 出荷予定がない
        .where.not(
          id: Inventory.joins(:shipments)
            .where(shipments: { status: ["pending", "preparing"] })
            .select(:id)
        )
        
        .distinct
        .order_by(:name)
        .results
    end

    # 例13: 在庫アラート対象の検索
    def stock_alert_candidates
      AdvancedSearchQuery.build
        .complex_where do
          or do
            # 在庫切れ
            where("inventories.quantity = ?", 0)
            
            # 低在庫（10個以下）
            and do
              where("inventories.quantity > ?", 0)
              where("inventories.quantity <= ?", 10)
            end
            
            # 期限切れ間近（7日以内）
            where(
              id: Inventory.joins(:batches)
                .where("batches.expires_on BETWEEN ? AND ?", Date.current, 7.days.from_now)
                .select(:id)
            )
          end
        end
        .with_status("active")
        .distinct
        .results
    end

    # 例14: パフォーマンスを考慮した大量データ検索
    def optimized_large_dataset_search(page = 1)
      AdvancedSearchQuery.build
        .with_status("active")
        .where("inventories.updated_at > ?", 1.month.ago)
        
        # 必要なカラムのみ選択
        .where.not(quantity: 0)
        
        # インデックスを活用したソート
        .order_by(:updated_at, :desc)
        
        # ページネーション
        .paginate(page: page, per_page: 50)
        .results
    end

    # 例15: 動的な検索条件の構築
    def dynamic_search(params)
      query = AdvancedSearchQuery.build

      # キーワード検索
      if params[:keyword].present?
        query = query.search_keywords(params[:keyword])
      end

      # ステータスフィルター
      if params[:status].present?
        query = query.with_status(params[:status])
      end

      # 価格範囲
      if params[:min_price].present? || params[:max_price].present?
        query = query.in_range("price", params[:min_price], params[:max_price])
      end

      # 在庫状態
      case params[:stock_status]
      when "out_of_stock"
        query = query.out_of_stock
      when "low_stock"
        query = query.low_stock(params[:low_stock_threshold] || 10)
      when "in_stock"
        query = query.where("quantity > ?", params[:low_stock_threshold] || 10)
      end

      # 期限切れフィルター
      if params[:expiring_soon].present?
        query = query.expiring_soon(params[:expiring_days] || 30)
      end

      # ソート
      sort_field = params[:sort] || "updated_at"
      sort_direction = params[:direction] || "desc"
      query = query.order_by(sort_field, sort_direction)

      # ページネーション
      query.paginate(
        page: params[:page] || 1,
        per_page: params[:per_page] || 20
      ).results
    end
  end
end