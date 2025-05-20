require "csv"

class Inventory < ApplicationRecord
  include InventoryStatistics

  has_many :batches, dependent: :destroy
  has_many :inventory_logs, dependent: :destroy

  # ステータス定義（Rails 8.0向けに更新）
  enum :status, { active: 0, archived: 1 }
  STATUSES = statuses.keys.freeze # 不変保証

  # バリデーション
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :quantity, numericality: { greater_than_or_equal_to: 0 }

  # コールバック
  after_save :log_inventory_changes, if: :saved_change_to_quantity?

  # スコープ
  scope :active, -> { where(status: :active) }

  # バルク登録用クラスメソッド
  class << self
    # CSVからの一括インポート
    # @param file [ActionDispatch::Http::UploadedFile|String] CSVファイルまたはファイルパス
    # @param options [Hash] インポートオプション
    # @option options [Integer] :batch_size バッチサイズ（デフォルト1000件）
    # @option options [Boolean] :update_existing 既存レコードを更新するかどうか（デフォルトfalse）
    # @option options [String] :unique_key 既存レコード識別に使用するキー（デフォルト'name'）
    # @return [Hash] インポート結果
    def import_from_csv(file, options = {})
      # オプションの初期値設定
      batch_size = options[:batch_size] || 1000
      update_existing = options[:update_existing] || false
      unique_key = options[:unique_key] || "name"

      # CSVデータの検証
      valid_records = []
      invalid_records = []
      update_records = []

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

          # 既存レコードの検索（更新モードの場合）
          existing_record = nil
          if update_existing && row[unique_key].present?
            # 安全なクエリのために許可されたカラム名かチェック
            if %w[name code sku barcode].include?(unique_key)
              # シンボルをカラム名として使用することでSQLインジェクションを防止
              existing_record = where({ unique_key.to_sym => row[unique_key] }).first
            else
              # 許可されていないカラム名の場合はデフォルトのnameを使用
              Rails.logger.warn("不正なunique_keyが指定されました: #{unique_key} - デフォルトの'name'を使用します")
              existing_record = where(name: row["name"]).first
            end
          end

          if existing_record
            # 既存レコードを更新
            existing_record.assign_attributes(
              quantity: row["quantity"].to_i,
              price: row["price"].to_f,
              status: status_value
            )

            if existing_record.valid?
              update_records << existing_record
            else
              invalid_records << { row: row, errors: existing_record.errors.full_messages }
            end
          else
            # 新規レコードを作成
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
          end

          # バッチサイズに達したら処理実行
          if valid_records.size >= batch_size
            bulk_insert(valid_records)
            valid_records = [] # バッファをクリア
          end

          if update_records.size >= batch_size
            bulk_update(update_records)
            update_records = [] # バッファをクリア
          end
        end

        # 残りのレコードを処理
        bulk_insert(valid_records) if valid_records.present?
        bulk_update(update_records) if update_records.present?
      end

      {
        valid_count: valid_records.size,
        update_count: update_records.size,
        invalid_records: invalid_records
      }
    end

    private

    # 有効なレコードをバルクインサートするプライベートメソッド
    # @param records [Array<Inventory>] インサートするInventoryオブジェクトの配列
    def bulk_insert(records)
      return if records.blank?

      # 挿入レコードの属性を収集
      inventory_attributes = records.map do |record|
        record.attributes.except("id", "created_at", "updated_at").merge(
          created_at: Time.current,
          updated_at: Time.current
        )
      end

      # Rails 6+の場合はinsert_allを使用
      result = Inventory.insert_all(inventory_attributes)

      # 在庫ログ用のデータを作成（bulk_insertでは通常のコールバックが動作しないため）
      create_bulk_inventory_logs(records, result.rows) if result.rows.present?

      result
    end

    # バルクインサート後の在庫ログ一括作成
    # @param records [Array<Inventory>] インサートしたInventoryオブジェクト
    # @param inserted_ids [Array<Array>] insert_allの戻り値（主キーの配列）
    def create_bulk_inventory_logs(records, inserted_ids)
      return if records.blank? || inserted_ids.blank?

      # ログ用の属性を作成
      inventory_log_attributes = []

      inserted_ids.each_with_index do |id_array, idx|
        inventory_id = id_array.first  # MySQLの場合は一次元配列
        record = records[idx]
        next if record.blank?

        inventory_log_attributes << {
          inventory_id: inventory_id,
          delta: record.quantity,  # 新規作成なので全量がdelta
          operation_type: "add",   # 新規作成は常に追加
          previous_quantity: 0,    # 新規なので前の数量は0
          current_quantity: record.quantity,
          user_id: defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil,
          note: "CSVインポートによる自動作成",
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      # ログをバルクインサート
      InventoryLog.insert_all(inventory_log_attributes) if inventory_log_attributes.present?
    rescue => e
      # ログインサートエラーはメインの処理に影響を与えないよう捕捉
      Rails.logger.error("CSVインポート後のログ記録エラー: #{e.message}")
    end

    # 既存レコードをバルク更新するプライベートメソッド
    # @param records [Array<Inventory>] 更新するInventoryオブジェクトの配列
    def bulk_update(records)
      return if records.blank?

      records.each do |record|
        # 変更内容を保存
        old_quantity = record.quantity_was || 0
        new_quantity = record.quantity

        # レコード更新（after_saveコールバックが発火）
        record.save!

        # 注：ここではlog_inventory_changesコールバックが自動で呼ばれるため、
        # 明示的なログ追加は不要
      end
    rescue => e
      Rails.logger.error("バルク更新エラー: #{e.message}")
      raise e # トランザクションをロールバックするため再スロー
    end
  end

  # バッチの合計数量を取得するメソッド
  def total_batch_quantity
    batches.sum(:quantity)
  end


  # 期限切れのバッチを取得するメソッド
  def expired_batches
    batches.expired
  end

  # 期限切れが近いバッチを取得するメソッド
  def expiring_soon_batches(days = 30)
    batches.expiring_soon(days)
  end

  # 在庫数量変更時にログを記録するコールバックメソッド
  private

  def log_inventory_changes
    previous_quantity = saved_change_to_quantity.first || 0
    current_quantity = quantity
    delta = current_quantity - previous_quantity

    inventory_logs.create!(
      delta: delta,
      operation_type: determine_operation_type(delta),
      previous_quantity: previous_quantity,
      current_quantity: current_quantity,
      # Current.userが設定されていない場合はnilのままでOK（optional: true）
      user_id: defined?(Current) && Current.respond_to?(:user) ? Current.user&.id : nil,
      note: "自動記録：数量変更"
    )
  rescue => e
    # ログ記録に失敗しても在庫更新自体は続行する（エラーログに記録）
    Rails.logger.error("在庫ログ記録エラー: #{e.message}")
  end

  def determine_operation_type(delta)
    case
    when delta > 0 then "add"
    when delta < 0 then "remove"
    else "adjust"
    end
  end

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
  #
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
  #
end
