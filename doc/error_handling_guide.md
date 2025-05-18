# StockRx エラーハンドリングガイド

このドキュメントはStockRxアプリケーションのエラーハンドリング機能の使い方と実装の詳細について説明します。

## 1. 概要

StockRxでは以下の方針でエラーハンドリングを実装しています：

1. **業務エラー** (入力ミス・権限不足等) → 4xx / バリデーションメッセージを返却
2. **システムエラー** (バグ・外部障害等) → 5xx / 詳細はログと通知サービスへ
3. `config.exceptions_app = routes` で **全例外をRailsルート配下で処理**
4. **JSON API形式を統一** し、フロントエンドは `code` パラメータで判定可能
5. HTML 422は描画せず、フォームは同一ページ再描画でUXを向上

## 2. 使用方法

### 標準例外を活用したシンプルな実装

```ruby
# 変更前: 手動でエラーチェックして404返却
def show
  @inventory = Inventory.find_by(id: params[:id])
  return head 404 if @inventory.nil?
  # ...処理...
end

# 変更後: findメソッドの自然な例外をそのまま活用
def show
  @inventory = Inventory.find(params[:id])  # RecordNotFoundで自動的に404
  # ...処理...
end
```

### バリデーションエラーの処理

```ruby
# 変更前: バリデーションエラーを手動で処理
def create
  @inventory = Inventory.new(inventory_params)
  if @inventory.save
    redirect_to @inventory, notice: "在庫が作成されました"
  else
    flash.now[:alert] = "入力エラーがあります"
    render :new, status: :unprocessable_entity
  end
end

# 変更後: save!で例外を発生させ、共通エラーハンドラでキャッチ
def create
  @inventory = Inventory.new(inventory_params)
  @inventory.save!  # バリデーションエラーでActiveRecord::RecordInvalidが発生
  redirect_to @inventory, notice: "在庫が作成されました"
end
```

### カスタムエラーの使用

```ruby
# 競合チェック
if params[:inventory][:lock_version].to_i != @inventory.lock_version
  # 競合発生時はカスタムエラーを発生
  raise CustomError::ResourceConflict.new(
    "他のユーザーがこの在庫を更新しました。最新の情報を確認してください。", 
    ["同時編集が検出されました"]
  )
end
```

### JSON APIレスポンス例

```json
// 404エラー
{
  "code": "resource_not_found",
  "message": "指定されたリソースが見つかりません"
}

// 422バリデーションエラー
{
  "code": "validation_error",
  "message": "入力内容に問題があります",
  "details": [
    "価格は0以上で入力してください",
    "名称を入力してください"
  ]
}

// 409競合エラー
{
  "code": "conflict",
  "message": "他のユーザーがこの在庫を更新しました。最新の情報を確認してください。",
  "details": [
    "同時編集が検出されました"
  ]
}
```

## 3. 対応HTTPステータスコード一覧

| コード | シンボル | 対応例外クラス | 使用例 |
|:------|:---------|:--------------|:-------|
| 200 | :ok | - | 通常の成功レスポンス |
| 201 | :created | - | リソース作成成功 |
| 204 | :no_content | - | 削除成功 |
| 400 | :bad_request | ActionController::ParameterMissing | パラメータ不足・形式不正 |
| 401 | :unauthorized | Devise::UnauthorizedError | 認証失敗 |
| 403 | :forbidden | Pundit::NotAuthorizedError | 権限不足 |
| 404 | :not_found | ActiveRecord::RecordNotFound | リソース不在 |
| 409 | :conflict | CustomError::ResourceConflict | 楽観的ロック失敗・リソース競合 |
| 422 | :unprocessable_entity | ActiveRecord::RecordInvalid | バリデーションエラー |
| 429 | :too_many_requests | CustomError::RateLimitExceeded | レート制限超過 |
| 500 | :internal_server_error | StandardError | サーバー内部エラー |

## 4. エラーの種類と処理方針

### 業務エラー（4xx系）

業務エラーはユーザー操作に起因するエラーで、ユーザーへのフィードバックが重要です：

- **400** (Bad Request): 不正なリクエスト形式
- **401** (Unauthorized): 認証エラー
- **403** (Forbidden): 認可エラー
- **404** (Not Found): リソース不在
- **409** (Conflict): リソース競合
- **422** (Unprocessable Entity): バリデーションエラー
- **429** (Too Many Requests): レート制限超過

### システムエラー（5xx系）

システムエラーはアプリケーション内部の問題やインフラ障害に起因するエラーです：

- **500** (Internal Server Error): サーバー内部エラー
- **503** (Service Unavailable): サービス一時停止

## 5. テストとデバッグ

エラーハンドリングのテスト用コマンドが用意されています：

```bash
# 本番モードで開発サーバーを起動
make test-error-handling
```

開発モードでも本番同様のエラーページをテストするには：

```
# URLパラメータでエラーページ表示モードを切り替え
http://localhost:3000/some_url?debug=0  # 本番環境同様のエラーページ表示
http://localhost:3000/some_url?debug=1  # 開発環境デフォルトのエラーページ表示
```

## 6. RSpecテスト実装例

共通のshared_examplesを使ってエラーハンドリングのテストを簡単に実装できます：

