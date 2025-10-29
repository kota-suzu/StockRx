# モダンデザイン要件定義書 - /stores ページ刷新

## CLAUDE.md準拠: メタ認知的設計アプローチ

### 📋 現状分析（Phase 1）

#### 技術的課題
- ❌ **デザインシステム不統一**: Font Awesome（店舗選択）vs Bootstrap Icons（管理画面）
- ❌ **視覚階層不明確**: 単調なカード配置、色彩コントラスト不足
- ❌ **インタラクション不足**: 静的なボタン、フィードバックなし
- ❌ **レスポンシブ設計**: モバイルファーストでない、タッチフレンドリーでない

#### UX/ビジネス課題
- ❌ **認知負荷高い**: 店舗選択の重要性が視覚的に伝わらない
- ❌ **操作効率低い**: クリック可能領域が小さい、最近使用店舗が目立たない
- ❌ **ブランド価値低い**: 古いデザインによる信頼性への影響

### 🎨 モダンデザイン要件（Phase 2-3）

#### 1. カラーシステム設計
```scss
// プライマリカラー（企業ブランド）
$primary-gradient: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
$primary-shadow: 0 10px 30px -12px rgba(102, 126, 234, 0.4);

// セマンティックカラー（機能別）
$success-gradient: linear-gradient(135deg, #4ade80 0%, #22c55e 100%);
$warning-gradient: linear-gradient(135deg, #fbbf24 0%, #f59e0b 100%);
$danger-gradient: linear-gradient(135deg, #f87171 0%, #ef4444 100%);

// ニュートラルカラー（情報階層）
$surface-elevation-1: rgba(255, 255, 255, 0.95);
$surface-elevation-2: rgba(255, 255, 255, 0.8);
$glass-effect: backdrop-filter: blur(10px);
```

#### 2. タイポグラフィシステム
```scss
// ヘッダー階層
.display-1 { font-size: 3rem; font-weight: 700; line-height: 1.2; }
.heading-1 { font-size: 2rem; font-weight: 600; line-height: 1.3; }
.heading-2 { font-size: 1.5rem; font-weight: 500; line-height: 1.4; }

// 本文・UIテキスト
.body-large { font-size: 1.125rem; line-height: 1.6; }
.body-medium { font-size: 1rem; line-height: 1.5; }
.caption { font-size: 0.875rem; line-height: 1.4; font-weight: 500; }
```

#### 3. インタラクションデザイン
```scss
// ホバー・フォーカス状態
.interactive-card {
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
  &:hover {
    transform: translateY(-8px) scale(1.02);
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.25);
  }
}

// ボタンアニメーション
.btn-modern {
  position: relative;
  overflow: hidden;
  &::before {
    content: '';
    position: absolute;
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.4), transparent);
    transition: transform 0.6s;
    transform: translateX(-100%);
  }
  &:hover::before {
    transform: translateX(100%);
  }
}
```

#### 4. レイアウトシステム
```scss
// Grid System（CSS Grid採用）
.store-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  gap: 2rem;
  
  @media (max-width: 768px) {
    grid-template-columns: 1fr;
    gap: 1rem;
  }
}

// Container Queries対応（未来対応）
.store-card {
  container-type: inline-size;
  &[style*="--card-width: small"] .card-content { flex-direction: column; }
}
```

### 🔧 技術実装戦略（Phase 3-4）

#### アイコンシステム統一
- **決定**: Bootstrap Icons 1.11.x に統一（管理画面との一貫性）
- **移行計画**: Font Awesome → Bootstrap Icons マッピング実装
- **フォールバック**: CDN + ローカルファイル併用

#### CSS Architecture
```
app/assets/stylesheets/
├── components/
│   ├── _store-selection.scss    # 店舗選択専用コンポーネント
│   ├── _modern-cards.scss       # モダンカードコンポーネント
│   └── _interactive-buttons.scss # インタラクティブボタン
├── utilities/
│   ├── _animations.scss         # アニメーション定義
│   ├── _gradients.scss          # グラデーション定義
│   └── _glass-morphism.scss     # ガラスモーフィズム効果
└── store_selection.scss         # メインスタイル
```

### 📱 レスポンシブ・アクセシビリティ要件（Phase 4）

#### ブレークポイント戦略
```scss
$breakpoints: (
  'mobile': 320px,   // モバイル最小
  'tablet': 768px,   // タブレット
  'desktop': 1024px, // デスクトップ
  'wide': 1440px     // ワイドスクリーン
);
```

#### アクセシビリティ要件
- **キーボードナビゲーション**: Tab/Enter/Space/Arrow対応
- **スクリーンリーダー**: aria-label、role、live-region設定
- **カラーコントラスト**: WCAG AA準拠（4.5:1以上）
- **フォーカス管理**: visible focus indicator、skip links

### 🚀 段階的実装計画

#### Phase 2: 基礎デザインシステム構築（1日）
1. ✅ カラーパレット・グラデーション定義
2. ✅ タイポグラフィシステム構築
3. ✅ Bootstrap Icons統一

#### Phase 3: コンポーネント実装（1-2日）
1. ✅ モダンカードコンポーネント
2. ✅ インタラクティブボタン
3. ✅ アニメーション・トランジション

#### Phase 4: レスポンシブ・A11y（1日）
1. ✅ モバイルファースト設計
2. ✅ アクセシビリティ対応
3. ✅ パフォーマンス最適化

#### Phase 5: 横展開・統一化（0.5日）
1. ✅ 他の店舗関連ページへの適用
2. ✅ デザインシステム文書化
3. ✅ コンポーネント再利用可能化

### 🔍 メタ認知チェックポイント

#### 設計判断の根拠
- **グラデーション採用**: 2024年トレンド、ブランド差別化、視覚階層構築
- **ガラスモーフィズム**: モダン感、軽やかさ、情報階層明確化
- **アニメーション**: ユーザビリティ向上、フィードバック強化

#### 将来への拡張性
- **コンポーネント再利用**: 他ページでの活用可能性
- **ブランディング**: ロゴ・CI変更時の柔軟性
- **国際化**: 多言語対応時のレイアウト適応性

### ⚠️ リスク・制約事項

#### 技術的制約
- **パフォーマンス**: CSS animation、backdrop-filter の古いブラウザ対応
- **アクセシビリティ**: 過度なアニメーションによる vestibular disorder 配慮
- **SEO**: JavaScript依存の最小化

#### ビジネス制約
- **ブランドガイドライン**: 既存CI/VIとの整合性確保
- **ユーザー習慣**: 既存ユーザーの操作パターン変更影響
- **保守性**: 複雑すぎるCSSによるメンテナンス性低下

### 📊 成功指標（KPI）

#### ユーザビリティ指標
- **Task Success Rate**: 店舗選択完了率 > 95%
- **Time on Task**: 平均選択時間 < 10秒
- **Error Rate**: 誤選択率 < 2%

#### 技術指標
- **Core Web Vitals**: LCP < 2.5s, FID < 100ms, CLS < 0.1
- **Accessibility Score**: Lighthouse Accessibility > 95
- **Performance Score**: Lighthouse Performance > 90

---

**実装方針**: 段階的実装による品質確保、横展開による一貫性維持、将来拡張性を考慮した設計