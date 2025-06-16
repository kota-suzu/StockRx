# frozen_string_literal: true

# カスタムDevise認証失敗ハンドラー
# ============================================
# Phase 2: 店舗別ログインシステム
# 管理者と店舗ユーザーで異なる認証失敗処理を実装
# ============================================
class CustomFailureApp < Devise::FailureApp
  # リダイレクト先のパスを決定
  def redirect_url
    if scope == :store_user
      # 店舗ユーザーの場合
      if store_slug_from_path.present?
        # 特定店舗のログインページへ
        store_login_page_path(slug: store_slug_from_path)
      else
        # 店舗選択画面へ
        store_selection_path
      end
    else
      # 管理者の場合は通常のDevise処理
      super
    end
  end

  # レスポンスの処理
  def respond
    if http_auth?
      http_auth
    elsif warden_message == :timeout
      # タイムアウトの場合は元のページに戻れるようにする
      redirect_with_timeout_message
    else
      redirect
    end
  end

  private

  # パスから店舗スラッグを抽出
  def store_slug_from_path
    # /store/pharmacy-tokyo/... のようなパスから店舗スラッグを抽出
    if request.path =~ %r{^/store/([^/]+)}
      Regexp.last_match(1)
    end
  end

  # タイムアウト時の特別処理
  def redirect_with_timeout_message
    if scope == :store_user
      flash[:alert] = I18n.t("devise.failure.timeout")
      redirect_to redirect_url, status: :see_other
    else
      redirect
    end
  end

  # 認証が必要なメッセージを国際化対応
  def i18n_message(default = nil)
    if scope == :store_user && warden_message == :unauthenticated
      # 店舗ユーザー向けのカスタムメッセージ
      I18n.t("devise.failure.store_user_unauthenticated", default: default)
    else
      super
    end
  end
end

# ============================================
# TODO: Phase 3以降の拡張予定
# ============================================
# 1. 🟡 IPアドレス制限機能
#    - 特定店舗は特定IPからのみアクセス可能
#    - セキュリティポリシーの実装
#
# 2. 🟢 多要素認証失敗時の処理
#    - SMS/TOTP認証失敗時の特別処理
#    - リトライ制限とロックアウト
#
# 3. 🔵 監査ログ
#    - 認証失敗の詳細記録
#    - 不審なアクセスパターンの検出
