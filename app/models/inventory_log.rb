# frozen_string_literal: true

class InventoryLog < ApplicationRecord
  belongs_to :inventory, counter_cache: true
  belongs_to :user, optional: true, class_name: "Admin"

  # バリデーション
  validates :delta, presence: true, numericality: true
  validates :operation_type, presence: true
  validates :previous_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :current_quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # 操作種別の定数定義
  OPERATION_TYPES = %w[add remove adjust ship receive].freeze

  # 操作種別のenum定義（Rails 8 対応：位置引数使用）
  enum :operation_type, {
    add: "add",
    remove: "remove",
    adjust: "adjust",
    ship: "ship",
    receive: "receive"
  }

  # スコープ
  scope :recent, -> { order(created_at: :desc) }
  scope :by_operation_type, ->(type) { where(operation_type: type) }
  scope :by_date_range, ->(start_date, end_date) {
    start_date = start_date.beginning_of_day if start_date
    end_date = end_date.end_of_day if end_date

    query = all
    query = query.where("created_at >= ?", start_date) if start_date
    query = query.where("created_at <= ?", end_date) if end_date
    query
  }

  # 統計スコープ
  scope :additions, -> { by_operation_type("add") }
  scope :removals, -> { by_operation_type("remove") }
  scope :adjustments, -> { by_operation_type("adjust") }
  scope :shipments, -> { by_operation_type("ship") }
  scope :receipts, -> { by_operation_type("receive") }
  scope :this_month, -> { by_date_range(Time.current.beginning_of_month, Time.current) }
  scope :previous_month, -> { by_date_range(1.month.ago.beginning_of_month, 1.month.ago.end_of_month) }
  scope :this_year, -> { by_date_range(Time.current.beginning_of_year, Time.current) }

  # 操作種別のバリデーション
  validates :operation_type, inclusion: { in: OPERATION_TYPES }

  # ============================================
  # TODO: 在庫ログ機能の拡張計画
  # ============================================
  # 1. 高度な分析機能
  #    - 在庫変動パターンの機械学習による分析
  #    - 異常操作検出アルゴリズムの実装
  #    - 予測分析（需要予測、在庫最適化）
  #    - リアルタイムダッシュボード機能
  #
  # 2. セキュリティ・監査強化
  #    - ログのデジタル署名機能
  #    - ハッシュチェーンによる改ざん防止
  #    - 操作者認証の強化（2FA連携）
  #    - 監査証跡の暗号化保存
  #
  # 3. パフォーマンス最適化
  #    - 大量データの効率的な処理（バッチ処理）
  #    - インデックス最適化戦略
  #    - データアーカイブ機能（古いログの自動圧縮）
  #    - キャッシュ戦略の実装
  #
  # 4. レポート・可視化機能
  #    - グラフィカルレポート生成（Chart.js連携）
  #    - PDF/Excel エクスポート機能
  #    - カスタムレポートビルダー
  #    - 定期レポート自動生成・配信
  #
  # 5. 国際化・多言語対応
  #    - 多言語操作ログメッセージ
  #    - タイムゾーン対応の強化
  #    - 各国会計基準への対応
  #    - 通貨単位の適切な表示

  # CSVヘッダー
  def self.csv_header
    %w[ID 在庫ID 在庫名 操作種別 変化量 変更前数量 変更後数量 備考 作成日時]
  end

  # CSVデータ行
  def csv_row
    [
      id,
      inventory_id,
      inventory.name,
      operation_type,
      delta,
      previous_quantity,
      current_quantity,
      note,
      created_at.strftime("%Y-%m-%d %H:%M:%S")
    ]
  end

  # CSVデータ生成
  def self.generate_csv(logs)
    CSV.generate(headers: true) do |csv|
      csv << csv_header

      logs.each do |log|
        csv << log.csv_row
      end
    end
  end

  # 統計メソッド
  def self.operation_summary(start_date = 30.days.ago, end_date = Time.current)
    by_date_range(start_date, end_date)
      .group(:operation_type)
      .select("operation_type, COUNT(*) as count, SUM(ABS(delta)) as total_quantity")
  end

  def self.daily_transaction_summary(days = 30)
    start_date = days.days.ago.beginning_of_day

    by_date_range(start_date, Time.current)
      .group("DATE(created_at)")
      .select("DATE(created_at) as date, COUNT(*) as count, SUM(ABS(delta)) as total_quantity")
      .order("date DESC")
  end

  def self.top_products_by_activity(limit = 10, days = 30)
    start_date = days.days.ago.beginning_of_day

    joins(:inventory)
      .by_date_range(start_date, Time.current)
      .group("inventory_id, inventories.name")
      .select("inventory_id, inventories.name, COUNT(*) as operation_count")
      .order("operation_count DESC")
      .limit(limit)
  end

  # ============================================
  # 監査ログの完全性保護（読み取り専用）
  # ============================================

  # 更新を禁止（監査ログは変更不可）
  def update(*)
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records are immutable for audit integrity"
  end

  def update!(*)
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records are immutable for audit integrity"
  end

  def update_attribute(*)
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records are immutable for audit integrity"
  end

  def update_attributes(*)
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records are immutable for audit integrity"
  end

  def update_columns(*)
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records are immutable for audit integrity"
  end

  # 削除を禁止（監査ログは永続保存）
  def destroy
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records cannot be deleted for audit integrity"
  end

  def destroy!
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records cannot be deleted for audit integrity"
  end

  def delete
    raise ActiveRecord::ReadOnlyRecord, "InventoryLog records cannot be deleted for audit integrity"
  end

  # ============================================
  # TODO: 統計・分析機能の拡張
  # ============================================
  # 1. 高度な統計分析
  #    - 在庫回転率の計算
  #    - 季節性分析（月別・曜日別パターン）
  #    - 操作頻度のヒートマップデータ生成
  #    - 異常値検出（統計的手法）
  #
  # 2. リアルタイム分析
  #    - WebSocket経由のリアルタイム統計更新
  #    - ライブダッシュボード用データ提供
  #    - アラート閾値の動的調整
  #
  # 3. 予測分析
  #    - 線形回帰による需要予測
  #    - ARIMA モデルによる時系列予測
  #    - 機械学習による最適在庫レベル予測
  #
  # 4. ビジネスインテリジェンス
  #    - KPI ダッシュボードデータ生成
  #    - ROI（投資収益率）計算
  #    - コスト分析レポート
  #    - パフォーマンス指標の自動計算

  # 日時フォーマット
  def formatted_created_at
    created_at.strftime("%Y年%m月%d日 %H:%M:%S")
  end

  # 操作タイプの日本語表示名
  def operation_display_name
    case operation_type
    when "add" then "追加"
    when "remove" then "削除"
    when "adjust" then "調整"
    when "ship" then "出荷"
    when "receive" then "入荷"
    else operation_type
    end
  end
end
