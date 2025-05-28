# frozen_string_literal: true

# Selenium/Chrome関連のヘルパーメソッド
module SeleniumHelper
  # JavaScriptテストの実行可否を判定
  def javascript_test_available?
    @javascript_test_available ||= begin
      if File.exist?('/.dockerenv') || ENV['DOCKER_CONTAINER'].present?
        # Docker環境ではSeleniumサービスの存在を確認
        system('nc -z selenium 4444 > /dev/null 2>&1')
      else
        # ローカル環境ではChromeが利用可能か確認
        system('which chromedriver > /dev/null 2>&1')
      end
    rescue StandardError
      false
    end
  end

  # JavaScript必須テストの前処理
  def setup_javascript_driver
    if javascript_test_available?
      Capybara.current_driver = Capybara.javascript_driver
      true
    else
      skip 'JavaScriptテストはスキップされました（Selenium/Chromeが利用できません）'
      false
    end
  end

  # JavaScript必須テストの後処理
  def teardown_javascript_driver
    Capybara.use_default_driver
  end
end

# RSpecの設定に組み込み
RSpec.configure do |config|
  config.include SeleniumHelper, type: :feature

  # js: true タグが付いたテストの自動設定
  config.before(:each, js: true) do
    setup_javascript_driver
  end

  config.after(:each, js: true) do
    teardown_javascript_driver
  end
end
