# frozen_string_literal: true

# Rails 8対応 Zeitwerk設定ファイル
# ================================

# Rails 8では、autoload_pathsが初期化完了後に凍結される
# そのため、動的な変更は避け、Railsの規約に従った構造にする

# 1. 特殊なディレクトリ構造の処理
# --------------------------------
# admin_helpersディレクトリ内のファイルが
# トップレベルのモジュールとして扱われるよう設定
Rails.autoloaders.main.collapse("#{Rails.root}/app/helpers/admin_helpers") if Dir.exist?("#{Rails.root}/app/helpers/admin_helpers")

# 2. カスタムインフレクター設定（必要に応じて）
# -------------------------------------
# Rails.autoloaders.main.inflector.inflect(
#   "api" => "API",
#   "csv" => "CSV"
# )

# 3. 無視するパスの設定
# -------------------
Rails.autoloaders.main.ignore("#{Rails.root}/app/assets")
Rails.autoloaders.main.ignore("#{Rails.root}/lib/assets")
Rails.autoloaders.main.ignore("#{Rails.root}/lib/tasks")

# 4. lib配下の自動読み込み設定
# --------------------------
# Rails 8では、libディレクトリは明示的に追加する必要がある
# ただし、config/application.rbのafter_initializeで設定済み

# 5. 開発環境での再読み込み設定
# ---------------------------
if Rails.env.development?
  Rails.autoloaders.main.enable_reloading

  # 特定のディレクトリの変更を監視から除外
  Rails.autoloaders.main.do_not_eager_load("#{Rails.root}/app/lib/security") if Dir.exist?("#{Rails.root}/app/lib/security")
end

# NOTE: Rails 8のベストプラクティス
# =================================
# 1. autoload_pathsへの直接アクセスは避ける
# 2. Railsの規約に従ったディレクトリ構造を使用する
# 3. 特殊な構造が必要な場合は、collapseやignoreを使用する
# 4. libディレクトリの扱いは慎重に（eager_load_pathsへの追加を推奨）