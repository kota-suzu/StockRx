# 役割定義とレビュー基準

## 1. 役割定義詳細

### PM（プロジェクトマネージャー）

#### 主要責務
1. **品質保証の最終責任者**
   - 全てのリリースの品質を保証
   - 品質基準の策定と更新
   - 品質問題のエスカレーション対応

2. **プロジェクト管理**
   - スケジュール管理
   - リソース配分の最適化
   - ステークホルダーとのコミュニケーション

3. **リスク管理**
   - 技術的リスクの特定と対策
   - ビジネスリスクの評価
   - コンティンジェンシープランの策定

#### 必要スキル
- プロジェクト管理の実務経験5年以上
- 品質管理手法（ISO 9001等）の理解
- リーダーシップとコミュニケーション能力
- データ分析と意思決定能力

### PL（プロジェクトリーダー）

#### 主要責務
1. **技術的リーダーシップ**
   - アーキテクチャ設計の承認
   - 技術選定の最終決定
   - 技術的問題の解決支援

2. **開発標準の管理**
   - コーディング規約の策定
   - 開発プロセスの改善
   - ベストプラクティスの推進

3. **チーム育成**
   - 技術メンタリング
   - コードレビューを通じた指導
   - スキル向上計画の策定

#### 必要スキル
- 開発経験3年以上
- システム設計の実務経験
- 複数の技術スタックの知識
- 問題解決能力とメンタリングスキル

### Dev（開発者）

#### 主要責務
1. **実装責任**
   - 要件に基づく正確な実装
   - 高品質なコードの作成
   - 適切なエラーハンドリング

2. **テスト作成**
   - ユニットテストの完全性
   - 統合テストの作成
   - テストカバレッジの維持

3. **ドキュメント作成**
   - コードコメントの記載
   - API仕様書の作成
   - 実装ガイドの作成

#### 必要スキル
- プログラミング言語の熟練度
- テスト駆動開発の理解
- バージョン管理システムの使用経験
- 継続的学習への意欲

## 2. レビュー基準詳細

### コード品質評価基準

#### A. コーディング規約（20点）

**評価項目:**
1. **命名規則（5点）**
   - 変数名・メソッド名の明確性
   - クラス名の適切性
   - 定数の命名規則遵守

2. **コード構造（5点）**
   - 適切なインデント
   - 行長制限（80-120文字）
   - ファイル構成の論理性

3. **コメント（5点）**
   - 複雑なロジックの説明
   - TODOコメントの適切な使用
   - ドキュメントコメントの完備

4. **一貫性（5点）**
   - プロジェクト全体での統一性
   - 既存コードとの整合性
   - スタイルガイドの遵守

**採点基準:**
```ruby
# 自動評価スクリプト例
class CodingStandardsEvaluator
  def evaluate(file_path)
    rubocop_result = run_rubocop(file_path)
    
    score = case rubocop_result[:offense_count]
    when 0
      20
    when 1..5
      15
    when 6..10
      10
    when 11..20
      5
    else
      0
    end
    
    {
      score: score,
      details: rubocop_result[:offenses]
    }
  end
end
```

#### B. テストカバレッジ（25点）

**評価項目:**
1. **行カバレッジ（10点）**
   - 90%以上: 10点
   - 80-89%: 7点
   - 70-79%: 4点
   - 70%未満: 0点

2. **分岐カバレッジ（10点）**
   - 全分岐網羅: 10点
   - 主要分岐網羅: 7点
   - 部分的網羅: 4点
   - 不十分: 0点

3. **エッジケース（5点）**
   - 境界値テスト実装
   - 異常系テスト実装
   - null/空値のテスト

**採点基準:**
```ruby
class TestCoverageEvaluator
  def evaluate(coverage_report)
    line_coverage_score = calculate_line_coverage_score(coverage_report[:line])
    branch_coverage_score = calculate_branch_coverage_score(coverage_report[:branch])
    edge_case_score = evaluate_edge_cases(coverage_report[:test_cases])
    
    {
      total_score: line_coverage_score + branch_coverage_score + edge_case_score,
      breakdown: {
        line_coverage: line_coverage_score,
        branch_coverage: branch_coverage_score,
        edge_cases: edge_case_score
      }
    }
  end
end
```

#### C. パフォーマンス（20点）

**評価項目:**
1. **応答時間（10点）**
   - 100ms以下: 10点
   - 100-200ms: 7点
   - 200-500ms: 4点
   - 500ms以上: 0点

