# frozen_string_literal: true

# CLAUDE.md準拠: 統一的なAPIエラーレスポンスフォーマット
# メタ認知: RESTful API設計原則に基づくエラー構造
# 横展開: 全APIエンドポイントで一貫性のあるエラーレスポンス

json.status "error"
json.code case @status
when 400 then "bad_request"
when 401 then "unauthorized"
when 403 then "forbidden"
when 404 then "resource_not_found"
when 406 then "not_acceptable"
when 409 then "conflict"
when 413 then "payload_too_large"
when 415 then "unsupported_media_type"
when 422 then "validation_error"
when 429 then "too_many_requests"
when 500 then "internal_server_error"
when 503 then "service_unavailable"
when 504 then "gateway_timeout"
else "unknown_error"
end

json.message @message || case @status
                         when 400 then "リクエストが不正です"
                         when 401 then "認証が必要です"
                         when 403 then "この操作を実行する権限がありません"
                         when 404 then "リソースが見つかりません"
                         when 406 then "要求された形式でレスポンスを生成できません"
                         when 409 then "リソースが競合しています"
                         when 413 then "リクエストボディが大きすぎます"
                         when 415 then "サポートされないメディアタイプです"
                         when 422 then "処理できないエンティティです"
                         when 429 then "リクエスト頻度が制限を超えています"
                         when 500 then "サーバー内部エラーが発生しました"
                         when 503 then "一時的にサービスを利用できません"
                         when 504 then "リクエストの処理がタイムアウトしました"
                         else "エラーが発生しました"
                         end

# 追加のエラー詳細がある場合
if @errors.present?
  json.errors @errors
end

# メタデータ
json.meta do
  json.timestamp Time.current.iso8601
  json.request_id request.request_id if request.request_id.present?

  # 特定のステータスコードに応じた追加情報
  case @status
  when 404
    json.resource_type params[:resource_type] if params[:resource_type].present?
    json.resource_id params[:resource_id] if params[:resource_id].present?
  when 429
    # レート制限情報
    if response.headers["Retry-After"].present?
      json.retry_after response.headers["Retry-After"]
    end
  when 413
    # ペイロードサイズ情報
    json.max_size "10MB"
    json.received_size request.content_length if request.content_length.present?
  end
end
