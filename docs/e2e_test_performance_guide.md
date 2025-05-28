# E2Eテストパフォーマンスガイド

## 概要
このガイドでは、E2E（End-to-End）テストの実行速度を改善するための方法を説明します。

## 高速化の戦略

### 1. テストの分類と分割

#### JavaScript不要なテストの分離
```ruby
# 軽量版（js: false）
RSpec.describe 'Feature', type: :feature, js: false do
  # rack_testドライバーを使用（高速）
end

# JavaScript必要版（js: true）
RSpec.describe 'Feature', type: :feature, js: true do
  # Seleniumドライバーを使用（遅い）
end
```

#### APIテストへの置き換え
E2Eテストの一部をAPIテストに置き換えることで、大幅な高速化が可能です。

```ruby
# 遅い: E2Eテスト
scenario 'creates inventory' do
  visit new_inventory_path
  fill_in 'Name', with: 'Test'
  click_button 'Create'
  expect(page).to have_content('Success')
end

# 速い: APIテスト
it 'creates inventory' do
  post inventories_path, params: { inventory: { name: 'Test' } }
  expect(response).to redirect_to(inventory_path(Inventory.last))
end
```

### 2. 並列実行

#### Makefileコマンド
```bash
# 通常のE2Eテスト実行
make test-features

# 高速版E2Eテスト（slowタグを除外）
make test-e2e-fast

# 並列実行（2プロセス）
make test-e2e-parallel

# 全テストの並列実行（4プロセス）
make test-parallel-all
```

### 3. アセットの最適化

#### プリコンパイル
```bash
# テスト実行前にアセットをプリコンパイル
RAILS_ENV=test bundle exec rails assets:precompile

# テスト実行（プリコンパイル済み）
PRECOMPILE_ASSETS=false bundle exec rspec spec/features

# クリーンアップ
RAILS_ENV=test bundle exec rails assets:clobber
```

### 4. Dockerでの最適化

#### Seleniumサービスの利用
```yaml
# docker-compose.yml
services:
  selenium:
    image: selenium/standalone-chrome:latest
    ports:
      - "4444:4444"
    shm_size: 2gb
```

#### 環境変数の設定
```bash
# .env.test
SELENIUM_REMOTE_URL=http://selenium:4444/wd/hub
DOCKER_CONTAINER=true
```

### 5. Capybaraの設定最適化

#### タイムアウトの調整
```ruby
# spec/support/capybara_performance.rb
Capybara.default_max_wait_time = 2  # デフォルト: 5秒
```

#### 不要な機能の無効化
```ruby
# Chromeオプション
options.add_argument('--disable-images')  # 画像読み込み無効化
options.add_argument('--disable-extensions')  # 拡張機能無効化
options.add_argument('--disable-gpu')  # GPU無効化
```

## パフォーマンス測定

### 実行時間の計測
```bash
# プロファイル付きテスト実行
make test-profile

# 特定のテストの時間計測
time bundle exec rspec spec/features/csv_import_spec.rb
```

### ボトルネックの特定
1. **遅いテストの特定**
   ```bash
   bundle exec rspec --profile 10
   ```

2. **データベースクエリの最適化**
   - N+1クエリの解消
   - 不要なデータの読み込み削除

3. **待機時間の最適化**
   - 明示的なsleepの削除
   - Capybaraのwait条件の適切な使用

## ベストプラクティス

### 1. テストデータの最小化
```ruby
# 悪い例
create_list(:inventory, 100)

# 良い例
create_list(:inventory, 3)  # 必要最小限
```

### 2. ページ遷移の最小化
```ruby
# 悪い例
visit root_path
click_link 'Inventories'
click_link 'New'

# 良い例
visit new_inventory_path  # 直接アクセス
```

### 3. 非同期処理の適切な待機
```ruby
# 悪い例
sleep 3

# 良い例
expect(page).to have_content('Success', wait: 3)
```

### 4. テストの独立性
```ruby
# 各テストが独立して実行できるように
before do
  # 必要なデータのセットアップ
end

after do
  # クリーンアップ
end
```

## トラブルシューティング

### Selenium接続エラー
```bash
# Seleniumサービスの再起動
docker-compose restart selenium

# ログ確認
docker-compose logs selenium
```

### メモリ不足
```bash
# Chrome起動オプションに追加
options.add_argument('--memory-pressure-off')
options.add_argument('--max_old_space_size=4096')
```

### タイムアウトエラー
```ruby
# 特定のテストのみタイムアウトを延長
it 'handles large file', :slow do
  using_wait_time(10) do
    # 処理
  end
end
```

## CI/CD環境での実行

### GitHub Actions例
```yaml
- name: Run E2E tests
  run: |
    docker-compose up -d selenium
    make test-e2e-fast
  env:
    RAILS_ENV: test
    SELENIUM_REMOTE_URL: http://localhost:4444/wd/hub
```

### 並列実行の設定
```yaml
strategy:
  matrix:
    test-suite: [models, requests, features]
```

## まとめ

E2Eテストの高速化は以下の組み合わせで実現できます：

1. **テストの適切な分類** - JSが必要なテストを最小限に
2. **並列実行** - 複数プロセスでの同時実行
3. **キャッシング** - アセットやデータベースのキャッシュ活用
4. **最適化された設定** - Capybara/Seleniumの設定調整
5. **継続的な改善** - プロファイリングによるボトルネック特定

これらの手法を組み合わせることで、E2Eテストの実行時間を大幅に短縮できます。