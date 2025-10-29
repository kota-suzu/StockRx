# frozen_string_literal: true

# テスト用のコントローラー定義
module StoreControllers
  class TestController < BaseController
    def index
      render html: "<h1>Store Index</h1>".html_safe
    end

    def show
      render html: "<h1>Store Show</h1>".html_safe
    end

    def search
      render html: "<h1>Store Search</h1>".html_safe
    end

    def private_action
      render html: "<h1>Private Action</h1>".html_safe
    end

    def health
      render plain: "Health Check"
    end

    def status
      render plain: "Status Check"
    end

    private

    # テスト用のpublic_action?実装をオーバーライド
    def public_action?
      action_name.in?(%w[index show search health status])
    end
  end
end
