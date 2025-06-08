# frozen_string_literal: true

module RequestHelpers
  def default_headers
    {
      'Host' => 'localhost',
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def html_headers
    {
      'Host' => 'localhost',
      'Content-Type' => 'application/x-www-form-urlencoded',
      'Accept' => 'text/html'
    }
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
