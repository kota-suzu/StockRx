# frozen_string_literal: true

# ============================================================================
# Kaminari ページネーション設定
# ============================================================================
# CLAUDE.md準拠: Phase 1完了 - 基本設定とBootstrap 5テーマ問題の暫定対応

Kaminari.configure do |config|
  # 基本ページネーション設定
  config.default_per_page = 20
  config.max_per_page = 100
  config.window = 2         # 現在ページの前後に表示するページ数
  config.outer_window = 1   # 最初と最後に表示するページ数
  # config.left = 0
  # config.right = 0
  config.page_method_name = :page
  config.param_name = :page
  config.max_pages = nil
  config.params_on_first_page = false
end

# ============================================
# TODO: 🟡 Phase 5（改善）- Bootstrap 5対応の完全実装
# ============================================
# 優先度: 中（UI改善）
# 
# 実装方法:
# 1. bootstrap5-kaminari-views gem の適切な設定
#    - Gemfile: gem 'bootstrap5-kaminari-views'
#    - 設定: rails g kaminari:views bootstrap5
# 
# 2. または、カスタムKaminariテンプレートの作成
#    - app/views/kaminari/ ディレクトリにBootstrap 5対応テンプレート配置
#    - _paginator.html.erb, _next_page.html.erb, _prev_page.html.erb 等
# 
# 3. テーマ使用時の設定
#    - <%= paginate @collection, theme: :bootstrap_5 %>
# 
# 期待効果:
#   - Bootstrap 5スタイルによる統一されたページネーション
#   - レスポンシブ対応の向上
#   - アクセシビリティの向上
# 
# 横展開: 全ページネーション箇所で同様修正適用
# メタ認知: UIの一貫性確保によるユーザー体験向上
# ============================================
