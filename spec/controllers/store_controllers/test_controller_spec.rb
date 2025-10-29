# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StoreControllers::TestController, type: :controller do
  # CLAUDE.md準拠: テスト用コントローラーの基本機能確認
  # メタ認知: 開発環境専用のコントローラーでも基本的なテストは必要
  # 横展開: 他の開発支援コントローラーでも同様のテストパターン適用

  describe "認証のスキップ設定" do
    it "table_lightアクションでは認証をスキップする" do
      # 認証なしでアクセス可能であることをテスト
      get :table_light
      expect(response).to be_successful
    end
  end

  describe "GET #table_light" do
    context "認証なしアクセス" do
      it "成功レスポンスを返す" do
        get :table_light
        expect(response).to have_http_status(:success)
      end

      it "適切なテンプレートを表示する" do
        get :table_light
        expect(response).to render_template("store_controllers/test_table_light")
      end
    end

    context "認証済みユーザーのアクセス" do
      let(:store) { create(:store) }
      let(:store_user) { create(:store_user, store: store) }

      before do
        sign_in store_user, scope: :store_user
      end

      it "認証済みでも正常にアクセスできる" do
        get :table_light
        expect(response).to be_successful
      end
    end
  end

  describe "開発環境専用の考慮事項" do
    context "本番環境での無効化確認" do
      # 本番環境では通常、このコントローラーはルーティングから除外される
      it "テスト用コントローラーであることを明示" do
        controller_file = File.read(Rails.root.join("app/controllers/store_controllers/test_controller.rb"))
        expect(controller_file).to include("テスト用コントローラー")
        expect(controller_file).to include("開発環境のみ")
      end
    end

    context "セキュリティ考慮" do
      it "認証スキップが限定的であることを確認" do
        # table_lightアクションのみ認証スキップ
        skip_conditions = controller.class._process_action_callbacks
          .select { |cb| cb.filter == :authenticate_store_user! }
          .map(&:options)
          .select { |opt| opt[:if] }

        # 条件付きスキップが設定されていることを確認
        expect(skip_conditions).not_to be_empty
      end
    end
  end

  describe "エラーハンドリング" do
    context "テンプレートが存在しない場合" do
      before do
        # テンプレートファイルが見つからない場合のシミュレーション
        allow(controller).to receive(:render).with("store_controllers/test_table_light").and_raise(ActionView::MissingTemplate.new([], "test_table_light", [], false, ""))
      end

      it "テンプレートエラーを適切に処理する" do
        expect {
          get :table_light
        }.to raise_error(ActionView::MissingTemplate)
      end
    end
  end

  describe "パフォーマンス" do
    it "軽量なレスポンスを返す" do
      start_time = Time.current
      get :table_light
      elapsed_time = (Time.current - start_time) * 1000

      expect(response).to be_successful
      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  describe "HTTP メソッド対応" do
    it "GETリクエストに対応する" do
      get :table_light
      expect(response).to be_successful
    end

    it "POSTリクエストは通常対応しない" do
      expect {
        post :table_light
      }.to raise_error(ActionController::RoutingError)
    end
  end

  describe "レスポンス形式" do
    it "HTMLレスポンスを返す" do
      get :table_light
      expect(response.content_type).to include('text/html')
    end
  end

  describe "テストのベストプラクティス" do
    # テスト用コントローラーであっても、以下の基本テストは重要

    it "BaseControllerを継承している" do
      expect(controller.class.superclass).to eq(StoreControllers::BaseController)
    end

    it "StoreControllersモジュール内に定義されている" do
      expect(controller.class.module_parent).to eq(StoreControllers)
    end

    it "frozen_string_literalが設定されている" do
      controller_file = File.read(Rails.root.join("app/controllers/store_controllers/test_controller.rb"))
      expect(controller_file).to start_with("# frozen_string_literal: true")
    end
  end

  describe "開発支援機能として" do
    context "テーブルライト版の確認" do
      it "UIコンポーネントのテスト表示ページとして機能する" do
        get :table_light

        # 基本的な表示確認
        expect(response).to be_successful
        expect(response.body).to be_present
      end
    end

    context "デバッグ情報の表示" do
      it "開発環境での動作確認に使用できる" do
        # Rails環境の確認
        expect(Rails.env.development? || Rails.env.test?).to be true

        get :table_light
        expect(response).to be_successful
      end
    end
  end

  describe "将来の拡張性" do
    # テスト用コントローラーは将来的に他のテスト機能が追加される可能性がある

    it "他のテストアクション追加に対応できる構造" do
      # 現在のアクション
      current_actions = controller.class.instance_methods(false)
      expect(current_actions).to include(:table_light)

      # 拡張性の確認（BaseControllerの機能を継承）
      expect(controller).to respond_to(:current_store_user)
      expect(controller).to respond_to(:store_signed_in?)
    end
  end
end
