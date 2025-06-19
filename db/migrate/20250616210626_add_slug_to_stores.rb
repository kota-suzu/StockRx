# frozen_string_literal: true

class AddSlugToStores < ActiveRecord::Migration[8.0]
  def change
    add_column :stores, :slug, :string
    add_index :stores, :slug, unique: true

    # 既存データがある場合のデフォルトスラッグ生成
    reversible do |dir|
      dir.up do
        Store.find_each do |store|
          store.update_column(:slug, store.code.downcase.gsub(/[^a-z0-9]/, '-'))
        end

        # スラッグをNOT NULLに変更
        change_column_null :stores, :slug, false
      end
    end
  end
end
