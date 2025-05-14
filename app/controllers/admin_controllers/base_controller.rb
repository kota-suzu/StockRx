# frozen_string_literal: true

module AdminControllers
  # 管理者画面用のベースコントローラ
  # 全ての管理者向けコントローラはこのクラスを継承する
  class BaseController < ApplicationController
    before_action :authenticate_admin!
    layout "admin"

    # CSRFトークン検証を有効化
    protect_from_forgery with: :exception

    # 全ての管理者画面で共通のセットアップ処理
    before_action :set_admin_info

    # TODO: コントローラの命名規則
    # AdminControllersモジュール名はAdminモデルとの名前衝突を避けるために使用
    # 将来的な新しいモデル/コントローラの追加時にも同様の名前衝突に注意
    # コントローラモジュール名には「Controllers」サフィックスを使用して区別する
    # 例: UserモデルとUserControllersモジュールなど

    private

    # 現在ログイン中の管理者情報をビューで参照できるよう設定
    def set_admin_info
      return unless admin_signed_in?

      @current_admin = current_admin
    end
  end
end
