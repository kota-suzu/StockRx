# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## エンジニアリング原則 - Google L8相当のエキスパートとしての行動指針

### 1. 基本的なマインドセット

#### メタ認知の実践
- 常に自身の思考プロセスを客観視し、「なぜこの方法を選んだのか？」を自問する
- 不明点は正直に「わからない」と表明し、具体的な解消計画を立てる
- 仮説と検証を繰り返し、間違いから学び、速やかに軌道修正する

#### Before/After形式での思考
すべての重要な決定において：
- **Before**: 最初の直感的アプローチ
- **After**: 複数案の比較検討後の洗練された案  
- **理由**: トレードオフとその判断根拠を明確に記録（ADR形式）

### 2. 要求分析と設計アプローチ

#### 要求の深掘り
1. **機能要件**: ユーザーストーリー、正常系・異常系、エッジケースまで網羅
2. **非機能要件**: パフォーマンス、可用性、セキュリティ、保守性を定量化
3. **制約条件**: 技術、期間、予算、既存システムとの整合性を明確化

#### 多角的な設計視点
- **機能充足性**: 要求を過不足なく満たすか
- **パフォーマンス**: ボトルネックの予測と対策
- **スケーラビリティ**: 将来の成長に対応可能か
- **保守性**: 半年後の自分でも理解・修正できるか
- **セキュリティ**: 設計段階からの組み込み（Security by Design）
- **運用性**: デプロイ、監視、トラブルシューティングの容易さ

### 3. 実装の品質基準

#### コーディング原則
- **SOLID原則**の適用（特に単一責任、依存性逆転）
- **KISS**: 必要十分なシンプルさを保つ
- **DRY**: 重複を避けつつ、過度な抽象化は避ける
- **YAGNI**: 今必要ない機能は実装しない

#### エラーハンドリング
- 早期検知・早期失敗（Fail Fast）
- 回復可能なエラーと致命的エラーの区別
- 適切なリトライとフォールバック戦略
- エラー時のデータ整合性維持

#### 可観測性の確保
- 構造化ログ（JSON形式、コンテキスト情報付き）
- 主要メトリクスの収集と監視
- 分散トレーシング（該当する場合）
- アクション可能なアラート設定

### 4. テスト戦略

#### テストピラミッド
1. **単体テスト**: 最も多く、高速、独立性を保つ
2. **統合テスト**: モジュール間連携の検証
3. **E2Eテスト**: 重要なユーザーシナリオに絞る

#### TDD/BDDの実践（推奨）
- Red → Green → Refactorサイクル
- テスト容易な設計への自然な誘導
- 回帰バグの早期発見

### 5. 継続的改善

#### プロセス改善
- 定期的な振り返り（レトロスペクティブ）
- インシデントからの学び（ポストモーテム）
- 技術的負債の可視化と計画的解消

#### 意思決定の記録
- Architecture Decision Records（ADR）の活用
- 検討した選択肢と却下理由の記録
- トレードオフの明確化

---

## Build and Development Commands

### Starting the Application
```bash
make up          # Start all containers (Rails, MySQL, Redis, Sidekiq)
make server      # Alias for 'make up' with health check
make logs        # View logs (follow mode)
make ps          # Check container status
```

### Database Operations
```bash
make db-setup    # Create database, run migrations, and seed data
make db-migrate  # Run pending migrations
make db-reset    # Drop, create, migrate, and seed database
make db-seed     # Load seed data
```

### Running Tests
```bash
# Quick tests (recommended for development)
make test-unit-only    # Models, helpers, decorators only (~3.5s)
make test-models       # Model tests only
make test-fast         # Models, controllers, and units

# Comprehensive tests
make test              # Run all tests (alias: make rspec)
make test-coverage     # Run tests with coverage report
make test-integration  # Feature and job tests

# Test utilities
make test-failed       # Re-run only failed tests
make test-profile      # Show 10 slowest tests
make test-parallel     # Run tests in parallel
```

### Code Quality
```bash
make lint              # Run RuboCop
make lint-fix          # Auto-fix safe issues
make lint-fix-unsafe   # Auto-fix all issues (use with caution)
make security-scan     # Run Brakeman security scan
```

### Utilities
```bash
make console           # Rails console
make routes           # Show all routes
docker-compose exec web bundle exec sidekiq  # Start Sidekiq worker
```

## Architecture Overview

### Namespace Structure
The application uses specific namespace patterns to avoid conflicts with model names:

- **Controllers**: `AdminControllers` module for admin-related controllers
  - Located in `app/controllers/admin_controllers/`
  - Example: `AdminControllers::DashboardController`
  
- **Helpers**: Standard helper naming convention
  - Admin helpers: `app/helpers/admin_controllers/`
  - Example: `AdminControllers::InventoriesHelper`

- **Views**: Match controller namespace structure
  - Admin views: `app/views/admin_controllers/`

### Key Models and Relationships

```ruby
# Core inventory management
Inventory (has_many :batches, :inventory_logs)
  ├── Batch (belongs_to :inventory) - Lot/batch tracking
  ├── InventoryLog - Audit trail for all changes
  ├── Receipt - Incoming stock records  
  └── Shipment - Outgoing stock records

# Authentication
Admin (Devise with :lockable, :timeoutable)
  └── AdminNotificationSetting - Email preferences
```

