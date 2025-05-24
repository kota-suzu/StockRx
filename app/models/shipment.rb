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

  # ============================================
  # TODO: 出荷管理機能の拡張計画
  # ============================================
  # 1. 配送最適化・ルート管理
  #    - 配送ルート最適化アルゴリズム
  #    - GPS追跡・リアルタイム位置情報
  #    - 配送コスト最小化計算
  #    - 複数配送業者との連携API
  #
  # 2. 顧客体験向上
  #    - 配送状況のリアルタイム通知
  #    - 配送予定時刻の自動更新
  #    - 配送完了の自動確認
  #    - 顧客満足度フィードバック収集
  #
  # 3. 倉庫・ピッキング効率化
  #    - ピッキングリスト自動生成
  #    - 最適ピッキング順序の計算
  #    - 梱包材の自動選定
  #    - バーコード/RFID連携
  #
  # 4. 国際配送対応
  #    - 関税・税務計算の自動化
  #    - 輸出入書類の自動生成
  #    - 各国配送規制への対応
  #    - 多通貨対応の配送料金計算
  #
  # 5. 分析・最適化
  #    - 配送パフォーマンス分析
  #    - コスト削減機会の特定
  #    - 季節・地域別配送パターン分析
  #    - 返品・再配送率の最小化
  #
  # 6. サステナビリティ
  #    - カーボンフットプリント計算
  #    - エコフレンドリー配送オプション
  #    - 梱包材の最適化・削減
  #    - 循環型物流の実現
end
