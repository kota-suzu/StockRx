# frozen_string_literal: true

module AdminNamespace
  # 管理者画面用のベースコントローラ
  # 全ての管理者向けコントローラはこのクラスを継承する
  class BaseController < ApplicationController
    before_action :authenticate_admin!
    layout "admin"

    # CSRFトークン検証を有効化
    protect_from_forgery with: :exception

    # 全ての管理者画面で共通のセットアップ処理
    before_action :set_admin_info

    private

    # 現在ログイン中の管理者情報をビューで参照できるよう設定
    def set_admin_info
      return unless admin_signed_in?

      @current_admin = current_admin
    end
  end
end
