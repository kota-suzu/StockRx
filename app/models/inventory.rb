require "csv"

class Inventory < ApplicationRecord
  has_many :batches, dependent: :destroy

  # ステータス定義（Rails 8.0向けに更新）
  enum :status, { active: 0, archived: 1 }
  STATUSES = statuses.keys.freeze # 不変保証

  # バリデーション
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  # スコープ
  scope :active, -> { where(status: :active) }
  scope :out_of_stock, -> { where(quantity: 0) }
  scope :low_stock, ->(threshold = nil) { where("quantity > 0 AND quantity <= ?", threshold || 5) }

  # バルク登録用クラスメソッド
  class << self
    # CSVからの一括インポート
    # @param file [ActionDispatch::Http::UploadedFile|String] CSVファイルまたはファイルパス
    # @param options [Hash] インポートオプション
    # @option options [Integer] :batch_size バッチサイズ（デフォルト1000件）
    # @return [Hash] インポート結果
    def import_from_csv(file, options = {})
      # オプションの初期値設定
      batch_size = options[:batch_size] || 1000

      # CSVデータの検証
      valid_records = []
      invalid_records = []

      # ファイルパスまたはアップロードされたファイルを処理
      file_path = file.respond_to?(:path) ? file.path : file

      # トランザクション内で処理
      ActiveRecord::Base.transaction do
        CSV.foreach(file_path, headers: true) do |row|
          # ステータスのバリデーション（無効な値の場合はデフォルト値を使用）
          status_value = row["status"].presence || "active"
          unless STATUSES.include?(status_value)
            status_value = "active" # デフォルト値を使用
          end

          inventory = new(
            name: row["name"],
            quantity: row["quantity"].to_i,
            price: row["price"].to_f,
            status: status_value
          )

          if inventory.valid?
            valid_records << inventory
          else
            invalid_records << { row: row, errors: inventory.errors.full_messages }
          end

          # バッチサイズに達したらバルクインサート実行
          if valid_records.size >= batch_size
            bulk_insert(valid_records)
            valid_records = [] # バッファをクリア
          end
        end

        # 残りのレコードをバルクインサート
        bulk_insert(valid_records) if valid_records.present?
      end

      { valid_count: valid_records.size, invalid_records: invalid_records }
    end

    private

    # 有効なレコードをバルクインサートするプライベートメソッド
    # @param records [Array<Inventory>] インサートするInventoryオブジェクトの配列
    def bulk_insert(records)
      return if records.blank?

      # Rails 6+の場合はinsert_allを使用
      Inventory.insert_all(
        records.map { |record|
          record.attributes.except("id", "created_at", "updated_at").merge(
            created_at: Time.current,
            updated_at: Time.current
          )
        }
      )

      # TODO: activerecord-importを使用する場合の実装（必要に応じて）
      # 例: Inventory.import records, validate: false
    end
  end

  # バッチの合計数量を取得するメソッド
  def total_batch_quantity
    batches.sum(:quantity)
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

  # 期限切れのバッチを取得するメソッド
  def expired_batches
    batches.expired
  end

  # 期限切れが近いバッチを取得するメソッド
  def expiring_soon_batches(days = 30)
    batches.expiring_soon(days)
  end

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
  #    - 商品カテゴリごとの閾値設定
  #    - ユーザーインターフェースの実装
  #    - データベース設計の拡張

  # ============================================
  # TODO: バーコードスキャン対応
  # ============================================
  # 1. バーコードでの商品検索機能
  #    - バーコードスキャナーからの入力対応
  #    - JavaScript/モバイル対応（PWA対応）
  #    - バーコード規格: JAN/EAN-13対応
  #
  # 2. QRコード生成機能
  #    - 商品情報をQRコードとして出力
  #    - QRコードをPDFラベルとして印刷
  #    - rqrcode gemを使用
  #
  # 3. モバイルスキャンアプリとの連携
  #    - REST APIの拡張
  #    - JWT認証の実装
  #    - スマートフォンカメラでのスキャン対応

  # ============================================
  # TODO: 高度な在庫分析機能
  # ============================================
  # 1. 在庫回転率の計算
  #    - 期間ごとの在庫回転率
  #    - 分析データのグラフ表示
  #    - ChartJSまたはD3.jsでのデータ可視化
  #
  # 2. 発注点（Reorder Point）の計算と通知
  #    - リードタイムと需要予測に基づく発注点自動計算
  #    - 自動発注通知
  #    - 安全在庫の計算ロジック
  #
  # 3. 需要予測と最適在庫レベルの提案
  #    - 過去のデータに基づく機械学習予測
  #    - 季節性要因の分析
  #    - 在庫コスト最適化
  #
  # 4. 履歴データに基づく季節変動分析
  #    - 季節ごとの需要パターン分析
  #    - トレンド予測
  #    - ビジネスインテリジェンスダッシュボード

  # ============================================
  # TODO: システムテスト環境の整備
  # ============================================
  # 1. CapybaraとSeleniumの設定改善
  #    - ヘッドレスChromeでのテスト実行
  #    - スクリーンショット自動保存
  #    - CIパイプラインとの統合
  #
  # 2. Docker環境でのUIテスト対応
  #    - Seleniumコンテナとの連携
  #    - ネットワーク設定の最適化
  #    - テスト用のDocker Compose設定
  #
  # 3. E2Eテストの実装
  #    - 主要ユーザーフローのE2Eテスト
  #    - フィーチャーごとのテスト分離
  #    - テストデータ生成の自動化
end
