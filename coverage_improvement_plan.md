# StockRx Test Coverage Improvement Plan

## Current Status (as of 2025-06-25)
- **Current Coverage**: 19.49% (2,717/13,941 lines)
- **Target Coverage**: 70%
- **Lines Needed**: 7,041 lines
- **Estimated Effort**: ~141 person-days (assuming 50 lines of test coverage per day)

> **Note**: This plan was created in June 2025. Current coverage may have improved since then.

## Coverage by Category

| Category | Current Coverage | Uncovered Lines | Priority |
|----------|-----------------|-----------------|----------|
| Helpers | 0.0% | 1,381 | High |
| Controllers | 18.06% | 2,582 | High |
| Models | 27.75% | 1,888 | High |
| Jobs | 17.84% | 760 | Medium |
| Services | 30.83% | 1,550 | Medium |
| Lib | 13.35% | 1,493 | Low |
| Other | 17.67% | 1,570 | Low |

## Top 15 Priority Files to Test

### 1. **app/models/concerns/auditable.rb** (289 lines, 0% coverage)
- **Type**: Model Concern
- **Priority**: CRITICAL
- **Reason**: Core audit logging functionality used across multiple models
- **Estimated Effort**: 3 days

### 2. **app/models/concerns/data_portable.rb** (298 lines, 0% coverage)
- **Type**: Model Concern
- **Priority**: CRITICAL
- **Reason**: Data import/export functionality critical for business operations
- **Estimated Effort**: 3 days

### 3. **app/controllers/store_controllers/transfers_controller.rb** (231 lines, 0% coverage)
- **Type**: Controller
- **Priority**: HIGH
- **Reason**: Inter-store transfer functionality is business-critical
- **Estimated Effort**: 2.5 days

### 4. **app/helpers/application_helper.rb** (203 lines, 0% coverage)
- **Type**: Helper
- **Priority**: HIGH
- **Reason**: Core helper methods used throughout the application
- **Estimated Effort**: 2 days

### 5. **app/lib/security_monitor.rb** (248 lines, 0% coverage)
- **Type**: Library
- **Priority**: HIGH
- **Reason**: Security monitoring is critical for compliance
- **Estimated Effort**: 2.5 days

### 6. **app/models/store_user.rb** (141 lines, 0% coverage)
- **Type**: Model
- **Priority**: HIGH
- **Reason**: Core authentication model for store users
- **Estimated Effort**: 1.5 days

### 7. **app/models/admin.rb** (133 lines, 0% coverage)
- **Type**: Model
- **Priority**: HIGH
- **Reason**: Core authentication model for administrators
- **Estimated Effort**: 1.5 days

### 8. **app/services/search_query.rb** (186 uncovered lines, 6.53% coverage)
- **Type**: Service
- **Priority**: HIGH
- **Reason**: Search functionality is heavily used
- **Estimated Effort**: 2 days

### 9. **app/helpers/admin_controllers/compliance_audit_logs_helper.rb** (224 lines, 0% coverage)
- **Type**: Helper
- **Priority**: MEDIUM
- **Reason**: Compliance audit functionality
- **Estimated Effort**: 2 days

### 10. **app/lib/security/key_provider.rb** (182 lines, 0% coverage)
- **Type**: Library
- **Priority**: MEDIUM
- **Reason**: Encryption key management
- **Estimated Effort**: 2 days

### 11. **app/services/data_patch_registry.rb** (159 lines, 0% coverage)
- **Type**: Service
- **Priority**: MEDIUM
- **Reason**: Data migration management
- **Estimated Effort**: 1.5 days

### 12. **app/jobs/external_api_sync_job.rb** (126 lines, 0% coverage)
- **Type**: Job
- **Priority**: MEDIUM
- **Reason**: External integrations
- **Estimated Effort**: 1.5 days

### 13. **app/controllers/store_controllers/sessions_controller.rb** (151 lines, 0% coverage)
- **Type**: Controller
- **Priority**: MEDIUM
- **Reason**: Authentication flow
- **Estimated Effort**: 1.5 days

### 14. **app/models/concerns/csv_importable.rb** (174 lines, 12.07% coverage)
- **Type**: Model Concern
- **Priority**: MEDIUM
- **Reason**: CSV import functionality
- **Estimated Effort**: 1.5 days

### 15. **app/jobs/monthly_report_job.rb** (158 uncovered lines, 16.4% coverage)
- **Type**: Job
- **Priority**: MEDIUM
- **Reason**: Regular reporting functionality
- **Estimated Effort**: 1.5 days

## Implementation Strategy

### Phase 1: Critical Infrastructure (Weeks 1-2)
1. Test core model concerns (Auditable, DataPortable)
2. Test authentication models (Admin, StoreUser)
3. Test ApplicationHelper
**Expected Coverage Gain**: +10-12%

### Phase 2: Business Logic (Weeks 3-4)
1. Test transfer controllers
2. Test search services
3. Test security libraries
**Expected Coverage Gain**: +12-15%

### Phase 3: Supporting Features (Weeks 5-6)
1. Test background jobs
2. Test remaining helpers
3. Test session controllers
**Expected Coverage Gain**: +15-18%

### Phase 4: Refinement (Weeks 7-8)
1. Test remaining services
2. Test data patches
3. Increase coverage on partially tested files
**Expected Coverage Gain**: +10-15%

## Quick Wins (Can be done immediately)

1. **Model tests without associations**: Admin, StoreUser, BatchMovement
   - Simple validation and method tests
   - ~2 days effort for ~5% coverage gain

2. **Helper method tests**: Test isolated helper methods
   - ApplicationHelper, ModernUiHelper
   - ~3 days effort for ~8% coverage gain

3. **Service object tests**: Complete partially tested services
   - SearchQuery, ReportFileStorageService
   - ~2 days effort for ~4% coverage gain

## Recommendations

1. **Start with Model Concerns**: These are used across multiple models and will provide the most coverage bang for buck
2. **Use shared examples**: For common patterns like Auditable, create shared examples to reuse across tests
3. **Focus on happy paths first**: Get basic coverage before edge cases
4. **Leverage factories**: Ensure FactoryBot factories exist for all models
5. **Parallel testing**: Use parallel_tests gem to speed up test runs as coverage grows

## Metrics to Track

- Daily coverage percentage increase
- Number of files with 0% coverage (currently ~40 files)
- Average coverage per category
- Test execution time
- Test stability (flaky test count)

## Success Criteria

- Reach 70% overall coverage
- No critical business logic files with <50% coverage
- All authentication/authorization code >80% coverage
- All models and services >60% coverage
- Test suite runs in <5 minutes

## Completed Tasks (Archived)

### 2025年6月 完了分
- ✅ ヘルパー機能の改善
  - ビューファイル内のヘルパーメソッド定義を適切なヘルパーファイルに移動
  - AdminControllers::InventoriesHelper への統合
  - ソートアイコン機能の追加
  - 重複ヘルパーファイルの削除

### テスト実装済み
- ✅ 一部のモデルテスト（Inventory, Batch等の基本モデル）
- ✅ 一部のコントローラーテスト（AdminControllers関連）
- ✅ 一部のヘルパーテスト（基本的なヘルパー機能）