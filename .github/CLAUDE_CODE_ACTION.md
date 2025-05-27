# Claude Code GitHub Action

このGitHub Actionは、PR やイシューのコメントで `@claude` メンションを使用してClaude Codeを実行できるようにします。

## セットアップ

### 1. 必要なシークレットの設定

リポジトリの Settings > Secrets and variables > Actions で以下のシークレットを設定してください：

- `ANTHROPIC_API_KEY`: Anthropic APIキー（Claude APIへのアクセスに必要）

### 2. 使い方

#### イシューでの使用

イシューの本文またはコメントで以下のように記述します：

```
@claude この関数のバグを修正してください
```

#### PRでの使用

PRの本文またはレビューコメントで以下のように記述します：

```
@claude このコードをリファクタリングしてください
```

### 3. 動作の流れ

1. `@claude` メンションを含むコメントが投稿される
2. GitHub ActionがトリガーされClaude Codeが実行される
3. コードに変更がある場合：
   - イシューの場合：新しいブランチを作成してPRを作成
   - PRの場合：現在のブランチに直接コミット
4. 実行結果がコメントとして投稿される

### 4. 権限

このActionは以下の権限を必要とします：

- `contents: write` - コードの変更をコミット
- `issues: write` - イシューへのコメント投稿
- `pull-requests: write` - PRの作成とコメント投稿

### 5. 注意事項

- Claude CLIがインストールされている必要があります
- APIキーの使用量に注意してください
- 生成されたコードは必ずレビューしてからマージしてください