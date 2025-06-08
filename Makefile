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
RSPEC            := $(COMPOSE) run --rm -e RAILS_ENV=test -e DISABLE_HOST_AUTHORIZATION=true web bundle exec rspec
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
        setup services-health-check bundle-install test rspec \
        test-fast test-models test-requests test-jobs test-features test-integration \
        test-failed test-parallel test-coverage test-profile test-skip-heavy \
        test-unit-fast test-models-only \
        ci ci-github security-scan security-scan-github lint lint-github lint-fix lint-fix-unsafe test-all test-github \
        console routes backup restore help diagnose fix-connection fix-ssl-error \
        perf-generate-csv perf-test-import perf-benchmark-batch test-error-handling

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
# TODO: セットアップ処理の堅牢性向上（ヘルスチェック待機、エラーハンドリング）
# TODO: 段階的なサービス起動とヘルスチェック確認
setup: services-health-check bundle-install db-setup

services-health-check:
	@echo "=== サービス起動とヘルスチェック ==="
	$(COMPOSE) up -d db redis
	@echo "MySQL初期化待機中..."
	@for i in {1..30}; do \
		if docker compose exec -T db mysqladmin ping -h localhost -u root -ppassword > /dev/null 2>&1; then \
			echo "✅ MySQL起動完了"; \
			break; \
		fi; \
		echo "MySQL初期化中... ($$i/30)"; \
		sleep 2; \
	done

bundle-install:
	mkdir -p tmp/bundle_cache && chmod -R 777 tmp/bundle_cache
	$(BUNDLE) config set frozen false
	$(BUNDLE) install

# --------------------------- データベース操作 ------------------------------
db-%:
	$(WEB_RUN) bin/rails db:$*

# エイリアス - TODO: 循環参照の修正完了、db:*タスクへの適切な転送
.db-aliases: ;
# 以下は不要な循環参照エイリアスを削除し、直接的な依存に変更

# --------------------------- テスト ----------------------------------------
# TODO: Host Authorization対策 - 全テストでDISABLE_HOST_AUTHORIZATION=trueを設定
# 根本的解決: Makefileレベルで環境変数を設定し、403 Blocked hostエラーを完全回避
# 横展開確認: CI/CD環境でも同様の設定が必要
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
	$(call run_rspec,高速, spec/models spec/requests spec/helpers spec/decorators spec/validators spec/forms, $(TEST_PROGRESS))

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
	$(COMPOSE) run --rm -e RAILS_ENV=test -e DISABLE_HOST_AUTHORIZATION=true web bundle exec parallel_rspec spec/models spec/requests spec/helpers spec/decorators

test-coverage:
	@echo "=== カバレッジ計測付きテスト実行 ==="
	$(COMPOSE) run --rm -e RAILS_ENV=test -e DISABLE_HOST_AUTHORIZATION=true -e COVERAGE=true web bundle exec rspec && echo "📊 カバレッジレポート: coverage/index.html"

test-profile:
	$(RSPEC) --profile 10

test-skip-heavy:
	$(RSPEC) --tag ~slow --tag ~integration --tag ~js --format $(TEST_PROGRESS)

test-unit-fast:
	$(call run_rspec,軽量ユニット, spec/models spec/helpers spec/decorators spec/validators spec/jobs --tag ~slow, $(TEST_PROGRESS))

test-models-only:
	$(call run_rspec,モデル限定, spec/models spec/helpers spec/decorators spec/validators, $(TEST_PROGRESS))

# --------------------------- CI / Lint / Security -------------------------

# 共通CI環境変数（横展開一貫性確保）
CI_ENV_VARS = \
	-e RAILS_ENV=test \
	-e CI=true \
	-e DATABASE_URL=mysql2://root:password@db:3306/app_test \
	-e DATABASE_PASSWORD="password" \
	-e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
	-e DISABLE_HOST_AUTHORIZATION=true \
	-e RAILS_ZEITWERK_MISMATCHES=error

