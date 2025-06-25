# StockRx Documentation

このディレクトリには、StockRxプロジェクトのすべてのドキュメントが整理されています。

## 📁 ディレクトリ構造

```
docs/
├── guides/                     # 実用的なガイド
│   ├── github_oauth_setup.md   # GitHub OAuth認証セットアップガイド
│   └── testing_guide.md        # テスト実行ガイド
├── design/                     # 設計ドキュメント
│   ├── api_design.md
│   ├── controller_structure.md
│   ├── inventory_management_design.md
│   ├── multi_store_management_design.md
│   └── ...
├── archive/                    # アーカイブされた古いドキュメント
│   └── 2024/
│       └── temporary_fixes/    # 一時的な修正ログ
└── README.md                   # このファイル
```

## 📚 主要ドキュメント

### セットアップ・運用ガイド
- [GitHub OAuth認証セットアップ](./guides/github_oauth_setup.md) - OAuth認証の設定手順とトラブルシューティング
- [テストガイド](./guides/testing_guide.md) - テストの実行方法と認証機能のテスト手順

### 設計ドキュメント
- [API設計](./design/api_design.md) - RESTful API設計仕様
- [コントローラー構造](./design/controller_structure.md) - AdminControllersモジュール設計
- [在庫管理設計](./design/inventory_management_design.md) - 在庫管理システムの設計
- [マルチストア管理設計](./design/multi_store_management_design.md) - 薬局チェーン向けSaaS設計

### その他の重要な情報
- [開発ガイドライン（CLAUDE.md）](../CLAUDE.md) - AI支援開発のためのプロジェクトガイド
- [プロジェクトREADME](../README.md) - プロジェクト概要とセットアップ手順

## 🔄 ドキュメント更新ガイドライン

1. **新しいガイドを追加する場合**: `guides/`ディレクトリに配置
2. **設計ドキュメントを追加する場合**: `design/`ディレクトリに配置
3. **古いドキュメントをアーカイブする場合**: `archive/YYYY/`に移動
4. **重複を避ける**: 既存のドキュメントを確認してから新規作成

## 📝 ドキュメント作成のベストプラクティス

- 明確で簡潔なタイトルを使用
- 目次（TOC）を含める
- コード例を豊富に含める
- 更新日時を記載する
- 関連ドキュメントへのリンクを含める

## 🗓️ 最終更新: 2025-06-25

---

質問や提案がある場合は、プロジェクトのissueトラッカーにお寄せください。