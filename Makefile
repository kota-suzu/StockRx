# ============================================================================
# StockRx – Makefile (Refactored 2025-05-28)
# 保守性とDRY原則を重視したクリーンな設計
# ----------------------------------------------------------------------------
# 使い方: `make <target>` で実行。例: `make up`, `make test-models` 等
# ============================================================================

# --------------------------- シェル設定とエラーハンドリング ------------------
SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

# --------------------------- 変数定義 --------------------------------------
COMPOSE          := docker compose
WEB_SERVICE      := web
DB_SERVICE       := db
WEB_RUN          := $(COMPOSE) run --rm $(WEB_SERVICE)
WEB_UP           := $(COMPOSE) up -d
HTTP_PORT        ?= 3000
RAILS_ENV        ?= development
TEST_ENV_FLAGS   := -e RAILS_ENV=test -e TEST_DATABASE_HOST=$(DB_SERVICE) -e DATABASE_HOST=$(DB_SERVICE)
BUNDLE           := $(WEB_RUN) bundle
CURL             := curl -s -o /dev/null
DATE_STAMP       := $(shell date +%Y%m%d_%H%M%S)

# テスト関連
RSPEC_BASE       := $(COMPOSE) run --rm $(TEST_ENV_FLAGS) $(WEB_SERVICE) bundle exec rspec
TEST_FORMATS     := documentation progress

# --------------------------- ヘルパー関数 ----------------------------------
define log_info
	@printf "\033[36m=== %s ===\033[0m\n" "$(1)"
endef

define log_success
	@printf "\033[32m✅ %s\033[0m\n" "$(1)"
endef

define log_error
	@printf "\033[31m❌ %s\033[0m\n" "$(1)"
endef

define log_warning
	@printf "\033[33m⚠️  %s\033[0m\n" "$(1)"
endef

