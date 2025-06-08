# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiResponse do
  describe "ファクトリーメソッド" do
    describe ".success" do
      it "成功レスポンスを作成する" do
        data = { id: 1, name: "Test" }
        response = described_class.success(data, "成功しました")

        expect(response.successful?).to be true
        expect(response.data).to eq(data)
        expect(response.message).to eq("成功しました")
        expect(response.status_code).to eq(200)
        expect(response.errors).to be_empty
      end

      it "メッセージ省略時にデフォルトメッセージを使用する" do
        response = described_class.success("test data")
        expect(response.message).to include("処理が正常に完了しました")
      end
    end

    describe ".created" do
      it "作成成功レスポンスを作成する" do
        data = { id: 2, name: "Created" }
        response = described_class.created(data)

        expect(response.successful?).to be true
        expect(response.data).to eq(data)
        expect(response.status_code).to eq(201)
        expect(response.message).to eq("リソースが正常に作成されました")
      end
    end

    describe ".no_content" do
      it "No Contentレスポンスを作成する" do
        response = described_class.no_content

        expect(response.successful?).to be true
        expect(response.data).to be_nil
        expect(response.status_code).to eq(204)
      end
    end

    describe ".error" do
      it "エラーレスポンスを作成する" do
        response = described_class.error("エラーメッセージ", [ "詳細1", "詳細2" ], 422)

        expect(response.failed?).to be true
        expect(response.message).to eq("エラーメッセージ")
        expect(response.errors).to eq([ "詳細1", "詳細2" ])
        expect(response.status_code).to eq(422)
      end
    end

    describe ".validation_error" do
      it "バリデーションエラーレスポンスを作成する" do
        errors = [ "名前は必須です", "価格は0以上である必要があります" ]
        response = described_class.validation_error(errors)

        expect(response.failed?).to be true
        expect(response.status_code).to eq(422)
        expect(response.errors).to eq(errors)
        expect(response.metadata[:type]).to eq("validation_error")
      end
    end

    describe ".not_found" do
      it "Not Foundレスポンスを作成する" do
        response = described_class.not_found("在庫")

        expect(response.failed?).to be true
        expect(response.status_code).to eq(404)
        expect(response.message).to eq("在庫が見つかりません")
        expect(response.metadata[:type]).to eq("not_found")
      end
    end

    describe ".forbidden" do
      it "Forbiddenレスポンスを作成する" do
        response = described_class.forbidden

        expect(response.failed?).to be true
        expect(response.status_code).to eq(403)
        expect(response.metadata[:type]).to eq("forbidden")
      end
    end

    describe ".conflict" do
      it "Conflictレスポンスを作成する" do
        response = described_class.conflict

        expect(response.failed?).to be true
        expect(response.status_code).to eq(409)
        expect(response.metadata[:type]).to eq("conflict")
      end
    end

    describe ".rate_limited" do
      it "Rate Limitedレスポンスを作成する" do
        response = described_class.rate_limited("制限中", 120)

        expect(response.failed?).to be true
        expect(response.status_code).to eq(429)
        expect(response.metadata[:retry_after]).to eq(120)
      end
    end

    describe ".internal_error" do
      it "Internal Errorレスポンスを作成する" do
        response = described_class.internal_error

        expect(response.failed?).to be true
        expect(response.status_code).to eq(500)
        expect(response.metadata[:type]).to eq("internal_error")
      end
    end
  end

  describe ".from_exception" do
    it "ActiveRecord::RecordNotFoundからNot Foundレスポンスを作成する" do
      exception = ActiveRecord::RecordNotFound.new("Couldn't find Inventory")
      allow(exception).to receive(:model).and_return("Inventory")

      response = described_class.from_exception(exception)
      expect(response.status_code).to eq(404)
    end

    it "ActiveRecord::RecordInvalidからバリデーションエラーレスポンスを作成する" do
      inventory = build(:inventory, name: nil)
      inventory.valid? # エラーを発生させる
      exception = ActiveRecord::RecordInvalid.new(inventory)

      response = described_class.from_exception(exception)
      expect(response.status_code).to eq(422)
      expect(response.errors).not_to be_empty
    end

    it "CustomError::ResourceConflictから競合レスポンスを作成する" do
      exception = CustomError::ResourceConflict.new("競合エラー")

      response = described_class.from_exception(exception)
      expect(response.status_code).to eq(409)
    end

    it "その他の例外から内部エラーレスポンスを作成する" do
      exception = StandardError.new("予期しないエラー")

      response = described_class.from_exception(exception)
      expect(response.status_code).to eq(500)
    end
  end

  describe "インスタンスメソッド" do
    let(:success_response) { described_class.success("data", "成功") }
    let(:error_response) { described_class.error("失敗", [], 400) }

    describe "#successful?" do
      it "成功レスポンスでtrueを返す" do
        expect(success_response.successful?).to be true
      end

      it "エラーレスポンスでfalseを返す" do
        expect(error_response.successful?).to be false
      end
    end

    describe "#failed?" do
      it "成功レスポンスでfalseを返す" do
        expect(success_response.failed?).to be false
      end

      it "エラーレスポンスでtrueを返す" do
        expect(error_response.failed?).to be true
      end
    end

    describe "#client_error?" do
      it "4xxエラーでtrueを返す" do
        expect(error_response.client_error?).to be true
      end

      it "200でfalseを返す" do
        expect(success_response.client_error?).to be false
      end
    end

    describe "#server_error?" do
      let(:server_error_response) { described_class.internal_error }

      it "5xxエラーでtrueを返す" do
        expect(server_error_response.server_error?).to be true
      end

      it "4xxエラーでfalseを返す" do
        expect(error_response.server_error?).to be false
      end
    end
  end

  describe "出力機能" do
    let(:response) { described_class.success({ id: 1 }, "成功") }

    describe "#to_h" do
      it "ハッシュ形式で出力する" do
        hash = response.to_h

        expect(hash).to include(
          :success, :data, :message, :errors, :metadata
        )
        expect(hash[:success]).to be true
        expect(hash[:data]).to eq({ id: 1 })
      end
    end

    describe "#to_json" do
      it "JSON形式で出力する" do
        json_string = response.to_json
        parsed = JSON.parse(json_string)

        expect(parsed).to include("success", "data", "message")
        expect(parsed["success"]).to be true
      end
    end

    describe "#headers" do
      it "適切なHTTPヘッダーを生成する" do
        headers = response.headers

        expect(headers['Content-Type']).to eq('application/json; charset=utf-8')
        expect(headers['X-Content-Type-Options']).to eq('nosniff')
        expect(headers['X-Frame-Options']).to eq('DENY')
        expect(headers['X-XSS-Protection']).to eq('1; mode=block')
      end

      it "Rate Limitedの場合にRetry-Afterヘッダーを追加する" do
        rate_limited_response = described_class.rate_limited("制限中", 60)
        headers = rate_limited_response.headers

        expect(headers['Retry-After']).to eq('60')
      end
    end
  end

  describe "Rails統合機能" do
    let(:response) { described_class.success("data") }

    describe "#render_options" do
      it "Railsのrenderメソッド用オプションを生成する" do
        options = response.render_options

        expect(options).to include(:json, :status, :headers)
        expect(options[:status]).to eq(200)
        expect(options[:json]).to be_a(Hash)
      end
    end
  end

  describe "ページネーション統合" do
    let(:search_result) { double('SearchResult') }

    before do
      allow(search_result).to receive(:pagination_info).and_return({
        current_page: 1, total_pages: 3
      })
      allow(search_result).to receive(:search_metadata).and_return({
        execution_time: 0.1
      })
      allow(search_result).to receive(:sanitized_records).and_return([])
      allow(search_result).to receive(:total_count).and_return(0)
    end

    describe ".paginated" do
      it "SearchResultからページネーションレスポンスを作成する" do
        response = described_class.paginated(search_result)

        expect(response.successful?).to be true
        expect(response.metadata).to include(:pagination, :search)
      end
    end
  end

  describe "エラー正規化" do
    it "文字列エラーを配列に変換する" do
      response = described_class.error("メッセージ", "単一エラー")
      expect(response.errors).to eq([ "単一エラー" ])
    end

    it "ハッシュエラーを配列に変換する" do
      hash_errors = { name: [ "必須です" ], price: [ "正の数である必要があります" ] }
      response = described_class.error("メッセージ", hash_errors)

      expect(response.errors).to include("name: 必須です", "price: 正の数である必要があります")
    end

    it "ActiveModel::Errorsを配列に変換する" do
      inventory = build(:inventory, name: nil)
      inventory.valid?

      response = described_class.error("メッセージ", inventory.errors)
      expect(response.errors).to be_an(Array)
      expect(response.errors).not_to be_empty
    end
  end

  describe "メタデータ機能" do
    it "ベースメタデータを含む" do
      response = described_class.success("data")

      expect(response.metadata).to include(:timestamp, :request_id, :version)
    end

    it "現在の管理者IDを含む" do
      admin = create(:admin)
      allow(Current).to receive(:admin).and_return(admin)

      response = described_class.success("data")
      expect(response.metadata[:admin_id]).to eq(admin.id)
    end
  end

  describe "ログ出力機能" do
    let(:response) { described_class.success("data") }

    describe "#log_summary" do
      it "ログ用サマリーを生成する" do
        summary = response.log_summary

        expect(summary).to include(
          :success, :status_code, :message, :error_count, :request_id
        )
      end

      context "本番環境でない場合" do
        before { allow(Rails.env).to receive(:production?).and_return(false) }

        it "データタイプを含む" do
          summary = response.log_summary
          expect(summary).to include(:data_type, :metadata_keys)
        end
      end

      context "本番環境の場合" do
        before { allow(Rails.env).to receive(:production?).and_return(true) }

        it "機密データを除外する" do
          summary = response.log_summary
          expect(summary).not_to include(:data_type, :metadata_keys)
        end
      end
    end
  end

  describe "データシリアライゼーション" do
    it "ActiveRecordオブジェクトをシリアライズする" do
      inventory = create(:inventory)
      response = described_class.success(inventory)

      serialized_data = response.send(:serialize_data)
      expect(serialized_data).to be_a(Hash)
    end

    it "配列をシリアライズする" do
      inventories = create_list(:inventory, 2)
      response = described_class.success(inventories)

      serialized_data = response.send(:serialize_data)
      expect(serialized_data).to be_an(Array)
      expect(serialized_data.size).to eq(2)
    end

    it "SearchResultをシリアライズする" do
      # 実際のSearchResultインスタンスを作成
      inventories = create_list(:inventory, 2)
      search_result = SearchResult.new(
        records: Inventory.where(id: inventories.map(&:id)),
        total_count: 2,
        current_page: 1,
        per_page: 10,
        conditions_summary: "テスト",
        query_metadata: {},
        execution_time: 0.1,
        search_params: {}
      )

      response = described_class.success(search_result)
      serialized_data = response.send(:serialize_data)

      expect(serialized_data).to include(:data, :pagination, :metadata)
    end
  end
end
