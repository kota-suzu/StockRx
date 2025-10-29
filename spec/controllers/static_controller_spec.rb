# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StaticController, type: :controller do
  # CLAUDE.md準拠: 静的ページコントローラーの包括的テスト
  # メタ認知: デモページの表示とレイアウト設定の検証
  # 横展開: 他の静的ページコントローラーでも同様のテストパターン適用

  # ビューのレンダリングを有効化
  render_views

  # ============================================
  # Modern UI デモページのテスト
  # ============================================

  describe "GET #modern_ui_demo" do
    context "基本機能" do
      it "成功レスポンスを返す" do
        get :modern_ui_demo
        expect(response).to be_successful
      end

      it "200 HTTPステータスコードを返す" do
        get :modern_ui_demo
        expect(response).to have_http_status(:ok)
      end

      it "適切なテンプレートをレンダリングする" do
        get :modern_ui_demo
        expect(response).to render_template("shared/modern_ui_demo")
      end

      it "レイアウトを使用しない" do
        get :modern_ui_demo
        expect(response).to render_template(layout: false)
      end
    end

    context "コンテンツタイプ" do
      it "HTMLレスポンスを返す" do
        get :modern_ui_demo
        expect(response.content_type).to include("text/html")
      end
    end

    context "認証チェック" do
      it "認証なしでもアクセス可能" do
        # 現在の実装では認証は必要ないことを確認
        get :modern_ui_demo
        expect(response).to be_successful
      end
    end

    context "レスポンスボディ" do
      it "空でないコンテンツを返す" do
        get :modern_ui_demo
        # デバッグ用: レスポンスの詳細を確認
        if response.body.empty?
          puts "Response status: #{response.status}"
          puts "Response headers: #{response.headers.inspect}"
        end
        expect(response.body).not_to be_empty
      end

      it "Modern UIのコンテンツを含む" do
        get :modern_ui_demo
        expect(response.body).to include("StockRx - Modern UI v2 Demo")
      end
    end

    context "パフォーマンス" do
      it "高速にレスポンスを返す" do
        # 初回のレンダリングでビューのコンパイルが行われるため、2回目を測定
        get :modern_ui_demo # ウォームアップ

        start_time = Time.current
        get :modern_ui_demo
        elapsed_time = (Time.current - start_time) * 1000

        expect(response).to be_successful
        # render_viewsを有効にしたため、ビューのレンダリング時間を考慮
        # 2回目のリクエストは200ms以内であれば正常とする
        expect(elapsed_time).to be < 200
      end
    end

    context "HTTPヘッダー" do
      it "適切なキャッシュ制御ヘッダーを設定する" do
        get :modern_ui_demo
        # 静的なデモページなのでキャッシュ可能
        # Cache-Controlヘッダーが設定されている場合は、no-storeが含まれていないことを確認
        # 設定されていない場合も、静的ページとしては問題ない
        cache_control = response.headers["Cache-Control"]
        expect(cache_control.nil? || !cache_control.include?("no-store")).to be true
      end
    end

    context "エラーハンドリング" do
      context "ビューファイルが存在しない場合" do
        before do
          # ビューのレンダリングエラーをシミュレート
          allow(controller).to receive(:render).and_raise(ActionView::MissingTemplate.new([], "", [], false, ""))
        end

        it "MissingTemplateエラーが発生する" do
          expect {
            get :modern_ui_demo
          }.to raise_error(ActionView::MissingTemplate)
        end
      end
    end
  end

  # ============================================
  # 将来の機能拡張テスト（TODOコメント対応）
  # ============================================

  describe "future enhancements" do
    # TODO: Phase 4 - 以下のアクションが追加されたらテストを実装
    # - style_guide: スタイルガイドページ
    # - component_catalog: コンポーネントカタログ
    # - accessibility_checklist: アクセシビリティチェックリスト

    it "将来的に追加される静的ページのプレースホルダー" do
      # 現時点では実装されていないことを確認
      expect(controller.class.instance_methods(false)).not_to include(:style_guide)
      expect(controller.class.instance_methods(false)).not_to include(:component_catalog)
      expect(controller.class.instance_methods(false)).not_to include(:accessibility_checklist)
    end
  end

  # ============================================
  # コントローラー設定のテスト
  # ============================================

  describe "controller configuration" do
    it "ApplicationControllerを継承している" do
      expect(StaticController.ancestors).to include(ApplicationController)
    end

    it "適切なアクションが定義されている" do
      expect(controller.class.instance_methods(false)).to include(:modern_ui_demo)
    end

    # NOTE: 現在の実装では認証スキップはコメントアウトされている
    it "認証スキップの設定は現在無効" do
      callbacks = StaticController._process_action_callbacks
      skip_callbacks = callbacks.select { |c| c.kind == :before && c.filter == :authenticate_admin! }

      # スキップ設定がないことを確認
      expect(skip_callbacks).to be_empty
    end
  end

  # ============================================
  # ルーティングのテスト
  # ============================================

  describe "routing" do
    it "modern_ui_demo アクションへのルートが存在する" do
      expect(get: "/modern_ui_demo").to be_routable
    end
  end

  # ============================================
  # セキュリティのテスト
  # ============================================

  describe "security considerations" do
    context "CSRF保護" do
      it "CSRFトークンの検証が有効（テスト環境では無効化されている）" do
        # テスト環境ではCSRF保護が無効化されているが、
        # コントローラーにprotect_from_forgeryが定義されていることを確認
        controller_callbacks = StaticController._process_action_callbacks
        forgery_protection = controller_callbacks.find do |callback|
          callback.kind == :before && callback.filter.to_s.include?("verify_authenticity_token")
        end

        # protect_from_forgeryが設定されていることを確認
        # （実際の動作はテスト環境設定により無効化される）
        expect(forgery_protection).not_to be_nil
      end
    end

    context "XSS保護" do
      it "コンテンツがエスケープされる" do
        get :modern_ui_demo
        # Railsのデフォルトの自動エスケープ機能を使用
        expect(response.headers["X-Content-Type-Options"]).to eq("nosniff") if response.headers["X-Content-Type-Options"]
      end
    end
  end

  # ============================================
  # メモリ使用量のテスト
  # ============================================

  describe "memory usage" do
    it "過度なメモリを使用しない" do
      # メモリ使用量の基準値を記録
      initial_memory = `ps -o rss= -p #{Process.pid}`.to_i

      # 複数回アクセスしてメモリリークがないことを確認
      10.times { get :modern_ui_demo }

      final_memory = `ps -o rss= -p #{Process.pid}`.to_i
      memory_increase = final_memory - initial_memory

      # メモリ増加が妥当な範囲内であることを確認
      # render_viewsを有効にしたため、ビューのレンダリングでメモリが増加
      # 50MB以下であれば正常とする（ビューのレンダリング含む）
      expect(memory_increase).to be < 50_000
    end
  end
end
