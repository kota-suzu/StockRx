# frozen_string_literal: true

module StoreControllers
  # テスト用コントローラー（開発環境のみ）
  class TestController < ApplicationController
    skip_before_action :authenticate_store_user!, if: -> { action_name == "table_light" }
    
    def table_light
      # テーブルライト版の確認ページ
      render "store_controllers/test_table_light"
    end
  end
end