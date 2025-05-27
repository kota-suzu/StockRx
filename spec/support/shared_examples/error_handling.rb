# frozen_string_literal: true

# エラーハンドリングの共通テストモジュール
# 使い方: コントローラスペックで `it_behaves_like "handles not found error"` のように呼び出す

# 404 Not Found エラーハンドリングの共通テスト
RSpec.shared_examples "handles not found error" do
  let(:non_existent_id) { "non-existent-id" }

  it "returns 404 for non-existent resource" do
    get :show, params: { id: non_existent_id }
    expect(response).to have_http_status(:not_found)

    # JSONリクエストの場合はJSONレスポンスのフォーマットも検証
    if request.format.json? || request.headers["Accept"] == "application/json"
      json = JSON.parse(response.body)
      expect(json["code"]).to eq("resource_not_found")
      expect(json).to have_key("message")
    end
  end
end

# 422 Validation Error ハンドリングの共通テスト
RSpec.shared_examples "handles validation error" do |action, params_method, valid_params|
  let(:invalid_params) { send(params_method).merge(invalid_attribute) }
  let(:invalid_attribute) { { name: "" } } # デフォルト - オーバーライド可能

  it "returns 422 for invalid parameters" do
    # action（:create, :updateなど）に応じてHTTPメソッドを選択
    case action
    when :create
      post :create, params: invalid_params, format: format
    when :update
      put :update, params: invalid_params, format: format
    else
      raise "Unsupported action: #{action}"
    end

    expect(response).to have_http_status(:unprocessable_entity)

    # JSONリクエストの場合はレスポンス形式を検証
    if request.format.json? || request.headers["Accept"] == "application/json"
      json = JSON.parse(response.body)
      expect(json["code"]).to eq("validation_error")
      expect(json).to have_key("message")
      expect(json).to have_key("details")
      expect(json["details"]).to be_an(Array)
      expect(json["details"]).not_to be_empty
    end
  end
end

# 403 Forbidden エラーハンドリングの共通テスト
# Pundit使用時を想定
RSpec.shared_examples "handles authorization error" do |action, params_method|
  before do
    # モックされたPunditポリシーでアクセス拒否を発生させる準備
    # テスト対象のコントローラに応じて適切なポリシークラスをモック
    policy_double = instance_double("SomePolicy", "#{action}?": false)
    allow(controller).to receive(:authorize).and_raise(Pundit::NotAuthorizedError.new("Access denied"))
  end

  it "returns 403 when authorized fails" do
    # リクエスト実行
    case action
    when :show
      get :show, params: send(params_method), format: format
    when :create
      post :create, params: send(params_method), format: format
    when :update
      put :update, params: send(params_method), format: format
    when :destroy
      delete :destroy, params: send(params_method), format: format
    else
      raise "Unsupported action: #{action}"
    end

    expect(response).to have_http_status(:forbidden)

    # JSONリクエストの場合はレスポンス形式を検証
    if request.format.json? || request.headers["Accept"] == "application/json"
      json = JSON.parse(response.body)
      expect(json["code"]).to eq("forbidden")
      expect(json).to have_key("message")
    end
  end
end

# 409 Conflict エラーハンドリングの共通テスト
# 楽観的ロック（StaleObjectError）またはカスタムエラーをテスト
RSpec.shared_examples "handles conflict error" do |action, params_method|
  before do
    # テスト対象のコントローラアクションでResourceConflictエラーが発生するようセットアップ
    allow_any_instance_of(model_class).to receive(:update!).and_raise(
      CustomError::ResourceConflict.new("リソースが競合しています")
    )
  end

  it "returns 409 on resource conflict" do
    # リクエスト実行（通常はPUTリクエスト）
    put :update, params: send(params_method), format: format

    expect(response).to have_http_status(:conflict)

    # JSONリクエストの場合はレスポンス形式を検証
    if request.format.json? || request.headers["Accept"] == "application/json"
      json = JSON.parse(response.body)
      expect(json["code"]).to eq("conflict")
      expect(json).to have_key("message")
    end
  end
end

# 400 Bad Request エラーハンドリングの共通テスト
RSpec.shared_examples "handles parameter missing error" do |action|
  # 必須パラメータを持たないパラメータ
  let(:missing_param_request) { { invalid_root: { some_attribute: "value" } } }

  it "returns 400 when required parameter is missing" do
    # ActionController::ParameterMissingエラーを発生させるリクエスト
    case action
    when :create
      post :create, params: missing_param_request, format: format
    when :update
      put :update, params: missing_param_request, format: format
    else
      raise "Unsupported action: #{action}"
    end

    expect(response).to have_http_status(:bad_request)

    # JSONリクエストの場合はレスポンス形式を検証
    if request.format.json? || request.headers["Accept"] == "application/json"
      json = JSON.parse(response.body)
      expect(json["code"]).to eq("parameter_missing")
      expect(json).to have_key("message")
    end
  end
end
