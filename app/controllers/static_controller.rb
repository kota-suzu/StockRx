# frozen_string_literal: true

# ============================================
# Static Pages Controller
# ============================================
# 静的ページとデモページの表示用コントローラー
# CLAUDE.md準拠: 開発環境でのUI確認用
# ============================================

class StaticController < ApplicationController
  # 認証をスキップ（デモページアクセスのため）
  skip_before_action :authenticate_admin!, if: -> { action_name == "modern_ui_demo" }

  # Modern UI v2 デモページ
  # CLAUDE.md準拠: 最新UIトレンドに対応した新デザインシステムのショーケース
  def modern_ui_demo
    # デモページでは特別なレイアウトを使用しない（フルページ表示）
    render "shared/modern_ui_demo", layout: false
  end

  # TODO: Phase 4 - 追加の静的ページ
  # - スタイルガイドページ
  # - コンポーネントカタログ
  # - アクセシビリティチェックリスト
end
