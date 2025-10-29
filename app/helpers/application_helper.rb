module ApplicationHelper
  # Modern UI v2 ヘルパーを含める
  # CLAUDE.md準拠: 最新UIトレンド対応のためのヘルパー統合
  include ModernUiHelper

  # GitHubアイコンのSVGを生成
  def github_icon(css_class: "github-icon")
    content_tag :svg,
                class: css_class,
                viewBox: "0 0 24 24",
                fill: "currentColor" do
      content_tag :path, "",
                  d: "M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"
    end
  end

  # フラッシュメッセージのクラス変換
  def flash_class(type)
    case type.to_s
    when "notice" then "success"
    when "alert" then "danger"
    when "error" then "danger"
    when "warning" then "warning"
    when "info" then "info"
    else type.to_s
    end
  end

  # アクティブなナビゲーションアイテムのクラス
  def active_class(path)
    current_page?(path) ? "active" : ""
  end

  # ============================================
  # Phase 5-2: 監査ログ関連ヘルパー
  # ============================================

  # 監査ログアクションの色クラス
  def audit_log_action_color(action)
    case action.to_s
    when "login", "signup" then "success"
    when "logout" then "info"
    when "failed_login" then "danger"
    when "create" then "success"
    when "update" then "warning"
    when "delete", "destroy" then "danger"
    when "view", "show" then "info"
    when "export" then "warning"
    when "permission_change" then "danger"
    when "password_change" then "warning"
    else "secondary"
    end
  end

  # セキュリティイベントの色クラス
  def security_event_color(action)
    case action.to_s
    when "failed_login", "rate_limit_exceeded", "suspicious_activity" then "danger"
    when "login_success", "password_changed" then "success"
    when "permission_granted", "access_granted" then "info"
    when "session_expired" then "warning"
    else "secondary"
    end
  end

  # ============================================
  # ソートアイコン表示ヘルパー
  # ============================================

  # ソートアイコンを表示（汎用版）
  # @param column [String] 列名
  # @param current_sort [String] 現在のソート列
  # @param current_direction [String] 現在のソート方向
  # @return [ActiveSupport::SafeBuffer] HTMLアイコン
  def sort_icon(column, current_sort = params[:sort], current_direction = params[:direction])
    return "".html_safe unless current_sort == column.to_s

    if current_direction == "asc"
      tag.i(class: "fas fa-sort-up ms-1")
    else
      tag.i(class: "fas fa-sort-down ms-1")
    end
  end

  # ============================================
  # 🔴 Phase 4: カテゴリ推定機能（緊急対応）
  # ============================================

  # 商品名からカテゴリを推定するヘルパーメソッド
  # CLAUDE.md準拠: ベストプラクティス - 推定ロジックの明示化と横展開
  # 横展開: 全コントローラー・ビューで統一的なカテゴリ推定を実現
  # TODO: 🔴 Phase 4（緊急）- categoryカラム追加後、このメソッドは不要となり削除予定
  def categorize_by_name(product_name)
    return "その他" if product_name.blank?

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

  # ============================================
  # 統一フラッシュメッセージ・レイアウト支援ヘルパー
  # ============================================

  # 統一フラッシュメッセージのアラートクラス
  def flash_alert_class(type)
    case type.to_s
    when "notice", "success" then "alert-success"
    when "alert", "error" then "alert-danger"
    when "warning" then "alert-warning"
    when "info" then "alert-info"
    else "alert-info"
    end
  end

  # 統一フラッシュメッセージのアイコンクラス
  def flash_icon_class(type)
    case type.to_s
    when "notice", "success" then "bi bi-check-circle"
    when "alert", "error" then "bi bi-exclamation-triangle"
    when "warning" then "bi bi-exclamation-circle"
    when "info" then "bi bi-info-circle"
    else "bi bi-info-circle"
    end
  end

  # フラッシュメッセージタイトル（オプション）
  def flash_title_for(type)
    case type.to_s
    when "notice", "success" then "成功"
    when "alert", "error" then "エラー"
    when "warning" then "警告"
    when "info" then "情報"
    else nil
    end
  end

  # フラッシュメッセージ詳細（オプション）
  def flash_detail_for(type, message)
    case type.to_s
    when "alert", "error" then "エラーが解決しない場合は管理者にお問い合わせください。"
    else nil
    end
  end

  # ============================================
  # 統一フッター支援ヘルパー
  # ============================================

  # フッター全体のCSSクラス
  def footer_classes
    case current_section
    when "admin" then "footer-admin py-4 mt-auto"
    when "store" then "footer-store py-4 mt-auto"
    else "footer-public bg-dark text-light py-4 mt-auto"
    end
  end

  # フッターコンテナのCSSクラス
  def footer_container_classes
    case current_section
    when "admin", "store" then "container-fluid"
    else "container"
    end
  end

  # フッター区切り線のCSSクラス
  def footer_divider_classes
    "my-3 opacity-25"
  end

  # フッターブランドアイコンクラス
  def footer_brand_icon_class
    case current_section
    when "admin" then "bi bi-boxes"
    when "store" then "bi bi-shop"
    else "bi bi-boxes-stacked"
    end
  end

  # フッターブランドアイコン色
  def footer_brand_icon_color
    case current_section
    when "admin" then "text-primary"
    when "store" then "text-info"
    else "text-primary"
    end
  end

  # フッターブランドテキスト
  def footer_brand_text
    "StockRx"
  end

  # フッターバッジクラス（オプション）
  def footer_badge_class
    case current_section
    when "admin" then "bg-danger"
    when "store" then "bg-success"
    else "bg-secondary"
    end
  end

  # フッターデフォルト説明文
  def footer_default_description
    case current_section
    when "admin" then "モダンな在庫管理システム - 管理者画面"
    when "store" then "モダンな在庫管理システム - 店舗画面"
    else "モダンな在庫管理システム"
    end
  end

  # フッター説明文クラス
  def footer_description_class
    "small"
  end

  # フッターメタ情報の配置
  def footer_meta_alignment
    "justify-content-md-end"
  end

  # フッターセキュリティアイコン色
  def footer_security_icon_color
    "text-success"
  end

  # フッターセキュリティテキスト
  def footer_security_text
    "SSL保護済み"
  end

  # フッターコピーライト保持者
  def footer_copyright_holder
    "StockRx"
  end

  # ============================================
  # 統一ブランディング支援ヘルパー
  # ============================================

  # ブランドリンクパス（動的リンク生成）
  def brand_link_path
    if defined?(current_admin) && current_admin
      admin_root_path
    elsif defined?(current_store_user) && current_store_user
      store_root_path
    else
      root_path
    end
  end

  # 現在のセクション判定
  def current_section
    case controller.class.name
    when /^AdminControllers::/
      "admin"
    when /^StoreControllers::/
      "store"
    else
      "public"
    end
  end

  # ブランドアイコンクラス（ナビゲーション用）
  def brand_icon_class
    case current_section
    when "admin" then "bi bi-boxes"
    when "store" then "bi bi-shop"
    else "bi bi-boxes-stacked"
    end
  end

  # ブランドテキスト
  def brand_text
    "StockRx"
  end

  # ブランドクラス（ナビゲーション用）
  def brand_classes
    "d-flex align-items-center"
  end

  # ブランドテキストクラス
  def brand_text_classes
    "fw-bold"
  end

  # バッジクラス（ナビゲーション用）
  def badge_classes
    "ms-2 badge bg-light text-dark"
  end

  # ============================================
  # 🔴 Phase 1: 未定義ヘルパーメソッド実装（緊急対応）
  # ============================================

  # 在庫レベルバッジ表示
  # @param store_inventory [StoreInventory] 店舗在庫オブジェクト
  # @return [Hash] バッジ情報ハッシュ { class: "CSSクラス", text: "表示テキスト" }
  def stock_level_badge(store_inventory)
    quantity = store_inventory.quantity
    safety_level = store_inventory.safety_stock_level

    case
    when quantity == 0
      { class: "badge bg-danger", text: "在庫切れ" }
    when quantity <= safety_level
      { class: "badge bg-warning text-dark", text: "在庫少" }
    when quantity <= safety_level * 2
      { class: "badge bg-info", text: "通常" }
    else
      { class: "badge bg-success", text: "在庫充分" }
    end
  end

  # 在庫回転日数計算
  # @param store_inventory [StoreInventory] 店舗在庫オブジェクト
  # @return [String] 回転日数文字列
  def turnover_days(store_inventory)
    return "N/A" if store_inventory.quantity <= 0

    # 簡易計算：安全在庫レベルベースの推定
    # TODO: 🟡 Phase 3 - 実際の消費履歴データを使用した精密計算
    daily_consumption = [ store_inventory.safety_stock_level / 30.0, 1.0 ].max
    days = (store_inventory.quantity / daily_consumption).round

    "#{days}日"
  end

  # IPアドレスフォーマット（セキュリティ考慮）
  # @param ip [String] IPアドレス
  # @return [String] フォーマット済みIPアドレス
  def format_ip_address(ip)
    return "不明" if ip.blank?

    # セキュリティ考慮：最後のオクテットをマスク
    ip.to_s.gsub(/\.\d+$/, ".***")
  end

  # パスワード強度CSSクラス
  # @param days_until_expiry [Integer] 有効期限までの日数
  # @return [String] CSSクラス名
  def password_strength_class(days_until_expiry)
    case days_until_expiry
    when 0..7
      "text-danger"
    when 8..30
      "text-warning"
    else
      "text-success"
    end
  end

  # ソート方向ヘルパー
  # @return [String] asc または desc
  def sort_direction
    params[:direction] == "desc" ? "desc" : "asc"
  end

  # TODO: 🟡 Phase 6（重要）- 高度なヘルパー機能
  # 優先度: 中（UI/UX向上）
  # 実装内容:
  #   - リスクスコア可視化ヘルパー
  #   - 時系列データ表示ヘルパー
  #   - 国際化対応強化
  #   - セクション別テーマ動的切り替え
  # 期待効果: より直感的なUI表示、統一されたブランド体験
end
