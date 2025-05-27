# コントローラ設計ガイドライン

## 基本構造

StockRxアプリケーションでは、以下の命名規則と構造に従ってコントローラを実装しています。

### 名前空間

- `AdminControllers::` - 管理者向け機能のコントローラ
- `Api::` - API機能のコントローラ（将来的に実装予定）
- ルート名前空間 - 一般ユーザー向け機能のコントローラ

### 命名規則について

- モデル名とコントローラの名前空間が衝突しないように注意
  - 例: `Admin`モデルが存在するため、管理者コントローラには`AdminControllers`名前空間を使用

### ディレクトリ構造

```
app/controllers/
  ├── application_controller.rb       # ベースコントローラ
  ├── home_controller.rb              # トップページ用コントローラ
  ├── admin_controllers/              # 管理者向けコントローラ
  │   ├── base_controller.rb          # 管理者用ベースコントローラ
  │   ├── dashboard_controller.rb     # ダッシュボード
  │   ├── passwords_controller.rb     # パスワード管理（Devise拡張）
  │   └── sessions_controller.rb      # セッション管理（Devise拡張）
  └── concerns/                       # 共通コンサーン
      └── error_handling.rb           # エラーハンドリング（将来的に実装予定）
```

### ビューディレクトリ構造

```
app/views/
  ├── layouts/
  │   ├── application.html.erb        # 一般ユーザー用レイアウト
  │   └── admin.html.erb              # 管理者用レイアウト
  ├── home/                           # 一般ユーザー向けビュー
  │   └── index.html.erb              # トップページ
  └── admin_controllers/              # 管理者向けビュー
      ├── dashboard/                  # ダッシュボード関連ビュー
      ├── sessions/                   # ログイン関連ビュー
      ├── passwords/                  # パスワード管理ビュー
      └── shared/                     # 共通部品
```

## モジュールとディレクトリの一致

Railsでは、オートロード機能が正しく動作するために、モジュール名とディレクトリ構造を一致させる必要があります：

- モジュール `AdminControllers` → ディレクトリ `app/controllers/admin_controllers/`
- モジュール `Api::V1` → ディレクトリ `app/controllers/api/v1/`

これにより、`uninitialized constant` エラーを防ぐことができます。

## コントローラの責務

- コントローラはビジネスロジックを含まず、モデルやサービスオブジェクトに処理を委譲する
- 入力パラメータのバリデーションと整形
- 適切なビューの選択またはレスポンスの生成
- 認証・認可の確認

## コントローラの拡張方法

### 新しい管理者用コントローラの追加

```ruby
# app/controllers/admin_controllers/items_controller.rb
module AdminControllers
  class ItemsController < BaseController
    # 全管理者用コントローラはBaseControllerを継承
    
    # アクション定義
    # ...
  end
end
```

### Deviseコントローラのカスタマイズ

Deviseコントローラをカスタマイズする場合は、以下のパターンに従ってください：

```ruby
module AdminControllers
  class CustomDeviseController < Devise::SomeController
    layout "admin"  # 管理者用レイアウトを使用
    
    # オーバーライドするメソッド
    # ...
    
    protected
    
    # リダイレクト先など保護されたメソッド
    # ...
  end
end
```

## 今後の拡張予定

1. API名前空間の追加
   - RESTful APIエンドポイントの実装
   - JSON形式でのレスポンス
   - トークンベースの認証

2. ユーザー向けコントローラの追加
   - 一般スタッフ向けインターフェース
   - 権限に基づいた機能制限

3. GraphQLサポート（検討中）
   - クエリの柔軟性向上
   - フロントエンドとの統合改善
   
## TODO

1. アクセス制御の強化
   - 権限ベースの認可機能の実装
   - コントローラレベルのアクセス制限
   
2. エラーハンドリングの統一
   - 共通のエラーハンドリングメカニズムの実装
   - エラーログの構造化と監視
   
3. パフォーマンス最適化
   - N+1クエリ問題への対応
   - キャッシュ戦略の実装
   
4. API機能の拡張
   - WebSocket/ActionCableを活用したリアルタイム機能
   - バッチ処理とバックグラウンドジョブの連携 