require "csv" # CSVライブラリの読み込みをファイルの先頭に移動

class Inventory < ApplicationRecord
  include InventoryStatistics
  include CsvImportable
  include InventoryLoggable
  include BatchManageable

  # TODO: 2025-06 リリースまでに LOW_STOCK_THRESHOLD を settings テーブルへ移行
  # To ensure consistent behavior for low stock calculations across all environments (local CI, GitHub Actions, etc.),
  # we explicitly set LOW_STOCK_THRESHOLD to 5. This aligns with the previous default
  # and removes potential discrepancies caused by differing ENV variable settings.
  # If a configurable threshold is needed in the future, ensure the ENV variable is consistently set across all environments,
  # or proceed with the TODO to move this to a settings table.
  LOW_STOCK_THRESHOLD = 5

  # ステータス定義
  # インスタンスメソッド (e.g., inventory.active?) が自動生成されます
  enum :status, { active: 0, archived: 1 }
  STATUSES = statuses.keys.freeze # 不変保証

  # バリデーション
  validates :name, presence: true
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }
  validates :price,    numericality: { greater_than_or_equal_to: 0 }

  # スコープ定義
  # enum :status により status_active, status_archived スコープが自動生成されます。
  # activeスコープを追加
  scope :active, -> { where(status: :active) }
  scope :out_of_stock, -> { where("quantity <= 0") }
  scope :low_stock,    ->(t = LOW_STOCK_THRESHOLD) { where("quantity > 0 AND quantity <= ?", t) }
  scope :normal_stock, ->(t = LOW_STOCK_THRESHOLD) { where("quantity > ?", t) }

  # 在庫切れかどうかを判定するメソッド
  # InventoryStatistics concern のメソッドをオーバーライド
  def out_of_stock?
    quantity <= 0
  end

  # 在庫が少ないかどうかを判定するメソッド（デフォルト閾値は5）
  # InventoryStatistics concern のメソッドをオーバーライド
  def low_stock?(threshold = nil)
    threshold ||= LOW_STOCK_THRESHOLD
    quantity.positive? && quantity <= threshold
  end
  # BatchManageable concern に total_batch_quantity, expired_batches, expiring_soon_batches が定義されているため、
  # Inventory モデル内の同名メソッドは削除します。
  # InventoryLoggable concern に log_inventory_changes, determine_operation_type が定義されているため、
  # Inventory モデル内の同名メソッドは削除します。

  # ============================================
  # TODO: 在庫ログ機能の拡張
  # ============================================
  # 1. アクティビティ分析機能
  #    - 在庫変動パターンの可視化
  #    - 操作の多いユーザーや製品の特定
  #    - 操作頻度のレポート生成
  #
  # 2. アラート機能との連携
  #    - 異常な在庫減少時の通知
  #    - 指定閾値を超える減少操作の検出
  #    - 定期的な在庫ログレポート生成
  #
  # 3. 監査証跡の強化
  #    - ログのエクスポート機能強化（PDF形式など）
  #    - 変更理由の入力機能
  #    - ログの改ざん防止機能（ハッシュチェーンなど）
  #
  # ============================================
  # TODO: 在庫アラート機能の実装
  # ============================================
  # 1. メール通知機能
  #    - 在庫切れ/在庫少時に管理者へ自動メール送信
  #    - 送信先/頻度を設定画面から調整可能に
  #    - ActionMailerを使用したHTMLメールテンプレート
  #
  # 2. 在庫切れ商品の自動レポート生成機能
  #    - 日次/週次/月次の定期レポート
  #    - PDFフォーマットでのエクスポート
  #    - Rubyプロセッサで集計 + プロセスをSidekiqで実行
  #
  # 3. アラート閾値の設定インターフェース
  #    - 商品ごとのカスタム閾値設定
  #    - カテゴリごとの一括設定機能
  #    - 在庫回転率に基づく推奨閾値自動計算

  # ============================================
  # TODO: バーコードスキャン対応
  # ============================================
  # 1. バーコードでの商品検索機能
  #    - JAN/EANコード対応
  #    - QRコード対応
  #    - WebカメラAPIを使用したブラウザスキャン
  #
  # 2. QRコード生成機能
  #    - 商品ごとのQRコード自動生成
  #    - ラベル印刷機能との連携
  #    - バッチ/ロット情報の埋め込み
  #
  # 3. モバイルスキャンアプリとの連携
  #    - iOS/Android対応アプリ開発
  #    - PWA対応のWebスキャナー実装
  #    - モバイル専用APIエンドポイント最適化
  #
  # ============================================
  # TODO: 高度な在庫分析機能
  # ============================================
  # 1. 在庫回転率の計算
  #    - 商品ごとの在庫回転率分析
  #    - カテゴリ別の比較グラフ
  #    - 回転率に基づく商品評価
  #
  # 2. 発注点（Reorder Point）の計算と通知
  #    - リードタイムを考慮した発注点計算
  #    - 安全在庫水準の自動推定
  #    - 発注点到達時の自動通知機能
  #
  # 3. 需要予測と最適在庫レベルの提案
  #    - 過去データに基づく将来需要予測
  #    - 機械学習モデルを活用した高度予測
  #    - 季節性・トレンドを考慮した予測
  #
  # 4. 履歴データに基づく季節変動分析
  #    - 月別・季節別の需要パターン分析
  #    - 季節イベントの影響度測定
  #    - 複数年データに基づく長期予測
  #
  # ============================================
  # TODO: システムテスト環境の整備
  # ============================================
  # 1. CapybaraとSeleniumの設定改善
  #    - ChromeDriver安定化対策
  #    - スクリーンショット自動保存機能
  #    - テスト失敗時のビデオ録画機能
  #
  # 2. Docker環境でのUIテスト対応
  #    - Dockerコンテナ内でのGUI非依存テスト
  #    - CI/CD環境での安定実行
  #    - 並列テスト実行の最適化
  #
  # 3. E2Eテストの実装
  #    - 複雑な業務フローのE2Eテスト
  #    - データ準備の自動化
  #    - テストカバレッジ向上策

  # CSV 一括インポート
  # CsvImportable concern のメソッドと重複するが、ユーザー指示のコード片を優先。
  # TODO: [CSV Import Refactor]
  #   - CsvImportable concern の import_from_csv メソッドとの機能重複を解消する。
  #     - 現状は Inventory モデル独自の簡易的な実装が優先されているが、
  #       concern側のより堅牢で汎用的な実装 (エラーハンドリング、ログ記録、コールバックなど) に統合することを検討する。
  #     - どちらの実装を主とするか、または両者の良い点を組み合わせるかを決定する。
  #   - 大量データインポート時のパフォーマンス改善のため activerecord-import gem の利用を検討する。
  #   - CSV.import_from_csv の処理をバックグラウンドジョブ (例: Sidekiq) に移行し、
  #     専用のキュー (例: 'imports') で処理することを検討する (特にファイルサイズが大きい場合)。
  def self.import_from_csv(file_path) # file_path を受け取るように変更 (RSpecのテストに合わせる)
    imported_count = 0
    invalid_records = []
    # RSpecのテストでは file.path を渡しているため、file_path をそのまま使用
    CSV.foreach(file_path, headers: true, encoding: "UTF-8") do |row| # encoding指定を追加
      begin
        # status が enum で定義された値以外の場合、ArgumentError が発生するためハンドリング
        status_value = row["status"]
        # statusがnilまたは空文字の場合は'active'をデフォルトとする
        status_value = "active" if status_value.blank?

        inv = new(
          name:     row["name"],
          quantity: row["quantity"].to_i,
          price:    row["price"].to_f,
          status:   status_value
        )
      rescue ArgumentError => e # 不正なstatus値の場合
        invalid_records << { row: row.to_h, errors: [ e.message ] }
        next # 次の行へ
      end
      inv.save ? imported_count += 1 : invalid_records << { row: row.to_h, errors: inv.errors.full_messages }
    end
    { imported: imported_count, invalid: invalid_records } # RSpecのテストに合わせる
  end
end