2. **リソース使用量（5点）**
   - メモリ効率
   - CPU使用率
   - データベースクエリ最適化

3. **スケーラビリティ（5点）**
   - 同時接続数への対応
   - データ量増加への対応
   - 負荷分散の考慮

**採点基準:**
```ruby
class PerformanceEvaluator
  def evaluate(performance_metrics)
    response_time_score = calculate_response_time_score(performance_metrics[:avg_response_time])
    resource_score = calculate_resource_score(performance_metrics[:resource_usage])
    scalability_score = evaluate_scalability(performance_metrics[:load_test_results])
    
    {
      total_score: response_time_score + resource_score + scalability_score,
      recommendations: generate_performance_recommendations(performance_metrics)
    }
  end
end
```

#### D. セキュリティ（20点）

**評価項目:**
1. **脆弱性スキャン（10点）**
   - 脆弱性なし: 10点
   - 低リスクのみ: 7点
   - 中リスクあり: 3点
   - 高リスクあり: 0点

2. **認証・認可（5点）**
   - 適切な権限チェック
   - セッション管理
   - 入力検証

3. **データ保護（5点）**
   - 暗号化の実装
   - 機密情報の取り扱い
   - ログへの配慮

**採点基準:**
```ruby
class SecurityEvaluator
  def evaluate(code_changes)
    brakeman_score = run_brakeman_analysis(code_changes)
    auth_score = evaluate_authentication(code_changes)
    data_protection_score = evaluate_data_protection(code_changes)
    
    {
      total_score: brakeman_score + auth_score + data_protection_score,
      vulnerabilities: list_vulnerabilities(code_changes),
      recommendations: security_recommendations(code_changes)
    }
  end
end
```

#### E. ドキュメント（15点）

**評価項目:**
1. **API仕様書（5点）**
   - エンドポイント定義
   - リクエスト/レスポンス例
   - エラーコード一覧

2. **実装説明（5点）**
   - アーキテクチャ図
   - 処理フロー説明
   - 設計判断の記録

3. **運用ドキュメント（5点）**
   - デプロイ手順
   - 設定方法
   - トラブルシューティング

**採点基準:**
```ruby
class DocumentationEvaluator
  def evaluate(documentation)
    api_doc_score = evaluate_api_documentation(documentation[:api])
    implementation_score = evaluate_implementation_docs(documentation[:implementation])
    operation_score = evaluate_operation_docs(documentation[:operation])
    
    {
      total_score: api_doc_score + implementation_score + operation_score,
      missing_sections: identify_missing_sections(documentation),
      quality_assessment: assess_documentation_quality(documentation)
    }
  end
end
```

## 3. レビュープロセスのSOP

### ステップ1: 自己レビュー（開発者）
1. コードの動作確認
2. テストの実行と確認
3. セルフチェックリストの完了
4. プルリクエストの作成

### ステップ2: ピアレビュー（他の開発者）
1. コードの可読性確認
2. ロジックの妥当性検証
3. テストケースの網羅性確認
4. 改善提案の記載

### ステップ3: テクニカルレビュー（PL）
1. アーキテクチャ適合性の確認
2. 技術的債務の評価
3. パフォーマンス影響の確認
4. セキュリティリスクの評価

### ステップ4: 最終承認（PM）
1. ビジネス要件との整合性確認
2. 品質スコアの確認（85点以上）
3. リリース影響の評価
4. 承認またはフィードバック

## 4. エスカレーションルール

### レベル1: 軽微な問題
- 対応: 開発者間で解決
- 期限: 24時間以内
- 例: コーディング規約違反、軽微なバグ

### レベル2: 中程度の問題
- 対応: PLへエスカレーション
- 期限: 48時間以内
- 例: 設計変更が必要、パフォーマンス問題

### レベル3: 重大な問題
- 対応: PMへ即座にエスカレーション
- 期限: 即時対応
- 例: セキュリティ脆弱性、データ損失リスク

## 5. 継続的改善

### 月次レビュー会議
1. レビュー統計の分析
2. 共通問題の特定
3. プロセス改善の提案
4. 基準の見直し

### 四半期評価
1. チーム全体の品質向上度
2. 個人のスキル向上評価
3. ツールとプロセスの効果測定
4. 次四半期の目標設定

### 年次見直し
1. 役割定義の妥当性評価
2. レビュー基準の更新
3. 新技術への対応
4. 組織全体への展開