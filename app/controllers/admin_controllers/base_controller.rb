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

    # TODO: 将来的な機能拡張
    # - 管理者権限レベルによるアクセス制御（role-based authorization）
    # - 管理操作の監査ログ記録
    # - 共通エラーハンドリング機能の実装
    # - 多言語対応の基盤整備

    private

    # 現在ログイン中の管理者情報をビューで参照できるよう設定
    def set_admin_info
      return unless admin_signed_in?

      @current_admin = current_admin
    end
  end
end
