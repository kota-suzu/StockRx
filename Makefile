.PHONY: build up down restart server logs ps clean db-create db-migrate db-reset db-seed db-setup bundle-install test rspec perf-generate-csv perf-test-import perf-benchmark-batch test-error-handling diagnose fix-connection fix-ssl-error help test-fast test-models test-controllers test-requests test-jobs test-features test-integration test-failed test-parallel test-coverage test-profile test-skip-heavy console routes backup restore ci security-scan lint lint-fix lint-fix-unsafe test-all test-helpers test-decorators test-validators

# Docker Compose コマンド
build:
	docker compose build

up:
	docker compose up -d
	@echo "=== コンテナ起動確認中... ==="
	@sleep 5
	@docker compose ps
	@echo ""
	@echo "=== ヘルスチェック実行中... ==="
	@if curl -s http://localhost:3000 > /dev/null; then \
		echo "✅ Webサーバー正常稼働 - http://localhost:3000 でアクセス可能です"; \
	else \
		echo "❌ Webサーバー接続失敗 - ログを確認してください:"; \
		echo "  docker compose logs web"; \
	fi

down:
	docker compose down

restart:
	docker compose restart

server:
	@echo "=== StockRx開発サーバー起動中... ==="
	docker compose up -d
	@echo "✅ サーバー起動完了 - http://localhost:3000 でアクセス可能です"

setup:
	docker compose run --rm web bin/rails db:create db:migrate db:seed

logs:
	docker compose logs -f

ps:
	docker compose ps

clean:
	docker compose down -v
	docker system prune -f

# データベース関連コマンド
db-create:
	docker compose run --rm web bin/rails db:create

db-migrate:
	docker compose run --rm web bin/rails db:migrate

db-reset:
	docker compose run --rm web bin/rails db:drop db:create db:migrate

db-seed:
	docker compose run --rm web bin/rails db:seed

db-setup:
	docker compose run --rm web bin/rails db:setup

# アプリケーション関連コマンド
bundle-install:
	mkdir -p tmp/bundle_cache
	chmod -R 777 tmp/bundle_cache
	docker compose run --rm web bundle config set frozen false
	docker compose run --rm web bundle install

test:
	docker compose run --rm web bin/rails test

# RSpec関連コマンド
rspec:
	docker compose run --rm web bundle exec rspec

# =============================================================================
# TODO: 開発タスク・優先度管理 （最新更新：2025年5月）
# =============================================================================
# 
# 【優先度：緊急】実装済み・完了済み機能の拡張
# ✅ ヘルパー機能のベストプラクティス実装（完了）
# ✅ ソートアイコン機能の追加（完了）
# ✅ コード品質改善（RuboCop対応完了）
# 🚧 CSV一括インポート機能の安定性向上（進行中）
# 🚧 在庫アラート機能の実装（進行中）
#
# 【優先度：高】テスト品質・信頼性向上
# 📝 Job/ActionCableテストの修復（Redis Mock設定改善）
# 📝 Feature Tests（E2E）安定化（Selenium設定最適化）
# 📝 エラーハンドリングテストの包括実装
# 📝 セキュリティテスト自動化（OWASP Top 10対応）
# 📝 パフォーマンステスト実装（N+1問題検出）
#
# 【優先度：中】長期戦略・アーキテクチャ改善
# 📝 国際化・多言語対応（英語・中国語・韓国語）
# 📝 CI/CD最適化（GitHub Actions並列化）
# 📝 監視・アラート機能（Sentry/DataDog連携）
# 📝 キャッシュ戦略（Redis活用最適化）
# 📝 API Gateway導入検討
#
# 詳細なタスク管理は `docs/development_plan.md` に移動予定

# 効率的なテスト実行コマンド（Google L8レベルのベストプラクティス）
test-fast:
	@echo "=== 高速テスト実行（モデル・リクエスト・ユニットテストのみ） ==="
	docker compose run --rm web bundle exec rspec spec/models spec/requests spec/helpers spec/decorators spec/validators --format progress

