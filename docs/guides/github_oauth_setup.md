# GitHub OAuth認証セットアップガイド（統合版）

## 概要
StockRx管理画面でGitHub OAuth認証を有効にするための完全ガイドです。このガイドは、セットアップ手順、トラブルシューティング、デバッグツールを統合しています。

## 前提条件
- GitHubアカウント
- Docker環境が起動していること
- Rails credentialsまたは環境変数へのアクセス権限

## セットアップ手順

### 1. GitHub OAuth Appの作成

#### 1.1 OAuth Appの新規作成
1. GitHubにログインして、[Developer settings](https://github.com/settings/developers)にアクセス
2. 左メニューから「OAuth Apps」を選択
3. 「New OAuth App」または「Register a new application」をクリック

#### 1.2 アプリケーション情報の入力

**開発環境用の設定**
```
Application name: StockRx Development
Homepage URL: http://localhost:3000
Application description: StockRx inventory management system (Development)
Authorization callback URL: http://localhost:3000/admin/auth/github/callback
```

**本番環境用の設定**
```
Application name: StockRx Production
Homepage URL: https://your-domain.com
Application description: StockRx inventory management system
Authorization callback URL: https://your-domain.com/admin/auth/github/callback
```

⚠️ **重要な注意事項**:
- 末尾の`callback`が完全に入力されていることを確認
- 開発環境では`http://`を使用（`https://`ではない）
- `localhost`を使用（`127.0.0.1`ではない）
- ポート番号`:3000`を含める
- 末尾にスラッシュ`/`を付けない

#### 1.3 クライアント情報の取得
1. 「Register application」をクリック後、以下を確認：
   - **Client ID**: 公開可能なID（例: `Ov23li...`）
   - **Client Secret**: 「Generate a new client secret」をクリックして生成
2. ⚠️ **重要**: Client Secretは一度しか表示されないので、必ずコピーして安全な場所に保存

### 2. アプリケーション側の設定

#### 2.1 環境変数による設定（開発環境推奨）

1. `.env`ファイルを作成：
```bash
cp .env.example .env
```

2. GitHubの認証情報を設定：
```bash
# .env
GITHUB_CLIENT_ID=your_actual_client_id_here
GITHUB_CLIENT_SECRET=your_actual_client_secret_here
```

#### 2.2 Rails Credentialsによる設定（本番環境推奨）

1. Dockerコンテナ内でcredentialsを編集：
```bash
docker-compose exec web bash
EDITOR=nano rails credentials:edit
```

2. 以下の設定を追加：
```yaml
github:
  client_id: "your_actual_client_id_here"
  client_secret: "your_actual_client_secret_here"
```

3. Ctrl+X → Y → Enter で保存

### 3. アプリケーションの再起動

```bash
# 開発環境（Docker）
docker-compose restart web

# または完全再起動
make down
make up

# 本番環境
sudo systemctl restart rails-app
```

### 4. 動作確認

#### 4.1 設定の確認
```bash
# ログで設定確認
make logs | grep -E "(GitHub|OAuth)"
```

期待される出力:
```
✅ GitHub OAuth configured successfully
```

#### 4.2 ブラウザでの確認
1. http://localhost:3000/admin/sign_in にアクセス
2. 「GitHubでログイン」ボタンが表示されることを確認
3. ボタンをクリックしてGitHub認証フローをテスト
4. GitHubの認証画面で「Authorize」をクリック
5. StockRxの管理画面にリダイレクトされることを確認

## トラブルシューティング

### エラー: "Not found. Authentication passthru"
**原因**: Devise OmniAuthでpassthruアクションが未実装、またはGitHub credentialsが未設定

**解決策**:
1. 環境変数またはcredentialsが正しく設定されているか確認
2. `Admins::OmniauthCallbacksController`に`passthru`メソッドが実装されているか確認
```ruby
def passthru
  super
end
```

### エラー: 404 Not Found
**原因**: OmniAuthの設定が正しく読み込まれていない

**解決策**:
1. 環境変数の確認：
```bash
docker-compose exec web env | grep GITHUB
```
2. アプリケーションログで警告メッセージを確認
3. アプリケーションを再起動

### エラー: "The redirect_uri MUST be a value associated with this application"
**原因**: GitHub OAuth AppのCallback URLが正しくない

**解決策**:
1. GitHub OAuth App設定でCallback URLを確認
2. 以下のチェックリストを確認：
   - [ ] URLは`http://localhost:3000/admin/auth/github/callback`と完全一致
   - [ ] 末尾にスラッシュがない
   - [ ] 開発環境では`http://`を使用（`https://`ではない）
   - [ ] `localhost`を使用（`127.0.0.1`ではない）
   - [ ] ポート`:3000`が含まれている
   - [ ] パスは`/admin/`で始まる（`/admins/`ではない）

### エラー: Invalid credentials
**原因**: Client IDまたはClient Secretが間違っている

**解決策**:
1. 環境変数またはcredentialsを再確認
2. Client Secretを再生成して設定し直す
3. アプリケーションを再起動

### エラー: ActiveSupport::MessageEncryptor::InvalidMessage
**原因**: master.keyとcredentials.yml.encの不整合

**解決策**:

**方法1: 環境変数による回避（推奨）**
1. `.env`ファイルに必要な設定を追加（上記参照）
2. credentialsファイルの使用を避ける

**方法2: credentialsの再生成**
```bash
# バックアップ作成
cp config/credentials.yml.enc config/credentials.yml.enc.backup
cp config/master.key config/master.key.backup

# 既存ファイル削除
rm config/credentials.yml.enc
rm config/master.key

# 新規作成
EDITOR=nano rails credentials:edit
```

## デバッグツール

### OAuth Debug Page
開発環境でOAuth設定を確認するためのデバッグページが利用可能：

1. http://localhost:3000/admin/oauth_debug にアクセス
2. 以下の情報を確認：
   - 期待されるredirect URI
   - 現在のOmniAuth設定
   - リクエスト情報（host、port、protocol）
   - ライブコールバックURLテスト

### ログの確認
```bash
# リアルタイムログ
docker-compose logs -f web

# OmniAuth関連ログのみ
docker-compose logs web | grep -i "OmniAuth"

# エラーのみ抽出
docker-compose logs web | grep -E "(ERROR|WARN|FATAL)"
```

### ブラウザでのOAuthフロー確認
1. ブラウザの開発者ツールを開く（F12）
2. Networkタブに移動
3. GitHub認証を試行
4. `github.com/login/oauth/authorize`へのリクエストを確認
5. URLパラメータの`redirect_uri`を確認

## セキュリティベストプラクティス

### 1. Client Secretの管理
- **絶対にGitリポジトリにコミットしない**
- 本番環境では環境変数またはRails credentialsを使用
- 定期的にローテーション（3-6ヶ月ごと）
- `.gitignore`に`.env`ファイルが含まれていることを確認

### 2. 環境別設定
- 開発環境と本番環境で異なるOAuth Appを使用
- 本番環境では必ずHTTPSを使用（OAuth 2.0仕様の要件）
- 各環境に適切なCallback URLを設定

### 3. アクセス制御
- 必要最小限のOAuthスコープのみ要求（現在は`user:email`のみ）
- GitHub組織やチームによるアクセス制限を検討
- 管理者の2要素認証を有効化

### 4. エラーハンドリング
- エラーメッセージに機密情報を含めない
- ユーザーフレンドリーなエラーメッセージの表示
- 詳細なエラー情報はログに記録

## 関連ファイル

### 設定ファイル
- `/config/initializers/devise.rb` - Devise OAuth設定
- `/config/initializers/omniauth.rb` - OmniAuth基本設定
- `.env` - 環境変数（開発環境）
- `config/credentials.yml.enc` - 暗号化された認証情報（本番環境）

### 実装ファイル
- `/app/controllers/admins/omniauth_callbacks_controller.rb` - コールバック処理
- `/app/models/admin.rb` - OAuth認証ロジック
- `/config/routes.rb` - ルーティング設定

### デバッグファイル（開発環境のみ）
- `/app/controllers/admin_controllers/oauth_debug_controller.rb` - デバッグコントローラー
- `/app/views/admin_controllers/oauth_debug/` - デバッグビュー
- `/config/initializers/omniauth_debug.rb` - デバッグ用ログ設定

## Docker環境の管理

### 完全リセット（データベース含む）
```bash
docker-compose down -v
docker-compose up -d
docker-compose exec web rails db:create db:migrate db:seed
```

### コンテナのみ再起動
```bash
docker-compose restart web
```

### 環境変数の確認
```bash
docker-compose exec web env | grep GITHUB
```

## 次のステップ

### 他のOAuthプロバイダーの追加
```ruby
# config/initializers/devise.rb に追加
config.omniauth :google_oauth2,
                Rails.application.credentials.dig(:google, :client_id),
                Rails.application.credentials.dig(:google, :client_secret)
```

### エラーハンドリングの強化
`app/controllers/admins/omniauth_callbacks_controller.rb`で以下を実装：
- より詳細なエラーメッセージ
- ログ記録の改善
- ユーザーへの適切なフィードバック

## 参考資料
- [Devise OmniAuth Documentation](https://github.com/heartcombo/devise/wiki/OmniAuth:-Overview)
- [GitHub OAuth Documentation](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [Rails Credentials Guide](https://guides.rubyonrails.org/security.html#custom-credentials)