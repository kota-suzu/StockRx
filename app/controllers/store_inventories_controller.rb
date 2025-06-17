# frozen_string_literal: true

# 店舗別公開在庫一覧コントローラー
# ============================================
# Phase 3: マルチストア対応
# 認証不要の公開情報として基本的な在庫情報を提供
# CLAUDE.md準拠: セキュリティ最優先、機密情報の適切なマスキング
# ============================================
class StoreInventoriesController < ApplicationController
  # セキュリティ対策
  include SecurityHeaders

  # 認証不要（公開情報）
  # CLAUDE.md準拠: 公開APIは認証不要だが、セキュリティ対策は必須
  # Note: ApplicationControllerには認証フィルターがないため、skip不要

  before_action :set_store
  before_action :check_store_active
  before_action :apply_rate_limiting

  # TODO: Phase 2 - Redis導入後、より高度なキャッシュ戦略実装
  #   - 店舗別・カテゴリ別のキャッシュキー設計
  #   - 在庫更新時の自動キャッシュ無効化
  #   - 横展開: 他の公開APIでも同様のキャッシュ戦略適用

  # ============================================
  # アクション
  # ============================================

  # 店舗在庫一覧（公開情報）
  def index
    # N+1クエリ完全回避（CLAUDE.md: パフォーマンス最適化）
    @store_inventories = @store.store_inventories
                              .joins(:inventory)
                              .includes(:inventory)
                              .merge(Inventory.where(status: :active)) # 有効な在庫のみ
                              .select(public_inventory_columns)
                              .order(sort_column => sort_direction)
                              .page(params[:page])
                              .per(per_page_limit)

    # 統計情報（公開可能な範囲のみ）
    @statistics = calculate_public_statistics

    respond_to do |format|
      format.html
      format.json { render json: public_inventory_json }
    end
  end

  # 在庫検索API（公開）
  # TODO: Phase 3 - Elasticsearch統合
  #   - 全文検索機能
  #   - ファセット検索
  #   - 検索結果のスコアリング
  def search
    query = params[:q].to_s.strip

    if query.blank?
      render json: { error: "検索キーワードを入力してください" }, status: :bad_request
      return
    end

    # 基本的な検索（LIKE検索）
    # TODO: Phase 3 - より高度な検索機能実装
    results = @store.store_inventories
                   .joins(:inventory)
                   .where("inventories.name LIKE :query OR inventories.sku LIKE :query",
                         query: "%#{sanitize_sql_like(query)}%")
                   .merge(Inventory.where(status: :active))
                   .select(public_inventory_columns)
                   .limit(20)

    render json: {
      query: query,
      count: results.count,
      items: results.map { |si| public_inventory_data(si) }
    }
  end

  private

  # ============================================
  # 共通処理
  # ============================================

  def set_store
    @store = Store.find_by(id: params[:store_id])

    unless @store
      respond_to do |format|
        format.html { redirect_to stores_path, alert: "指定された店舗が見つかりません" }
        format.json { render json: { error: "Store not found" }, status: :not_found }
      end
    end
  end

  def check_store_active
    return if @store&.active?

    respond_to do |format|
      format.html { redirect_to stores_path, alert: "この店舗は現在利用できません" }
      format.json { render json: { error: "Store is not active" }, status: :forbidden }
    end
  end

  # レート制限（簡易実装）
  # TODO: Phase 2 - Rack::Attack導入で本格実装
  def apply_rate_limiting
    # セッションベースの簡易レート制限
    session[:api_requests] ||= []
    session[:api_requests] = session[:api_requests].select { |time| time > 1.minute.ago }

    if session[:api_requests].count >= 60
      respond_to do |format|
        format.html { redirect_to stores_path, alert: "リクエスト数が制限を超えました。しばらくお待ちください。" }
        format.json { render json: { error: "Rate limit exceeded" }, status: :too_many_requests }
      end
      return
    end

    session[:api_requests] << Time.current
  end

  # ============================================
  # データ処理
  # ============================================

  # 公開可能なカラムのみ選択（セキュリティ対策）
  def public_inventory_columns
    # 機密情報（原価、仕入先等）は除外
    # TODO: 🔴 Phase 4（緊急）- categoryカラム追加後、inventories.categoryを復活
    # 現在はスキーマに存在しないため除外
    # TODO: 🔴 Phase 1（緊急）- manufacturerカラム追加後、inventories.manufacturerを復活
    # 現在はスキーマに存在しないため除外（エラーの原因）
    %w[
      store_inventories.id
      store_inventories.quantity
      store_inventories.updated_at
      inventories.id as inventory_id
      inventories.name
      inventories.sku
      inventories.unit
    ].join(", ")
  end

  # 公開用統計情報
  def calculate_public_statistics
    # TODO: 🔴 Phase 4（緊急）- categoryカラム追加の検討
    # 優先度: 高（機能完成度向上）
    # 実装内容: マイグレーションでcategoryカラム追加後、正確なカテゴリ分析が可能

    # 暫定実装: パターンベースカテゴリ数カウント
    # CLAUDE.md準拠: スキーマ不一致問題の解決（category不存在）
    # 横展開: 他コントローラーと同様のパターンマッチング手法活用
    inventories = @store.inventories.where(status: :active).select(:id, :name)
    category_count = inventories.map { |inv| categorize_by_name(inv.name) }
                                .uniq
                                .compact
                                .count

    {
      total_items: @store_inventories.count,
      categories: category_count,
      last_updated: @store.store_inventories.maximum(:updated_at),
      store_info: {
        name: @store.name,
        type: @store.store_type_text,
        address: @store.address
      }
    }
  end

  # JSON用データ整形
  def public_inventory_data(store_inventory)
    {
      id: store_inventory.inventory_id,
      name: store_inventory.inventory.name,
      sku: store_inventory.inventory.sku,
      category: categorize_by_name(store_inventory.inventory.name),
      # TODO: 🔴 Phase 1（緊急）- manufacturerカラム追加後に有効化
      # manufacturer: store_inventory.inventory.manufacturer,
      manufacturer: "未設定",  # 暫定値
      unit: store_inventory.inventory.unit,
      stock_status: stock_status(store_inventory.quantity),
      last_updated: store_inventory.updated_at.iso8601
    }
  end

  def public_inventory_json
    {
      store: {
        id: @store.id,
        name: @store.name,
        type: @store.store_type
      },
      statistics: @statistics,
      inventories: @store_inventories.map { |si| public_inventory_data(si) },
      pagination: {
        current_page: @store_inventories.current_page,
        total_pages: @store_inventories.total_pages,
        total_count: @store_inventories.total_count
      }
    }
  end

  # 在庫ステータス（数量は非公開）
  def stock_status(quantity)
    case quantity
    when 0
      "out_of_stock"
    when 1..10
      "low_stock"
    else
      "in_stock"
    end
  end

  # ============================================
  # ソート・ページネーション
  # ============================================

  def sort_column
    # 公開情報のみソート可能
    # TODO: 🔴 Phase 4（緊急）- categoryカラム追加後、inventories.categoryソート機能復旧
    # 現在はスキーマに存在しないため除外
    %w[inventories.name inventories.sku].include?(params[:sort]) ?
      params[:sort] : "inventories.name"
  end

  def sort_direction
    %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
  end

  def per_page_limit
    # 公開APIは最大50件/ページに制限
    [ params[:per_page].to_i, 50 ].min.then { |n| n > 0 ? n : 25 }
  end

  # キャッシュキー生成
  def store_inventories_cache_key
    "store_inventories/#{@store.id}/#{params[:page]}/#{sort_column}/#{sort_direction}"
  end

  # SQL Like演算子のサニタイズ
  # CLAUDE.md準拠: SQLインジェクション対策の徹底
  def sanitize_sql_like(string)
    # 危険な文字をエスケープ
    string.gsub(/[%_\\]/, '\\\\\\&')
  end

  # XSS対策: 出力時のエスケープ
  # TODO: Phase 4 - Content Security Policyの強化
  #   - インラインスクリプトの完全排除
  #   - nonceベースのスクリプト管理
  #   - 外部リソースのホワイトリスト化
  def sanitize_output(text)
    CGI.escapeHTML(text.to_s)
  end

  # 商品名からカテゴリを推定するヘルパーメソッド
  # CLAUDE.md準拠: ベストプラクティス - 推定ロジックの明示化
  # 横展開: dashboard_controller.rb、inventories_controller.rb、admin store_inventories_controller.rbと同一ロジック
  def categorize_by_name(product_name)
    # 医薬品キーワード
    medicine_keywords = %w[錠 カプセル 軟膏 点眼 坐剤 注射 シロップ 細粒 顆粒 液 mg IU
                         アスピリン パラセタモール オメプラゾール アムロジピン インスリン
                         抗生 消毒 ビタミン プレドニゾロン エキス]

    # 医療機器キーワード
    device_keywords = %w[血圧計 体温計 パルスオキシメーター 聴診器 測定器]

    # 消耗品キーワード
    supply_keywords = %w[マスク 手袋 アルコール ガーゼ 注射針]

    # サプリメントキーワード
    supplement_keywords = %w[ビタミン サプリ オメガ プロバイオティクス フィッシュオイル]

    case product_name
    when /#{device_keywords.join('|')}/i
      "医療機器"
    when /#{supply_keywords.join('|')}/i
      "消耗品"
    when /#{supplement_keywords.join('|')}/i
      "サプリメント"
    when /#{medicine_keywords.join('|')}/i
      "医薬品"
    else
      "その他"
    end
  end