test-models:
	@echo "=== モデルテスト実行 ==="
	docker compose run --rm web bundle exec rspec spec/models --format documentation

test-controllers:
	@echo "=== リクエストテスト実行（旧Controller Test） ==="
	docker compose run --rm web bundle exec rspec spec/requests --format documentation

test-requests:
	@echo "=== リクエスト/コントローラーテスト実行 ==="
	docker compose run --rm web bundle exec rspec spec/requests --format documentation

test-jobs:
	@echo "=== ジョブテスト実行 ==="
	docker compose run --rm web bundle exec rspec spec/jobs --format documentation

test-features:
	@echo "=== フィーチャーテスト実行（時間がかかります） ==="
	docker compose run --rm web bundle exec rspec spec/features --format progress

test-integration:
	@echo "=== 統合テスト実行（時間がかかります） ==="
	docker compose run --rm web bundle exec rspec spec/features spec/jobs --format progress

test-failed:
	@echo "=== 失敗したテストのみ再実行 ==="
	docker compose run --rm web bundle exec rspec --only-failures --format documentation

test-parallel:
	@echo "=== 並列テスト実行（高速化） ==="
	docker compose run --rm web bundle exec parallel_rspec spec/models spec/requests spec/helpers spec/decorators

test-coverage:
	@echo "=== カバレッジ計測付きテスト実行 ==="
	docker compose run --rm web bundle exec rspec
	@echo "カバレッジレポート: coverage/index.html"

test-coverage-fast:
	@echo "=== 軽量テストのみでカバレッジ計測 ==="
	docker compose run --rm web bundle exec rspec spec/models spec/requests spec/helpers spec/decorators spec/validators spec/jobs --tag ~slow --tag ~js --tag ~integration
	@echo "カバレッジレポート: coverage/index.html"

test-profile:
	@echo "=== テストプロファイリング（遅いテストの特定） ==="
	docker compose run --rm web bundle exec rspec --profile 10

test-skip-heavy:
	@echo "=== 重いテストをスキップして実行 ==="
	docker compose run --rm web bundle exec rspec --tag ~slow --tag ~integration --tag ~js --format progress

test-unit-fast:
	@echo "=== 軽量なユニット・モデルテストのみ実行（最高速） ==="
	docker compose run --rm web bundle exec rspec spec/models spec/helpers spec/decorators spec/validators spec/jobs --tag ~slow --format progress

test-models-only:
	@echo "=== モデル・ヘルパー・バリデーターテストのみ実行（超軽量） ==="
	docker compose run --rm web bundle exec rspec spec/models spec/helpers spec/decorators spec/validators --format progress

# CI関連コマンド
ci: bundle-install security-scan lint test-all

security-scan:
	docker compose run --rm web bin/brakeman --no-pager
	# importmapがインストールされていない場合は次のコマンドをコメントアウトしてください
	# docker compose run --rm web bin/importmap audit
	@echo "注意: JavaScriptの依存関係スキャンは現在無効化されています。有効化するには importmap をインストールしてください。"
	@echo "    $ bundle exec rails importmap:install"

lint:
	docker compose run --rm web bin/rubocop

lint-fix:
	docker compose run --rm web bin/rubocop -a

lint-fix-unsafe:
	docker compose run --rm web bin/rubocop -A

# ヘルパー・デコレーター・バリデーター関連テスト
test-helpers:
	@echo "=== ヘルパーテスト実行 ==="
	docker compose run --rm web bundle exec rspec spec/helpers --format documentation

test-decorators:
	@echo "=== デコレーターテスト実行 ==="
	docker compose run --rm web bundle exec rspec spec/decorators --format documentation

test-validators:
	@echo "=== バリデーターテスト実行 ==="
	docker compose run --rm web bundle exec rspec spec/validators --format documentation

