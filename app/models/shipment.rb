# frozen_string_literal: true

class Shipment < ApplicationRecord
  belongs_to :inventory

  # 配送ステータスの列挙型
  enum shipment_status: {
    pending: 0,      # 出荷準備中
    processing: 1,   # 処理中
    shipped: 2,      # 出荷済み
    delivered: 3,    # 配達済み
    returned: 4,     # 返品
    cancelled: 5     # キャンセル
  }

  # バリデーション
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :destination, presence: true
  validates :scheduled_date, presence: true
  validates :shipment_status, presence: true

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(shipment_status: status) }
  scope :by_date_range, ->(start_date, end_date) { where(scheduled_date: start_date..end_date) }

  # インスタンスメソッド
  def can_cancel?
    pending? || processing?
  end

  def can_return?
    shipped? || delivered?
  end

  def formatted_scheduled_date
    scheduled_date&.strftime("%Y年%m月%d日")
  end

  # TODO: 出荷管理機能の拡張
  # 1. 配送トラッキング機能
  #    - 配送業者APIとの連携（ヤマト運輸、佐川急便等）
  #    - リアルタイム配送状況の取得
  #    - 配送遅延の自動検出と通知
  #
  # 2. 配送コスト計算機能
  #    - 配送距離・重量による配送料自動計算
  #    - 配送業者別料金比較機能
  #    - 配送コスト最適化提案
  #
  # 3. 出荷予測・最適化
  #    - AI による最適出荷ルート計算
  #    - 配送効率化のための出荷スケジューリング
  #    - 在庫立地最適化提案
end
