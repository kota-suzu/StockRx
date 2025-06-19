# frozen_string_literal: true

# CSV Import Progress Channel
# ============================================
# CLAUDE.md準拠: リアルタイム進捗表示機能
# 優先度: 中（UX向上）
# ============================================
class ImportProgressChannel < ApplicationCable::Channel
  # チャンネル登録
  def subscribed
    # 認証チェック
    unless current_admin
      reject
      return
    end

    # CSVインポート用のストリーム名生成
    stream_name = "import_progress_#{current_admin.id}"
    stream_from stream_name

    Rails.logger.info "📡 Import progress channel subscribed: #{stream_name}"
  end

  # チャンネル登録解除
  def unsubscribed
    Rails.logger.info "📡 Import progress channel unsubscribed"
  end

  # 進捗更新受信
  def receive(data)
    # セキュリティ: クライアントからの受信は基本的に無視
    # サーバー側からのブロードキャストのみ処理
    Rails.logger.debug "📨 Import progress channel received: #{data}"
  end

  # プログレス通知メソッド（クラスメソッド）
  def self.broadcast_progress(admin_id, progress_data)
    # 進捗データの検証
    validated_data = validate_progress_data(progress_data)

    stream_name = "import_progress_#{admin_id}"

    Rails.logger.info "📤 Broadcasting import progress to #{stream_name}: #{validated_data[:status]}"

    # ActionCableでブロードキャスト
    ActionCable.server.broadcast(stream_name, validated_data)
  end

  # エラー通知メソッド
  def self.broadcast_error(admin_id, error_message, details = {})
    error_data = {
      status: "error",
      message: error_message.to_s.truncate(500), # セキュリティ: 長大なエラーメッセージを制限
      details: details.slice(:line_number, :csv_row, :error_type), # セキュリティ: 必要な情報のみ
      timestamp: Time.current.iso8601
    }

    broadcast_progress(admin_id, error_data)
  end

  # 完了通知メソッド
  def self.broadcast_completion(admin_id, result_data)
    completion_data = {
      status: "completed",
      message: "CSVインポートが完了しました",
      result: result_data.slice(:processed, :successful, :failed, :errors), # セキュリティ: 必要な情報のみ
      timestamp: Time.current.iso8601
    }

    broadcast_progress(admin_id, completion_data)
  end

  private

  # 進捗データのバリデーション（セキュリティ強化）
  def self.validate_progress_data(data)
    # 基本構造の確認
    validated = {
      status: sanitize_status(data[:status]),
      message: sanitize_message(data[:message]),
      timestamp: Time.current.iso8601
    }

    # 進捗情報の追加（statusがprogressの場合）
    if data[:status] == "progress"
      validated.merge!({
        progress: validate_progress_percentage(data[:progress]),
        processed: validate_count(data[:processed]),
        total: validate_count(data[:total]),
        current_item: sanitize_message(data[:current_item])
      })
    end

    # エラー情報の追加（statusがerrorの場合）
    if data[:status] == "error"
      validated.merge!({
        error_type: sanitize_error_type(data[:error_type]),
        line_number: validate_count(data[:line_number])
      })
    end

    # 結果情報の追加（statusがcompletedの場合）
    if data[:status] == "completed"
      validated.merge!({
        result: {
          processed: validate_count(data.dig(:result, :processed)),
          successful: validate_count(data.dig(:result, :successful)),
          failed: validate_count(data.dig(:result, :failed))
        }
      })
    end

    validated
  end

  # ステータスのサニタイゼーション
  def self.sanitize_status(status)
    allowed_statuses = %w[pending progress error completed cancelled]
    status.to_s.downcase.in?(allowed_statuses) ? status.to_s.downcase : "unknown"
  end

  # メッセージのサニタイゼーション
  def self.sanitize_message(message)
    return "" if message.blank?

    # HTMLタグ除去・長さ制限
    ActionView::Base.full_sanitizer.sanitize(message.to_s).truncate(200)
  end

  # 進捗パーセンテージのバリデーション
  def self.validate_progress_percentage(progress)
    percentage = progress.to_f
    [ [ percentage, 0 ].max, 100 ].min # 0-100の範囲に制限
  end

  # カウント値のバリデーション
  def self.validate_count(count)
    [ count.to_i, 0 ].max # 負数は0に修正
  end

  # エラータイプのサニタイゼーション
  def self.sanitize_error_type(error_type)
    allowed_types = %w[validation_error file_error processing_error system_error]
    error_type.to_s.downcase.in?(allowed_types) ? error_type.to_s.downcase : "unknown_error"
  end

  # 管理者認証の確認
  def current_admin
    # ApplicationCable::Connectionで設定されるcurrent_adminを使用
    connection.current_admin
  end
end

# ============================================
# TODO: 🟡 Phase 6（推奨）- 高度な進捗機能実装
# ============================================
# 優先度: 中（UX改善）
#
# 【計画中の拡張機能】
# 1. 📊 詳細進捗情報
#    - 処理速度（行/秒）の表示
#    - 推定残り時間の計算
#    - メモリ使用量の監視
#
# 2. 🎛️ インタラクティブ機能
#    - 処理のキャンセル機能
#    - 一時停止・再開機能
#    - 優先度調整機能
#
# 3. 📈 視覚化強化
#    - プログレスバーのアニメーション
#    - チャート形式での進捗表示
#    - エラー分析グラフ
#
# 4. 🔔 通知機能
#    - 完了時のブラウザ通知
#    - Slack / メール通知連携
#    - モバイル通知対応
# ============================================