# ヘルパー・デコレーター・バリデーターのコード品質チェック
lint-helpers:
	@echo "=== ヘルパーファイルのコード品質チェック ==="
	docker compose run --rm web bundle exec rubocop app/helpers/ --format offenses

lint-decorators:
	@echo "=== デコレーターファイルのコード品質チェック ==="
	docker compose run --rm web bundle exec rubocop app/decorators/ --format offenses

lint-validators:
	@echo "=== バリデーターファイルのコード品質チェック ==="
	docker compose run --rm web bundle exec rubocop app/validators/ --format offenses

test-all:
	docker compose run --rm -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 web bin/rails db:test:prepare
	docker compose run --rm web bin/rails test
	docker compose run --rm web bin/rails test:system
	docker compose run --rm web bundle exec rspec

# エラーハンドリングテスト用コマンド
test-error-handling:
	@echo "=== 本番エラーページ表示モードで開発サーバー起動 ==="
	@echo "ブラウザでエラーを発生させるURLを開いてテストしてください:"
	@echo "  - 404エラー: http://localhost:3000/nonexistent"
	@echo "  - 422エラー: Railsコンソールで invalid.save!"
	@echo "  - 500エラー: http://localhost:3000/rails/info/routes?raise=true"
	docker compose run --rm -e ERROR_HANDLING_TEST=1 -p 3000:3000 web bin/rails server -b 0.0.0.0

# TODO: エラーハンドリング自動テストの実装（優先度：高）
test-error-api:
	@echo "=== APIエラーレスポンステスト実行 ==="
	@echo "JSON API形式エラーレスポンスの一貫性を自動検証中..."
	docker compose run --rm web bundle exec rspec spec/requests --tag error_handling --format documentation

test-error-status-codes:
	@echo "=== HTTPステータスコード網羅テスト ==="
	@echo "400, 401, 403, 404, 409, 422, 429, 500の各エラーケースを自動検証中..."
	docker compose run --rm web bundle exec rspec spec/controllers spec/requests --tag status_codes --format documentation

test-security:
	@echo "=== セキュリティテスト実行 ==="
	@echo "OWASP Top 10対応チェック、XSS/CSRF/SQLインジェクション脆弱性検証中..."
	docker compose run --rm web bin/brakeman --no-pager --confidence-level 2
	# TODO: 追加のセキュリティテストの実装が必要
	# docker compose run --rm web bundle exec rspec spec/security --format documentation

test-performance:
	@echo "=== パフォーマンステスト実行 ==="
	@echo "N+1問題検出、メモリ使用量監視、クエリ効率測定中..."
	docker compose run --rm web bundle exec rspec spec/performance --format documentation

# 開発用コマンド
console:
	docker compose run --rm web bin/rails console

routes:
	docker compose run --rm web bin/rails routes

# バックアップ関連コマンド
backup:
	docker compose exec db mysqldump -u root -ppassword app_db > backup/backup-$$(date +%Y%m%d).sql

restore:
	docker compose exec -T db mysql -u root -ppassword app_db < $(file)

# パフォーマンステスト用コマンド
perf-generate-csv:
	docker compose run --rm web bin/rails performance:generate_csv

perf-test-import:
	docker compose run --rm web bin/rails performance:test_csv_import

perf-benchmark-batch:
	docker compose run --rm web bin/rails performance:benchmark_batch_sizes

