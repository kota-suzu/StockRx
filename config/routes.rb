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
  get "store", to: "store_controllers/store_selection#index", as: :store_selection
  get "store/:slug", to: "store_controllers/store_selection#show", as: :store_login_page

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
    resources :inventories

    # ジョブステータス確認用API
    resources :job_statuses, only: [ :show ]

    # 🏪 Phase 2: Multi-Store Management
    resources :stores do
      member do
        get :dashboard  # 店舗個別ダッシュボード
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
    resources :inter_store_transfers, path: :transfers, only: [ :index, :show, :new, :create ] do
      collection do
        get :pending      # 承認待ち一覧
        get :analytics    # 移動分析
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

    # 今後の機能として追加予定のリソース
    # resources :reports
    # resources :settings
  end

  # 在庫管理リソース（HTML/JSONレスポンス対応）
  resources :inventories do
    resources :inventory_logs, only: [ :index ]
  end

  # 在庫ログリソース
  resources :inventory_logs, only: [ :index, :show ] do
    collection do
      get :all
      get "operation/:operation_type", to: "inventory_logs#by_operation", as: :operation
    end
  end

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
