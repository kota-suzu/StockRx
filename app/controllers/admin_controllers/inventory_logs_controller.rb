# frozen_string_literal: true

module AdminControllers
  # 在庫変動履歴管理コントローラー
  # ============================================
  # Phase 3: 管理機能の一元化（CLAUDE.md準拠）
  # 旧: /inventory_logs → 新: /admin/inventory_logs
  # ============================================
  class InventoryLogsController < BaseController
    # CLAUDE.md準拠: セキュリティ機能最適化
    # メタ認知: 在庫ログは読み取り専用（監査証跡）のため編集・削除操作なし
    # 横展開: 他の監査ログ系コントローラーでも同様の考慮が必要
    skip_around_action :audit_sensitive_data_access

    before_action :set_inventory, only: [ :index, :show ]
    PER_PAGE = 20  # 1ページあたりの表示件数

    # ============================================
    # アクション
    # ============================================

    # 特定の在庫アイテムのログ一覧を表示
    def index
      base_query = @inventory ? @inventory.inventory_logs.recent : InventoryLog.recent

      # 日付範囲フィルター（不正な日付形式はスキップ）
      apply_date_filter(base_query)

      # 管理者権限に応じたフィルタリング
      base_query = apply_permission_filter(base_query)

      @logs = base_query.includes(:inventory, :admin).page(params[:page]).per(PER_PAGE)

      respond_to do |format|
        format.html
        format.json { render json: logs_json }
        format.csv { send_data generate_csv(base_query), filename: csv_filename }
      end
    end

    # 特定のログ詳細を表示
    def show
      @log = find_log_with_permission
    end

    # システム全体のログを表示（本部管理者のみ）
    def all
      authorize_headquarters_admin!

      @logs = InventoryLog.includes(:inventory, :admin)
                         .recent
                         .page(params[:page])
                         .per(PER_PAGE)

      render :index
    end

    # 特定の操作種別のログを表示
    def by_operation
      @operation_type = params[:operation_type]

      base_query = InventoryLog.by_operation(@operation_type)
      base_query = apply_permission_filter(base_query)

      @logs = base_query.includes(:inventory, :admin)
                       .recent
                       .page(params[:page])
                       .per(PER_PAGE)

      render :index
    end

    private

    # ============================================
    # フィルタリング
    # ============================================

    def set_inventory
      @inventory = Inventory.find(params[:inventory_id]) if params[:inventory_id]
    end

    # 日付範囲フィルターの適用
    def apply_date_filter(query)
      begin
        if params[:start_date].present? || params[:end_date].present?
          start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : nil
          end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : nil
          @logs_query = query.by_date_range(start_date, end_date)
        else
          @logs_query = query
        end
      rescue Date::Error => e
        # 不正な日付形式の場合はflashメッセージを表示してフィルターをスキップ
        flash.now[:alert] = "日付の形式が正しくありません。フィルターは適用されませんでした。"
        Rails.logger.info("Invalid date format in inventory logs filter: #{e.message}")
        @logs_query = query
      end
    end

    # 権限に基づくフィルタリング
    def apply_permission_filter(query)
      if current_admin.store_manager? || current_admin.store_user?
        # 店舗管理者・ユーザーは自店舗の履歴のみ閲覧可能
        query.joins(inventory: :store_inventories)
             .where(store_inventories: { store_id: current_admin.store_id })
      else
        # 本部管理者は全履歴閲覧可能
        query
      end
    end

    # 権限チェック付きログ取得
    def find_log_with_permission
      log = InventoryLog.find(params[:id])

      # 店舗管理者の場合、自店舗のログのみ閲覧可能
      if current_admin.store_manager? || current_admin.store_user?
        unless log.inventory.store_inventories.exists?(store_id: current_admin.store_id)
          raise ActiveRecord::RecordNotFound
        end
      end

      log
    end

    # ============================================
    # レスポンス生成
    # ============================================

    # CLAUDE.md準拠: メタ認知 - JSONレスポンスのメソッド名不一致を修正
    # 横展開: 他のコントローラーでも同様のメソッド名確認が必要
    def logs_json
      @logs.map do |log|
        {
          id: log.id,
          inventory: {
            id: log.inventory.id,
            name: log.inventory.name
          },
          operation_type: log.operation_type,
          operation_type_text: log.operation_display_name,
          delta: log.delta,
          previous_quantity: log.previous_quantity,
          current_quantity: log.current_quantity,
          admin: {
            id: log.admin&.id,
            name: log.admin&.display_name
          },
          note: log.note,
          created_at: log.created_at.strftime("%Y-%m-%d %H:%M:%S")
        }
      end
    end

    def generate_csv(query)
      CSV.generate(headers: true) do |csv|
        csv << [
          "日時",
          "商品名",
          "操作種別",
          "変動数",
          "変動前在庫",
          "変動後在庫",
          "実行者",
          "備考"
        ]

        query.includes(:inventory, :admin).find_each do |log|
          csv << [
            log.created_at.strftime("%Y-%m-%d %H:%M:%S"),
            log.inventory.name,
            log.operation_display_name,
            log.delta,
            log.previous_quantity,
            log.current_quantity,
            log.admin&.display_name,
            log.note
          ]
        end
      end
    end

    def csv_filename
      if @inventory
        "inventory_logs-#{@inventory.name.gsub(/[^\w\-]/, '_')}-#{Date.today}.csv"
      else
        "inventory_logs-all-#{Date.today}.csv"
      end
    end

    # ============================================
    # 認可
    # ============================================

    def authorize_headquarters_admin!
      unless current_admin.headquarters_admin?
        redirect_to admin_root_path,
                    alert: "この操作は本部管理者のみ実行可能です。"
      end
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張予定
# ============================================
# 1. 🔴 高度なフィルタリング機能
#    - 複数条件の組み合わせ検索
#    - 保存可能な検索条件
#    - エクスポート条件の詳細設定
#
# 2. 🟡 分析機能の追加
#    - 在庫変動トレンド分析
#    - 異常検知（通常と異なる変動パターン）
#    - レポート自動生成
#
# 3. 🟢 監査ログ（AuditLog）との統合
#    - 統一的な履歴管理インターフェース
#    - クロスリファレンス機能
#    - コンプライアンスレポート
#
# 4. 🔴 Phase 1（緊急）- 関連付け命名規則の統一
#    - 全ログ系モデルでuser/admin関連付けの統一
#    - 既存ファクトリ・テストでの対応
#    - シードデータでの整合性確保
#    - ベストプラクティス: 意味的に正しい関連付け名の使用
#
# 5. 🟡 Phase 2（重要）- パフォーマンステスト実装
#    - N+1クエリ検出テスト（exceed_query_limit matcher活用）
#    - レスポンス時間ベンチマーク（目標: <200ms）
#    - 大量データでのパフォーマンス確認（10万件）
#    - CLAUDE.md準拠: AdminControllers全体でのN+1テスト横展開
