#!/bin/bash

# StockRx MySQL最適化設定スクリプト
# Team 6: データベース最適化
# ===================================
# 用途: MySQL設定ファイルの最適化
# 対象: 開発環境・本番環境
# ===================================

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# メモリサイズの取得
get_total_memory() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        echo $(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    else
        # Linux
        echo $(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    fi
}

# MySQL設定の生成
generate_mysql_config() {
    local total_memory=$1
    local buffer_pool_size=$((total_memory * 70 / 100))
    
    if [ $buffer_pool_size -lt 1 ]; then
        buffer_pool_size=1
    fi
    
    cat <<EOF
# StockRx MySQL最適化設定
# 生成日: $(date)
# システムメモリ: ${total_memory}GB
# ===================================

[mysqld]
# 基本設定
port = 3306
bind-address = 0.0.0.0
default-storage-engine = InnoDB
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# InnoDBバッファプール（メモリの70%）
innodb_buffer_pool_size = ${buffer_pool_size}G
innodb_buffer_pool_instances = 8

# ログファイル設定
innodb_log_file_size = 256M
innodb_log_buffer_size = 64M
innodb_flush_log_at_trx_commit = 2

# ファイルI/O最適化
innodb_io_capacity = 2000
innodb_io_capacity_max = 4000
innodb_read_io_threads = 4
innodb_write_io_threads = 4

# その他のバッファ
key_buffer_size = 32M
sort_buffer_size = 2M
read_buffer_size = 2M
read_rnd_buffer_size = 8M
join_buffer_size = 2M

# クエリキャッシュ（MySQL 5.7以前）
# query_cache_type = 1
# query_cache_size = 64M
# query_cache_limit = 2M

# 接続設定
max_connections = 200
max_connect_errors = 1000000
thread_cache_size = 50
table_open_cache = 4000
open_files_limit = 65535

# テンポラリテーブル
tmp_table_size = 64M
max_heap_table_size = 64M

# スロークエリログ
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow-query.log
long_query_time = 1
log_queries_not_using_indexes = 1

# バイナリログ（レプリケーション用）
log_bin = mysql-bin
binlog_format = ROW
expire_logs_days = 7
max_binlog_size = 100M

# パフォーマンススキーマ
performance_schema = ON

# その他の最適化
innodb_autoinc_lock_mode = 2
innodb_stats_on_metadata = 0
innodb_file_per_table = 1

[client]
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4
EOF
}

# Docker Compose用のカスタムMySQLi設定生成
generate_docker_mysql_config() {
    cat <<EOF
# Docker用MySQL設定（軽量版）
[mysqld]
# 基本設定
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# メモリ設定（Docker用に控えめ）
innodb_buffer_pool_size = 512M
innodb_log_file_size = 128M
key_buffer_size = 16M

# パフォーマンス設定
innodb_flush_log_at_trx_commit = 2
innodb_file_per_table = 1

# スロークエリ
slow_query_log = 1
long_query_time = 1

# 接続数
max_connections = 100

[client]
default-character-set = utf8mb4
EOF
}

# メイン処理
main() {
    log_info "StockRx MySQL最適化設定の生成を開始します"
    
    # システムメモリの取得
    total_memory=$(get_total_memory)
    log_info "システムメモリ: ${total_memory}GB"
    
    # 出力ディレクトリの作成
    mkdir -p config/mysql
    
    # 本番用設定の生成
    log_info "本番環境用MySQL設定を生成中..."
    generate_mysql_config $total_memory > config/mysql/production.cnf
    log_info "config/mysql/production.cnf を生成しました"
    
    # Docker用設定の生成
    log_info "Docker環境用MySQL設定を生成中..."
    generate_docker_mysql_config > config/mysql/docker.cnf
    log_info "config/mysql/docker.cnf を生成しました"
    
    # docker-compose.ymlの更新案を表示
    log_info "docker-compose.ymlに以下を追加してください:"
    cat <<EOF

  db:
    image: mysql:8.0
    volumes:
      - ./config/mysql/docker.cnf:/etc/mysql/conf.d/custom.cnf:ro
      - db_data:/var/lib/mysql
    environment:
      MYSQL_ROOT_PASSWORD: password
      # 他の環境変数...
EOF
    
    log_info "設定ファイルの生成が完了しました"
    log_warn "本番環境に適用する前に、必ず設定内容を確認してください"
}

# スクリプト実行
main "$@"