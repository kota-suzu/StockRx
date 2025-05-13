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
	@echo "  make console       - Railsコンソールを起動"
	@echo "  make routes        - ルーティングを表示"
	@echo "  make backup        - データベースをバックアップ"
	@echo "  make restore file=FILE - バックアップから復元" 