# StockRx 設計ドキュメント

**最終更新**: 2025年5月28日  
**バージョン**: 1.0

## 概要

このディレクトリには、StockRxシステムの設計ドキュメントが含まれています。各ドキュメントは特定の機能領域やアーキテクチャ側面に焦点を当てています。

## ドキュメント一覧

### 🏗️ アーキテクチャ設計

#### [controller_structure.md](./controller_structure.md)
- **概要**: コントローラの設計ガイドライン
- **ステータス**: 実装済み
- **内容**: 名前空間構造、ディレクトリ規約、責務定義

#### [refactoring_summary.md](./refactoring_summary.md)
- **概要**: 名前空間リファクタリングの記録
- **ステータス**: 完了
- **内容**: AdminとAdminControllersの名前衝突解決

### 💼 ビジネスロジック

#### [inventory_management_design.md](./inventory_management_design.md) 🆕
- **概要**: 在庫管理システムの詳細設計
- **ステータス**: 実装中
- **内容**: データモデル、ビジネスロジック、API設計、セキュリティ

### ⚙️ バックグラウンド処理

#### [job_processing_design.md](./job_processing_design.md) 🆕
- **概要**: Sidekiqジョブ処理システムの設計
- **ステータス**: 実装済み・拡張中
- **内容**: ジョブパターン、キュー設計、監視、ベストプラクティス

#### [jobs/import_inventories_job_design.md](./jobs/import_inventories_job_design.md)
- **概要**: CSVインポートジョブの詳細設計
- **ステータス**: 実装済み
- **内容**: セキュリティ検証、進捗追跡、エラーハンドリング

### 🌐 API設計

#### [api_design.md](./api_design.md) 🆕
- **概要**: RESTful API設計書
- **ステータス**: v1稼働中、v2計画中
- **内容**: エンドポイント設計、認証、セキュリティ、バージョニング

## 設計原則

### 1. **セキュリティファースト**
- 全ての設計判断においてセキュリティを最優先
- 多層防御の実装
- 監査ログの完全性

### 2. **スケーラビリティ**
- 水平スケーリング対応
- マイクロサービス化を見据えた設計
- 非同期処理の活用

### 3. **保守性**
- コードの可読性と一貫性
- ドキュメントの継続的更新
- テスト駆動開発

### 4. **パフォーマンス**
- N+1問題の排除
- 適切なキャッシュ戦略
- データベースインデックス最適化

## ドキュメント規約

### ファイル構造
```
docs/design/
├── README.md                         # このファイル
├── controller_structure.md           # コントローラ設計
├── inventory_management_design.md    # 在庫管理設計
├── job_processing_design.md          # ジョブ処理設計
├── api_design.md                     # API設計
├── refactoring_summary.md            # リファクタリング記録
└── jobs/
    └── import_inventories_job_design.md  # 個別ジョブ設計
```

### ドキュメントフォーマット
各設計ドキュメントには以下のセクションを含める：

1. **メタデータ**
   - 最終更新日
   - バージョン
   - ステータス（計画中/実装中/実装済み/廃止）

2. **概要**
   - 目的と範囲
   - 主要機能

3. **詳細設計**
   - アーキテクチャ
   - データモデル
   - 実装詳細

4. **セキュリティ考慮事項**
5. **パフォーマンス最適化**
6. **テスト戦略**
7. **ベストプラクティス**
8. **今後の拡張計画**

## 関連ドキュメント

### 運用ドキュメント（../doc/）
- [actioncable_integration_guide.md](../../doc/actioncable_integration_guide.md)
- [error_handling_guide.md](../../doc/error_handling_guide.md)
- [http_status_implementation.md](../../doc/http_status_implementation.md)
- [remaining_tasks.md](../../doc/remaining_tasks.md)

### 開発計画
- [development_plan.md](../development_plan.md)
- [devise_admin_setup.md](../devise_admin_setup.md)

## 更新履歴

### 2025年5月28日
- 初版作成
- inventory_management_design.md 追加
- job_processing_design.md 追加
- api_design.md 追加
- 既存ドキュメントの更新（優先度とフェーズ情報追加）

## コントリビューション

設計ドキュメントを追加・更新する際は：
1. 上記のドキュメントフォーマットに従う
2. メタデータを最新に保つ
3. 関連するコードのTODOコメントに参照を追加
4. このREADME.mdのインデックスを更新

## 次のステップ

### Phase 1（1-2週間）
- [ ] セキュリティ設計書の作成
- [ ] データベース設計書の作成
- [ ] 認証・認可設計の詳細化

### Phase 2（2-3週間）
- [ ] フロントエンド設計書の作成
- [ ] テスト戦略ドキュメントの作成
- [ ] デプロイメント設計書の作成

### Phase 3（1-2ヶ月）
- [ ] マイクロサービス移行計画
- [ ] パフォーマンス最適化ガイド
- [ ] 災害復旧計画