# 高速化されたGitHub Actions互換のCIコマンド（メタ認知的最適化）
ci-github: 
	@echo "🚀 === GitHub Actions高速化CI実行開始 ==="
	@echo "📊 最適化項目: 並列処理、条件付き実行、キャッシュ活用"
	@$(MAKE) --no-print-directory bundle-install-conditional
	@$(MAKE) --no-print-directory ci-fast-check
	@$(MAKE) --no-print-directory -j3 security-scan-github lint-github ci-prepare-db
	@$(MAKE) --no-print-directory test-github-optimized
	@echo "✅ === CI実行完了 ==="

# 高速事前チェック（横展開確認項目）
ci-fast-check:
	@echo "=== 高速事前チェック ==="
	@echo "📋 Zeitwerkチェック..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) web bundle exec rails zeitwerk:check
	@echo "🐳 コンテナ健全性チェック..."
	@if ! docker inspect stockrx-db-1 --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then \
		echo "⚠️  データベースコンテナが不健全です"; \
		$(COMPOSE) restart db; \
		sleep 5; \
	fi

# 条件付きbundle install（CLAUDE.md準拠：無駄を排除）
bundle-install-conditional:
	@echo "=== 条件付き依存関係チェック ==="
	@if [ ! -f .bundle/config ] || [ Gemfile -nt .bundle/config ] || [ Gemfile.lock -nt .bundle/config ]; then \
		echo "📦 Gemfile更新検出 - bundle install実行"; \
		mkdir -p tmp/bundle_cache && chmod -R 777 tmp/bundle_cache; \
		$(WEB_RUN) bundle config set frozen false; \
		$(WEB_RUN) bundle install; \
		touch .bundle/config; \
	else \
		echo "✅ 依存関係は最新 - bundle installスキップ"; \
	fi

# 高速データベース準備（CI最適化版）
ci-prepare-db:
	@echo "=== 📊 高速データベース準備 ==="
	@echo "戦略: 段階的準備、エラー回復、並列処理"
	
	# Step 1: データベース存在確認と高速作成
	@echo "🔍 データベース状態確認..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) web sh -c " \
		if ! bundle exec rails runner 'ActiveRecord::Base.connection.execute(\"SELECT 1\")' 2>/dev/null; then \
			echo '📝 テストデータベース作成中...'; \
			bundle exec rails db:create:all || echo '⚠️  データベース作成スキップ（既存の可能性）'; \
		else \
			echo '✅ データベース接続確認済み'; \
		fi"
	
	# Step 2: スキーマ高速ロード（マイグレーションより高速）
	@echo "⚡ スキーマ高速ロード..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) web sh -c " \
		if [ -f db/structure.sql ] || [ -f db/schema.rb ]; then \
			timeout 60 bundle exec rails db:test:load_schema || ( \
				echo '⚠️  スキーマロード失敗、マイグレーション実行...'; \
				timeout 90 bundle exec rails db:migrate \
			); \
		else \
			echo '📝 初回マイグレーション実行...'; \
			timeout 90 bundle exec rails db:migrate; \
		fi"
	
	# Step 3: データベース整合性検証
	@echo "🔧 データベース整合性検証..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) web bundle exec rails runner " \
		puts '✅ テーブル数: ' + ActiveRecord::Base.connection.tables.count.to_s; \
		puts '✅ データベース準備完了'"

# 従来のCIコマンド（後方互換性）
ci: bundle-install-conditional security-scan lint test-all

# GitHub Actions互換のセキュリティスキャン（並列実行対応）
security-scan-github:
	@echo "=== 🔒 セキュリティスキャン ==="
	@$(WEB_RUN) bin/brakeman --no-pager --quiet

# GitHub Actions互換のLint（並列実行対応）
lint-github:
	@echo "=== 📝 コード品質チェック ==="
	@$(WEB_RUN) bin/rubocop -f github --fail-level error

