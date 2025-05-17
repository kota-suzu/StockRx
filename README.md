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

## 開発ガイドライン

### コード構造

- 管理者機能のコントローラは `AdminControllers` モジュール内に定義
- モデルとコントローラの名前空間の衝突に注意（`Admin`モデルと`Admin`モジュールは共存できない）
- モジュール名とディレクトリ構造を一致させる（例: `AdminControllers` → `app/controllers/admin_controllers/`）
- 詳細な設計ガイドラインは `docs/design/` ディレクトリを参照

### 命名規則

- モデル: 単数形、キャメルケース（例: `Admin`, `InventoryItem`）
- コントローラ: 複数形、キャメルケース（例: `AdminControllers::ItemsController`）
- テーブル: 複数形、スネークケース（例: `admins`, `inventory_items`）

## 重要な注意事項

- **名前空間とディレクトリ構造**: Railsのオートロード機能は名前空間とディレクトリ構造の一致を前提としています
  - コントローラ名前空間はファイルパスに反映する必要があります
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
- [ ] 在庫アラート機能（在庫切れ・期限切れ）
- [ ] バーコードスキャン対応

### レポート機能
- [ ] 在庫レポート生成
- [ ] 利用状況分析
- [ ] データエクスポート機能（CSV/Excel）

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
