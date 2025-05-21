# Rails 7.2 凍結配列問題と Rails 8.0 移行準備に関するドキュメント

## 凍結配列問題の背景

Rails 7.2では、パフォーマンス改善や安全性向上のため、設定に関連する配列が凍結されるようになりました。
この変更により、従来の方法で配列を変更しようとすると `FrozenError: can't modify frozen Array` というエラーが発生します。

## 現在の対応策

1. 初期化ファイル `config/initializers/000_rails_frozen_array_fix.rb` で凍結配列を安全に扱うためのモンキーパッチを導入

2. CI環境で特に問題が発生しやすいため、GitHub Actionsワークフローに以下の対策を実装:
   - キャッシュクリア
   - 環境変数設定 (`RAILS_AVOID_FREEZING_ARRAYS`, `RAILS_SAFE_ARRAY_OPERATIONS`等)
   - テスト失敗時の自動リトライ

3. 非推奨のenum構文を修正:
   - 古い形式: `enum :status, { active: 0, archived: 1 }`
   - 新しい形式: `enum status: { active: 0, archived: 1 }`

## Rails 8.0に向けた準備

Rails 8.0に向けて、以下の対応が必要になります:

1. **凍結配列対応の恒常化**:
   - すべての配列操作を非破壊的な形式に修正する（`<<`や`unshift`ではなく`+`や`+=`を使用）
   - モンキーパッチを削除し、正規の方法で配列操作を行う
   - `config/initializers/000_rails_array_safety.rb`と`config/initializers/000_rails_frozen_array_fix.rb`を削除

2. **モデル更新**:
   - `inventory_fixed.rb`のRails 8.0向け実装を`inventory.rb`に統合
   - その他の非推奨機能や構文の更新

3. **テスト強化**:
   - CI環境での特殊な対応を徐々に削減し、ローカル・CI両方で一貫した動作を実現

## 横展開すべき点

1. 配列を変更する操作をすべて見直し、非破壊的な方法に更新
2. すべてのモデルでenumの新しい構文を使用
3. CI/CD環境とローカル環境での動作の差異を最小化

## 参考資料

- [Rails 7.2 リリースノート](https://edgeguides.rubyonrails.org/7_2_release_notes.html)
- [Rails 8.0 アップグレードガイド（仮）](https://edgeguides.rubyonrails.org/upgrading_ruby_on_rails.html)
