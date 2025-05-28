# StockRx TODO List

## 高優先度タスク

### テスト環境の改善
- [ ] **Selenium/Chrome環境の自動セットアップ** (spec/rails_helper.rb:171-173)
  - Docker環境での自動検出と設定
  - CI/CD環境での最適化
  - プロキシ設定の追加

- [ ] **並列テスト実行時の最適化** (spec/rails_helper.rb:252-267)
  - データベース分離設定
  - ファイルシステム分離
  - ポート番号の動的割り当て

### パフォーマンス最適化
- [ ] **大量データ処理の最適化** (app/jobs/import_inventories_job.rb:126-130)
  - ストリーミング処理の実装
  - チャンク処理の最適化
  - メモリ効率の改善

- [ ] **Redis接続エラー対策** (config/initializers/sidekiq.rb:70-78)
  - 再接続ロジックの実装
  - タイムアウト設定の調整
  - エラーハンドリングの強化

## 中優先度タスク

### インフラストラクチャ
- [ ] **Docker Compose設定の改善** (docker-compose.yml:1-9)
  - 環境変数の.envファイル移行
  - バックアップ自動削除機能
  - Redisメモリ設定の最適化
  - セキュリティ強化（SSL/TLS設定）

- [ ] **CI/CD環境での最適化** (spec/rails_helper.rb:269-291)
  - CI環境専用の軽量設定
  - Selenium Grid連携
  - Docker環境でのSelenium Grid使用

### 機能改善
- [ ] **ActionCable通信テスト** (spec/features/csv_import_spec.rb:262-263)
  - リアルタイム通信の詳細テスト実装
  - 統合テストでの実装

- [ ] **バッチ処理の改善** (app/models/batch.rb:147-151)
  - バッチ処理の並列化
  - エラーハンドリングの強化
  - 進捗レポートの詳細化

## 低優先度タスク

### コード品質
- [ ] **デコレーター層の拡充** (app/decorators/)
  - 他のモデル用デコレーターの実装
  - ビューヘルパーの整理

- [ ] **API認証の実装** (app/controllers/api/v1/inventories_controller.rb:5-7)
  - JWTトークン認証
  - レート制限の実装
  - APIキー管理

### ドキュメント
- [ ] **API仕様書の作成**
  - OpenAPI/Swagger定義
  - 使用例の追加

- [ ] **デプロイメントガイド**
  - 本番環境のセットアップ手順
  - パフォーマンスチューニングガイド

## 完了したタスク
- [x] Selenium WebDriverエラーの調査と修正
- [x] ActionCableのconnectメソッドエラーの修正
- [x] 横展開の確認と修正
- [x] ベストプラクティスの実装（SeleniumHelper）
- [x] リダイレクトURL不一致エラーの修正
- [x] CSVインポート表示テキストの修正
- [x] Redis接続エラーのスキップ処理
- [x] CSVインポート実際の処理動作確認
- [x] ActiveJob設定の統一化と最適化
- [x] テスト環境でのジョブ実行問題の解決
- [x] Sidekiq::Testing設定の改善

## メモ
- JavaScript必須のテストは `js: true` タグを付ける
- Docker環境では `docker-compose up selenium` でSeleniumサービスを起動
- テスト実行時は `make rspec` または `docker-compose exec web bundle exec rspec` を使用

## テスト設定の改善点

### ActiveJob設定
- `config/environments/test.rb`: `config.active_job.queue_adapter = :inline`
- `spec/support/sidekiq.rb`: 自動的にCSVインポートテストでインライン実行
- feature specでは `ensure_job_execution` ヘルパーが利用可能

### Sidekiq設定
- テスト環境: `Sidekiq::Testing.inline!` で即座実行
- Redis接続エラー時: 自動スキップ処理
- UI関連テスト: `skip_if_redis_unavailable` でスキップ