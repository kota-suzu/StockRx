# Git履歴からシークレットを削除する手順

## 問題の状況
GitHubのプッシュ保護により、コミット `d945d4c` にStripe APIキーパターンが検出されました。

## 解決方法

### オプション1: BFG Repo-Cleanerを使用（推奨）
```bash
# BFGをインストール（Homebrewを使用）
brew install bfg

# リポジトリのミラークローンを作成
git clone --mirror git@github.com:kota-suzu/StockRx.git StockRx-mirror
cd StockRx-mirror

# APIキーパターンを削除
bfg --replace-text <(echo 'sk_live_*==>test_token_*') --no-blob-protection
bfg --replace-text <(echo 'cs_live_*==>test_secret_*') --no-blob-protection
bfg --replace-text <(echo 'sk_test_*==>test_key_*') --no-blob-protection

# リポジトリをクリーンアップ
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# 変更をプッシュ
git push
```

### オプション2: git filter-branchを使用
```bash
# 注意: これは破壊的な操作です。バックアップを取ってください。

# 履歴を書き換える
git filter-branch --tree-filter '
  find . -type f -name "*.rb" -exec sed -i "" \
    -e "s/sk_live_[a-zA-Z0-9_]*/test_token_placeholder/g" \
    -e "s/cs_live_[a-zA-Z0-9_]*/test_secret_placeholder/g" \
    -e "s/sk_test_[a-zA-Z0-9_]*/test_key_placeholder/g" {} \;
' -- --all

# 古い参照を削除
rm -rf .git/refs/original/
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### オプション3: GitHubの例外を許可
GitHubが提供するURLを使用して、この特定のケースでの例外を許可することもできます：
https://github.com/kota-suzu/StockRx/security/secret-scanning/unblock-secret/2yEeNdwPdvvK3zazOMk58Yo7t6u

ただし、これは推奨されません。

## 推奨アプローチ

1. 既存のブランチを保護するため、新しいブランチを作成
2. 問題のあるコミット以降の変更を新しいブランチに適用
3. 履歴をクリーンな状態で再構築

```bash
# 新しいブランチを作成
git checkout -b feature/secure-activejob-parameter-filtering-clean main

# 現在のブランチの変更をチェリーピック（問題のコミットを除く）
git cherry-pick bebab9a..11d01f1

# 新しいブランチをプッシュ
git push -u origin feature/secure-activejob-parameter-filtering-clean
```

## セキュリティベストプラクティス

今後同様の問題を防ぐため：

1. **pre-commitフックの使用**
   ```bash
   # .git/hooks/pre-commit
   #!/bin/bash
   if git diff --cached | grep -E "(sk_live_|cs_live_|sk_test_)"; then
     echo "Error: Potential API key detected!"
     exit 1
   fi
   ```

2. **環境変数の使用**
   - 本番APIキー: `ENV['STRIPE_API_KEY']`
   - テスト用: `test_token_` プレフィックスを使用

3. **Rails credentialsの活用**
   ```ruby
   Rails.application.credentials.stripe[:api_key]
   ```

4. **GitGuardianやtruffleHogの導入**
   CIパイプラインでシークレットスキャンを自動化