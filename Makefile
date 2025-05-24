.PHONY: build up down restart logs ps clean db-create db-migrate db-reset db-seed db-setup bundle-install test rspec perf-generate-csv perf-test-import perf-benchmark-batch test-error-handling diagnose fix-connection fix-ssl-error

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
	@echo "利用可能なコマンド:"
	@echo "  make build          - Dockerイメージをビルド"
	@echo "  make up            - コンテナを起動"
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
	@echo "開発サーバー起動後は http://localhost:3000 でアクセス可能です"

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