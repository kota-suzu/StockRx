# CI環境トラブルシューティングガイド

## 概要

GitHub ActionsでのRailsテスト実行時に発生する一般的な問題と解決方法をまとめています。

## データベース接続エラー

### 問題: MySQL接続認証失敗

```
Mysql2::Error::ConnectionError: Access denied for user 'root'@'172.18.0.1' (using password: YES)
```

#### 原因
- MySQLサービスの認証設定とRailsアプリケーションの接続設定の不整合
- Docker内部ネットワーク（172.18.0.x）からの接続許可問題
- データベース名の不一致

#### 解決方法

1. **GitHub Actionsワークフローの修正**
```yaml
services:
  mysql:
    image: mysql:8.0
    env:
      MYSQL_ROOT_PASSWORD: password
      MYSQL_DATABASE: app_test
      MYSQL_USER: test_user
      MYSQL_PASSWORD: password
    ports:
      - 3306:3306
    options: >-
      --health-cmd="mysqladmin ping --host=127.0.0.1 --port=3306 --user=root --password=password"
      --health-interval=10s
      --health-timeout=5s
      --health-retries=10
```

2. **環境変数の統一**
```yaml
env:
  DATABASE_URL: mysql2://root:password@127.0.0.1:3306/app_test
  DATABASE_HOST: 127.0.0.1
  DATABASE_PORT: 3306
  DATABASE_USERNAME: root
  DATABASE_PASSWORD: password
```

3. **接続待機処理の追加（ロバストエラーハンドリング付き）**
```bash
# MySQL接続の確認と待機
echo "Waiting for MySQL to be ready..."
mysql_ready=0
for i in {1..30}; do
  if mysqladmin ping -h 127.0.0.1 -P 3306 -u root -ppassword --silent; then
    echo "MySQL is ready!"
    mysql_ready=1
    break
  fi
  echo "Waiting for MySQL... ($i/30)"
  sleep 2
done

# エラーハンドリング（ベストプラクティス）
if [ $mysql_ready -eq 0 ]; then
  echo "ERROR: MySQL failed to start after 30 attempts (60 seconds)"
  echo "Checking MySQL container logs..."
  docker ps -a
  docker logs $(docker ps -aq --filter "ancestor=mysql:8.0") || true
  exit 1
fi
```

### 問題: Redis接続エラー

#### 解決方法
```yaml
services:
  redis:
    image: redis:7
    ports:
      - 6379:6379
    options: --health-cmd "redis-cli ping" --health-interval 10s --health-timeout 5s --health-retries 5
```

## テスト実行エラー

### 問題: RSpec CSV::MalformedCSVError モックエラー

#### 症状
```
ArgumentError: wrong number of arguments (given 0, expected 2)
```

#### 原因
- `CSV::MalformedCSVError`は初期化時にメッセージと行番号の引数が必要
- RSpecのモックで引数なしでインスタンス化しようとするとエラー

#### 解決方法
```ruby
# NG - 引数なし
allow(Inventory).to receive(:import_from_csv).and_raise(CSV::MalformedCSVError)

# OK - 必要な引数付き
allow(Inventory).to receive(:import_from_csv).and_raise(CSV::MalformedCSVError.new("Invalid CSV format", 1))
```

## アセット・キャッシュ問題

### 問題: Zeitwerk autoload エラー

#### 症状
```
can't reload, please call loader.enable_reloading before setup (Zeitwerk::ReloadingDisabledError)
```

#### 原因
- test/production環境では`config.enable_reloading = false`が設定されている
- CI環境でautoloaderのリロードを試みると上記エラーが発生

#### 解決方法
```bash
# キャッシュクリア（物理的削除）
rm -rf tmp/cache/bootsnap-*
mkdir -p tmp/cache/assets tmp/storage tmp/pids
chmod -R 777 tmp/cache tmp/storage tmp/pids

# Zeitwerkの整合性チェック（リロードではなく）
bundle exec rails zeitwerk:check

# 注意: test/production環境では以下は使用しない
# DISABLE_SPRING=1 bundle exec rails runner 'Rails.autoloaders.main.reload' # NG
```

## パフォーマンス最適化

### 1. 並列実行の活用
```yaml
strategy:
  matrix:
    ruby-version: ['3.3.8']
    database: ['mysql:8.0']
  fail-fast: false
```

### 2. キャッシュの活用
```yaml
- name: Cache bundle
  uses: actions/cache@v4
  with:
    path: vendor/bundle
    key: ${{ runner.os }}-gems-${{ hashFiles('**/Gemfile.lock') }}
    restore-keys: |
      ${{ runner.os }}-gems-
```

### 3. テスト分割
```yaml
- name: Run RSpec tests
  run: |
    bundle exec rspec --format progress --format RspecJunitFormatter --out tmp/rspec.xml
```

## セキュリティ対策

### 1. 機密情報の管理
```yaml
env:
  DATABASE_PASSWORD: ${{ secrets.DATABASE_PASSWORD }}
  SECRET_KEY_BASE: ${{ secrets.SECRET_KEY_BASE }}
```

### 2. 依存関係のスキャン
```yaml
- name: Security audit
  run: |
    bundle audit --update
    bundle exec brakeman --no-pager
```

## モニタリング・アラート

### 1. テスト結果の可視化
```yaml
- name: Publish test results
  uses: dorny/test-reporter@v1
  if: always()
  with:
    name: RSpec Tests
    path: tmp/rspec.xml
    reporter: java-junit
```

### 2. 実行時間の監視
```yaml
- name: Monitor test duration
  run: |
    echo "Test duration: ${{ steps.test.outputs.duration }}"
```

## トラブルシューティング手順

### 1. ログの確認
- GitHub Actionsの詳細ログを確認
- データベース接続ログの分析
- アプリケーションログの確認

### 2. ローカル環境での再現
```bash
# Docker環境での再現テスト
docker-compose up -d
docker-compose exec web bundle exec rspec

# CI環境の環境変数を模擬
export RAILS_ENV=test
export DATABASE_URL=mysql2://root:password@127.0.0.1:3306/app_test
```

### 3. 段階的デバッグ
1. データベース接続のみテスト
2. 単一テストファイルの実行
3. 全テストスイートの実行

## 関連リンク

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [MySQL Docker Hub](https://hub.docker.com/_/mysql)
- [Rails Testing Guide](https://guides.rubyonrails.org/testing.html)
- [Docker Compose for Rails](https://docs.docker.com/samples/rails/)

## 今後の改善項目

### 高優先度
- [ ] テスト並列実行の導入
- [ ] より詳細なエラーログ設定
- [ ] パフォーマンス監視の強化

### 中優先度  
- [ ] テストデータベースの最適化
- [ ] CI実行時間の短縮
- [ ] より堅牢なヘルスチェック

### 低優先度
- [ ] 複数ブラウザでのE2Eテスト
- [ ] 負荷テストの追加
- [ ] セキュリティスキャンの拡充