module ApplicationHelper
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

  # TODO: 🟡 Phase 6（重要）- 高度なヘルパー機能
  # 優先度: 中（UI/UX向上）
  # 実装内容:
  #   - リスクスコア可視化ヘルパー
  #   - 時系列データ表示ヘルパー
  #   - 国際化対応強化
  # 期待効果: より直感的なUI表示
end
