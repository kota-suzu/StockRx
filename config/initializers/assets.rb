# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Precompile additional assets.
# application.js, application.css, and all non-JS/CSS in the app/assets
# folder are already added.
Rails.application.config.assets.precompile += %w[ admin.js admin.css admin_inventories.js ]

# ログファイルに資産コンパイルの詳細情報を出力（開発環境のトラブルシューティング用）
Rails.application.config.assets.debug = true if Rails.env.development?

# TODO: 本番環境でのアセット最適化設定
# - gzipの有効化
# - CDN対応の検討
# - フィンガープリントの設定
