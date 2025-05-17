# frozen_string_literal: true

# コレクションデコレータ
# モデルのコレクション（例: Inventory.all）をデコレートする際に使用するクラス
if defined?(Draper)
  class CollectionDecorator < Draper::CollectionDecorator
    # コレクションの各要素に適用されるデコレータクラスを自動で選択
    def decorator_class
      return nil if object.empty?

      # コレクションの最初の要素から推測（例：Inventoryのコレクションなら、InventoryDecorator）
      "#{object.first.class.name}Decorator".constantize
    rescue NameError
      nil
    end
  end
end
