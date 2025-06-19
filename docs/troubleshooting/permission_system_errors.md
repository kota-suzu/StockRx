# 権限システムエラー トラブルシューティングガイド

## 🚨 NoMethodError: undefined method `super_admin?'

### 症状
```
NoMethodError in AdminControllers::AuditLogsController#compliance_report
undefined method `super_admin?' for an instance of Admin
```

### 原因分析
1. **キャッシュ問題**: Rails開発環境でのクラスキャッシュ（Spring/Bootsnap）が古いコードを保持
2. **ブラウザキャッシュ**: 古いJavaScript/HTMLがキャッシュされている
3. **コード不整合**: 権限メソッド名の不一致

### 解決手順

#### Phase 1: 緊急対応（即座に実行）
```bash
# 1. Railsサーバー完全停止
pkill -f 'rails server'

# 2. Spring停止（キャッシュクリア）
bin/spring stop

# 3. tmp/cacheクリア
rm -rf tmp/cache/

# 4. サーバー再起動
make server  # または docker-compose up
```

#### Phase 2: ブラウザ側対応
1. **ブラウザキャッシュクリア**: Cmd+Shift+R (Mac) / Ctrl+Shift+R (Windows)
2. **ハードリロード**: DevTools開いた状態でリロードボタン長押し → "Empty Cache and Hard Reload"
3. **シークレットウィンドウ**: 新しいシークレットウィンドウで問題再現確認

#### Phase 3: 根本検証
```bash
# 権限システム整合性確認
grep -r "super_admin?" app/ --include="*.rb"
# 期待結果: コメント内のみ存在、実際のコードでは使用されていない

# 現在の権限メソッド確認
grep -r "headquarters_admin?" app/ --include="*.rb"
# 期待結果: AuditLogsController等で正しく使用されている
```

### 現在の権限システム設計

#### 権限階層（上位→下位）
```
headquarters_admin > store_manager > pharmacist > store_user
```

#### 各権限の責任範囲
- **headquarters_admin**: 全店舗管理、監査ログ、システム設定
- **store_manager**: 担当店舗管理、移動承認、スタッフ管理  
- **pharmacist**: 薬事関連業務、在庫確認、品質管理
- **store_user**: 基本在庫操作、日常業務

#### 実装済み権限メソッド
```ruby
# Admin model (app/models/admin.rb)
enum :role, {
  store_user: "store_user",
  pharmacist: "pharmacist", 
  store_manager: "store_manager",
  headquarters_admin: "headquarters_admin"
}

# 自動生成メソッド
current_admin.headquarters_admin?  # 最高権限
current_admin.store_manager?       # 店舗管理権限
current_admin.pharmacist?          # 薬剤師権限
current_admin.store_user?          # 基本ユーザー権限

# カスタムメソッド  
current_admin.can_access_all_stores?
current_admin.can_manage_store?(target_store)
current_admin.can_approve_transfers?
```

### 予防策

#### 開発時のベストプラクティス
1. **権限チェックの一貫性**: `headquarters_admin?` を使用
2. **enum活用**: Railsのenum機能による自動メソッド生成を活用
3. **権限テスト**: 権限変更時は必ずテスト実行
4. **キャッシュクリア**: コード変更後は必ずキャッシュクリア

#### コードレビューチェックリスト
- [ ] 権限メソッド名は現在のenum定義と一致しているか？
- [ ] 新しい権限メソッドを追加した場合、既存コードとの整合性は保たれているか？
- [ ] 権限変更のテストケースは追加されているか？
- [ ] 権限関連のコメント・文書は更新されているか？

### 将来拡張予定

#### Phase 5: 権限システム拡張（将来実装）
```ruby
# 予定されている権限階層拡張
enum :role, {
  store_user: "store_user",
  pharmacist: "pharmacist",
  store_manager: "store_manager", 
  headquarters_admin: "headquarters_admin",
  admin: "admin",                    # 新規追加予定
  super_admin: "super_admin"         # 新規追加予定
}
```

**実装条件**: 現在のheadquarters_adminで要件が充足されなくなった場合のみ
**原則**: YAGNI（You Aren't Gonna Need It）- 過度な権限分割を避ける

### 関連ファイル
- `app/models/admin.rb`: 権限システム定義
- `app/controllers/admin_controllers/audit_logs_controller.rb`: 監査ログ権限制御
- `spec/models/admin_spec.rb`: 権限システムテスト
- `db/schema.rb`: role enum定義

### 緊急連絡先
開発中にこのエラーが解決できない場合:
1. サーバー再起動後も問題が継続する場合は、最新のmainブランチとの差分確認
2. テスト環境での権限システム動作確認
3. ログファイル（log/development.log）でのエラー詳細確認

---
*最終更新: 2025年6月17日*
*CLAUDE.md準拠で作成*