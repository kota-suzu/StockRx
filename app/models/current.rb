# リクエストごとの情報を保持するためのシングルトンクラス
# @see https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html
#
# 注意: ActiveSupport::CurrentAttributesの使用に関する注意点
# 1. #resetメソッドは引数を取らないように実装する必要があります
#    - 親クラスの#resetメソッドは引数なしのため、オーバーライド時に引数があるとArgumentErrorが発生
#    - 修正履歴: 2025-02-XX ArgumentError対応（引数ありresetメソッド→引数なしresetに変更）
# 2. リクエスト情報を設定するには別途メソッド(set_request_info)を用意する
# 3. テスト内でCurrentを使う場合は、テスト終了時にreset()を呼び出す
class Current < ActiveSupport::CurrentAttributes
  # 属性の定義
  attribute :user
  attribute :request_id
  attribute :ip_address

  # リクエストオブジェクト（テスト互換性のため）
  attribute :request

  # ユーザーエージェント情報（モバイル連携時に利用）
  attribute :user_agent

  # API バージョン情報（API リクエスト時に利用）
  attribute :api_version

  # API クライアント情報（API リクエスト時に利用）
  attribute :api_client

  # 管理者情報（認証されたadminユーザー）
  attribute :admin

  # 店舗ユーザー情報（認証された店舗ユーザー）
  # 店舗コントローラーで設定され、監査ログで使用
  attribute :store_user

  # 店舗情報（現在の店舗コンテキスト）
  # 店舗スコープでの操作時に設定
  attribute :store

  # 操作の理由（オプション、管理操作の監査証跡に利用）
  attribute :reason

  # 在庫操作ソース（アプリ、API、バッチ処理、インポート等）
  attribute :operation_source

  # 在庫操作タイプ（手動、自動、バルク、等）
  attribute :operation_type

  # リクエスト情報の設定
  # @param request [ActionDispatch::Request] リクエストオブジェクト
  def set_request_info(request)
    return unless request
    self.request_id = request.uuid
    self.ip_address = request.remote_ip
    self.user_agent = request.user_agent

    # デフォルトの操作元をwebに設定
    self.operation_source ||= "web"
  end

  # 操作情報の設定
  # @param source [String] 操作元情報
  # @param type [String] 操作種別
  # @param reason [String] 操作理由
  def set_operation_info(source: nil, type: nil, reason: nil)
    self.operation_source = source if source
    self.operation_type = type if type
    self.reason = reason if reason
  end

  # ActiveSupport::CurrentAttributes#resetをオーバーライド
  # 引数なしで呼び出せるようにする
  def reset
    super()
  end

  # リクエストごとに情報をリセットする
  # ApplicationControllerのbefore_actionで呼び出されることを想定
  def self.reset
    super
  end

  # リクエスト情報を設定
  def self.set_request_info(request)
    self.request_id = request.request_id
    self.ip_address = request.remote_ip
    self.user_agent = request.user_agent
  end

  # 在庫操作情報を設定
  def self.set_operation_info(source, type = nil, reason = nil)
    self.operation_source = source
    self.operation_type = type if type
    self.reason = reason if reason
  end

  # バッチ処理用の操作情報を設定
  def self.set_batch_operation(job_name, reason = nil)
    set_operation_info("batch", "automated", reason || "バッチ処理: #{job_name}")
  end

  # インポート操作情報を設定
  def self.set_import_operation(import_type, reason = nil)
    set_operation_info("import", import_type, reason || "データインポート: #{import_type}")
  end

  # ============================================
  # TODO: 🟡 Phase 3（重要）- Current機能拡張
  # ============================================
  # 優先度: 中（監査・セキュリティ強化）
  # 実装内容:
  #   - 店舗ユーザー用ヘルパーメソッド追加
  #   - 権限ベースの情報設定メソッド
  #   - 自動リセット機能の強化
  #   - パフォーマンス監視機能
  # 期待効果: 監査精度向上、権限制御強化、開発効率向上

  # TODO: 🟢 Phase 4（推奨）- 横展開と統合
  # 優先度: 中（アーキテクチャ統一）
  # 実装内容:
  #   - API認証との統合（Current.user設定）
  #   - WebSocket接続時のコンテキスト管理
  #   - 多店舗同時操作時のコンテキスト分離
  #   - リクエストID連携強化
  # 期待効果: システム全体の一貫性、リアルタイム機能対応
end
