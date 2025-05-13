#!/bin/bash

# バックアップディレクトリの作成
BACKUP_DIR="/backup"
mkdir -p $BACKUP_DIR

# 日付を取得（YYYY-MM-DD形式）
DATE=$(date +%Y-%m-%d)

# バックアップファイル名
BACKUP_FILE="$BACKUP_DIR/app_db_$DATE.sql.gz"

# mysqldumpを実行し、gzipで圧縮
mysqldump -h db -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" | gzip > "$BACKUP_FILE"

# 古いバックアップの削除（30日以上前のファイル）
find $BACKUP_DIR -name "app_db_*.sql.gz" -mtime +30 -delete

# バックアップ完了ログ
echo "Backup completed: $BACKUP_FILE" 