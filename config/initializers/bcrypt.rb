# frozen_string_literal: true

# BCrypt暗号化強度設定
# CLAUDE.md準拠：セキュリティベストプラクティス実装

# 環境別の適切なコスト設定
# 本番環境：セキュリティを最優先（高コスト）
# 開発・テスト：レスポンス性能も考慮（中コスト）

if Rails.env.production?
  # 本番環境：最高レベルのセキュリティ
  BCrypt::Engine.cost = 12
elsif Rails.env.development?
  # 開発環境：セキュリティとパフォーマンスのバランス
  BCrypt::Engine.cost = 10
else
  # テスト環境：テスト高速化のため最低限のセキュリティ
  BCrypt::Engine.cost = 4
end

# セキュリティ設定の可視化
Rails.logger.info "[Security] BCrypt cost set to: #{BCrypt::Engine.cost}"
