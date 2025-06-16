# frozen_string_literal: true

module StoreControllers
  # 店舗ユーザー用パスワードコントローラー
  # ============================================
  # Phase 3: 店舗別ログインシステム
  # Phase 5-1: レート制限追加
  # パスワードリセット機能を提供
  # ============================================
  class PasswordsController < Devise::PasswordsController
    include RateLimitable

    # レイアウト設定
    layout "store_auth"

    # 店舗情報の設定
    before_action :set_store_from_params, only: [ :new, :create, :edit, :update ]

    # ============================================
    # アクション
    # ============================================

    # パスワードリセット申請フォーム
    def new
      # 店舗が指定されていない場合は店舗選択画面へ
      redirect_to store_selection_path and return unless @store

      super
    end

    # パスワードリセットメール送信
    def create
      # メールアドレスと店舗IDで検索
      self.resource = StoreUser.find_by(
        email: resource_params[:email]&.downcase,
        store_id: @store&.id
      )

      if resource.nil?
        # セキュリティのため、ユーザーが存在しない場合も成功したように見せる
        track_rate_limit_action! # レート制限カウント
        set_flash_message(:notice, :send_paranoid_instructions)
        redirect_to new_store_user_session_path(store_slug: @store&.slug)
      else
        # パスワードリセットトークンを生成して送信
        track_rate_limit_action! # レート制限カウント（成功時もカウント）
        resource.send_reset_password_instructions

        if successfully_sent?(resource)
          respond_with({}, location: after_sending_reset_password_instructions_path_for(resource_name))
        else
          respond_with(resource)
        end
      end
    end

    # パスワード変更フォーム
    def edit
      super do |resource|
        # トークンが無効な場合
        if resource.errors.any?
          redirect_to new_store_user_password_path(store_slug: @store&.slug),
                      alert: I18n.t("devise.passwords.invalid_token")
          return
        end
      end
    end

    # パスワード更新
    def update
      super do |resource|
        if resource.errors.empty?
          # パスワード変更成功時の処理
          resource.update_columns(
            password_changed_at: Time.current,
            must_change_password: false
          )

          # ログイン状態にする
          sign_in(resource_name, resource)

          # 成功メッセージを表示してダッシュボードへ
          set_flash_message(:notice, :updated_not_active) if is_flashing_format?
          redirect_to store_root_path and return
        end
      end
    end

    protected

    # ============================================
    # パラメータ処理
    # ============================================

    # パスワードリセット用のパラメータ
    def resource_params
      params.require(resource_name).permit(:email, :password, :password_confirmation, :reset_password_token)
    end

    # ============================================
    # リダイレクト先
    # ============================================

    # パスワードリセット申請後のリダイレクト先
    def after_sending_reset_password_instructions_path_for(resource_name)
      if @store
        new_store_user_session_path(store_slug: @store.slug)
      else
        store_selection_path
      end
    end

    # パスワード変更後のリダイレクト先
    def after_resetting_password_path_for(resource)
      store_root_path
    end

    # ============================================
    # 店舗管理
    # ============================================

    # パラメータから店舗を設定
    def set_store_from_params
      store_slug = params[:store_slug] ||
                   params[:store_user]&.dig(:store_slug) ||
                   extract_store_slug_from_referrer

      if store_slug.present?
        @store = Store.active.find_by(slug: store_slug)
      end
    end

    # リファラーから店舗スラッグを抽出
    def extract_store_slug_from_referrer
      return nil unless request.referrer.present?

      # /store/pharmacy-tokyo/... のようなパスから抽出
      if request.referrer =~ %r{/store/([^/]+)}
        Regexp.last_match(1)
      end
    end

    # ============================================
    # ビューヘルパー
    # ============================================

    # 店舗名を含むタイトル
    helper_method :page_title
    def page_title
      if @store
        "#{@store.name} - パスワードリセット"
      else
        "パスワードリセット"
      end
    end

    # ============================================
    # セキュリティ対策
    # ============================================

    # レート制限（ブルートフォース対策）
    def check_rate_limit
      # TODO: Phase 5 - レート制限の実装
      # rate_limiter = RateLimiter.new(
      #   key: "password_reset:#{request.remote_ip}",
      #   limit: 5,
      #   period: 1.hour
      # )
      #
      # unless rate_limiter.allowed?
      #   redirect_to store_selection_path,
      #               alert: I18n.t("errors.messages.too_many_requests")
      # end
    end

    # ============================================
    # レート制限設定（Phase 5-1）
    # ============================================

    def rate_limited_actions
      [ :create ]  # パスワードリセット要求のみ制限
    end

    def rate_limit_key_type
      :password_reset
    end

    def rate_limit_identifier
      # IPアドレスで識別（メールアドレスが分からない場合もあるため）
      request.remote_ip
    end
  end
end

# ============================================
# TODO: Phase 5以降の拡張予定
# ============================================
# 1. 🔴 セキュリティ質問
#    - パスワードリセット時の追加認証
#    - カスタマイズ可能な質問設定
#
# 2. 🟡 パスワード履歴
#    - 過去のパスワード再利用防止
#    - 履歴保持期間の設定
#
# 3. 🟢 管理者承認フロー
#    - 重要アカウントのパスワード変更承認
#    - 変更通知の自動送信
