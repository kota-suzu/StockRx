# Devise 管理者認証の設定ガイド

本ドキュメントでは、StockRxアプリケーションにおけるDevise認証基盤の設定手順および使用方法について説明します。

## 1. 概要

StockRxでは以下の特徴を持つ管理者認証システムを実装しています：

- Admin(管理者)モデル専用の認証基盤
- 12文字以上の強固なパスワード要件（大文字・小文字・数字・記号を含む）
- 5回の失敗でアカウントロック（15分間）
- 30分の非アクティブでセッションタイムアウト
- Turbo/Hotwire対応済み
- 日本語UI完全対応

将来的には以下の拡張も計画されています：

- 2要素認証(TOTP)
- 一般ユーザー(User)モデルの追加

## 2. セットアップ手順

### 2.1 Rails Credentialsの設定

本番環境では秘密鍵を安全に管理するため、以下の手順でRails Credentialsに設定が必要です。

```bash
# 開発環境でcredentialsファイルの編集（VSCodeの例）
EDITOR="code --wait" bin/rails credentials:edit

# 以下のような内容を追加してください
devise:
  secret_key: "長くランダムな文字列をここに設定" # 32文字以上の安全なキー

# 本番環境では別のファイルを使用
EDITOR="code --wait" bin/rails credentials:edit --environment production
```

### 2.2 マイグレーションの実行

Adminモデルとその関連テーブルを作成するには以下のコマンドを実行します：

```bash
bin/rails db:migrate
```

### 2.3 初期管理者ユーザーの作成

シードデータから初期管理者を作成します：

```bash
bin/rails db:seed
```

これにより、以下の管理者アカウントが作成されます：

- メール: admin@example.com
- パスワード: Password1234!

**注意**: 本番環境では、必ずこのデフォルトパスワードを変更してください。

## 3. 使用方法

### 3.1 管理者ログイン

- URL: `/admin/sign_in`
- 管理画面のルートは `/admin`（ログイン後自動的にリダイレクト）

### 3.2 パスワードリセット

- URL: `/admin/password/new`
- メールアドレスを入力するとリセット用のリンクが送信されます

### 3.3 セッションタイムアウト

- 30分間操作がない場合、セッションは自動的に無効になります
- 再ログインが必要になります

## 4. 開発者向け情報

### 4.1 新規コントローラでの認証適用

管理者認証を必要とする新しいコントローラを追加する場合は、`Admin::BaseController`を継承してください：

```ruby
module Admin
  class YourController < BaseController
    # BaseControllerですでに authenticate_admin! が適用されています
    def index
      # 実装...
    end
  end
end
```

### 4.2 2要素認証の追加方法（将来実装予定）

2要素認証を有効化するには、以下の手順が必要です：

1. Gemfileの`devise-two-factor`コメントアウトを解除
2. Adminモデルに`:two_factor_authenticatable`を追加
3. 必要なマイグレーションを実行
4. QRコード生成用のビューを追加

詳細は将来のドキュメントで提供予定です。

## 5. トラブルシューティング

### 5.1 ログインできない場合

以下を確認してください：

- メールアドレスとパスワードが正しいか
- アカウントがロックされていないか（5回の失敗でロック）
- パスワードが要件を満たしているか（12文字以上、大小文字・数字・記号を含む）

### 5.2 セッションがすぐに切れる場合

- `config/initializers/devise.rb`の`config.timeout_in`設定を確認
- 本番環境でのCookie設定が正しいか確認

## 6. セキュリティ上の注意

- 本番環境では必ずデフォルトの管理者パスワードを変更すること
- `secret_key`は絶対に公開リポジトリにコミットしないこと
- 本番環境ではHTTPS接続を強制することを推奨 