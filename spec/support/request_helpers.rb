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

  def json
    JSON.parse(response.body)
  end

  def json_response
    ActiveSupport::JSON.decode(response.body)
  end

  def auth_headers_for(user)
    post user_session_path, params: { user: { email: user.email, password: 'password' } }

    token = response.headers['Authorization']
    { 'Authorization' => token }
  end
end

# SQLクエリ数チェック用のカスタムマッチャー
RSpec::Matchers.define :exceed_query_limit do |expected|
  supports_block_expectations

  match do |block|
    @query_count = 0
    @queries = []

    # SQLクエリをカウントするためのSubscriberを追加
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
      unless payload[:name] =~ /SCHEMA|EXPLAIN/
        @query_count += 1
        @queries << payload[:sql]
      end
    end

    begin
      block.call
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    @query_count > expected
  end

  failure_message do |block|
    "expected SQL query count to exceed #{expected}, but got #{@query_count} queries:\n#{@queries.join("\n")}"
  end

  failure_message_when_negated do |block|
    "expected SQL query count not to exceed #{expected}, but got #{@query_count} queries:\n#{@queries.join("\n")}"
  end
end

RSpec.configure do |config|
  config.include RequestHelpers, type: :request
end
