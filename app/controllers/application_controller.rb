class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # リクエストごとにCurrentを設定
  before_action :set_current_attributes

  # 管理画面用ヘルパーはすべて「app/helpers」直下に配置し
  # Railsの規約に従ってモジュール名と一致させる
  # これによりZeitwerkのロード問題を解決
  # helper_method :some_method が必要であれば、ここに追加する

  private

  # Currentにリクエスト情報とユーザー情報を設定
  def set_current_attributes
    Current.reset
    Current.set_request_info(request)
    # ログイン機能実装後に有効化
    # Current.user = current_user if respond_to?(:current_user) && current_user
  end
end
