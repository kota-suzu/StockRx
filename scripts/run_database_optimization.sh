#!/bin/bash

# Team 6: データベース最適化実行スクリプト
# ==========================================
# 用途: 段階的なデータベース最適化の実行
# 実行: ./scripts/run_database_optimization.sh [phase]
# ==========================================

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_phase() {
    echo -e "${BLUE}[PHASE]${NC} $1"
}

# 環境確認
check_environment() {
    log_info "環境の確認中..."
    
    # Dockerが動いているか確認
    if ! docker-compose ps | grep -q "Up"; then
        log_error "Docker containers are not running. Please run 'make up' first."
        exit 1
    fi
    
    # データベース接続確認
    if ! docker-compose exec -T db mysql -u root -p'password' app_db -e "SELECT 1" >/dev/null 2>&1; then
        log_error "Cannot connect to database"
        exit 1
    fi
    
    log_info "環境確認完了"
}

# データベースバックアップ
backup_database() {
    log_info "データベースバックアップを作成中..."
    
    backup_file="backup/db_backup_$(date +%Y%m%d_%H%M%S).sql"
    mkdir -p backup
    
    docker-compose exec -T db mysqldump -u root -p'password' app_db > "$backup_file"
    
    if [ $? -eq 0 ]; then
        log_info "バックアップ作成完了: $backup_file"
    else
        log_error "バックアップ作成に失敗"
        exit 1
    fi
}

# Phase 1: インデックス最適化
phase1_index_optimization() {
    log_phase "Phase 1: インデックス最適化"
    
    log_info "重複インデックス削除とカバリングインデックス追加中..."
    
    # マイグレーション実行
    docker-compose exec web rails db:migrate:up VERSION=20250626
    
    if [ $? -eq 0 ]; then
        log_info "Phase 1 完了"
    else
        log_error "Phase 1 失敗"
        exit 1
    fi
}

# Phase 2: MySQL設定最適化
phase2_mysql_config() {
    log_phase "Phase 2: MySQL設定最適化"
    
    log_info "最適化されたMySQL設定を適用中..."
    
    # 設定ファイルのコピー
    if [ -f "config/mysql/docker.cnf" ]; then
        # docker-compose.ymlを更新して再起動が必要
        log_warn "MySQL設定を適用するにはdocker-compose.ymlを更新してコンテナを再起動してください"
        log_info "必要な変更:"
        cat <<EOF
volumes:
  - ./config/mysql/docker.cnf:/etc/mysql/conf.d/custom.cnf:ro
EOF
    else
        log_error "MySQL設定ファイルが見つかりません"
        exit 1
    fi
}

# Phase 3: アーカイブテーブル作成
phase3_archive_tables() {
    log_phase "Phase 3: アーカイブテーブル作成"
    
    log_info "アーカイブテーブル作成中..."
    
    # アーカイブテーブル作成マイグレーション実行
    docker-compose exec web rails db:migrate:up VERSION=20250626_create_archive_tables
    
    if [ $? -eq 0 ]; then
        log_info "Phase 3 完了"
    else
        log_error "Phase 3 失敗"
        exit 1
    fi
}

# Phase 4: パフォーマンステスト
phase4_performance_test() {
    log_phase "Phase 4: パフォーマンステスト"
    
    log_info "パフォーマンステスト実行中..."
    
    # テストデータの生成（もし存在しない場合）
    docker-compose exec web rails db:seed
    
    # パフォーマンス監視スクリプトの実行（バックグラウンド）
    log_info "パフォーマンス監視を開始します（60秒間）..."
    docker-compose exec web ruby scripts/monitor_database_performance.rb 60 &
    
    # ベンチマーククエリの実行
    run_benchmark_queries
    
    log_info "Phase 4 完了"
}

# ベンチマーククエリの実行
run_benchmark_queries() {
    log_info "ベンチマーククエリ実行中..."
    
    # 主要なクエリパターンをテスト
    queries=(
        "SELECT COUNT(*) FROM inventories WHERE status = 0"
        "SELECT si.*, i.name, i.price FROM store_inventories si JOIN inventories i ON si.inventory_id = i.id WHERE si.quantity <= si.safety_stock_level"
        "SELECT * FROM audit_logs WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY) ORDER BY created_at DESC LIMIT 100"
        "SELECT s.name, COUNT(si.id) as inventory_count FROM stores s LEFT JOIN store_inventories si ON s.id = si.store_id GROUP BY s.id"
    )
    
    for query in "${queries[@]}"; do
        echo "Testing: $query"
        docker-compose exec -T db mysql -u root -p'password' app_db -e "EXPLAIN $query"
    done
}

# 結果レポート生成
generate_report() {
    log_info "最適化結果レポートを生成中..."
    
    report_file="reports/optimization_report_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p reports
    
    {
        echo "StockRx データベース最適化レポート"
        echo "====================================="
        echo "実行日時: $(date)"
        echo "実行フェーズ: $1"
        echo ""
        
        echo "テーブルサイズ:"
        docker-compose exec -T db mysql -u root -p'password' app_db -e "
        SELECT 
          TABLE_NAME,
          ROUND(((DATA_LENGTH + INDEX_LENGTH) / 1024 / 1024), 2) AS 'Size(MB)',
          TABLE_ROWS AS 'Rows'
        FROM information_schema.TABLES 
        WHERE TABLE_SCHEMA = 'app_db'
        ORDER BY DATA_LENGTH + INDEX_LENGTH DESC;"
        
        echo ""
        echo "インデックス使用状況:"
        docker-compose exec -T db mysql -u root -p'password' app_db -e "
        SELECT 
          TABLE_NAME,
          INDEX_NAME,
          CARDINALITY
        FROM information_schema.STATISTICS 
        WHERE TABLE_SCHEMA = 'app_db' AND INDEX_NAME != 'PRIMARY'
        ORDER BY TABLE_NAME, CARDINALITY DESC;"
        
    } > "$report_file"
    
    log_info "レポート生成完了: $report_file"
}

# メイン処理
main() {
    local phase=${1:-"all"}
    
    echo "========================================"
    echo "StockRx データベース最適化スクリプト"
    echo "========================================"
    echo "実行フェーズ: $phase"
    echo "開始時刻: $(date)"
    echo "========================================"
    
    check_environment
    backup_database
    
    case $phase in
        "1"|"phase1"|"index")
            phase1_index_optimization
            ;;
        "2"|"phase2"|"config")
            phase2_mysql_config
            ;;
        "3"|"phase3"|"archive")
            phase3_archive_tables
            ;;
        "4"|"phase4"|"test")
            phase4_performance_test
            ;;
        "all")
            phase1_index_optimization
            phase2_mysql_config
            phase3_archive_tables
            phase4_performance_test
            ;;
        *)
            echo "Usage: $0 [1|2|3|4|all]"
            echo "  1: インデックス最適化"
            echo "  2: MySQL設定最適化"
            echo "  3: アーカイブテーブル作成"
            echo "  4: パフォーマンステスト"
            echo "  all: 全フェーズ実行"
            exit 1
            ;;
    esac
    
    generate_report "$phase"
    
    echo "========================================"
    echo "最適化完了: $(date)"
    echo "========================================"
    
    log_info "次のステップ:"
    log_info "1. reports/ ディレクトリの最適化レポートを確認"
    log_info "2. 本番環境への適用前にステージング環境でテスト"
    log_info "3. パフォーマンス監視を継続"
}

# スクリプト実行
main "$@"