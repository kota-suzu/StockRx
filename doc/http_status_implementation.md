# HTTPステータスコード実装状況

**最終更新**: 2025年5月28日  
**全体進捗**: Phase 1完了 (100%) | Phase 2-4計画中

## Phase 1 (基盤) - 完了 ✅

### 実装済み機能
1. **config.exceptions_app** 設定
   - `config/application.rb` に設定済み
   - 全例外をRoutes配下で処理

2. **ErrorHandlers モジュール**
   - `app/controllers/concerns/error_handlers.rb` 実装済み
   - 標準的な例外をキャッチして適切なHTTPステータスを返す
   - HTML/JSON/Turbo Stream 全てに対応

3. **ErrorsController**
   - `app/controllers/errors_controller.rb` 実装済み
   - 動的エラーページ表示
   - i18n対応

4. **静的エラーページ**
   - 400, 403, 404, 422, 429, 500 の静的HTMLページ作成済み
   - StockRxブランドデザイン適用

5. **ルーティング設定**
   - エラーページルーティング設定済み
   - ワイルドカードルート設定済み

6. **テスト実装**
   - shared_examples 実装済み
   - 主要コントローラーのテスト作成済み

## Phase 2 (拡張) - TODO 🚧

**目標**: ビジネスロジックに特化したエラー処理の実装  
**優先度**: 高  
**推定期間**: 1-2週間

### 409 Conflict 対応
```ruby
# TODO: app/controllers/concerns/error_handlers.rb に追加
# 楽観的ロック競合処理
rescue_from ActiveRecord::StaleObjectError, with: ->(e) { render_error 409, e }

# TODO: カスタムエラークラスの実装
# app/lib/custom_error.rb に以下を追加:
class CustomError::ResourceConflict < CustomError::BaseError
  def initialize(message = "リソースが競合しています")
    super(message, status: 409, code: "conflict")
  end
end
```

### i18n エラーメッセージ
```yaml
# TODO: config/locales/ja.errors.yml に追加
ja:
  errors:
    status:
      400: "不正なリクエストです"
      403: "アクセスが拒否されました"
      404: "ページが見つかりません"
      409: "リソースが競合しています"
      422: "入力内容を処理できません"
      429: "リクエストが多すぎます"
      500: "システムエラーが発生しました"
    codes:
      validation_error: "入力内容にエラーがあります"
      resource_not_found: "指定されたリソースが見つかりません"
      parameter_missing: "必須パラメータが不足しています"
      conflict: "リソースが競合しています"
      forbidden: "このリソースへのアクセス権限がありません"
```

## Phase 3 (運用強化) - TODO 🚧

**目標**: 本番環境での監視・セキュリティ強化  
**優先度**: 高  
**推定期間**: 2-3週間

### Sentry連携
```ruby
# TODO: app/controllers/concerns/error_handlers.rb の log_error メソッドに追加
# Sentry連携（エラー追跡・アラート）
if status >= 500 && Rails.env.production?
  Sentry.capture_exception(exception, extra: {
    request_id: request.request_id,
    user_id: current_user&.id,
    path: request.fullpath,
    params: filtered_parameters
  })
end
```

### Rack::Attack 設定
```ruby
# TODO: config/initializers/rack_attack.rb を作成
Rack::Attack.throttle('api/ip', limit: 300, period: 5.minutes) do |req|
  req.ip if req.path.start_with?('/api')
end

Rack::Attack.throttle('login/ip', limit: 5, period: 20.seconds) do |req|
  req.ip if req.path == '/admin/sign_in' && req.post?
end

# エラーハンドラーに追加
rescue_from Rack::Attack::Throttled, with: ->(e) { render_error 429, e }
```

### Pundit 認可連携
```ruby
# TODO: app/controllers/concerns/error_handlers.rb のコメントアウト部分を有効化
rescue_from Pundit::NotAuthorizedError, with: ->(e) { render_error 403, e }

# TODO: 各コントローラーに authorize を追加
# 例: app/controllers/inventories_controller.rb
def show
  @inventory = Inventory.find(params[:id])
  authorize @inventory  # Pundit認可チェック
end
```

### ログ強化
```ruby
# TODO: config/environments/production.rb に追加
# 構造化ログ設定
config.log_formatter = proc do |severity, datetime, progname, message|
  {
    timestamp: datetime.iso8601,
    level: severity,
    progname: progname,
    message: message,
    environment: Rails.env,
    application: 'StockRx'
  }.to_json + "\n"
end
```

## Phase 4 (将来拡張) - TODO 🔮

**目標**: グローバル対応・スケーラビリティ向上  
**優先度**: 中  
**推定期間**: 1-2ヶ月

### 多言語エラーページ
- [ ] 英語版エラーページの作成
- [ ] Accept-Language ヘッダーに基づく言語切り替え
- [ ] エラーメッセージの完全な国際化

### キャッシュ最適化
- [ ] エラーページのCDN配信設定
- [ ] Cache-Control ヘッダーの最適化
- [ ] 動的エラーページのフラグメントキャッシュ

### 監視・分析
- [ ] エラー発生パターンの分析ダッシュボード
- [ ] エラー発生時の自動通知システム
- [ ] パフォーマンスメトリクスの収集

## テスト実行方法

```bash
# エラーハンドリングのテスト実行
bundle exec rspec spec/requests/errors_spec.rb
bundle exec rspec spec/requests/inventories_spec.rb
bundle exec rspec spec/requests/api/v1/inventories_spec.rb

# shared_examples を使用したテスト
bundle exec rspec spec/support/shared_examples/error_handling.rb
```

## 実装ベストプラクティス

### エラーハンドリング設計原則
1. **一貫性**: 全APIで統一されたエラーレスポンス形式
2. **セキュリティ**: 内部情報の漏洩防止
3. **可用性**: 適切なフォールバック処理
4. **監視性**: エラー追跡・分析の容易性

## 注意事項

1. **422エラーの扱い**
   - HTMLフォームでは同一ページで再表示
   - JSON APIではエラーレスポンスを返却
   - Turbo Streamではフラッシュメッセージで通知

2. **セキュリティ**
   - エラーメッセージに内部情報を含めない
   - 本番環境では詳細なスタックトレースを隠蔽
   - request_id を使用したトレーサビリティ確保

3. **パフォーマンス**
   - 静的エラーページは public/ に配置してRailsを経由しない
   - エラーログは非同期で記録
   - 429エラーでレート制限を適切に実装