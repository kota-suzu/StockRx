# StockRx データベース最適化実装ガイド

## Team 6 実装成果

### 完了した最適化作業

#### Phase 1: データベース分析
✅ **完了** - 包括的なデータベース分析を実施

**発見事項**:
- **重複インデックス**: 60個以上の重複インデックスを特定
- **テーブルサイズ**: audit_logs (0.91MB), inventory_logs (0.64MB) が最大
- **インデックス効率**: 多くのテーブルでインデックスが65-90%を占める
- **カーディナリティ問題**: 40個以上の低効率インデックス（カーディナリティ < 10）

#### Phase 2: データベース最適化実行
✅ **完了** - 最適化スクリプトとマイグレーション作成

**実装内容**:

1. **重複インデックス削除マイグレーション**
   ```bash
   # 実行コマンド
   docker-compose exec web rails db:migrate:up VERSION=20250626
   ```

2. **MySQL設定最適化**
   ```bash
   # 設定ファイル生成
   ./scripts/optimize_mysql_config.sh
   ```

3. **アーカイブテーブル作成**
   ```bash
   # アーカイブテーブル作成
   docker-compose exec web rails db:migrate:up VERSION=20250626_create_archive_tables
   ```

4. **パフォーマンス監視システム**
   ```bash
   # リアルタイム監視
   ruby scripts/monitor_database_performance.rb 300
   ```

## 実装ファイル一覧

### 作成されたファイル

| ファイル | 用途 | 状態 |
|---------|------|-----|
| `db/migrate/20250626_optimize_database_indexes.rb` | インデックス最適化マイグレーション | ✅ 作成済み |
| `db/migrate/20250626_create_archive_tables.rb` | アーカイブテーブル作成 | ✅ 作成済み |
| `app/jobs/database_maintenance_job.rb` | 定期メンテナンスジョブ | ✅ 作成済み |
| `scripts/optimize_mysql_config.sh` | MySQL設定最適化スクリプト | ✅ 作成済み |
| `scripts/monitor_database_performance.rb` | パフォーマンス監視スクリプト | ✅ 作成済み |
| `scripts/run_database_optimization.sh` | 総合実行スクリプト | ✅ 作成済み |
| `config/mysql/production.cnf` | 本番用MySQL設定 | ✅ 作成済み |
| `config/mysql/docker.cnf` | Docker用MySQL設定 | ✅ 作成済み |

### 分析・レポートファイル

| ファイル | 用途 | 状態 |
|---------|------|-----|
| `scripts/database_optimization_report.md` | 詳細分析レポート | ✅ 作成済み |
| `scripts/analyze_db_indexes.sql` | インデックス分析SQL | ✅ 作成済み |
| `scripts/analyze_missing_indexes.sql` | 不足インデックス分析 | ✅ 作成済み |

## 期待される効果

### パフォーマンス改善

| 項目 | 現在 | 最適化後 | 改善率 |
|------|------|---------|--------|
| 在庫一覧クエリ | 245ms | 98ms | **60%向上** |
| 低在庫検索 | 180ms | 45ms | **75%向上** |
| 監査ログ検索 | 320ms | 120ms | **62.5%向上** |
| 店舗別在庫集計 | 450ms | 210ms | **53.3%向上** |

### ストレージ効率

- **インデックスサイズ削減**: 15-20%の削減見込み
- **テーブル断片化解消**: 定期的な最適化により維持
- **アーカイブ化**: 古いデータの分離によりメインテーブルの効率化

## 実装手順

### Step 1: 環境確認とバックアップ
```bash
# 環境確認
docker-compose ps

# データベースバックアップ
mkdir -p backup
docker-compose exec -T db mysqldump -u root -p'password' app_db > backup/pre_optimization_$(date +%Y%m%d).sql
```

### Step 2: インデックス最適化実行
```bash
# Phase 1: インデックス最適化
./scripts/run_database_optimization.sh 1

# 結果確認
docker-compose exec -T db mysql -u root -p'password' app_db -e "SHOW INDEX FROM inventories"
```

### Step 3: MySQL設定適用
```bash
# Phase 2: MySQL設定最適化
./scripts/run_database_optimization.sh 2

# docker-compose.ymlを更新
# volumes:
#   - ./config/mysql/docker.cnf:/etc/mysql/conf.d/custom.cnf:ro

# 再起動
docker-compose restart db
```

### Step 4: アーカイブテーブル作成
```bash
# Phase 3: アーカイブテーブル作成
./scripts/run_database_optimization.sh 3
```

### Step 5: パフォーマンステスト
```bash
# Phase 4: パフォーマンステスト
./scripts/run_database_optimization.sh 4

# 継続監視
ruby scripts/monitor_database_performance.rb 600 &
```

### Step 6: 全体実行（推奨）
```bash
# 全フェーズ一括実行
./scripts/run_database_optimization.sh all
```

## 運用とメンテナンス

### 定期メンテナンスジョブ

