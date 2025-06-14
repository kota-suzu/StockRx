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
# GitHub Actions完全互換のCIコマンド
ci-github: bundle-install security-scan-github lint-github test-github

# 従来のCIコマンド（後方互換性）
ci: bundle-install security-scan lint test-all

# TODO: 🔴 Phase 1 - セキュリティスキャン機能強化（推定1日）
# 優先度: 最高（セキュリティ基盤）
# 実装内容:
#   - Dependency-Check (OWASP) 統合
#   - SAST (Static Application Security Testing) 自動実行
#   - 脆弱性レポート生成とSlack通知
#   - セキュリティベースライン検証
# 横展開確認:
#   - CI/CDパイプラインへの統合
#   - プリコミットフックでの軽量チェック
#   - セキュリティダッシュボードへのデータ送信

# GitHub Actions互換のセキュリティスキャン
security-scan-github:
	@echo "=== GitHub Actions互換 - セキュリティスキャン ==="
	$(WEB_RUN) bin/brakeman --no-pager
	@echo "=== bundler-audit脆弱性チェック ==="
	$(WEB_RUN) bundle exec bundle-audit check --update
	# TODO: 🟠 Phase 2 - 追加セキュリティツール統合（推定2日）
	# 実装予定:
	#   - bundle exec bundle-audit check --ignore CVE-XXXX-YYYY
	#   - bundle exec semgrep --config=p/security-audit --json
	#   - bundle exec rails_best_practices --format json
	#   - bundle exec rubocop --only Security --format json

# GitHub Actions互換のLint
lint-github:
	@echo "=== GitHub Actions互換 - Lint ==="
	$(WEB_RUN) bin/rubocop -f github

# TODO: 🟢 Phase 3 - 統合セキュリティレポート（推定3日）
# 優先度: 中（運用効率化）
# 実装内容:
#   - security-report: 全スキャン結果の統合HTML/JSONレポート生成
#   - security-dashboard: リアルタイムセキュリティステータス表示
#   - security-baseline: セキュリティベースライン設定・比較
#   - security-remediation: 修正提案とチェックリスト生成
# 横展開確認:
#   - 経営陣向けセキュリティサマリー
#   - 監査対応用エビデンス自動収集
#   - SOC2/ISO27001対応レポート生成

# GitHub Actions完全互換のテスト実行（修正版 - Pendingテスト対応）
test-github:
	@echo "=== GitHub Actions互換 - テスト環境準備 ==="
	# キャッシュクリア（GitHub Actionsと同じ）
	rm -rf tmp/cache tmp/bootsnap* tmp/caching-dev.txt || true
	mkdir -p tmp/cache/assets tmp/storage tmp/pids tmp/screenshots
	chmod -R 777 tmp/cache tmp/storage tmp/pids tmp/screenshots || true
	touch tmp/restart.txt
	
	@echo "=== GitHub Actions互換 - サービス確認（既存コンテナ活用）==="
	# 既存のサービスが動作していれば再利用、停止していれば起動
	$(COMPOSE) up -d db redis
	@echo "サービス起動待機中..."
	@for i in {1..30}; do \
		if docker compose exec -T db mysqladmin ping -h localhost -u root -ppassword > /dev/null 2>&1; then \
			echo "✅ MySQL稼働確認完了"; \
			break; \
		fi; \
		echo "MySQL確認中... ($$i/30)"; \
		sleep 2; \
	done
	
	@echo "=== GitHub Actions互換 - Zeitwerkチェック ==="
	$(COMPOSE) run --rm \
	  -e RAILS_ENV=test \
	  -e CI=true \
	  web bundle exec rails zeitwerk:check || true
	
	@echo "=== GitHub Actions互換 - データベース準備 ==="
	$(COMPOSE) run --rm \
	  -e RAILS_ENV=test \
	  -e DATABASE_PASSWORD="password" \
	  -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
	  -e DISABLE_HOST_AUTHORIZATION=true \
	  -e CI=true \
	  -e TEST_DATABASE_READ_TIMEOUT=60 \
	  -e TEST_DATABASE_CONNECT_TIMEOUT=30 \
	  -e TEST_DATABASE_WRITE_TIMEOUT=30 \
	  web bin/rails db:test:prepare
	
	@echo "=== GitHub Actions互換 - RSpecテスト実行 ==="
	$(COMPOSE) run --rm \
	  -e RAILS_ENV=test \
	  -e DATABASE_PASSWORD="password" \
	  -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 \
	  -e DISABLE_HOST_AUTHORIZATION=true \
	  -e RAILS_ZEITWERK_MISMATCHES=error \
	  -e CI=true \
	  -e TEST_DATABASE_READ_TIMEOUT=60 \
	  -e TEST_DATABASE_CONNECT_TIMEOUT=30 \
	  -e TEST_DATABASE_WRITE_TIMEOUT=30 \
	  -e CAPYBARA_SERVER_HOST=0.0.0.0 \
	  -e CAPYBARA_SERVER_PORT=3001 \
	  -e CHROME_HEADLESS=1 \
	  -e SELENIUM_CHROME_OPTIONS="--headless --no-sandbox --disable-dev-shm-usage --disable-gpu --window-size=1024,768" \
	  web bundle exec rspec --format progress; \
	  RSPEC_EXIT_CODE=$$?; \
	  echo ""; \
	  echo "=== CI成功判定：Failureがなければ成功 ==="; \
	  if [ $$RSPEC_EXIT_CODE -eq 0 ]; then \
	    echo "✅ テスト完了: すべてのテストが成功しました"; \
	    echo ""; \
	    echo "🎯 メタ認知的確認："; \
	    echo "   - 実装済み機能: すべてのテストが成功"; \
	    echo "   - Pending機能: 将来実装予定（CLAUDE.mdのTODOリスト参照）"; \
	    echo "   - 横展開状況: 同様のCI成功基準を他のプロジェクトでも適用可能"; \
	    exit 0; \
	  else \
	    echo "❌ テスト失敗: RSpecが failures を検出しました"; \
	    echo "   Exit Code: $$RSPEC_EXIT_CODE"; \
	    echo "   修正後に再実行してください"; \
	    exit $$RSPEC_EXIT_CODE; \
	  fi

