# StockRx - 在庫管理システム

StockRxは薬局・医療機関向けの在庫管理システムです。商品の入出庫管理、在庫レベルの監視、レポート作成などの機能を提供します。

## 技術スタック

* Ruby 3.3.8
* Rails 7.2.2
* MySQL 8.4
* Docker / Docker Compose

## 開発環境セットアップ

```bash
# リポジトリのクローン
git clone [repository-url]
cd StockRx

# Docker環境の起動
docker-compose up -d

# データベースのセットアップ
docker-compose exec web bin/rails db:setup
```

## 基本的な使い方

1. ブラウザで http://localhost:3000 にアクセス
2. 管理者としてログイン（デフォルト：admin@example.com / Password1234!）
3. ダッシュボードから各機能にアクセス

## トラブルシューティング

### 接続エラー（ERR_CONNECTION_REFUSED）

**症状**: ブラウザで `ERR_CONNECTION_REFUSED` エラーが表示される

**原因**: webコンテナが起動していない（最も一般的）

**解決手順**:
```bash
# 1. 状況確認
make diagnose

# 2. 自動修復を試行
make fix-connection

# 3. 手動での確認・修復
docker compose ps              # コンテナ状態確認
docker compose logs web        # webコンテナのログ確認
docker compose up -d web       # webコンテナ再起動
```

### SSL/HTTPS接続エラー

**症状**: Pumaログに "SSL connection to a non-SSL Puma" エラー

**原因**: ブラウザが `https://localhost:3000` でアクセスしている

**解決方法**:
```bash
# 対処法の表示
make fix-ssl-error

# 正しいアクセス方法
# ✅ http://localhost:3000
# ❌ https://localhost:3000
```

### よくある問題と解決策

| 問題 | 原因 | 解決方法 |
|------|------|----------|
| webコンテナが起動しない | Dockerfile/依存関係エラー | `docker compose build web` でリビルド |
| ポート3000が使用中 | 他のプロセスがポート占有 | `lsof -i :3000` で確認後、プロセス終了 |
| データベース接続エラー | dbコンテナ未起動 | `docker compose up -d db` |
| ブラウザキャッシュ問題 | 古いHTTPS設定が残存 | Ctrl+Shift+R（強制リロード） |
| CSVインポートが動作しない | Sidekiqワーカー未起動 | `docker-compose exec web bundle exec sidekiq -C config/sidekiq.yml` |
| Redis接続エラー | redisコンテナ未起動 | `docker compose up -d redis` |
| ジョブが処理されない | Sidekiq設定エラー | `rails sidekiq:health` でヘルスチェック |

### Sidekiq関連のトラブルシューティング

```bash
# Sidekiqヘルスチェック
docker-compose exec web bin/rails sidekiq:health

# キュー状況確認
docker-compose exec web bin/rails sidekiq:queues

# 失敗ジョブのクリア
docker-compose exec web bin/rails sidekiq:clear_failed

# Redis接続確認
docker-compose exec redis redis-cli ping

# Sidekiqワーカー情報表示
docker-compose exec web bin/rails sidekiq:workers
```

### 診断コマンド

```bash
# システム全体の診断
make diagnose

# 接続問題の自動修復
make fix-connection

# SSL問題の対処法表示
make fix-ssl-error

# 詳細ログ確認
docker compose logs -f web
```

## 開発ガイドライン

### コード構造

- 管理者機能のコントローラは `AdminControllers` モジュール内に定義
- 管理者向けヘルパーは `AdminHelpers` モジュール内に定義
- モデルとコントローラ/ヘルパーの名前空間の衝突に注意
  - `Admin`モデルと`Admin`モジュールは共存できない → `AdminControllers`や`AdminHelpers`を使用
  - 同様に、他のモデル名と同名のモジュールを避ける（例: `User`モデルと`User`モジュール）
- **重要**: モジュール名とディレクトリ構造を一致させる必要がある（Zeitwerk規約）
  - `AdminControllers` → `app/controllers/admin_controllers/`
  - `AdminHelpers` → `app/helpers/admin_helpers/`