# 最適化されたテスト実行（CLAUDE.md準拠：段階的実行）
test-github-optimized:
	@echo "=== 🧪 最適化テスト実行 ==="
	@echo "📊 実行戦略: 高速テスト優先、段階的フィードバック"
	
	# Phase 1: 高速ユニットテスト（約30秒）
	@echo "Phase 1: 高速ユニットテスト実行中..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) \
		web bundle exec rspec spec/models spec/helpers spec/decorators spec/validators spec/forms \
		--format progress --fail-fast
	
	# Phase 2: サービス・リクエストテスト（約60秒）
	@echo "Phase 2: サービス・リクエストテスト実行中..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) \
		web bundle exec rspec spec/requests spec/services spec/lib \
		--format progress --fail-fast
	
	# Phase 3: 統合・フィーチャーテスト（約90秒）
	@echo "Phase 3: 統合テスト実行中..."
	@$(COMPOSE) run --rm $(CI_ENV_VARS) \
		-e CAPYBARA_SERVER_HOST=0.0.0.0 \
		-e CAPYBARA_SERVER_PORT=3001 \
		-e CHROME_HEADLESS=1 \
		-e SELENIUM_CHROME_OPTIONS="--headless --no-sandbox --disable-dev-shm-usage --disable-gpu --remote-debugging-port=9222" \
		-e DISABLE_SELENIUM_TESTS=true \
		web bundle exec rspec spec/features spec/jobs \
		--format progress --fail-fast \
		--tag '~selenium_required'

# TODO: 包括的CI最適化（CLAUDE.md準拠）
# 
# 🔴 高優先度（推定実装時間: 2-3日）
# ■ インクリメンタルテスト実装
#   - Git差分ベースのテスト選択
#   - 変更ファイルと関連テストの自動検出
#   - 最小実行セットでのCI時間削減（目標: 5分以内）
#
# ■ 並列テスト実行基盤
#   - RSpec並列実行（parallel_tests gem活用）
#   - データベース分割による並列度向上
#   - CI環境でのマルチコア活用（目標: 3-4倍高速化）
#
# ■ テストデータ最適化
#   - FactoryBot最適化とメモリ効率改善
#   - 共有テストデータベースの活用
#   - トランザクション分離による高速リセット
#
# 🟡 中優先度（推定実装時間: 1週間）
# ■ CI結果キャッシュシステム
#   - テスト結果のキャッシュとリプレイ
#   - 依存関係変更時のみフル実行
#   - 段階的テストスイート（smoke → full）
#
# ■ 動的テスト選択
#   - コード変更影響範囲の自動解析
#   - 関連テストの優先実行
#   - リスクベーステスト選択アルゴリズム
#
# ■ CI/CDパイプライン監視
#   - 実行時間監視とアラート
#   - ボトルネック自動検出
#   - パフォーマンス回帰の早期発見
#
# 🟢 低優先度（推定実装時間: 2-3週間）
# ■ 機械学習ベーステスト最適化
#   - 過去の実行データからの学習
#   - 失敗予測モデル
#   - 自動テスト戦略調整
#
# ■ クロスプラットフォームCI
#   - 複数OS環境での並列実行
#   - ブラウザ互換性テスト自動化
#   - デバイス固有テストの実装
#
# 📈 成功指標・KPI
# - CI実行時間: 現在15-20分 → 目標5分以内
# - テスト成功率: 目標95%以上維持
# - 並列度: 目標3-4倍の高速化
# - 開発者フィードバック時間: 目標2分以内
# - CI安定性: 偽陽性率1%以下

security-scan:
	$(WEB_RUN) bin/brakeman --no-pager

lint:
	$(WEB_RUN) bin/rubocop

lint-fix:
	$(WEB_RUN) bin/rubocop -a

lint-fix-unsafe:
	$(WEB_RUN) bin/rubocop -A

test-all:
	$(COMPOSE) run --rm -e RAILS_ENV=test -e DISABLE_HOST_AUTHORIZATION=true web bin/rails db:test:prepare test test:system

# --------------------------- パフォーマンステスト --------------------------
perf-generate-csv:
	@echo "=== テスト用の1万行CSVファイルを生成 ==="
	$(WEB_RUN) bin/rails performance:generate_test_csv

perf-test-import:
	@echo "=== CSVインポートのパフォーマンステスト実行 ==="
	$(WEB_RUN) bin/rails performance:test_import

perf-benchmark-batch:
	@echo "=== 異なるバッチサイズでCSVインポートをベンチマーク ==="
	$(WEB_RUN) bin/rails performance:benchmark_batch_sizes

