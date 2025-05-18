# frozen_string_literal: true

# Zeitwerk設定ファイル
# Rails 7.2以降の名前空間解決と凍結配列問題への対応

# 1. Rails 7.2のfrozen array問題対策
# --------------------------------
# Rails 7.2以降で配列オブジェクトが凍結されるようになり、
# autoload_pathsの変更が制限されるようになった問題への対策
Rails.autoloaders.each do |autoloader|
  def autoloader.mutate_autoload_paths
    # frozen error回避のためのパッチ：何もしないオーバーライド
  end
end

# 2. ディレクトリとモジュール構造のマッピング
# ----------------------------------
# 従来のadmin_helpersディレクトリ内のファイルが
# トップレベルのモジュールとして扱われるよう設定
Rails.autoloaders.main.collapse("app/helpers/admin_helpers")

# 3. モジュール読み込みの順序制御
# -------------------------
# helpers.rbイニシャライザがヘルパーモジュールを事前定義

# TODO: 将来的なクリーンアップ
# -----------------------
# 1. admin_helpersディレクトリを削除し、規約に従ったヘルパー構造に完全移行
# 2. AdminHelpersモジュールへの参照をすべて直接のモジュール参照に修正
