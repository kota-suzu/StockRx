# frozen_string_literal: true

class Batch < ApplicationRecord
  include InventoryStatistics

  belongs_to :inventory, counter_cache: true

  # バリデーション
  validates :lot_code, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  # ロットコードと在庫IDの組み合わせでユニーク（DBレベルでも制約あり）
  validates :lot_code, uniqueness: { scope: :inventory_id, case_sensitive: false }

  # スコープ
  scope :expired, -> { where("expires_on < ?", Date.current) }
  scope :not_expired, -> { where("expires_on >= ? OR expires_on IS NULL", Date.current) }
  scope :expiring_soon, ->(days = 30) { where("expires_on BETWEEN ? AND ?", Date.current, Date.current + days.days) }
  scope :out_of_stock, -> { where(quantity: 0) }
  scope :low_stock, ->(threshold = nil) { where("quantity > 0 AND quantity <= ?", threshold || 5) }

  # TODO: 期限切れアラート機能の実装
  # TODO: バッチ詳細表示機能の追加

  # TODO: 入荷登録機能の拡張
  # - 入荷日の記録と追跡
  # - サプライヤー情報の関連付け
  # - 入荷コストの記録

  # TODO: バッチ移動・譲渡機能
  # - 他の在庫への移動履歴
  # - 複数ロケーション管理

  # TODO: バッチ品質管理機能
  # - 品質検査結果の記録
  # - 温度管理要件の設定と監視
  # - バッチごとの安全性情報の記録

  # ============================================
  # TODO: バッチ管理機能の拡張計画
  # ============================================
  # 1. 高度なトレーサビリティ
  #    - サプライチェーン全体の追跡機能
  #    - 原材料から最終製品までの完全な履歴
  #    - ブロックチェーンによる改ざん防止
  #    - QRコード/RFID による即座のトレース
  #
  # 2. 品質管理・コンプライアンス
  #    - リコール対象範囲の即座特定
  #    - 品質検査結果の自動記録
  #    - GMP（Good Manufacturing Practice）対応
  #    - FDA/厚労省等規制当局への報告書自動生成
  #
  # 3. 期限管理・最適化
  #    - FEFO（First Expired, First Out）自動適用
  #    - 期限切れアラートの高度化
  #    - 廃棄コスト最小化アルゴリズム
  #    - 動的な安全在庫計算
  #
  # 4. 分析・最適化機能
  #    - バッチサイズ最適化提案
  #    - 製造効率性分析レポート
  #    - 品質データの統計分析
  #    - 収率改善提案システム
  #
  # 5. 国際対応・多拠点管理
  #    - 各国規制への自動対応
  #    - 多言語でのバッチ情報管理
  #    - 拠点間でのバッチ移動追跡
  #    - 通貨・単位の自動変換
  #
  # 6. IoT・自動化連携
  #    - センサーデータとの自動連携
  #    - 製造設備からの自動データ取得
  #    - 環境条件（温度・湿度）の自動記録
  #    - スマートファクトリー対応

  # 期限切れかどうかを判定するメソッド
  def expired?
    expires_on.present? && expires_on < Date.current
  end

  # 期限切れが近いかどうかを判定するメソッド（デフォルト30日前）
  def expiring_soon?(days_threshold = 30)
    expires_on.present? && !expired? && expires_on < Date.current + days_threshold.days
  end

  # 在庫切れかどうかを判定するメソッド
  def out_of_stock?
    quantity == 0
  end

  # 在庫が少ないかどうかを判定するメソッド（デフォルト閾値は5）
  def low_stock?(threshold = nil)
    threshold ||= low_stock_threshold
    quantity > 0 && quantity <= threshold
  end

  # 在庫アラート閾値の設定（将来的には設定から取得するなど拡張予定）
  def low_stock_threshold
    5 # デフォルト値
  end
end
