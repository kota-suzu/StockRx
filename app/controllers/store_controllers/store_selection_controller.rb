# frozen_string_literal: true

module StoreControllers
  # 店舗選択画面コントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # ログイン前の店舗選択機能を提供
  # ============================================
  class StoreSelectionController < ApplicationController
    include StoreAuthenticatable
    
    # 認証不要（ログイン前のアクセス）
    # ApplicationControllerには authenticate_admin! が定義されていないため、
    # このスキップは不要

    # レイアウト設定
    layout "store_selection"

    # ============================================
    # アクション
    # ============================================

    # 店舗一覧表示
    def index
      @stores = Store.active
                     .order(:store_type, :name)
                     .includes(:store_inventories)

      # 店舗タイプ別にグループ化
      @stores_by_type = @stores.group_by(&:store_type)

      # 最近アクセスした店舗（Cookieから取得）
      @recent_store_slugs = recent_stores_from_cookie
      @recent_stores = Store.where(slug: @recent_store_slugs).index_by(&:slug)
    end

    # 特定店舗のログインページ表示
    def show
      @store = Store.active.find_by!(slug: params[:slug])

      # より厳密な認証チェック：完全にログインしており、同じ店舗の場合のみダッシュボードへ
      # CLAUDE.md準拠: セキュリティ最優先の認証判定
      if store_signed_in? && current_store_user.store == @store && current_store.active?
        redirect_to store_root_path and return
      end

      # 不完全な認証状態の場合はセッションをクリア（CLAUDE.md: セキュリティ最優先）
      # メタ認知: store_user_signed_in?だけでなく、店舗の整合性も確認する必要性
      if store_user_signed_in? && (current_store_user.store != @store || !current_store&.active?)
        # TODO: Phase 4 - セキュリティ強化（推定1日）
        # 実装予定:
        #   - 監査ログに記録（不正アクセス試行の可能性）
        #   - セキュリティアラート機能
        #   - IP制限・デバイス認証との連携
        #   - 横展開: 他の認証箇所でも同様の保護を実装
        sign_out(:store_user)
        Rails.logger.info "Cleared invalid store session for store: #{@store.slug}, " \
                         "user_store: #{current_store_user.store&.slug}, " \
                         "ip: #{request.remote_ip}"
      end

      # 最近アクセスした店舗として記録
      save_to_recent_stores(@store.slug)

      # 店舗ユーザーのログインページへリダイレクト
      redirect_to new_store_user_session_path(store_slug: @store.slug)
    end

    private

    # ============================================
    # Cookie管理
    # ============================================

    # 最近アクセスした店舗をCookieから取得
    def recent_stores_from_cookie
      return [] unless cookies[:recent_stores].present?

      JSON.parse(cookies[:recent_stores])
    rescue JSON::ParserError
      []
    end

    # 最近アクセスした店舗として保存（最大5件）
    def save_to_recent_stores(slug)
      recent = recent_stores_from_cookie
      recent.delete(slug) # 既存のものは削除
      recent.unshift(slug) # 先頭に追加
      recent = recent.first(5) # 最大5件

      cookies[:recent_stores] = {
        value: recent.to_json,
        expires: 30.days.from_now,
        httponly: true
      }
    end

    # ============================================
    # ビューヘルパー
    # ============================================

    # 店舗タイプの表示名
    helper_method :store_type_display_name
    def store_type_display_name(type)
      I18n.t("activerecord.attributes.store.store_types.#{type}", default: type.humanize)
    end

    # 店舗タイプのアイコンクラス
    helper_method :store_type_icon_class
    def store_type_icon_class(type)
      case type
      when "pharmacy"
        "fas fa-prescription-bottle-alt"
      when "warehouse"
        "fas fa-warehouse"
      when "headquarters"
        "fas fa-building"
      else
        "fas fa-store"
      end
    end

    # 店舗の状態表示
    helper_method :store_status_badge
    def store_status_badge(store)
      if store.store_inventories.count.zero?
        { text: "準備中", class: "badge bg-secondary" }
      elsif store.low_stock_items_count > 0
        { text: "在庫不足: #{store.low_stock_items_count}件",
          class: "badge bg-warning text-dark" }
      else
        { text: "正常稼働中", class: "badge bg-success" }
      end
    end
  end
end

# ============================================
# TODO: Phase 4以降の拡張予定（CLAUDE.md準拠）
# ============================================
# 
# 🔴 Phase 4: セキュリティ強化（優先度: 高、推定3日）
# 1. 認証セキュリティ
#    - 店舗間のセッション漏洩検出・防止機能
#    - 不正アクセス試行の自動検出とアラート
#    - デバイス認証・IP制限との統合
#    - 横展開: BaseController等での同様保護実装
#
# 🟡 Phase 5: UX/利便性向上（優先度: 中、推定2日）
# 1. 店舗検索機能
#    - 地域別フィルタリング
#    - 店舗名での部分一致検索
#    - 最近アクセス履歴の改善（Cookie→DB保存）
#
# 2. 営業時間表示
#    - 現在の営業状態表示（リアルタイム）
#    - 次回営業開始時刻の案内
#    - 営業時間外アクセス時の適切な案内
#
# 🟢 Phase 6: 地図・位置情報（優先度: 低、推定5日）
# 1. 地図表示
#    - 店舗位置の地図表示（Google Maps API）
#    - 最寄り店舗の自動提案
#    - GPS連携での距離表示
#
# ============================================
# メタ認知的改善ポイント
# ============================================
# 1. 認証状態の整合性チェック強化の必要性
# 2. エラーログの構造化（JSON形式での出力）
# 3. セキュリティインシデント対応手順の文書化
# 4. 他コントローラーへの横展開適用チェックリスト作成