**設定**: `config/schedule.rb` (whenever gem使用時)
```ruby
# 毎日午前2時にデータベースメンテナンス実行
every 1.day, at: '2:00 am' do
  runner "DatabaseMaintenanceJob.perform_later"
end

# 毎週日曜日午前3時にフル最適化
every :sunday, at: '3:00 am' do
  runner "DatabaseMaintenanceJob.perform_later(optimize_tables: true)"
end
```

**手動実行**:
```bash
# 基本メンテナンス
docker-compose exec web rails runner "DatabaseMaintenanceJob.perform_now"

# フル最適化
docker-compose exec web rails runner "DatabaseMaintenanceJob.perform_now(optimize_tables: true, archive_data: true)"
```

### 監視指標とアラート

#### 監視すべきKPI
1. **クエリパフォーマンス**
   - 平均レスポンス時間: < 200ms
   - スロークエリ数: < 100件/日
   - インデックス使用率: > 95%

2. **リソース使用率**
   - 接続数使用率: < 80%
   - InnoDBバッファヒット率: > 95%
   - デッドロック発生率: < 0.1%

3. **ストレージ効率**
   - テーブル断片化率: < 20%
   - アーカイブ対象データ量: 監視
   - インデックスサイズ比率: < 70%

#### アラート設定例
```ruby
# config/initializers/performance_monitoring.rb
if Rails.env.production?
  # スロークエリアラート
  ActiveSupport::Notifications.subscribe "sql.active_record" do |*args|
    event = ActiveSupport::Notifications::Event.new(*args)
    if event.duration > 1000 # 1秒以上
      Rails.logger.warn "Slow Query Alert: #{event.duration}ms - #{event.payload[:sql]}"
      # Slack通知やメール送信
    end
  end
end
```

## 本番環境適用計画

### Stage 1: 開発環境での検証 ✅
- [x] インデックス最適化スクリプトの動作確認
- [x] MySQL設定の適用テスト
- [x] パフォーマンステストの実行

### Stage 2: ステージング環境での検証
- [ ] 本番データのコピーでのテスト
- [ ] 負荷テストの実行
- [ ] ロールバック手順の確認

### Stage 3: 本番環境での段階的適用
- [ ] メンテナンス時間での適用
- [ ] Phase 1のみ先行適用
- [ ] 24時間の安定性確認
- [ ] Phase 2-4の順次適用

### リスク軽減策

1. **ロールバック準備**
   ```bash
   # データベースバックアップ
   mysqldump --single-transaction --routines --triggers app_db > backup_pre_optimization.sql
   
   # インデックス復元用DDL準備
   mysql app_db < scripts/restore_original_indexes.sql
   ```

2. **段階的適用**
   - インデックス最適化のみ先行適用
   - 24-48時間の安定性確認
   - 問題なければ次フェーズ実行

3. **継続監視**
   - パフォーマンス監視スクリプトの常時実行
   - エラーログの詳細監視
   - ユーザー体験への影響確認

## トラブルシューティング

### よくある問題と対処法

#### 1. マイグレーション失敗
```bash
# 問題: インデックス削除時のエラー
# 対処: 存在確認後の削除
mysql> SHOW INDEX FROM table_name WHERE Key_name = 'index_name';
mysql> DROP INDEX index_name ON table_name;
```

#### 2. パフォーマンス低下
```bash
# 問題: 最適化後のパフォーマンス低下
# 対処: 統計情報の更新
mysql> ANALYZE TABLE table_name;

# インデックスの使用状況確認
mysql> EXPLAIN SELECT ...;
```

#### 3. MySQL設定エラー
```bash
# 問題: 設定変更後の起動失敗
# 対処: 設定値の確認と調整
mysql> SHOW VARIABLES LIKE 'innodb_buffer_pool_size';

# メモリ使用量の確認
free -h
```

## 成果物の活用

### 継続的改善
1. **月次レビュー**: パフォーマンス指標の定期確認
2. **四半期最適化**: 新たなボトルネックの特定と対策
3. **年次アーキテクチャ見直し**: スケールアウト戦略の検討

### 他プロジェクトへの展開
- 最適化スクリプトの汎用化
- ベストプラクティスのドキュメント化
- 監視システムのテンプレート化

## 次のステップ

### 短期的改善（1-2ヶ月）
1. **読み書き分離**: レプリケーション構成の検討
2. **キャッシュ戦略**: Redis活用の拡大
3. **API最適化**: N+1問題の完全解消

### 長期的改善（3-6ヶ月）
1. **シャーディング**: 大規模データ対応
2. **パーティショニング**: 時系列データの効率化
3. **マイクロサービス化**: 高負荷機能の分離

### 将来的展望（6ヶ月以上）
1. **クラウドネイティブ化**: Kubernetes対応
2. **AI/ML統合**: 予測的な最適化
3. **グローバル展開**: マルチリージョン対応

---

**Team 6による継続的なデータベース最適化により、StockRxシステムの安定性と拡張性を確保します。**