### Background Job Processing
The application uses Sidekiq for background jobs with Redis:

- **ImportInventoriesJob**: CSV import with progress tracking via ActionCable
- **Job monitoring**: Sidekiq Web UI at `/sidekiq` (admin auth required)
- **Progress tracking**: Real-time updates through ActionCable channels

### Error Handling
Modular error handling system with `config.exceptions_app = routes`:

- **ErrorHandlers** concern for consistent API/HTML responses
- **ErrorsController** for rendering error pages
- **Custom error classes** in `app/lib/custom_error.rb`
- Static error pages for 400, 403, 404, 422, 429, 500

### Security Considerations

- **CSV Import**: File size limit (10MB), MIME type validation
- **Authentication**: Devise with password strength validation (12+ chars)
- **Session timeout**: 30 minutes of inactivity
- **Failed login lockout**: 5 attempts → 15 minute lock
- **Current class**: Thread-local request/user context (use `Current.reset` in tests)

### Testing Strategy

- **RSpec** with FactoryBot for test data
- **Coverage tracking** with SimpleCov
- **Shared examples** for common patterns
- **Known issues**: 
  - Job tests may fail due to Redis/ActionCable setup
  - Feature tests need Capybara configuration
  - Auditable concern has error handling issues

### Performance Optimizations

- **N+1 detection**: Bullet gem in development
- **CSV import**: Batch processing (1000 records/batch)
- **Database indexes**: On foreign keys and search fields
- **Decorators**: Draper for view logic separation

## Common Development Tasks

### Adding a New Feature
1. **要求分析**: 機能・非機能要件を明確化し、エッジケースまで考慮
2. **設計検討**: 複数のアプローチを比較し、トレードオフを評価
3. **実装**:
   - Check namespace conventions (avoid model name conflicts)
   - Use `Current` class for request context
   - Add appropriate error handling with recovery strategies
   - Ensure observability (structured logging, metrics)
4. **テスト**: 
   - Write tests first or alongside implementation
   - Aim for >90% coverage of critical paths
   - Include edge cases and error scenarios
5. **品質チェック**:
   - Run linting and security scans
   - Perform code review focusing on maintainability
   - Document decisions in ADR if significant

### Working with Background Jobs
1. Inherit from `ApplicationJob`
2. Include `ProgressNotifier` for progress tracking
3. Use appropriate Sidekiq queue (default, critical, low)
4. **エラーハンドリング**:
   - Implement idempotency where possible
   - Add retry strategies with exponential backoff
   - Consider circuit breakers for external dependencies
5. Write both unit and integration tests

### Database Migrations
1. Use strong constraints and foreign keys
2. Add indexes for foreign keys and search fields
3. **データ移行戦略**:
   - Consider zero-downtime deployment requirements
   - Plan for rollback scenarios
   - Test with production-like data volumes
4. Document migration risks and rollback procedures

### パフォーマンス最適化の実践例

#### Before: N+1クエリ問題
```ruby
# inventories_controller.rb
def index
  @inventories = Inventory.all
  # ビューで inventory.batches.count を呼ぶとN+1発生
end
```

#### After: includesによる最適化
```ruby
# inventories_controller.rb
def index
  @inventories = Inventory.includes(:batches, :inventory_logs)
                         .with_attached_image
  # 関連データを事前ロードし、クエリ数を削減
end
```

**理由**: N+1クエリはパフォーマンスボトルネックの主要因。includesにより3N+1クエリが3クエリに削減される。

### セキュリティ実装の実践例

#### Before: 脆弱な入力処理
```ruby
def search
  @results = Inventory.where("name LIKE '%#{params[:q]}%'")
  # SQLインジェクション脆弱性
end
```

#### After: 安全なパラメータ処理
```ruby
def search
  @results = Inventory.where("name LIKE ?", "%#{sanitize_sql_like(params[:q])}%")
  # プレースホルダとサニタイズを使用
end
```

**理由**: ユーザー入力を直接SQLに埋め込むことは重大なセキュリティリスク。Railsの安全なクエリメソッドを活用。

## Important Notes

- **Docker required**: All commands run through Docker Compose
- **Port 3000**: Default Rails server port
- **Development URL**: http://localhost:3000 (not https)
- **Default admin**: admin@example.com / Password1234!
- **Time zone**: Application uses UTC internally
- **File uploads**: Currently stored locally, S3 integration planned

## 実装時の心構え

1. **メタ認知を常に**: なぜこの実装方法を選んだか？より良い方法はないか？
2. **横展開の確認**: 同様の処理が他にないか確認し、一貫性を保つ
3. **ベストプラクティスの適用**: 言語・フレームワーク固有の慣習に従う
4. **TODOの明確化**: 
   ```ruby
   # TODO: S3統合時にローカルストレージからの移行処理を実装
   # - 既存ファイルのS3への一括アップロード
   # - URLの更新処理
   # - ローカルファイルの削除タイミング検討
   ```

## 継続的な改善

- 定期的なコードレビューとリファクタリング
- パフォーマンスメトリクスの監視と最適化
- セキュリティアップデートの適用
- テストカバレッジの向上と品質改善
- ドキュメントの更新と知識共有