# --------------------------- エラーハンドリングテスト ----------------------
test-error-handling:
	@echo "=== エラーハンドリング動作確認用サーバー起動 ==="
	@echo "環境変数 ERROR_HANDLING_TEST=1 でproduction環境同様のエラーページを表示"
	ERROR_HANDLING_TEST=1 $(WEB_UP)
	@sleep 3
	@echo "以下でテスト可能:"
	@echo "  http://localhost:$(HTTP_PORT)/404 - 404エラーページ"
	@echo "  http://localhost:$(HTTP_PORT)/500 - 500エラーページ"
	@echo "  http://localhost:$(HTTP_PORT)?debug=0 - デバッグモード切替"

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
	@echo "利用可能なコマンド:"
	@echo ""
	@echo "Docker操作:"
	@echo "  make build         - Dockerイメージをビルド"
	@echo "  make up            - コンテナを起動"
	@echo "  make down          - コンテナを停止"
	@echo "  make restart       - コンテナを再起動"
	@echo "  make logs          - ログを表示"
	@echo "  make ps            - コンテナの状態を表示"
	@echo "  make clean         - コンテナとボリュームを削除"
	@echo ""
	@echo "データベース操作:"
	@echo "  make db-create     - データベースを作成"
	@echo "  make db-migrate    - マイグレーションを実行"
	@echo "  make db-reset      - データベースをリセット"
	@echo "  make bundle-install - 依存関係をインストール"
	@echo ""
	@echo "テスト実行:"
	@echo "  make test          - テストを実行"
	@echo "  make test-fast     - 高速テスト実行"
	@echo "  make test-models   - モデルテストのみ"
	@echo "  make test-coverage - カバレッジ計測付きテスト"
	@echo ""
	@echo "CI/品質管理:"
	@echo "  make ci-github     - 🎯 GitHub Actions完全互換のCIテスト"
	@echo "  make ci            - 従来のCIチェック実行"
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

# --------------------------- 診断 & 修復 ----------------------------------
diagnose:
	@echo "=== StockRx システム診断 ===" && echo
	@echo "Docker version:"
	@docker --version
	@echo "Docker Compose version:"
	@docker compose version
	@echo ""
	@echo "=== 実行中のコンテナ ==="
	@$(COMPOSE) ps
	@echo ""
	@echo "=== コンテナ詳細情報 ==="
	@docker ps -a --filter "name=stockrx"
	@echo ""
	@echo "=== ヘルスチェック ==="
	@docker inspect stockrx-db-1 --format='{{json .State.Health}}' 2>/dev/null | jq '.' || echo "DBコンテナが見つかりません"
	@echo ""
	@echo "=== ボリューム情報 ==="
	@docker volume ls --filter "name=stockrx"
	@echo ""
	@echo "=== ネットワーク情報 ==="
	@docker network ls --filter "name=stockrx"
	@echo ""
	@echo "=== ポート使用状況 ==="
	@lsof -i :$(HTTP_PORT) || echo "ポート$(HTTP_PORT)は使用されていません"
	@echo ""
	@echo "=== HTTP接続テスト ==="
	@if $(CURL) -I http://localhost:$(HTTP_PORT); then echo "✅ HTTP接続正常"; else echo "❌ HTTP接続失敗"; fi
	@echo ""
	@echo "--- Web Logs (最新10行) ---"
	@$(COMPOSE) logs --tail=10 web || true
	@echo "--- DB Logs (最新10行) ---"
	@$(COMPOSE) logs --tail=10 db || true

fix-connection:
	@echo "=== 接続問題の自動修復を試行中... ==="
	$(COMPOSE) restart web
	@sleep 5
	$(call check_health)

fix-ssl-error:
	@echo "=== SSL接続エラー対処 ===" && \
	  echo "開発環境は HTTP で動作します。 https://localhost:$(HTTP_PORT) は使わず http://localhost:$(HTTP_PORT) をご利用下さい。"
	@echo ""
	@echo "StockRxは開発環境でHTTPで動作します。"
	@echo ""
	@echo "正しいアクセス方法:"
	@echo "  ✅ http://localhost:3000"
	@echo "  ❌ https://localhost:3000"
	@echo ""
	@echo "ブラウザキャッシュクリア方法:"
	@echo "  Chrome: Ctrl+Shift+R (Windows) / Cmd+Shift+R (Mac)"
	@echo "  Firefox: Ctrl+F5 (Windows) / Cmd+Shift+R (Mac)"