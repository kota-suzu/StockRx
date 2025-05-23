# frozen_string_literal: true

class Receipt < ApplicationRecord
  belongs_to :inventory

  # 入荷ステータスの列挙型
  enum receipt_status: {
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

  # TODO: 入荷管理機能の拡張
  # 1. 品質管理機能
  #    - 入荷時の品質チェック項目管理
  #    - 不良品検出・分離機能
  #    - ロット品質履歴追跡機能
  #
  # 2. 供給業者管理
  #    - 供給業者評価・ランキング機能
  #    - 納期遵守率・品質評価の自動計算
  #    - 最適供給業者の提案機能
  #
  # 3. 入荷予測・計画
  #    - 需要予測に基づく入荷計画最適化
  #    - 季節変動を考慮した入荷スケジューリング
  #    - 在庫回転率向上のための入荷調整提案
end
