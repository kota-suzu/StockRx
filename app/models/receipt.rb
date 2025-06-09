# frozen_string_literal: true

class Receipt < ApplicationRecord
  belongs_to :inventory, counter_cache: true

  # 入荷ステータスの列挙型（Rails 8 対応：位置引数使用）
  enum :receipt_status, {
    expected: 0,     # 入荷予定
    partial: 1,      # 一部入荷
    completed: 2,    # 入荷完了
    rejected: 3,     # 受入拒否
    delayed: 4       # 入荷遅延
  }

  # バリデーション
  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :source, presence: true
  validates :receipt_date, presence: true
  validates :receipt_status, presence: true
  validates :cost_per_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_status, ->(status) { where(receipt_status: status) }
  scope :by_date_range, ->(start_date, end_date) { where(receipt_date: start_date..end_date) }
  scope :by_source, ->(source) { where(source: source) }

  # インスタンスメソッド
  def total_cost
    return nil unless cost_per_unit
    quantity * cost_per_unit
  end

  def can_reject?
    expected? || partial?
  end

  def formatted_receipt_date
    receipt_date&.strftime("%Y年%m月%d日")
  end

  # ============================================
  # TODO: 入荷管理機能の拡張計画
  # ============================================
  # 1. 品質管理機能
  #    - 品質検査チェックリストの実装
  #    - 不良品率の計算・追跡
  #    - ロット品質履歴の管理
  #    - 品質証明書のアップロード機能
  #
  # 2. 供給業者管理
  #    - 供給業者評価システム
  #    - 納期遵守率の自動計算
  #    - 供給業者ランキング機能
  #    - 契約条件管理（価格、リードタイム）
  #
  # 3. コスト分析・最適化
  #    - 単価変動分析
  #    - 大量購入割引の自動適用
  #    - 為替レート影響の計算
  #    - TCO（Total Cost of Ownership）分析
  #
  # 4. 自動化・効率化
  #    - EDI（Electronic Data Interchange）連携
  #    - 発注書の自動生成
  #    - 入荷予定の自動更新
  #    - バーコード/QRコードスキャン対応
  #
  # 5. レポート・分析
  #    - 入荷実績レポート
  #    - 供給業者パフォーマンス分析
  #    - コスト削減効果レポート
  #    - 季節変動分析
end
