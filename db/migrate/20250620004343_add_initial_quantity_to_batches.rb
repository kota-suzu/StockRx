class AddInitialQuantityToBatches < ActiveRecord::Migration[8.0]
  def change
    add_column :batches, :initial_quantity, :integer, comment: "初期数量（入荷時の数量）"

    # 既存レコードの初期数量を現在の数量で設定
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          UPDATE batches#{' '}
          SET initial_quantity = quantity#{' '}
          WHERE initial_quantity IS NULL
        SQL
      end
    end
  end
end
