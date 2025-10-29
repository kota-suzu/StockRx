# 2025-09-16 GitHub Issue 下書き

## 1. 非JSON要求拒否時の Double Render を解消する
- **概要**: `ApiController#ensure_json_request` が 406 を `render` した後もアクションが継続し、`Api::V1::InventoriesController#index` などで `AbstractController::DoubleRenderError` が発生しています。
- **根拠**: `app/controllers/api/api_controller.rb:32-47` の実装。`test_output.log` のスタックトレースで `render` が複数回呼ばれていることが確認できます。
- **再現手順**: `bundle exec rspec spec/controllers/api/v1/inventories_controller_spec.rb:512` を実行すると HTML リクエストのテストが例外で失敗します。
- **対応案**:
  - 406 応答を返す際に `render(...); return` のように早期リターンし、以降のフィルタ／アクションが実行されないようにする。
  - Regression テストを追加し、HTML リクエスト時に 406 が返り例外が発生しないことを保証する。

## 2. EmailAuthService のレート制限エラーを安全に扱う
- **概要**: `EmailAuthService#generate_and_send_temp_password` が rescue 範囲外で `validate_rate_limit` を呼び出すため、`RateLimitExceededError` がそのまま外部へ伝播します。またレート制限カウンタが共有 Hash (`@rate_limit_cache`) で実装されており、並列実行時に非安全です。
- **根拠**: `app/services/email_auth_service.rb:55-68` と `app/services/email_auth_service.rb:494-505`。`test_output.log` には並列テスト (`spec/services/email_auth_service_spec.rb:987`) 中に同例外が噴出したログがあります。
- **再現手順**: `bundle exec rspec spec/services/email_auth_service_spec.rb:950` で並列生成テストを実行すると例外が発生します。
- **対応案**:
  - レート制限チェックを rescue 範囲内へ移すか、`RateLimitExceededError` を明示的に rescue して API 応答を返す。
  - レート制限カウンタを Redis などスレッドセーフなストア（暫定的には `Concurrent::Map`）に変更し、テスト前にリセットする仕組みを整備する。

## 3. 有効期限切れ一時パスワードの自動削除 Job を実装する
- **概要**: TempPassword マイグレーションに緊急 TODO が残っており、期限切れレコードが自動削除されないため認証情報が長期間保存されるリスクがあります。
- **根拠**: `db/migrate/20250618035322_create_temp_passwords.rb:41-70` の TODO。`EmailAuthService#cleanup_expired_passwords` は存在するものの定期実行箇所がありません。
- **対応案**:
  - Sidekiq/cron ジョブを追加して `EmailAuthService#cleanup_expired_passwords` を定期実行し、削除件数と対象を監査ログに残す。
  - 運用ドキュメント（README や `AGENTS.md`）にスケジュールと手動実行手順を追記する。

## 4. docker-compose.yml の平文資格情報を .env 化する
- **概要**: `docker-compose.yml` に `MYSQL_ROOT_PASSWORD=password` などの資格情報が直書きされており、ファイル共有時に漏洩リスクが高い状態です。
- **根拠**: `docker-compose.yml:18-64` および `docker-compose.yml:83-110`。
- **対応案**:
  - `.env` と `.env.example` に値を移し `${VAR}` 参照へ変更する。
  - 新しい設定手順を README と `AGENTS.md` に記載し、既存開発者への周知を行う。

## 5. テストカバレッジ 70% 目標に向けた追跡 Issue を作成する
- **概要**: 2025-06-25 時点でテストカバレッジは 19.49% に留まっており、設定された 70% 目標との差分が大きいままです。
- **根拠**: `coverage_improvement_plan.md:1-39` に現状とターゲットが記載されています。
- **対応案**:
  - Auditable concern、StoreUser/Admin モデル、Security service など優先度の高いファイル群をスプリント／マイルストーンに分類した追跡 Issue を作成する。
  - PR テンプレートにカバレッジ差分の記入欄を追加し、各 PR で改善の有無を報告する運用に切り替える。

## 6. CI で SimpleCov を必ず実行する
- **概要**: RSpec 実行ログに「SimpleCov カバレッジ計測をスキップしました（COVERAGE=true で有効化）」と記録されており、GitHub Actions 上でもカバレッジ収集が行われていません。
- **根拠**: `rspec_output.log` の冒頭／末尾。`.github/workflows/ci-optimized.yml` の test ジョブに `COVERAGE=true` が設定されていない。
- **対応案**:
  - CI の RSpec 実行時に `COVERAGE=true`（必要なら `SIMPLECOV_PROFILE=ci`）を設定し、`coverage/` を成果物として保存する。
  - PR コメントまたは Summary にカバレッジ情報を自動掲示し、進捗を可視化する。

## 7. Dependency-Check ステップを実装する
- **概要**: CI のセキュリティマトリクスで `dependency-check` ステップが `echo` のみで実質未実装となっており、脆弱性スキャンがカバーされていません。
- **根拠**: `.github/workflows/ci-optimized.yml:56-74` にて `dependency-check` ケースが固定メッセージを出力するだけになっています。
- **対応案**:
  - OWASP Dependency-Check（公式 CLI か GitHub Action）を導入し、結果 JSON を `tmp/dependency-check.json` に保存してアーティファクト化する。
  - 致命的な脆弱性が検出された場合はジョブを失敗させ、PR で修正を促す運用にする。

---

### 次のステップ
1. 上記 7 件を GitHub Issue として登録する。
2. API の Double Render と EmailAuthService のレート制限問題を優先修正し、`make rspec` で回帰テストを確認する。
3. CI 設定変更後にパイプラインを再実行し、最新カバレッジ値を追跡 Issue に記録する。
