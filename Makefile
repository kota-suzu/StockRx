.PHONY: build up down restart logs ps clean db-create db-migrate db-reset bundle-install test

# Docker Compose コマンド
build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

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

# アプリケーション関連コマンド
bundle-install:
	docker compose run --rm web bundle install

test:
	docker compose run --rm web bin/rails test

# CI関連コマンド
ci: security-scan lint test-all

security-scan:
	docker compose run --rm web bin/brakeman --no-pager
	# importmapがインストールされていない場合は次のコマンドをコメントアウトしてください
	# docker compose run --rm web bin/importmap audit
	@echo "注意: JavaScriptの依存関係スキャンは現在無効化されています。有効化するには importmap をインストールしてください。"
	@echo "    $ bundle exec rails importmap:install"

lint:
	docker compose run --rm web bin/rubocop

test-all:
	docker compose run --rm web bin/rails db:test:prepare test test:system

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

# ヘルプ
help:
	@echo "利用可能なコマンド:"
	@echo "  make build          - Dockerイメージをビルド"
	@echo "  make up            - コンテナを起動"
	@echo "  make down          - コンテナを停止"
	@echo "  make restart       - コンテナを再起動"
	@echo "  make logs          - ログを表示"
	@echo "  make ps            - コンテナの状態を表示"
	@echo "  make clean         - コンテナとボリュームを削除"
	@echo "  make db-create     - データベースを作成"
	@echo "  make db-migrate    - マイグレーションを実行"
	@echo "  make db-reset      - データベースをリセット"
	@echo "  make bundle-install - 依存関係をインストール"
	@echo "  make test          - テストを実行"
	@echo "  make ci            - CIチェックをすべて実行（セキュリティスキャン、リント、テスト）"
	@echo "  make security-scan - セキュリティスキャンを実行"
	@echo "  make lint          - リントチェックを実行"
	@echo "  make test-all      - すべてのテストを実行"
	@echo "  make console       - Railsコンソールを起動"
	@echo "  make routes        - ルーティングを表示"
	@echo "  make backup        - データベースをバックアップ"
	@echo "  make restore file=FILE - バックアップから復元" 