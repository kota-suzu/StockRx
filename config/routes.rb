# frozen_string_literal: true

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Adminモデル用のDeviseルート
  # /admin/sign_in などのパスになるよう設定
  devise_for :admins,
             path: "admin",
             # :registerable は無効化するため不要
             skip: [ :registrations ],
             controllers: {
               sessions: "admin_controllers/sessions",
               passwords: "admin_controllers/passwords"
             }

  # 管理者ダッシュボード用のルーティング
  namespace :admin, module: :admin_controllers do
    # ダッシュボードをルートに設定
    root "dashboard#index"

    # 在庫管理
    resources :inventories do
      collection do
        get :import_form
        post :import
      end
    end

    # ジョブステータス確認用API
    resources :job_statuses, only: [ :show ]

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

  # アプリケーションのルートページ
  # 将来的にはユーザー向けページになる予定
  root "home#index"
end