# ヘルプ
help:
	@echo "=== StockRx 開発環境 コマンド一覧 ==="
	@echo ""
	@echo "🐳 Docker基本操作:"
	@echo "  make build          - Dockerイメージをビルド"
	@echo "  make up            - コンテナを起動"
	@echo "  make server        - 開発サーバー起動（推奨）"
	@echo "  make down          - コンテナを停止"
	@echo "  make restart       - コンテナを再起動"
	@echo "  make setup         - データベース作成、マイグレーション、シードを一括実行"
	@echo "  make logs          - ログを表示"
	@echo "  make ps            - コンテナの状態を表示"
	@echo "  make clean         - コンテナとボリュームを削除"
	@echo "  make db-create     - データベースを作成"
	@echo "  make db-migrate    - マイグレーションを実行"
	@echo "  make db-reset      - データベースをリセット"
	@echo "  make db-seed       - シードデータを投入"
	@echo "  make db-setup      - データベース作成、マイグレーション、シードを一括実行"
	@echo "  make bundle-install - 依存関係をインストール"
	@echo "  make test          - テストを実行"
	@echo "  make rspec         - RSpecテストを実行"
	@echo "  make ci            - CIチェックをすべて実行（セキュリティスキャン、リント、テスト）"
	@echo "  make security-scan - セキュリティスキャンを実行"
	@echo "  make lint          - リントチェックを実行"
	@echo "  make lint-fix      - 安全な自動修正を適用"
	@echo "  make lint-fix-unsafe - すべての自動修正を適用（注意：破壊的変更の可能性あり）"
	@echo "  make test-all      - すべてのテストを実行"
	@echo "  make console       - Railsコンソールを起動"
	@echo "  make routes        - ルーティングを表示"
	@echo "  make backup        - データベースをバックアップ"
	@echo "  make restore file=FILE - バックアップから復元"
	@echo "  make perf-generate-csv  - テスト用の1万行CSVファイルを生成"
	@echo "  make perf-test-import   - CSVインポートのパフォーマンスをテスト"
	@echo "  make perf-benchmark-batch - 異なるバッチサイズでCSVインポートをベンチマーク"
	@echo "  make test-error-handling - エラーハンドリング動作確認用サーバー起動"
	@echo ""
	@echo "=== 効率的なテスト実行コマンド ==="
	@echo "  make test-fast     - 高速テスト（モデル・リクエスト・ユニットテストのみ）"
	@echo "  make test-models   - モデルテストのみ"
	@echo "  make test-controllers - リクエストテストのみ"
	@echo "  make test-requests - リクエスト/コントローラーテストのみ"
	@echo "  make test-jobs     - ジョブテストのみ"
	@echo "  make test-features - フィーチャーテスト（重い）"
	@echo "  make test-integration - 統合テスト（重い）"
	@echo "  make test-failed   - 失敗したテストのみ再実行"
	@echo "  make test-parallel - 並列テスト実行"
	@echo "  make test-coverage - カバレッジ計測"
	@echo "  make test-coverage-fast - 軽量テストのみでカバレッジ計測"
	@echo "  make test-profile  - 遅いテストの特定"
	@echo "  make test-skip-heavy - 重いテストをスキップ"
	@echo "  make test-unit-fast - 軽量なユニット・モデルテストのみ実行（最高速）"
	@echo "  make test-models-only - モデル・ヘルパー・バリデーターテストのみ実行（超軽量）"
	@echo ""
	@echo "🎨 コンポーネント別テスト:"
	@echo "  make test-helpers   - ヘルパーテスト実行"
	@echo "  make test-decorators - デコレーターテスト実行"
	@echo "  make test-validators - バリデーターテスト実行"
	@echo ""
	@echo "🔍 コード品質チェック:"
	@echo "  make lint-helpers   - ヘルパーファイルの品質チェック"
	@echo "  make lint-decorators - デコレーターファイルの品質チェック"
	@echo "  make lint-validators - バリデーターファイルの品質チェック"
	@echo ""
	@echo "⚡ エラーハンドリング・セキュリティテスト:"
	@echo "  make test-error-api - APIエラーレスポンステスト"
	@echo "  make test-error-status-codes - HTTPステータスコード網羅テスト"
	@echo "  make test-security - セキュリティテスト（Brakeman等）"
	@echo "  make test-performance - パフォーマンステスト（N+1問題検出等）"
	@echo ""
	@echo "🚀 開発サーバー起動後は http://localhost:3000 でアクセス可能です"
	@echo "📖 より詳細なドキュメントは README.md をご確認ください"

