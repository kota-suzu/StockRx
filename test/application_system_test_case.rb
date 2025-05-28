require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Seleniumドライバーの可用性チェック
  def self.selenium_available?
    begin
      if ENV["DOCKER_CONTAINER"].present? || File.exist?("/.dockerenv")
        # Docker環境ではSeleniumサービスの存在を確認
        system("nc -z selenium 4444 > /dev/null 2>&1")
      else
        # ローカル環境ではChromeが利用可能か確認
        system("which chromedriver > /dev/null 2>&1")
      end
    rescue
      false
    end
  end

  # Seleniumが利用可能な場合のみ設定
  if selenium_available?
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
  else
    # Selenium/Chromeが利用できない場合はrack_testを使用
    # TODO: システムテストでJavaScriptが必要な場合は別途対応が必要
    driven_by :rack_test
    puts "警告: Selenium/Chromeが利用できないため、rack_testドライバーを使用します"
  end
end
