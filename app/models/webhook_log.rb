# frozen_string_literal: true

# CLAUDE.md準拠: Webhookログモデル（テスト用仮実装）
# TODO: Phase 3 - 実際のWebhook機能実装時に拡張
class WebhookLog < ApplicationRecord
  # 関連付け
  belongs_to :webhook_endpoint, optional: true

  # バリデーション
  validates :status, presence: true, inclusion: { in: %w[pending success failed] }
  validates :response_code, numericality: { only_integer: true }, allow_nil: true

  # スコープ
  scope :failed, -> { where(status: "failed") }
  scope :successful, -> { where(status: "success") }
  scope :recent, -> { order(created_at: :desc) }

  # デフォルト値
  attribute :status, :string, default: "pending"
end
