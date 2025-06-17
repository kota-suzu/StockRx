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
      # Counter Cache使用のため、includesは不要（N+1クエリ完全解消）
      # TODO: Phase 1 - Counter Cache整合性の定期チェック機能実装
      # - 開発環境: Counter Cache値の自動検証
      # - 本番環境: 定期的な整合性チェックバッチ処理
      # - 横展開確認: 他のCounter Cache使用箇所でも同様の最適化適用
      @stores = Store.active
                     .order(:store_type, :name)

      # 店舗タイプ別にグループ化
      @stores_by_type = @stores.group_by(&:store_type)

      # 最近アクセスした店舗（Cookieから取得）
      @recent_store_slugs = recent_stores_from_cookie
      @recent_stores = Store.where(slug: @recent_store_slugs).index_by(&:slug)
    end

    # 特定店舗のログインページ表示
    def show
      # 店舗検索（CLAUDE.md: セキュリティ最優先 - 不正なslugへの対策）
      @store = Store.active.find_by(slug: params[:slug])

      unless @store
        Rails.logger.warn "Store not found or inactive: slug=#{params[:slug]}, ip=#{request.remote_ip}"
        redirect_to store_selection_path,
                    alert: I18n.t("errors.messages.store_not_found") and return
      end

      # より厳密な認証チェック：完全にログインしており、同じ店舗の場合のみダッシュボードへ
      # CLAUDE.md準拠: セキュリティ最優先の認証判定
      begin
        # デバッグ情報の詳細ログ出力（CLAUDE.md: 問題解決のための可視化）
        store_signed_in_check = store_signed_in?
        store_user_signed_in_check = store_user_signed_in?
        current_store_check = current_store&.id
        current_store_active_check = current_store&.active?
        current_store_user_store_check = current_store_user&.store&.id
        target_store_check = @store.id

        Rails.logger.debug "AUTH_DEBUG: store_signed_in=#{store_signed_in_check}, " \
                          "store_user_signed_in=#{store_user_signed_in_check}, " \
                          "current_store_id=#{current_store_check}, " \
                          "current_store_active=#{current_store_active_check}, " \
                          "user_store_id=#{current_store_user_store_check}, " \
                          "target_store_id=#{target_store_check}"

        if store_signed_in? && current_store_user&.store == @store && current_store&.active?
          Rails.logger.info "AUTH_SUCCESS: Redirecting to dashboard for store #{@store.slug}, user: #{current_store_user&.email}"
          redirect_to store_root_path and return
        end
      rescue => e
        # 認証チェック中の例外をログ記録し、セッションクリア（CLAUDE.md: セキュリティ最優先）
        Rails.logger.error "Store authentication check failed: #{e.message}, store: #{@store.slug}, ip: #{request.remote_ip}"
        sign_out(:store_user) if store_user_signed_in?
      end

      # 異なる店舗へのアクセス時の処理（CLAUDE.md: セキュリティ最優先）
      # メタ認知: マルチテナント環境では店舗間の厳格な分離が必要
      if store_user_signed_in? && (current_store_user&.store != @store || !current_store&.active?)
        begin
          # sign_out前にユーザー情報を保存（CLAUDE.md: ベストプラクティス適用）
          current_user_store_slug = current_store_user&.store&.slug || "unknown"
          current_user_email = current_store_user&.email || "unknown"
          current_user_name = current_store_user&.name || "unknown"
          user_ip = request.remote_ip

          # 異なる店舗アクセスの理由を判定
          access_reason = if current_store_user&.store != @store
                           "different_store_access"
          elsif !current_store&.active?
                           "inactive_store_session"
          else
                           "unknown_reason"
          end

          sign_out(:store_user)

          # 情報ログ記録（正常な店舗切り替えの可能性もあるためINFOレベル）
          Rails.logger.info "Store session cleared for cross-store access - " \
                           "reason: #{access_reason}, " \
                           "from_store: #{current_user_store_slug}, " \
                           "to_store: #{@store.slug}, " \
                           "user: #{current_user_name}(#{current_user_email}), " \
                           "ip: #{user_ip}"

          # UX改善: 店舗切り替えの場合は専用メッセージとリダイレクト先変更
          if access_reason == "different_store_access"
            # 店舗切り替えを明確に伝えるメッセージ
            flash[:info] = "#{current_user_store_slug}から#{@store.slug}への店舗切り替えのため、再度ログインしてください。"

            # 店舗切り替えの場合は直接ログインページへ（UX改善）
            redirect_to new_store_user_session_path(store_slug: @store.slug) and return
          end

          # TODO: Phase 4 - セキュリティ強化（推定1日）
          # 実装予定:
          #   - 監査ログに記録（不正アクセス試行の可能性）
          #   - セキュリティアラート機能
          #   - IP制限・デバイス認証との連携
          #   - 横展開: 他の認証箇所でも同様の保護を実装
        rescue => e
          # セッションクリア処理での例外ハンドリング（CLAUDE.md: 堅牢性確保）
          Rails.logger.error "Session cleanup failed: #{e.message}, store: #{@store.slug}, ip: #{request.remote_ip}"
          # セッション全体をクリア
          reset_session
        end
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

    # 店舗タイプのアイコンクラス（Bootstrap Icons統一）
    # CLAUDE.md準拠: 管理画面との一貫性確保
    helper_method :store_type_icon_class
    def store_type_icon_class(type)
      case type
      when "pharmacy"
        "bi bi-capsule"
      when "warehouse"
        "bi bi-building"
      when "headquarters"
        "bi bi-building-gear"
      else
        "bi bi-shop"
      end
    end

    # 店舗の状態表示
    helper_method :store_status_badge
    def store_status_badge(store)
      # Counter Cacheを使用してN+1クエリ解消
      if store.store_inventories_count.zero?
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
# メタ認知的改善ポイント（今回の問題から得た教訓）
# ============================================
# 1. **nil安全性の確保**: sign_out後のcurrentユーザー参照回避
#    - 横展開チェック: 全認証関連メソッドで同様パターン確認済み
#    - ベストプラクティス: 操作前の状態保存パターン確立
#
# 2. **包括的エラーハンドリング**:
#    - 認証チェック時の例外処理追加
#    - セッションクリア処理の堅牢性確保
#    - ログ記録の詳細化（セキュリティ観点）
#
# 3. **セキュリティログの改善**:
#    - より詳細な情報記録（email, user_agent等）
#    - 重要度に応じたログレベル設定（WARN/ERROR）
#    - 不正アクセス試行の可視化強化
#
# 4. **今後の横展開適用チェックリスト**:
#    - [ ] 全コントローラーでのsign_out使用箇所確認
#    - [ ] currentユーザー参照のnil安全性監査
#    - [ ] 認証例外処理の標準化
#    - [ ] セキュリティログ記録の一元化