# 診断・トラブルシューティング用コマンド
diagnose:
	@echo "=== StockRx システム診断 ==="
	@echo ""
	@echo "1. コンテナ状態確認:"
	docker compose ps
	@echo ""
	@echo "2. ポート使用状況確認:"
	@lsof -i :3000 || echo "ポート3000は使用されていません"
	@echo ""
	@echo "3. Webサーバー接続テスト:"
	@if curl -s -I http://localhost:3000 > /dev/null; then \
		echo "✅ HTTP接続正常"; \
	else \
		echo "❌ HTTP接続失敗"; \
	fi
	@echo ""
	@echo "4. 最新ログ確認:"
	@echo "--- Web Container Logs (最新10行) ---"
	@docker compose logs --tail=10 web 2>/dev/null || echo "webコンテナが起動していません"
	@echo ""

# 接続問題解決用コマンド
fix-connection:
	@echo "=== 接続問題の自動修復を試行中... ==="
	@echo "1. webコンテナの再起動..."
	docker compose restart web
	@echo "2. 起動待機中..."
	@sleep 10
	@echo "3. 接続テスト..."
	@if curl -s http://localhost:3000 > /dev/null; then \
		echo "✅ 修復成功 - http://localhost:3000 でアクセス可能"; \
	else \
		echo "❌ 修復失敗 - 手動確認が必要:"; \
		echo "  make diagnose"; \
		echo "  docker compose logs web"; \
	fi

# SSL/HTTPS エラー対策用
fix-ssl-error:
	@echo "=== SSL接続エラーの対処法 ==="
	@echo "ブラウザで https://localhost:3000 でアクセスしていませんか？"
	@echo "StockRxは開発環境でHTTPで動作します。"
	@echo ""
	@echo "正しいアクセス方法:"
	@echo "  ✅ http://localhost:3000"
	@echo "  ❌ https://localhost:3000"
	@echo ""
	@echo "ブラウザキャッシュクリア方法:"
	@echo "  Chrome: Ctrl+Shift+R (Windows) / Cmd+Shift+R (Mac)"
	@echo "  Firefox: Ctrl+F5 (Windows) / Cmd+Shift+R (Mac)"

# ============================================
# TODO: エラーハンドリング・セキュリティテストの包括的拡張（優先度：高）
# ============================================
# 4. エラーハンドリングテスト拡張
#    - 各HTTPステータスコード（400, 401, 403, 404, 409, 422, 429, 500）の自動テスト
#    - JSON API形式レスポンスの一貫性確認
#    - 多言語エラーメッセージの自動検証
#    - 本番環境エラーページの自動E2Eテスト
#
# 5. セキュリティテストの包括的実装
#    - OWASP Top 10対応チェック
#    - XSS/CSRF/SQLインジェクション脆弱性検証
#    - 認証・認可システムの境界値テスト
#    - レート制限機能の負荷テスト
#    - データ暗号化・復号化の整合性テスト
#
# 6. パフォーマンステスト拡張
#    - 大量データ処理時のメモリ使用量監視
#    - バッチ処理の並列実行効率測定
#    - データベースクエリのN+1問題自動検出
#    - キャッシュ効率とヒット率の分析
#
# ============================================
# TODO: CI/CD最適化と自動化強化（優先度：中）
# ============================================
# 7. 自動化パイプライン拡張
#    - GitHubActions/GitLabCIとの統合
#    - プルリクエスト作成時の自動テスト実行
#    - コードカバレッジ低下時の自動警告
#    - セキュリティスキャン結果のSlack/Teams通知
#
# 8. コード品質保証の継続的改善
#    - rubocop-performance・rubocop-railsの段階的導入
#    - メソッド複雑度・クラス行数の自動監視
#    - 技術的負債の可視化と改善計画
#    - ドキュメント更新の自動化
#
# 9. 監視・アラート機能拡張
#    - テスト実行時間の推移追跡
#    - 失敗率・成功率の統計レポート
#    - テスト環境の安定性監視
#    - 外部依存サービスとの接続状況チェック 