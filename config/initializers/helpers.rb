# frozen_string_literal: true

# Rails 7.2以降との互換性のためのヘルパー設定
# ======================================

# 名前空間の整理とZeitwerk対応
#
# 問題点：
# 1. AdminモデルとAdmin名前空間が衝突
# 2. Rails 7.2での凍結配列問題
# 3. Zeitwerkのオートロード挙動変更
#
# 解決策：
# 1. ヘルパーを個別モジュールとして定義し、名前空間の衝突を解消
# 2. 互換性のためのブリッジ設定

# 下位互換性のための名前空間定義
# 既存のコードが参照している場合に備えて空のモジュールを用意
module AdminHelpers
  # 過去バージョンとの互換性のため
  # 警告：このモジュールは非推奨です
  # TODO: 将来的に削除し、直接のヘルパーモジュール参照に切り替える
  module BatchesHelper; end
  module InventoriesHelper; end
end

# NOTE: 実際のヘルパーモジュールはapp/helpers/以下に
# Railsの規約に従って配置されています
# - app/helpers/batches_helper.rb
# - app/helpers/inventories_helper.rb