# 従来のセキュリティスキャン
security-scan:
	$(WEB_RUN) bin/brakeman --no-pager
	@echo "=== bundler-audit脆弱性チェック ==="
	$(WEB_RUN) bundle exec bundle-audit check --update
	# TODO: 🔵 Phase 4 - セキュリティ自動修復（推定1週間）
	# 優先度: 低（自動化・効率化）
	# 実装内容:
	#   - 自動パッチ適用 (bundle update --patch)
	#   - セキュリティ設定の自動最適化
	#   - False Positiveの学習・フィルタリング
	#   - 影響度評価と優先度付け自動化
	# 横展開確認:
	#   - 本番環境への段階的ロールアウト
	#   - 緊急パッチ適用プロセスの自動化
	#   - セキュリティインシデント対応の自動化

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

# --------------------------- セキュリティ補助機能 --------------------------
# TODO: 🔴 Phase 1 - セキュリティ状況確認機能（推定半日）
# 優先度: 高（日常運用での安全性確認）
security-check:
	@echo "=== StockRx セキュリティ状況確認 ==="
	@echo "🔍 1. 暗号化状況チェック"
	$(WEB_RUN) ruby encryption_status_check.rb
	@echo ""
	@echo "🔍 2. ジョブログセキュリティ検証"
	$(WEB_RUN) ruby verify_job_logs.rb
	@echo ""
	@echo "🔍 3. 基本セキュリティスキャン"
	$(MAKE) security-scan

# TODO: 🟠 Phase 2 - 詳細セキュリティ監査（推定1日）
# 優先度: 中（定期監査・コンプライアンス対応）
security-audit:
	@echo "=== StockRx 詳細セキュリティ監査 ==="
	@echo "🔐 1. 包括的暗号化監査"
	$(WEB_RUN) ruby encryption_status_check.rb
	@echo ""
	@echo "🔍 2. 脆弱性スキャン"
	$(MAKE) security-scan
	@echo ""
	@echo "📊 3. セキュリティメトリクス収集"
	$(WEB_RUN) ruby simple_encryption_check.rb
	@echo ""
	@echo "🎯 4. セキュリティテスト実行"
	$(WEB_RUN) ruby test_security_job_execution.rb

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
	@echo "  make security-check - セキュリティ状況の包括的確認"
	@echo "  make security-audit - 詳細セキュリティ監査の実行"
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
	@if $(CURL) -I http://localhost:$(HTTP_PORT); then \
		echo "✅ HTTP接続正常"; \
	else \
		echo "❌ HTTP接続失敗"; \
		echo "🔧 自動修復を試行中..."; \
		$(MAKE) auto-fix-connection; \
	fi
	@echo ""
	@echo "--- Web Logs (最新10行) ---"
	@$(COMPOSE) logs --tail=10 web || true
	@echo "--- DB Logs (最新10行) ---"
	@$(COMPOSE) logs --tail=10 db || true

# TODO: 自動修復機能の強化 - 段階的なトラブルシューティング
# 1. Webサーバーコンテナの存在確認 → 未起動なら起動
# 2. サービス依存関係のチェック（DB、Redis）
# 3. ネットワーク接続の確認
# 4. エラーパターンに応じた専用修復手順の実行
# 横展開: 他のサービス（DB、Redis）の自動修復も同様のパターンで実装
auto-fix-connection:
	@echo "=== 自動修復プロセス開始 ==="
	@echo "1. Webサーバーコンテナの確認..."
	@if ! docker ps --filter "name=stockrx-web" --format "table {{.Names}}" | grep -q stockrx-web; then \
		echo "   Webサーバーが停止しています。起動中..."; \
		$(COMPOSE) up -d web; \
		sleep 5; \
	else \
		echo "   Webサーバーコンテナは存在します。再起動中..."; \
		$(COMPOSE) restart web; \
		sleep 5; \
	fi
	@echo "2. 依存サービスの確認..."
	@$(COMPOSE) up -d db redis
	@echo "3. ヘルスチェック再実行..."
	@sleep 3
	@if $(CURL) -I http://localhost:$(HTTP_PORT); then \
		echo "✅ 修復成功 - サーバーが正常に応答しています"; \
	else \
		echo "❌ 修復失敗 - 手動での確認が必要です"; \
		echo "次のコマンドで詳細確認: docker compose logs web"; \
	fi

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