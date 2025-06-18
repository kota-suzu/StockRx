# Pin npm packages by running ./bin/importmap

pin "application", preload: true
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"

# 認証画面専用JavaScript - インラインスクリプト外部化
# CLAUDE.md準拠: CSP対応とメンテナンス性向上
pin "authentication", to: "authentication.js", preload: true

# Bootstrap 5 JavaScript for interactive components
# CLAUDE.md準拠: メタ認知的アプローチ - Bootstrap JSが必要な理由を明確化
# 必要理由: collapse, dropdown, tooltip等のインタラクティブ機能のため
# 横展開: admin, store_controllersの両方で使用
# ベストプラクティス: bundle版にはPopper.js含まれるため、別途読み込み不要
pin "bootstrap", to: "https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js", preload: true
# TODO: 🔴 Phase 1（緊急）- CDNフォールバック機能実装
#   - CDN接続失敗時のローカルコピー提供
#   - ネットワーク分断耐性の向上
#   - 横展開: 全CDNリソースで適用
