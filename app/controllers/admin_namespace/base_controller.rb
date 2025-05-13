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

    # TODO: コントローラの名前空間変更に伴い、今後以下の対応が必要
    # 1. テスト（test/controllers/admin/）のディレクトリ構造も変更する
    # 2. ビューのパス参照を修正する可能性を確認する
    # 3. 管理者関連の権限機能を実装する際にコントローラ構造を見直す

    private

    # 現在ログイン中の管理者情報をビューで参照できるよう設定
    def set_admin_info
      return unless admin_signed_in?

      @current_admin = current_admin
    end
  end
end
