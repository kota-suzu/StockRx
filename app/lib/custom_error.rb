module CustomError
  # カスタムエラーの基底クラス
  class BaseError < StandardError
    attr_reader :status, :code, :details

    # @param message [String] エラーメッセージ
    # @param details [Array<String>] エラー詳細（オプション）
    # @param status [Integer] HTTPステータスコード（デフォルト422）
    # @param code [Symbol, String] エラーコード（デフォルトnil、自動設定）
    def initialize(message = nil, details = [], status = nil, code = nil)
      @status = status || default_status
      @code = code || default_code
      @details = details || []

      # メッセージが省略された場合、自動生成（i18n対応）
      message ||= I18n.t("errors.code.#{@code}", default: default_message)
      super(message)
    end

    # デフォルトのHTTPステータスコード
    # サブクラスでオーバーライド可能
    def default_status
      422 # Unprocessable Entity
    end

    # デフォルトのエラーコード
    # サブクラスでオーバーライド可能
    def default_code
      self.class.name.demodulize.underscore
    end

    # デフォルトのエラーメッセージ
    # サブクラスでオーバーライド可能
    def default_message
      "処理中にエラーが発生しました"
    end
  end

  # ===== 具体的なエラークラス =====

  # リソース競合エラー
  class ResourceConflict < BaseError
    def default_status
      409 # Conflict
    end

    def default_code
      "conflict"
    end

    def default_message
      "リソースが競合しています。最新の情報に更新してから再試行してください"
    end
  end

  # 認可エラー（Punditと併用可能）
  class Forbidden < BaseError
    def default_status
      403 # Forbidden
    end

    def default_code
      "forbidden"
    end

    def default_message
      "この操作を行う権限がありません"
    end
  end

  # リクエスト頻度制限エラー
  class RateLimitExceeded < BaseError
    def default_status
      429 # Too Many Requests
    end

    def default_code
      "too_many_requests"
    end

    def default_message
      "短時間に多くのリクエストが行われました。しばらく待ってから再試行してください"
    end
  end
end