end

# ============================================
# TODO: Phase 2以降の拡張予定（CLAUDE.md準拠）
# ============================================
#
# 🔴 Phase 2: セキュリティ強化（優先度: 高、推定2日）
# 1. アクセス制御
#    - IP制限機能（許可リスト管理）
#    - APIキー認証（B2B連携用）
#    - Rack::Attack統合（DDoS対策）
#    - 横展開: 全公開APIで同様のセキュリティ実装
#
# 🟡 Phase 3: 検索機能強化（優先度: 中、推定3日）
# 1. 高度な検索
#    - Elasticsearch統合
#    - カテゴリ別フィルタリング
#    - 在庫状況フィルタリング
#    - 検索履歴・サジェスト機能
#
# 🟢 Phase 4: パフォーマンス最適化（優先度: 低、推定5日）
# 1. キャッシュ戦略
#    - CDN統合（静的コンテンツ）
#    - GraphQL API（効率的なデータ取得）
#    - リアルタイム在庫更新（WebSocket）
#
# ============================================
# メタ認知的改善ポイント
# ============================================
# 1. **情報公開レベルの慎重な設計**
#    - 価格情報は非公開（競合対策）
#    - 具体的な在庫数は非公開（セキュリティ）
#    - 仕入先情報は完全非公開（機密保持）
#
# 2. **段階的な機能拡張**
#    - 基本機能から着実に実装
#    - セキュリティを後回しにしない
#    - パフォーマンスは測定してから最適化
#
# 3. **横展開の意識**
#    - 他の公開APIでも同様の設計パターン適用
#    - 認証・認可の一貫性確保
#    - エラーハンドリングの統一
