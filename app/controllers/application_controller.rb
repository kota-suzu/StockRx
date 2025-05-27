class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # 管理画面用ヘルパーはすべて「app/helpers」直下に配置し
  # Railsの規約に従ってモジュール名と一致させる
  # これによりZeitwerkのロード問題を解決
  # helper_method :some_method が必要であれば、ここに追加する
end
