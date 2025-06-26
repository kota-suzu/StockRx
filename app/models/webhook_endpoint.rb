# frozen_string_literal: true

# CLAUDE.md準拠: Webhook管理モデル（テスト用仮実装）
# TODO: Phase 3 - 実際のWebhook機能実装時に拡張
class WebhookEndpoint < ApplicationRecord
  # バリデーション
  validates :url, presence: true, format: { with: URI.regexp(%w[http https]) }
  validates :events, presence: true

  # デフォルト値
  attribute :active, :boolean, default: true
  attribute :events, :json, default: []

  # スコープ
  scope :active, -> { where(active: true) }
  scope :for_event, ->(event) { where("events @> ?", [ event ].to_json) }

  # インスタンスメソッド
  def subscribed_to?(event)
    events.include?(event.to_s)
  end
end
