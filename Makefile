\
# ============================================================================
# StockRx – Makefile (Refactored 2025-05-26)
# Practical, DRY, and developer-friendly. Less yak-shaving, more coding.
# ----------------------------------------------------------------------------
# 使い方: `make <target>` で実行。例: `make up`, `make test-models` 等
# ============================================================================

# --------------------------- 変数定義 --------------------------------------
SHELL            := /usr/bin/env bash
COMPOSE          := docker compose
WEB_RUN          := $(COMPOSE) run --rm web
WEB_UP           := $(COMPOSE) up -d
HTTP_PORT        ?= 3000
RSPEC            := $(WEB_RUN) bundle exec rspec
BUNDLE           := $(WEB_RUN) bundle
CURL             := curl -s -o /dev/null

# --------------------------- ヘルパー関数 ----------------------------------
define check_health
	@echo "=== ヘルスチェック: http://localhost:$(HTTP_PORT) ==="
	@if $(CURL) http://localhost:$(HTTP_PORT); then \
	  echo "✅ Webサーバー正常稼働"; \
	else \
	  echo "❌ Webサーバー接続失敗 — \e[33m$(COMPOSE) logs web\e[0m で確認"; \
	fi
endef

# --------------------------- デフォルトターゲット --------------------------
.DEFAULT_GOAL := help

# --------------------------- PHONY ターゲット ------------------------------
.PHONY: build up down restart server logs ps clean \
        db-create db-migrate db-reset db-seed db-setup \
        setup bundle-install test rspec \
        test-fast test-models test-requests test-jobs test-features test-integration \
        test-failed test-parallel test-coverage test-profile test-skip-heavy \
        test-unit-fast test-models-only \
        ci security-scan lint lint-fix lint-fix-unsafe test-all \
        console routes backup restore help diagnose fix-connection fix-ssl-error

# --------------------------- Docker 基本操作 -------------------------------
build:
	$(COMPOSE) build

up:
	$(WEB_UP)
	@sleep 3
	$(call check_health)
	down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

server: up
	@echo "🚀 開発サーバー起動完了 – http://localhost:$(HTTP_PORT)"

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean:
	$(COMPOSE) down -v
	docker system prune -f

# --------------------------- 初期セットアップ ------------------------------
setup: db-setup bundle-install

bundle-install:
	mkdir -p tmp/bundle_cache && chmod -R 777 tmp/bundle_cache
	$(BUNDLE) config set frozen false
	$(BUNDLE) install

# --------------------------- データベース操作 ------------------------------
db-%:
	$(WEB_RUN) bin/rails db:$*

# エイリアス
.db-aliases: ;
db-create   : db-create

db-migrate  : db-migrate

db-reset    : db-reset

db-seed     : db-seed

db-setup    : db-setup

# --------------------------- テスト ----------------------------------------
# 共通関数
define run_rspec
	@echo "=== $(1) テスト実行 ===";
	$(RSPEC) $(2) --format $(3)
endef

# メタターゲット
TEST_DOC      := documentation
TEST_PROGRESS := progress

test: rspec

rspec:
	$(RSPEC)

test-fast:
	$(call run_rspec,高速, spec/models spec/requests spec/helpers spec/decorators spec/validators, $(TEST_PROGRESS))

test-models:
	$(call run_rspec,モデル, spec/models, $(TEST_DOC))

test-requests:
	$(call run_rspec,リクエスト, spec/requests, $(TEST_DOC))

test-jobs:
	$(call run_rspec,ジョブ, spec/jobs, $(TEST_DOC))

test-features:
	$(call run_rspec,フィーチャ, spec/features, $(TEST_PROGRESS))

test-integration:
	$(call run_rspec,統合, spec/features spec/jobs, $(TEST_PROGRESS))

test-failed:
	$(RSPEC) --only-failures --format $(TEST_DOC)

test-parallel:
	$(WEB_RUN) bundle exec parallel_rspec spec/models spec/requests spec/helpers spec/decorators

test-coverage:
	$(RSPEC) && echo "カバレッジ: coverage/index.html"

test-profile:
	$(RSPEC) --profile 10

test-skip-heavy:
	$(RSPEC) --tag ~slow --tag ~integration --tag ~js --format $(TEST_PROGRESS)

test-unit-fast:
	$(call run_rspec,軽量ユニット, spec/models spec/helpers spec/decorators spec/validators spec/jobs --tag ~slow, $(TEST_PROGRESS))

test-models-only:
	$(call run_rspec,モデル限定, spec/models spec/helpers spec/decorators spec/validators, $(TEST_PROGRESS))

# --------------------------- CI / Lint / Security -------------------------
ci: bundle-install security-scan lint test-all

security-scan:
	$(WEB_RUN) bin/brakeman --no-pager

lint:
	$(WEB_RUN) bin/rubocop

lint-fix:
	$(WEB_RUN) bin/rubocop -a

lint-fix-unsafe:
	$(WEB_RUN) bin/rubocop -A

# --------------------------- その他ユーティリティ --------------------------
console:
	$(WEB_RUN) bin/rails console

routes:
	$(WEB_RUN) bin/rails routes

backup:
	$(COMPOSE) exec db mysqldump -u root -ppassword app_db > backup/backup-$(shell date +%Y%m%d).sql

restore:
	$(COMPOSE) exec -T db mysql -u root -ppassword app_db < $(file)

# --------------------------- ヘルプ ----------------------------------------
help:
	@grep -E '^[a-zA-Z_\-]+:.*?##' $(MAKEFILE_LIST) | \
		sed -e 's/^[^:]*://g' -e 's/##/📌/g' | \
		column -t -s "📌" | \
		sed -e 's/^/  /'

# --------------------------- 診断 & 修復 ----------------------------------
diagnose:
	@echo "=== StockRx システム診断 ===" && echo
	$(COMPOSE) ps && echo
	@lsof -i :$(HTTP_PORT) || echo "ポート$(HTTP_PORT)は使用されていません" && echo
	@if $(CURL) -I http://localhost:$(HTTP_PORT); then echo "✅ HTTP接続正常"; else echo "❌ HTTP接続失敗"; fi && echo
	@echo "--- Web Logs (最新10行) ---" && $(COMPOSE) logs --tail=10 web || true

fix-connection:
	@echo "=== 接続問題の自動修復を試行中... ==="
	$(COMPOSE) restart web
	@sleep 5
	$(call check_health)

fix-ssl-error:
	@echo "=== SSL接続エラー対処 ===" && \
	  echo "開発環境は HTTP で動作します。 https://localhost:$(HTTP_PORT) は使わず http://localhost:$(HTTP_PORT) をご利用下さい。"