- 詳細な設計ガイドラインは `docs/design/` ディレクトリを参照

### HTTPステータスコードとエラーハンドリング

本アプリケーションでは以下の方針に基づいたモジュラーなエラーハンドリングを実装しています：

#### 方針

1. **業務エラー** (入力ミス・権限不足等) → 4xx / バリデーションメッセージを返却
2. **システムエラー** (バグ・外部障害等) → 5xx / 詳細はログと通知サービスへ
3. `config.exceptions_app = routes` で **全例外をRailsルート配下で処理**
4. **JSON API形式を統一** し、フロントエンドは `code` パラメータで判定可能
5. HTML 422は描画せず、フォームは同一ページ再描画でUXを向上

#### 実装フェーズと進捗

| Phase | 内容 | 状態 | 成果物 |
|-------|------|------|--------|
| **1 基盤** | config.exceptions_app設定 / ErrorHandlersモジュール / 静的エラーページ | ✅ 完了 | app/controllers/concerns/error_handlers.rb<br>app/controllers/errors_controller.rb<br>app/views/errors/* |
| **2 拡張** | 409,429対応 / JSON統一 / i18nメッセージ | ✅ 完了 | app/lib/custom_error.rb<br>config/locales/*.errors.yml |
| **3 運用強化** | ログ強化 / Sentry連携 / レート制限 | 🔄 進行中 | - |
| **4 将来** | 多言語エラーページ / キャッシュ戦略 | 📅 計画中 | - |

#### 利用サンプル

シンプルなエラーハンドリングの例：

```ruby
# 変更前：手動でエラーチェック
def show
  @inventory = Inventory.find_by(id: params[:id])
  return head 404 if @inventory.nil?
  # ...処理...
end

# 変更後：findメソッドの例外を活用
def show
  @inventory = Inventory.find(params[:id])  # RecordNotFound → 自動404
  # ...処理...
end
```

詳細な実装例は `doc/examples/error_handling_examples.rb` を参照してください。

### 命名規則

- モデル: 単数形、キャメルケース（例: `Admin`, `InventoryItem`）
- コントローラ: 複数形、キャメルケース（例: `AdminControllers::ItemsController`）
- テーブル: 複数形、スネークケース（例: `admins`, `inventory_items`）

### パフォーマンステスト

StockRxには大量データ処理のパフォーマンステストが含まれています：

```bash
# テスト用の1万行CSVファイルを生成
make perf-generate-csv

# CSVインポートの性能テスト実行（目標: 30秒以内で1万行処理）
make perf-test-import

# 異なるバッチサイズでのパフォーマンス比較
make perf-benchmark-batch
```

前回のパフォーマンステスト結果：
- CSVインポート（1万行）: 0.68秒
- 最適バッチサイズ: 1000レコード（0.47秒）

## 重要な注意事項

- **名前空間とディレクトリ構造**: Railsの自動ロード機能（Zeitwerk）は名前空間とディレクトリ構造の一致を厳格に要求します
  - コントローラ名前空間はファイルパスに反映する必要があります
  - ヘルパー名前空間もディレクトリ構造に合わせる必要があります
  - ビューディレクトリもコントローラの名前空間に合わせる必要があります

## 残タスク

### 認証・認可関連
- [ ] ユーザーモデルの実装（一般スタッフ向け）
- [ ] 管理者権限レベルの実装（admin/super_admin）
- [ ] 2要素認証の導入

### 在庫管理機能
- [x] 商品マスタ管理 - モデル定義（Inventoryモデル）
- [x] ロット管理 - モデル定義（Batchモデル）
- [x] 商品マスタ管理（登録・編集・削除）UI実装
- [x] 在庫入出庫管理 UI実装
- [x] CSVインポート機能の実装と最適化
- [x] 在庫操作ログ機能の実装
  - [x] ログモデルとマイグレーション
  - [x] 自動ログ記録（数量変更時）
  - [x] CSVインポート時のログ
  - [x] ログ閲覧UIの実装
  - [x] フィルタリングとエクスポート機能
  - [ ] ログ統計分析機能の強化
- [ ] 在庫アラート機能（在庫切れ・期限切れ）
  - [ ] メール通知機能
  - [ ] 在庫切れ商品の自動レポート生成
  - [ ] アラート閾値の設定インターフェース
- [ ] バーコードスキャン対応
  - [ ] バーコードでの商品検索機能
  - [ ] QRコード生成機能
  - [ ] モバイルスキャンアプリとの連携

### エラーハンドリング関連
- [x] ErrorHandlersモジュール実装
- [x] エラーページコントローラ実装
- [x] 静的エラーページ（404, 403, 500など）
- [x] JSON API用エラーレスポンス統一
- [x] i18n対応エラーメッセージ
- [x] カスタムエラークラス実装
- [ ] 運用監視強化（ログ・通知連携）
- [ ] レート制限実装（429対応）
- [ ] 多言語HTML対応

### レポート機能
- [ ] 在庫レポート生成
- [ ] 利用状況分析
- [ ] データエクスポート機能（CSV/Excel）

### 高度な在庫分析機能
- [ ] 在庫回転率の計算
- [ ] 発注点（Reorder Point）の計算と通知
- [ ] 需要予測と最適在庫レベルの提案
- [ ] 履歴データに基づく季節変動分析

### インフラ関連
- [ ] バックアップの保存期間設定と古いバックアップの自動削除
- [ ] Redisのメモリ設定の最適化
- [ ] セキュリティ強化（パスワードの環境変数化、SSL/TLS設定）
- [ ] ログローテーション設定
- [ ] 本番環境向けのDockerfile最適化（マルチステージビルド）

### UI/UX改善
- [x] レスポンシブデザイン対応
- [ ] ダークモード対応
- [ ] ユーザビリティテスト実施

### テスト環境の整備
- [ ] CapybaraとSeleniumの設定改善
- [ ] Docker環境でのUIテスト対応
- [ ] E2Eテストの実装
- [ ] エラーハンドリング用共通テスト実装

### バックグラウンドジョブ処理
- [x] Sidekiq導入とセットアップ
  - [x] Redis設定とDocker Compose連携
  - [x] ApplicationJob基盤の強化（リトライ・ログ・監視）
  - [x] 3回リトライ機能実装
  - [x] Sidekiq Web UI設定（管理者認証付き）
- [x] ImportInventoriesJob Sidekiq対応
  - [x] 進捗追跡機能（Redis + ActionCable）
  - [x] セキュリティ検証強化
  - [x] エラーハンドリング改善
  - [x] テスト実装（単体・統合・パフォーマンス）
- [x] 運用管理ツール
  - [x] Rakeタスク（ヘルスチェック・監視・クリーンアップ）
  - [x] 横展開例（StockAlertJob・MonthlyReportJob）
- [ ] 定期実行ジョブ（sidekiq-scheduler）
- [ ] メール通知ジョブ
- [ ] 外部API連携ジョブ

## 開発ガイドライン（追加）

### Currentクラスの利用

- リクエスト情報や現在のユーザー情報など、スレッドローカルな値を保持するには`Current`クラスを使用します
- コントローラからは`Current.set_request_info(request)`を呼び出してリクエスト情報を設定します
- ユーザー情報は`Current.user = current_user`のように設定できます
- テスト内で`Current`の値を設定する場合は、テスト後に`Current.reset`で必ずリセットしてください
- `Current`クラスはリクエストスコープの情報のみを保持し、長期的な状態管理には使用しないでください

### Decoratorパターンの利用

- モデルの表示ロジックはDecoratorパターンを使って実装します
- すべてのデコレーターは`ApplicationDecorator`を継承します
- ビューでは`.decorate`メソッドを使用してデコレーター化したオブジェクトを利用します（例：`@inventory.decorate`）
- デコレーターのテストは`spec/decorators`ディレクトリに配置します

## 効率的なテスト実行ガイド（開発者生産性向上）

### テスト絞り込み戦略

StockRxでは、開発効率を最大化するため、Google L8レベルのテスト戦略を採用しています。

#### 🚀 最高速：ユニットテストのみ（推奨）
```bash
make test-unit-only    # モデル・ヘルパー・デコレータのみ（3.5秒）
make test-models       # モデルテストのみ
```

#### ⚡ 高速：コア機能テスト
```bash
make test-fast         # モデル・コントローラー・ユニット
make test-controllers  # コントローラーテスト
```

#### 🔧 問題解決：個別テスト
```bash
make test-failed       # 失敗したテストのみ再実行
make test-profile      # 遅いテストの特定
make test-skip-heavy   # 重いテストをスキップ
```

#### 📊 品質確保：包括的テスト
```bash
make test-coverage     # カバレッジ計測付き
make test-integration  # 統合テスト（時間要注意）
make test-features     # フィーチャーテスト（最重）
```

#### ⚙️ 高度な実行オプション
```bash
make test-parallel     # 並列実行（高速化）
make test-jobs         # ジョブテスト（要修正）
```

### 開発ワークフロー推奨例

1. **日常開発**: `make test-unit-only` （3.5秒で126例）
2. **機能追加**: `make test-fast` 
3. **リリース前**: `make test-coverage`
4. **問題調査**: `make test-failed` → `make test-profile`

### テスト問題の現状と対策

#### 既知の問題（修正必要）
- **ジョブテスト**: Redis接続・ActionCable統合の設定不備
- **フィーチャーテスト**: Capybara設定最適化要
- **Auditable concern**: エラーハンドリング修正要

#### 修正優先度
1. 🔥 **最高**: Redis接続設定の修正
2. 🔴 **高**: Auditable concernエラー解決
3. 🟡 **中**: ActionCable通知テスト改善

## ライセンス

[ライセンス情報]

以下は Joel Spolsky が提唱する\*\*「Painless Functional Specification」\*\*の書式を踏襲した、
あなたの在庫＋ロット・帳票アプリ（仮称 **PharDoc**）の機能仕様書です。
Joel 方式では *「仕様書は読む人を退屈させず、改訂が容易で、UI と非 UI を同列に扱う」* ことが重視されます ([Joel on Software][1], [Joel on Software][2])。

---

## 表紙（TITLE PAGE）

| 項目   | 内容                           |
| ---- | ---------------------------- |
| 製品名  | **PharDoc v0.1**             |
| 文書名  | **Functional Specification** |
| 著者   | Kota Suzuki                  |
| 最終更新 | 2025-05-14                   |
| 機密指定 | INTERNAL USE ONLY            |

---

## 1. はじめに (Introduction)

Joel は「なぜ作るのか」「誰が読むのか」を最初に書けと説いています ([Joel on Software][3])。
本仕様書は**薬局オーナー 1 名が在庫と請求書を 5 分で処理**できるアプリの振る舞いを定義し、
実装者（あなた）と未来のメンテナが迷わないようにすることを目的とします。

---

## 2. 製品概要 (Overview)

| 画面              | 目的          | 概要                         |
| --------------- | ----------- | -------------------------- |
| Dashboard       | 在庫とアラートを一望  | 在庫 0 や期限切れを赤帯表示            |
| Inventory List  | CRUD + CSV  | 検索・並べ替え・CSV インポート          |
| Batch Detail    | ロット管理       | 有効期限と残量を編集                 |
| Invoice History | 帳票ダウンロード    | PDF / Excel & 生成ステータス      |
| Admin Auth      | Devise ログイン | :lockable \:timeoutable 有効 |

---

## 3. ユーザーシナリオ (Scenarios)

Joel のサンプル仕様 *WhatTimeIsIt.com* と同じく「３〜５個のストーリー」に絞ります ([Joel on Software][4])。

1. **S-1 在庫追加**
   *前提*：薬が納品された。
   *操作*：Dashboard → 「＋新規」→ 品名・数量を入力。
   *結果*：Inventory に行が追加され、InventoryLog に `delta=+N` が記録される。

2. **S-2 CSV 取込**
   *前提*：初期在庫を CSV で用意済み。
   *操作*：Inventory List → 「CSV 取込」→ ファイル選択。
   *結果*：ImportInventoriesJob が非同期で走り、完了後 Toast 通知。

3. **S-3 請求書 PDF 生成**
   *前提*：月末締め。
   *操作*：Invoice History → 「＋新規」→ 在庫を１つ選択。
   *結果*：GenerateInvoiceJob が PDF を S3 に保存し、ステータスが `done` になる。

---

## 4. UI 仕様 (User-Interface Design)

Joel は「ワイヤーフレームは必ず貼る。文字だけでは誤解が生まれる」と強調します ([Joel on Software][5])。
ここではキーボードでも操作できる"キーボードファースト"を前提にレイアウトを記述。
（実線の枠は Figma モックで別紙提供）

### 4.1 Inventory List

| 要素    | 説明                                            |        |        |
| ----- | --------------------------------------------- | ------ | ------ |
| 検索バー  | キーワードで name LIKE 検索、Enter で実行                 |        |        |
| テーブル  | `name / quantity / price / status / actions`  |        |        |
| 行色    | `quantity <= 0` → `bg-amber-200 text-red-600` |        |        |
| アクション | ✏️ 編集                                         | 🗑️ 削除 | 📦 ロット |

**アクセシビリティ**

* `aria-label` を全ボタンに付与。
* 色弱対応でアイコン＋色の二重表現。

### 4.2 Login

| 要素       | 説明                                          |
| -------- | ------------------------------------------- |
| Email    | HTML5 `type=email` + client-side validation |
| Password | `minlength="12"` + zxcvbn 強度バー              |
| Lockout  | 5 回失敗で `unlock_token` メール                   |

---

## 5. 非 UI 仕様 (Non-UI Features)

| ID  | 機能           | 詳細                                                                |
| --- | ------------ | ----------------------------------------------------------------- |
| N-1 | パスワードポリシー    | 12 文字以上、英大/英小/数字必須 ([Joel on Software][2])                        |
| N-2 | :lockable    | 5 回失敗 → 15 分ロック ([Joel on Software][2])                           |
| N-3 | :timeoutable | 30 分無操作でセッション破棄 ([wayfdigital.com][6])                            |
| N-4 | 外部キー制約       | `ON DELETE CASCADE` で Batch を巻き込み削除                               |
| N-5 | ロット UNIQUE   | `(inventory_id, lot_code)` 複合一意 ([Joel on Software][5])           |
| N-6 | 金額精度         | `DECIMAL(10,2)` で桁あふれ防止 ([modernanalyst.com][7], [bawiki.com][8]) |
| N-7 | パフォーマンス      | 95%tile 応答 < 300 ms（ローカル）                                         |

---

## 6. オープン課題 (Open Issues)

| #   | 課題                   | 所感                                                            |
| --- | -------------------- | ------------------------------------------------------------- |
| O-1 | 2FA を TOTP で導入するか    | `devise-two-factor` を検証中 ([Joel on Software][9])              |
| O-2 | CSV 1 万行超の Import 戦略 | `insert_all` vs `activerecord-import` 比較 ([SpringerLink][10]) |
| O-3 | S3 署名 URL 期限         | 24 h か 7 d か要決定                                               |

---

## 7. 非対象 (Out of Scope)

* SNS ログイン（Google, LINE など）
* 患者向け User 画面
* 発注書自動生成（将来拡張）

Joel は「やらないことを必ず書け。決定を先送りすること自体が決定だ」と述べています ([Joel on Software][1])。

---

## 8. 変更履歴 (Revision History)

| 版   | 日付         | 変更   | 著者        |
| --- | ---------- | ---- | --------- |
| 0.1 | 2025-05-14 | 初版作成 | K. Suzuki |

---

## 9. 付録 (References & Tips)

* Joel Spolsky: *Painless Functional Specifications* 全 4 回 ([Joel on Software][1], [Joel on Software][2], [Joel on Software][5], [Joel on Software][3])
* 実サンプル **WhatTimeIsIt.com** 仕様書 ([Joel on Software][4])
* Functional Spec 書き方まとめ記事 ([wayfdigital.com][6])
* GitHub テンプレート集 ([GitHub][11])

---

### ✅ 次のアクション

1. この仕様書を Obsidian の `/projects/phardoc/` に保存。
2. WBS の「Inventory & Batch モデル」タスクに **Spec Ready** ラベルを付与。
3. 実装開始時は本書を随時更新し、変更履歴を Increment。

Joel 流に言えば *"コードを書くより仕様を変える方が 100 倍安い"*—
疑問が浮かんだら即座にこのドキュメントを直し、コーヒーをもう一杯どうぞ ☕。

[1]: https://www.joelonsoftware.com/2000/10/02/painless-functional-specifications-part-1-why-bother/?utm_source=chatgpt.com "Painless Functional Specifications – Part 1: Why Bother?"
[2]: https://www.joelonsoftware.com/2000/10/03/painless-functional-specifications-part-2-whats-a-spec/?utm_source=chatgpt.com "Painless Functional Specifications – Part 2: What's a Spec?"
[3]: https://www.joelonsoftware.com/2000/10/04/painless-functional-specifications-part-3-but-how/?utm_source=chatgpt.com "Painless Functional Specifications – Part 3: But… How?"
[4]: https://www.joelonsoftware.com/whattimeisit/?utm_source=chatgpt.com "WhatTimeIsIt - Joel on Software"
[5]: https://www.joelonsoftware.com/2000/10/15/painless-functional-specifications-part-4-tips/?utm_source=chatgpt.com "Painless Functional Specifications – Part 4: Tips - Joel on Software"
[6]: https://www.wayfdigital.com/blog/how-to-write-great-functional-specifications-according-to-joel-spolsky?utm_source=chatgpt.com "How to Write Great Functional Specifications, According to Joel ..."
[7]: https://www.modernanalyst.com/Resources/Articles/tabid/115/ID/46/Painless-Functional-Specifications--Part-1-Why-Bother.aspx?utm_source=chatgpt.com "Painless Functional Specifications - Part 1: Why Bother? > Business ..."
[8]: https://www.bawiki.com/blog/20160918_Recommended_Reading-Painless_Functional_Specifications.html?utm_source=chatgpt.com "Recommended Reading: Painless Functional Specifications | Blog"
[9]: https://www.joelonsoftware.com/author/joelonsoftware/page/12/?utm_source=chatgpt.com "Joel Spolsky – Page 12 - Joel on Software"
[10]: https://link.springer.com/chapter/10.1007/978-1-4302-0753-5_5?utm_source=chatgpt.com "Painless Functional Specifications Part 1: Why Bother? - SpringerLink"
[11]: https://github.com/joelparkerhenderson/functional-specifications-template?utm_source=chatgpt.com "joelparkerhenderson/functional-specifications-template - GitHub"

## 🔧 開発・運用計画

### 📋 実装済み機能のTODO

#### ヘルパー機能の改善（完了）
- [x] ビューファイル内のヘルパーメソッド定義を適切なヘルパーファイルに移動
- [x] AdminControllers::InventoriesHelper への統合
- [x] ソートアイコン機能の追加
- [x] 重複ヘルパーファイルの削除

#### 緊急対応が必要な機能（優先度：高）

##### 📊 CSVインポート機能の改善
- [ ] ファイル形式バリデーション（サイズ制限：10MB、MIME type、文字エンコーディング）
- [ ] カラム数・形式の事前検証
- [ ] エラーハンドリングの強化（部分的失敗時の処理）
- [ ] インポート進捗の詳細表示

##### 🔔 在庫アラート機能
- [ ] 在庫切れ時の自動メール送信（管理者・担当者向け）
- [ ] 期限切れ商品のアラートメール（バッチ期限管理連携）
- [ ] 低在庫アラート（設定可能な閾値ベース）
- [ ] ActionMailer + Sidekiq による配信システム

##### 🏷️ バッチ管理機能
- [ ] バッチ詳細ページの実装
- [ ] バッチCRUD機能の追加
- [ ] 期限切れアラート機能
- [ ] 先入先出（FIFO）自動消費機能

#### 中期開発計画（優先度：中）

##### 📈 レポート・分析機能
- [ ] 在庫一括操作機能（一括ステータス変更、一括削除）
- [ ] 在庫レポート機能（月次・年次レポート、在庫回転率）
- [ ] エクスポート機能（PDF、Excel、CSV）
- [ ] 在庫履歴・監査ログ機能
- [ ] KPI ダッシュボード機能

##### 🔐 セキュリティ・認証強化
- [ ] APIレート制限機能
- [ ] 認証機能強化（2FA対応）
- [ ] 監査証跡の暗号化保存
- [ ] ログの改ざん防止機能（ハッシュチェーン）

##### 🌍 国際化・拡張性
- [ ] 多言語対応（i18n）
- [ ] 多通貨対応システム
- [ ] タイムゾーン対応の強化
- [ ] プラットフォーム非依存性の向上

#### 長期開発計画（優先度：低）

##### 🤖 AI・機械学習機能
- [ ] 需要予測AIの実装
- [ ] 異常検知・不正検出システム
- [ ] 最適化アルゴリズムによる自動補充
- [ ] 画像認識による在庫確認システム

##### 🌐 IoT・ブロックチェーン連携
- [ ] RFID/NFCタグとの連携
- [ ] センサーによる自動在庫監視
- [ ] ブロックチェーンによるサプライチェーン透明性
- [ ] スマートコントラクトによる自動決済

##### 🏗️ アーキテクチャ進化
- [ ] マイクロサービス化
- [ ] イベント駆動アーキテクチャの導入
- [ ] ゼロトラストセキュリティアーキテクチャ
- [ ] 量子暗号化対応

### 🛠️ 技術的負債解消計画

#### フロントエンド刷新
- [ ] React/Vue.js による SPA 化
- [ ] PWA (Progressive Web App) 対応
- [ ] レスポンシブデザインの完全対応
- [ ] アクセシビリティ向上（WCAG 2.1 AA準拠）

#### バックエンド最適化
- [ ] N+1クエリの完全解消
- [ ] データベースインデックス最適化
- [ ] キャッシュ戦略の実装（Redis活用）
- [ ] 非同期処理の拡充（Sidekiq活用）

#### インフラ・DevOps
- [ ] コンテナ化の完全対応（Docker/Kubernetes）
- [ ] CI/CD パイプラインの強化
- [ ] 自動テストカバレッジ向上（目標：90%以上）
- [ ] パフォーマンス監視システム構築

### 📝 コード品質向上計画

#### テスト戦略
- [ ] 単体テストカバレッジ向上
- [ ] 統合テストの充実
- [ ] E2Eテストの自動化
- [ ] パフォーマンステストの実装

#### コードレビュー・静的解析
- [ ] 静的解析ツールの導入（RuboCop、Brakeman）
- [ ] 自動コードレビューの設定
- [ ] コーディング規約の策定・遵守
- [ ] 技術文書の充実

### 🌱 持続可能性・ESG対応

#### 環境配慮機能
- [ ] カーボンフットプリント計算
- [ ] 循環経済への対応機能
- [ ] 廃棄物削減最適化
- [ ] ESG報告書の自動生成

#### コンプライアンス対応
- [ ] GDPR対応（データポータビリティ、削除権）
- [ ] SOX法対応（監査証跡）
- [ ] 各国規制への対応機能
- [ ] 定期的なコンプライアンスチェック

### 📊 メトリクス・KPI

#### 開発効率指標
- [ ] コード品質メトリクス（複雑度、重複率）
- [ ] デプロイ頻度・リードタイム
- [ ] 障害復旧時間（MTTR）
- [ ] テストカバレッジ率

#### ビジネス指標
- [ ] システム稼働率（目標：99.9%）
- [ ] ユーザー満足度調査
- [ ] 在庫管理効率向上率
- [ ] コスト削減効果測定

---

**注意事項:**
- 各機能の実装優先度は事業要件に応じて調整してください
- セキュリティ関連機能は必ず実装前にセキュリティ監査を実施してください
- 大規模な変更の際は必ずバックアップを取得し、段階的なロールアウトを実施してください
