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

  # ユーザーエージェント情報（モバイルアプリ連携時に利用）
  attribute :user_agent

  # 操作の理由（オプション、管理操作の監査証跡に利用）
  attribute :reason

  # リクエスト情報の設定
  # @param request [ActionDispatch::Request] リクエストオブジェクト
  def set_request_info(request)
    return unless request
    self.request_id = request.uuid
    self.ip_address = request.remote_ip
    self.user_agent = request.user_agent
  end

  # ActiveSupport::CurrentAttributes#resetをオーバーライド
  # 引数なしで呼び出せるようにする
  def reset
    super()
  end
end