```ruby
RSpec.describe InventoriesController, type: :controller do
  describe "GET #show" do
    it_behaves_like "handles not found error"
  end
  
  describe "PUT #update" do
    it_behaves_like "handles validation error", :update, :valid_update_params
    it_behaves_like "handles conflict error", :update, :valid_update_params
  end
end
```

## 7. 実装の詳細

### コードの場所

- `app/controllers/concerns/error_handlers.rb` - エラーハンドリングモジュール
- `app/controllers/errors_controller.rb` - エラーページコントローラ
- `app/lib/custom_error.rb` - カスタムエラークラス
- `app/views/errors/` - エラーページテンプレート
- `config/locales/ja.errors.yml` / `config/locales/en.errors.yml` - エラーメッセージ国際化
- `doc/examples/error_handling_examples.rb` - 実装例

### 設定ファイル

- `config/application.rb` - exceptions_app設定
- `config/routes.rb` - エラーページルーティング
- `config/environments/development.rb` - 開発環境設定
- `config/environments/production.rb` - 本番環境設定

## 8. 将来の拡張計画

- Sentry/DataDogとの連携強化
- レート制限実装（Rack::Attack活用）
- 多言語HTML対応
- キャッシュ戦略最適化

## 9. 参考リソース

- [Rails: エラーハンドリングのベストプラクティス](https://qiita.com/jnchito/items/3ef95ea144ed15df3637)
- [7 Ways Of Effective Error Handling in Ruby](https://medium.com/@zahidensari116/7-ways-of-effective-error-handling-in-ruby-best-practices-and-strategies-a10454f4bd51)
- [Error Handling in Rails — The Modular Way](https://medium.com/rails-ember-beyond/error-handling-in-rails-the-modular-way-9afcddd2fe1b)

## 10. 既知の問題と対応策

### Devise認証の問題

#### POSTリクエストでのsign_in問題

Chrome（バージョン84以降）において、POSTリクエスト内でのDeviseの`sign_in`や`bypass_sign_in`メソッドが機能しない問題が報告されています。これはCSRFトークン検証とCookieの扱いに関するブラウザの変更が原因です。

**症状**：
- POSTリクエスト内で`sign_in`または`bypass_sign_in`を実行しても、ユーザーが認証されない
- 主にChromeブラウザで発生（Firefox、Safariでは問題なし）

**対応策**：
1. セッションコントローラのcreateアクションに対してCSRF検証をスキップする：
   ```ruby
   skip_before_action :verify_authenticity_token, only: :create
   ```

2. 別の方法として、POSTリクエスト後にGETリクエストにリダイレクトし、そのGETアクション内でサインインを行う方法も有効です：
   ```ruby
   # POSTリクエスト処理
   def post_action
     # 処理...
     redirect_to get_signin_path(token: one_time_token)
   end
   
   # GETリクエスト処理
   def get_signin
     user = find_user_by_token(params[:token])
     sign_in(user) if user
     redirect_to dashboard_path
   end
   ```

**セキュリティ上の注意点**：
- CSRF保護のスキップは必要最小限の範囲に制限する
- 代替手段としてワンタイムトークンを利用したGETリクエストフローを検討する
- スキップ部分をAPIにするなら、厳格なトークン認証に切り替える
- 長期的には以下のいずれかの手法に移行することを推奨：
  1. XHR/fetchベースのJSONリクエスト化
  2. 独自認証トークン生成による多重チェック
  3. SameSiteポリシー対応JWTなどの採用

**影響範囲**：
StockRxアプリケーションでは以下のコントローラで対応が必要：
- `app/controllers/admin_controllers/sessions_controller.rb`
- `app/controllers/admin_controllers/passwords_controller.rb`

**参考**：
- [Devise Issue #5155](https://github.com/heartcombo/devise/issues/5155)
- [Chrome SameSite Cookie Changes](https://blog.chromium.org/2019/10/developers-get-ready-for-new.html)

### ルーティング順序の問題

#### Devise認証ルートとエラーハンドリングの競合

アプリケーション全体でカスタムエラーハンドリングを行うと、特定のケースで認証ルートがエラーページにリダイレクトされてしまう問題が発生することがあります。

**症状**：
- 管理者ログインページ (`/admin/sign_in`) にアクセスすると404エラーページが表示される
- Deviseの認証ルート全般が機能しない

**原因**：
- ルーティング設定で `match "*path"` などのワイルドカードパスがDeviseのルートより先に定義されている
- リクエストがDeviseコントローラーに到達する前にエラーハンドラーでキャプチャされてしまう

**対応策**：
1. routes.rb内でDeviseルートを先に定義し、エラーハンドリングのwildcardルートは後方に配置する：
   ```ruby
   # 認証ルートを先に定義
   devise_for :admins, ...

   # 管理者ダッシュボード用のルーティング
   namespace :admin do
     ...
   end

   # エラーページルーティングは認証ルートの後に定義
   %w[400 403 404 422 429 500].each do |code|
     get code, to: "errors#show", code: code
   end

   # ワイルドカードパスは最後に定義
   match "*path", to: "errors#show", via: :all, ...
   ```

**注意点**：
- Rails 6以降では、ルーティングの順序が重要になる場面が多い
- ワイルドカードルート（`*path`）は、通常最後に定義する
- アプリケーション機能拡張時は、新たなルートが適切に動作するか確認する
- 認証・認可関連のルートは通常、高い優先度で定義する 