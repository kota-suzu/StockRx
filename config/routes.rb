# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # ============================================
  # Phase 2: 店舗別ログインシステム
  # ============================================

  # StoreUserモデル用のDeviseルート
  # /store/:store_slug/sign_in などのパスになるよう設定
  # NOTE: Deviseルートを先に定義して、store/:slugより優先されるようにする
  devise_for :store_users,
             path: "store",
             skip: [ :registrations, :omniauth_callbacks ],
             controllers: {
               sessions: "store_controllers/sessions",
               passwords: "store_controllers/passwords"
             }

  # 店舗選択画面（ログイン前）
  # CLAUDE.md準拠: 認証済みユーザーダッシュボード(/store)との競合回避のため/storesに変更
  get "stores", to: "store_controllers/store_selection#index", as: :store_selection
  get "stores/:slug", to: "store_controllers/store_selection#show", as: :store_login_page

  # 店舗別公開在庫一覧（認証不要）
  # CLAUDE.md準拠: メタ認知的設計 - 公開情報は限定的、詳細は認証エリア
  # TODO: Phase 2 - アクセス制御の段階的強化
  #   - IP制限機能
  #   - レート制限（1分あたり60リクエスト）
  #   - 機密情報のマスキング強化
  # ✅ Phase 1（完了）- ルーティングヘルパー名の衝突解決
  #   問題: store_inventories_pathが公開ルートと認証済みルートで衝突
  #   解決策: ビューファイル内で明示的パス(/store/inventories)を使用
  #   修正ファイル:
  #     - app/views/store_controllers/inventories/index.html.erb (検索フォーム、ソートリンク等)
  #     - app/views/store_controllers/inventories/show.html.erb (パンくず、戻るボタン)
  #     - app/views/layouts/store.html.erb (ナビゲーション)
  #     - app/views/store_controllers/dashboard/index.html.erb (リンク)
  #
  # TODO: 🟡 Phase 2（推奨）- 根本的な解決策の検討
  #   優先度: 中（将来的な改善）
  #   代替案:
  #     1. as: オプションで明示的な名前を付ける (例: as: :public_store_inventories)
  #     2. concern化による共通化
  #     3. 完全なnamespace分離
  #   メタ認知: 現在の解決策は動作するが、ヘルパー使用が理想的
  #   横展開: 他の類似ルートでも同様のパターン適用
  resources :stores, only: [] do
    resources :inventories, only: [ :index ], controller: "store_inventories" do
      collection do
        get :search  # 在庫検索API
      end
    end
  end

  # 店舗ユーザー用の認証済みルート
  authenticated :store_user do
    namespace :store, module: :store_controllers do
      root "dashboard#index"

      # 在庫管理（店舗スコープ）
      resources :inventories, only: [ :index, :show ] do
        member do
          post :request_transfer  # 移動申請
        end
      end

      # 店舗間移動（店舗視点）
      resources :transfers, only: [ :index, :show, :new, :create ] do
        member do
          patch :cancel  # 申請取消（申請者のみ）
        end
      end

      # プロフィール管理
      resource :profile, only: [ :show, :edit, :update ] do
        member do
          get :change_password
          patch :update_password
        end
      end
    end
  end

  # ============================================
  # 管理者認証（既存）
  # ============================================

  # Adminモデル用のDeviseルート
  # /admin/sign_in などのパスになるよう設定
  devise_for :admins,
             path: "admin",
             # :registerable は無効化するため不要
             skip: [ :registrations ],
             controllers: {
               sessions: "admin_controllers/sessions",
               passwords: "admin_controllers/passwords",
               omniauth_callbacks: "admin_controllers/omniauth_callbacks"
             }

  # ============================================
  # Sidekiq Web UI（管理者認証必須）
  # ============================================
  # Background job monitoring and management
  authenticate :admin do
    mount Sidekiq::Web => "/admin/sidekiq"
  end

  # TODO: 将来的な運用監視機能
  # authenticate :admin do
  #   mount RailsAdmin::Engine => '/admin/rails_admin', as: 'rails_admin'
  #   mount Flipper::UI.app(Flipper) => '/admin/flipper'  # Feature flags
  # end

  # 管理者ダッシュボード用のルーティング
  namespace :admin, module: :admin_controllers do
    # ダッシュボードをルートに設定
    root "dashboard#index"

    # 在庫管理
    resources :inventories do
      collection do
        get :import_form  # CSVインポートフォーム
        post :import      # CSVインポート実行
      end
    end

    # ジョブステータス確認用API
    resources :job_statuses, only: [ :show ]

    # 🏪 Phase 2: Multi-Store Management
    resources :stores do
      member do
        get :dashboard  # 店舗個別ダッシュボード
      end

      # 店舗別在庫管理（管理者用）
      # CLAUDE.md準拠: 管理者は全店舗の詳細在庫情報にアクセス可能
      resources :inventories, only: [ :index ], controller: "admin_controllers/store_inventories" do
        member do
          get :details  # 詳細情報（価格・仕入先含む）
        end
      end

      # 店舗間移動管理（ネストルーティング）
      resources :inter_store_transfers, path: :transfers do
        member do
          patch :approve    # 承認
          patch :reject     # 却下
          patch :complete   # 完了
          patch :cancel     # キャンセル
        end
      end
    end

    # 店舗間移動管理（独立ルーティング）
    # CLAUDE.md準拠: ルーティング構造の整理とコンテキスト統一
    # メタ認知: ネストルーティングと独立ルーティングの役割分担明確化
    resources :inter_store_transfers, path: :transfers, only: [ :index, :show, :new, :create ] do
      collection do
        get :pending      # 承認待ち一覧
        get :analytics    # 移動分析
      end

      # 横展開: pending.html.erb等で使用される管理アクション
      # TODO: 🟡 Phase 2（構造改善）- ルーティング設計の最適化
      # 優先度: 中（リファクタリング）
      # 現状: ネストルーティングと独立ルーティングで重複定義
      # 将来: 単一ルーティング構造への統合検討
      member do
        patch :approve    # 承認
        patch :reject     # 却下
        patch :complete   # 完了
        patch :cancel     # キャンセル
      end
    end

    # Phase 5-2: 監査ログ管理
    resources :audit_logs, only: [ :index, :show ] do
      collection do
        get :security_events    # セキュリティイベント一覧
        get :user_activity      # ユーザー別活動履歴
        get :compliance_report  # コンプライアンスレポート
      end
    end

    # Phase 3: 在庫変動履歴管理（管理画面に統合）
    # CLAUDE.md準拠: 管理機能の一元化
    # 旧: /inventory_logs → 新: /admin/inventory_logs
    resources :inventory_logs, only: [ :index, :show ] do
      collection do
        get :all
        get "operation/:operation_type", to: "inventory_logs#by_operation", as: :operation
      end
    end

    # 今後の機能として追加予定のリソース
    # resources :reports
    # resources :settings
  end

  # ============================================
  # 後方互換性のためのリダイレクト設定
  # ============================================
  # CLAUDE.md準拠: 段階的移行戦略
  # 旧: /inventories → 新: /admin/inventories
  # TODO: Phase 4 - 2025年Q2目標で完全削除予定
  #   - アクセスログ分析で利用状況確認
  #   - 301リダイレクトで検索エンジン対応
  #   - 削除時は404ではなく適切なエラーメッセージ表示

  # 在庫管理の旧URLリダイレクト（GETリクエスト）
  get "/inventories", to: redirect("/admin/inventories", status: 301)
  get "/inventories/new", to: redirect("/admin/inventories/new", status: 301)
  get "/inventories/:id", to: redirect("/admin/inventories/%{id}", status: 301)
  get "/inventories/:id/edit", to: redirect("/admin/inventories/%{id}/edit", status: 301)

  # 在庫管理の旧URLリダイレクト（POST/PUT/DELETE用）
  # NOTE: 301リダイレクトはPOSTデータを失うため、直接エラーメッセージを表示
  match "/inventories", to: proc { |env|
    [ 410, { "Content-Type" => "text/html" },
      [ "<html><body><h1>このURLは廃止されました</h1><p>新しいURL: <a href='/admin/inventories'>/admin/inventories</a></p></body></html>" ] ]
  }, via: [ :post ]

  match "/inventories/:id", to: proc { |env|
    id = env["action_dispatch.request.path_parameters"][:id]
    [ 410, { "Content-Type" => "text/html" },
      [ "<html><body><h1>このURLは廃止されました</h1><p>新しいURL: <a href='/admin/inventories/#{id}'>/admin/inventories/#{id}</a></p></body></html>" ] ]
  }, via: [ :put, :patch, :delete ]

  # ============================================
  # 横展開確認済み: 類似ルートの整合性について
  # ============================================
  #
  # inventory_logsは管理画面に統合完了（CLAUDE.md準拠）
  # ✅ 完了: Phase 3 - inventory_logs機能の管理画面統合（2025年6月）
  # 実装内容:
  #   - /inventory_logs → /admin/inventory_logs への移行完了
  #   - InventoryLogsController → AdminControllers::InventoryLogsController移行完了
  #   - 権限ベースのアクセス制御強化完了
  # 効果: 管理機能の一元化、セキュリティ向上
  #
  # 横展開検討済み項目:
  # ✅ 店舗関連ルート: 適切に名前空間分離済み（/store, /stores, /admin/stores）
  # ✅ API関連ルート: 独立したv1名前空間で適切に管理
  # ✅ 認証関連ルート: Devise管理下で適切に構成
  # ✅ 静的ファイル関連: Rails内部ルートで適切に除外設定済み
  # ✅ 在庫履歴ルート: admin名前空間に移行済み（/admin/inventory_logs）
  #

  # 在庫ログの旧URLリダイレクト（後方互換性維持）
  # CLAUDE.md準拠: 段階的移行戦略（2026年Q1削除予定）
  get "/inventory_logs", to: redirect("/admin/inventory_logs", status: 301)
  get "/inventory_logs/all", to: redirect("/admin/inventory_logs/all", status: 301)
  get "/inventory_logs/:id", to: redirect("/admin/inventory_logs/%{id}", status: 301)
  get "/inventory_logs/operation/:operation_type", to: redirect("/admin/inventory_logs/operation/%{operation_type}", status: 301)

  # API用ルーティング（バージョニング対応）
  namespace :api do
    namespace :v1 do
      resources :inventories, only: [ :index, :show, :create, :update, :destroy ]
    end
  end

  # Phase 5-3: CSP違反レポート収集
  post "/csp-reports", to: "csp_reports#create", as: :csp_reports

  # アプリケーションのルートページ
  # 将来的にはユーザー向けページになる予定
  root "home#index"

  # エラーページルーティング
  # 設計書に基づいて実装
  %w[400 403 404 422 429 500].each do |code|
    get code, to: "errors#show", defaults: { code: code }, as: "error_#{code}"
  end

  # エラーページへの統一パス
  get "error", to: "errors#show", as: :error

  # その他リクエスト漏れ対策 (ActiveStorage等除外)
  # TODO: 横展開確認 - 他のRails内部パスも適切に除外されることを確認
  match "*path", to: "errors#show", via: :all,
        constraints: ->(req) {
          # Rails内部ルートを除外
          !req.path.start_with?("/rails/") &&
          !req.path.start_with?("/cable") &&
          !req.path.start_with?("/__cypress/") # テスト環境用
        },
        defaults: { code: "404" }
end