define check_health
	$(call log_info,ヘルスチェック: http://localhost:$(HTTP_PORT))
	@if $(CURL) http://localhost:$(HTTP_PORT); then \
		$(call log_success,Webサーバー正常稼働); \
	else \
		$(call log_error,Webサーバー接続失敗); \
		$(call log_warning,$(COMPOSE) logs $(WEB_SERVICE) で詳細を確認してください); \
	fi
endef

define run_test
	$(call log_info,$(1)テスト実行)
	$(RSPEC_BASE) $(2) --format $(3)
endef

define rails_db_cmd
	$(WEB_RUN) bin/rails db:$(1)
endef

define rails_test_cmd
	$(COMPOSE) run --rm $(TEST_ENV_FLAGS) $(WEB_SERVICE) bin/rails $(1)
endef

# --------------------------- PHONY ターゲット ------------------------------
.PHONY: help build up down restart server logs ps clean status \
        setup bundle-install \
        db-create db-migrate db-reset db-seed db-setup db-drop db-rollback \
        db-test-prepare db-test-migrate db-test-reset \
        test rspec test-setup \
        test-fast test-models test-requests test-jobs test-features test-integration \
        test-failed test-parallel test-coverage test-profile test-skip-heavy \
        test-unit-fast test-models-only test-all \
        ci security-scan lint lint-fix lint-fix-unsafe \
        console routes backup restore \
        perf-generate-csv perf-test-import perf-benchmark-batch \
        test-error-handling diagnose fix-connection fix-ssl-error

# --------------------------- デフォルトターゲット --------------------------
.DEFAULT_GOAL := help

# --------------------------- Docker 基本操作 -------------------------------
build:
	$(call log_info,Dockerイメージをビルド中)
	$(COMPOSE) build
	$(call log_success,ビルド完了)

up:
	$(call log_info,コンテナを起動中)
	$(WEB_UP)
	@sleep 3
	$(call check_health)

down:
	$(call log_info,コンテナを停止中)
	$(COMPOSE) down
	$(call log_success,コンテナ停止完了)

restart: down up

server: up
	$(call log_success,開発サーバー起動完了 – http://localhost:$(HTTP_PORT))

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

status: ps
	$(call check_health)

clean:
	$(call log_warning,すべてのコンテナとボリュームを削除します)
	$(COMPOSE) down -v --remove-orphans
	docker system prune -f
	$(call log_success,クリーンアップ完了)

# --------------------------- 初期セットアップ ------------------------------
setup: bundle-install db-setup
	$(call log_success,セットアップ完了)

bundle-install:
	$(call log_info,依存関係をインストール中)
	@mkdir -p tmp/bundle_cache && chmod -R 777 tmp/bundle_cache
	$(BUNDLE) config set frozen false
	$(BUNDLE) install
	$(call log_success,Bundle install完了)

# --------------------------- データベース操作 ------------------------------
# 開発環境用データベースコマンド
db-create:
	$(call log_info,データベースを作成中)
	$(call rails_db_cmd,create)
	$(call log_success,データベース作成完了)

db-migrate:
	$(call log_info,マイグレーションを実行中)
	$(call rails_db_cmd,migrate)
	$(call log_success,マイグレーション完了)

db-reset:
	$(call log_warning,データベースをリセット中)
	$(call rails_db_cmd,reset)
	$(call log_success,データベースリセット完了)

db-seed:
	$(call log_info,シードデータを投入中)
	$(call rails_db_cmd,seed)
	$(call log_success,シード投入完了)

db-setup:
	$(call log_info,データベースセットアップ中)
	$(call rails_db_cmd,setup)
	$(call log_success,データベースセットアップ完了)

db-drop:
	$(call log_warning,データベースを削除中)
	$(call rails_db_cmd,drop)
	$(call log_success,データベース削除完了)

db-rollback:
	$(call log_info,マイグレーションをロールバック中)
	$(call rails_db_cmd,rollback)
	$(call log_success,ロールバック完了)

# テスト環境用データベースコマンド
db-test-prepare:
	$(call log_info,テストデータベースを準備中)
	$(call rails_test_cmd,db:test:prepare)
	$(call log_success,テストデータベース準備完了)

db-test-migrate:
	$(call log_info,テスト環境でマイグレーション実行中)
	$(call rails_test_cmd,db:migrate)
	$(call log_success,テスト環境マイグレーション完了)

db-test-reset:
	$(call log_warning,テストデータベースをリセット中)
	$(call rails_test_cmd,db:reset)
	$(call log_success,テストデータベースリセット完了)

# --------------------------- テスト関連 ------------------------------------
test-setup: db-test-prepare
	$(call log_success,テスト環境準備完了)

test: test-setup rspec

rspec:
	$(call log_info,RSpecテスト実行)
	$(RSPEC_BASE)

# 高速テスト（軽量なテストのみ）
test-fast:
	$(call run_test,高速,spec/models spec/requests spec/helpers spec/decorators spec/validators,progress)

# カテゴリ別テスト
test-models:
	$(call run_test,モデル,spec/models,documentation)

test-requests:
	$(call run_test,リクエスト,spec/requests,documentation)

test-jobs:
	$(call run_test,ジョブ,spec/jobs,documentation)

test-features:
	$(call run_test,フィーチャー,spec/features,progress)

test-integration:
	$(call run_test,統合,spec/features spec/jobs,progress)

# 特殊なテスト実行
test-failed:
	$(call log_info,失敗したテストのみ再実行)
	$(RSPEC_BASE) --only-failures --format documentation

test-parallel:
	$(call log_info,並列テスト実行)
	$(WEB_RUN) bundle exec parallel_rspec spec/models spec/requests spec/helpers spec/decorators

test-parallel-all:
	$(call log_info,全テストの並列実行)
	$(WEB_RUN) bundle exec parallel_rspec spec/ -n 4

test-e2e-fast:
	$(call log_info,E2Eテスト高速実行)
	@echo "🔹 アセットをプリコンパイル中..."
	$(WEB_RUN) RAILS_ENV=test bundle exec rails assets:precompile
	@echo "🔹 E2Eテストを実行中..."
	$(WEB_RUN) PRECOMPILE_ASSETS=false bundle exec rspec spec/features --tag ~slow
	@echo "🔹 アセットをクリーンアップ中..."
	$(WEB_RUN) RAILS_ENV=test bundle exec rails assets:clobber

test-e2e-parallel:
	$(call log_info,E2Eテスト並列実行)
	$(WEB_RUN) bundle exec parallel_rspec spec/features -n 2

test-coverage:
	$(call log_info,カバレッジ測定付きテスト実行)
	$(RSPEC_BASE)
	$(call log_success,カバレッジレポート: coverage/index.html)

test-profile:
	$(call log_info,プロファイル付きテスト実行)
	$(RSPEC_BASE) --profile 10

test-skip-heavy:
	$(call run_test,軽量,--tag ~slow --tag ~integration --tag ~js,progress)

test-unit-fast:
	$(call run_test,高速ユニット,spec/models spec/helpers spec/decorators spec/validators spec/jobs --tag ~slow,progress)

test-models-only:
	$(call run_test,モデル限定,spec/models spec/helpers spec/decorators spec/validators,progress)

test-all: test-setup
	$(call log_info,全テスト実行（システムテスト含む）)
	$(call rails_test_cmd,test test:system)

# --------------------------- CI / 品質管理 ---------------------------------
ci: bundle-install security-scan lint test-all
	$(call log_success,CI処理完了)

security-scan:
	$(call log_info,セキュリティスキャン実行中)
	$(WEB_RUN) bin/brakeman --no-pager
	$(call log_success,セキュリティスキャン完了)

lint:
	$(call log_info,Rubocopリントチェック実行中)
	$(WEB_RUN) bin/rubocop
	$(call log_success,リントチェック完了)

lint-fix:
	$(call log_info,Rubocop自動修正（安全）実行中)
	$(WEB_RUN) bin/rubocop -a
	$(call log_success,安全な自動修正完了)

lint-fix-unsafe:
	$(call log_warning,Rubocop自動修正（非安全）実行中)
	$(WEB_RUN) bin/rubocop -A
	$(call log_success,全自動修正完了)

# --------------------------- パフォーマンステスト --------------------------
perf-generate-csv:
	$(call log_info,テスト用1万行CSVファイル生成中)
	$(WEB_RUN) bin/rails performance:generate_test_csv
	$(call log_success,CSVファイル生成完了)

perf-test-import:
	$(call log_info,CSVインポートパフォーマンステスト実行中)
	$(WEB_RUN) bin/rails performance:test_import
	$(call log_success,パフォーマンステスト完了)

perf-benchmark-batch:
	$(call log_info,バッチサイズ別CSVインポートベンチマーク実行中)
	$(WEB_RUN) bin/rails performance:benchmark_batch_sizes
	$(call log_success,ベンチマーク完了)

# --------------------------- エラーハンドリングテスト ----------------------
test-error-handling:
	$(call log_info,エラーハンドリング動作確認用サーバー起動)
	$(call log_warning,環境変数 ERROR_HANDLING_TEST=1 でproduction環境同様のエラーページを表示)
	ERROR_HANDLING_TEST=1 $(WEB_UP)
	@sleep 3
	@echo "テスト用URL:"
	@echo "  http://localhost:$(HTTP_PORT)/404 - 404エラーページ"
	@echo "  http://localhost:$(HTTP_PORT)/500 - 500エラーページ"
	@echo "  http://localhost:$(HTTP_PORT)?debug=0 - デバッグモード切替"

# --------------------------- ユーティリティ --------------------------------
console:
	$(call log_info,Railsコンソール起動)
	$(WEB_RUN) bin/rails console

routes:
	$(call log_info,ルーティング表示)
	$(WEB_RUN) bin/rails routes

backup:
	$(call log_info,データベースバックアップ作成中)
	@mkdir -p backup
	$(COMPOSE) exec $(DB_SERVICE) mysqldump -u root -ppassword app_db > backup/backup-$(DATE_STAMP).sql
	$(call log_success,バックアップ完了: backup/backup-$(DATE_STAMP).sql)

restore:
	$(call log_info,データベース復元中: $(file))
	@if [ -z "$(file)" ]; then \
		$(call log_error,ファイルを指定してください: make restore file=backup/backup.sql); \
		exit 1; \
	fi
	$(COMPOSE) exec -T $(DB_SERVICE) mysql -u root -ppassword app_db < $(file)
	$(call log_success,データベース復元完了)

# --------------------------- 診断 & 修復 ----------------------------------
diagnose:
	$(call log_info,StockRx システム診断)
	@echo
	@echo "=== コンテナ状態 ==="
	$(COMPOSE) ps
	@echo
	@echo "=== ポート使用状況 ==="
	@lsof -i :$(HTTP_PORT) || echo "ポート$(HTTP_PORT)は使用されていません"
	@echo
	@echo "=== HTTP接続確認 ==="
	@if $(CURL) -I http://localhost:$(HTTP_PORT); then \
		$(call log_success,HTTP接続正常); \
	else \
		$(call log_error,HTTP接続失敗); \
	fi
	@echo
	@echo "=== Web Logs (最新10行) ==="
	$(COMPOSE) logs --tail=10 $(WEB_SERVICE) || true

fix-connection:
	$(call log_info,接続問題の自動修復を試行中)
	$(COMPOSE) restart $(WEB_SERVICE)
	@sleep 5
	$(call check_health)

fix-ssl-error:
	$(call log_warning,SSL接続エラー対処)
	@echo "StockRxは開発環境でHTTPで動作します。"
	@echo
	@echo "正しいアクセス方法:"
	@echo "  ✅ http://localhost:$(HTTP_PORT)"
	@echo "  ❌ https://localhost:$(HTTP_PORT)"
	@echo
	@echo "ブラウザキャッシュクリア方法:"
	@echo "  Chrome: Ctrl+Shift+R (Windows) / Cmd+Shift+R (Mac)"
	@echo "  Firefox: Ctrl+F5 (Windows) / Cmd+Shift+R (Mac)"

# --------------------------- ヘルプ ----------------------------------------
help:
	@echo "StockRx Makefile - 利用可能なコマンド一覧"
	@echo "========================================"
	@echo
	@echo "🐳 Docker操作:"
	@echo "  build           - Dockerイメージをビルド"
	@echo "  up              - コンテナを起動"
	@echo "  down            - コンテナを停止"
	@echo "  restart         - コンテナを再起動"
	@echo "  server          - 開発サーバー起動（up + ヘルスチェック）"
	@echo "  logs            - ログを表示"
	@echo "  ps              - コンテナの状態を表示"
	@echo "  status          - システム状態を確認"
	@echo "  clean           - コンテナとボリュームを削除"
	@echo
	@echo "🔧 セットアップ:"
	@echo "  setup           - 初回セットアップ（bundle + db-setup）"
	@echo "  bundle-install  - 依存関係をインストール"
	@echo
	@echo "🗄️  データベース操作:"
	@echo "  db-create       - データベースを作成"
	@echo "  db-migrate      - マイグレーションを実行"
	@echo "  db-reset        - データベースをリセット"
	@echo "  db-seed         - シードデータを投入"
	@echo "  db-setup        - データベース完全セットアップ"
	@echo "  db-drop         - データベースを削除"
	@echo "  db-rollback     - マイグレーションをロールバック"
	@echo "  db-test-prepare - テストデータベース準備"
	@echo "  db-test-migrate - テスト環境マイグレーション"
	@echo "  db-test-reset   - テストデータベースリセット"
	@echo
	@echo "🧪 テスト実行:"
	@echo "  test            - テストを実行"
	@echo "  test-setup      - テスト環境準備"
	@echo "  test-fast       - 高速テスト実行"
	@echo "  test-models     - モデルテストのみ"
	@echo "  test-requests   - リクエストテストのみ"
	@echo "  test-jobs       - ジョブテストのみ"
	@echo "  test-features   - フィーチャーテストのみ"
	@echo "  test-integration- 統合テスト"
	@echo "  test-failed     - 失敗したテストのみ再実行"
	@echo "  test-parallel   - 並列テスト実行"
	@echo "  test-coverage   - カバレッジ計測付きテスト"
	@echo "  test-all        - すべてのテスト実行"
	@echo
	@echo "🔍 CI/品質管理:"
	@echo "  ci              - CIチェックをすべて実行"
	@echo "  security-scan   - セキュリティスキャン"
	@echo "  lint            - リントチェック"
	@echo "  lint-fix        - 安全な自動修正"
	@echo "  lint-fix-unsafe - 全自動修正（注意）"
	@echo
	@echo "⚡ パフォーマンス:"
	@echo "  perf-generate-csv   - テスト用CSVファイル生成"
	@echo "  perf-test-import    - CSVインポートパフォーマンステスト"
	@echo "  perf-benchmark-batch- バッチサイズ別ベンチマーク"
	@echo
	@echo "🛠️  ユーティリティ:"
	@echo "  console         - Railsコンソール起動"
	@echo "  routes          - ルーティング表示"
	@echo "  backup          - データベースバックアップ"
	@echo "  restore file=FILE - バックアップから復元"
	@echo
	@echo "🔧 診断・修復:"
	@echo "  diagnose        - システム診断"
	@echo "  fix-connection  - 接続問題の自動修復"
	@echo "  fix-ssl-error   - SSL接続エラー対処"
	@echo "  test-error-handling - エラーハンドリング動作確認"
	@echo
	@echo "開発サーバー起動後は http://localhost:$(HTTP_PORT) でアクセス可能です"