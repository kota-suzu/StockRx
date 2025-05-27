# frozen_string_literal: true

# ヘルパーモジュールの定義はhelpers.rbに移動しました

# Draperのデコレータ設定
if defined?(Draper) && defined?(ApplicationController)
  Draper.configure do |config|
    # デコレータを適用すると、Kaminariページネーター用のメソッド (#current_page, #total_pages) も
    # デコレートされるオブジェクトに委譲される
    config.default_controller = ApplicationController

    # 一貫性のために常にコレクションをデコレートする
    config.collection_decorator_class = CollectionDecorator if defined?(CollectionDecorator)

    # TODO: Ransackを導入するときに有効にする
    # config.default_query_method_name = :ransack
  end
end
