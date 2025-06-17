// JSコードのエントリーポイント
// Rails 7 importmap で使用されるメインJavaScriptファイル

// Rails標準のライブラリ
import "@hotwired/turbo-rails"
import "./controllers"

// Bootstrap 5 JavaScript
// CLAUDE.md準拠: Bootstrap JSインポート - インタラクティブ機能のため必須
// メタ認知: collapse, dropdown, modal, tooltip等の動的機能が依存
// 横展開: 全ての管理画面・店舗画面で共通使用
import "bootstrap"

// Turboとの互換性確保
// CLAUDE.md準拠: ベストプラクティス - Turbo環境でのBootstrap初期化
document.addEventListener("turbo:load", () => {
  // Bootstrap コンポーネントの初期化
  // メタ認知: Turboページ遷移後も動的コンポーネントが動作するよう再初期化
  initializeBootstrapComponents()
  
  // フラッシュメッセージが存在する場合は5秒後に自動的に消す
  const flashMessages = document.querySelectorAll(".flash-message")
  
  flashMessages.forEach((message) => {
    setTimeout(() => {
      message.classList.add("opacity-0")
      message.addEventListener("transitionend", () => {
        message.remove()
      })
    }, 5000)
  })
  
  // CSVインポート進捗表示の初期設定
  const progressElement = document.getElementById("csv-import-progress")
  if (progressElement && new URLSearchParams(window.location.search).get("import_started") === "true") {
    // インポート開始パラメータがある場合、進捗表示を表示
    progressElement.classList.remove("hidden")
  }
})

// Bootstrap コンポーネント初期化関数
// CLAUDE.md準拠: 横展開 - 全てのBootstrapコンポーネントで適用
function initializeBootstrapComponents() {
  // Tooltipの初期化
  const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
  tooltipTriggerList.map(function (tooltipTriggerEl) {
    return new bootstrap.Tooltip(tooltipTriggerEl)
  })
  
  // Popoverの初期化（必要に応じて）
  const popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'))
  popoverTriggerList.map(function (popoverTriggerEl) {
    return new bootstrap.Popover(popoverTriggerEl)
  })

  // TODO: 🟡 Phase 3（中）- Toastメッセージ機能の実装
  // 優先度: 中（UX向上）
  // 実装内容: 
  //   - 成功・エラーメッセージのトースト表示
  //   - 自動消去タイマー
  //   - スタック表示
  // 期待効果: ユーザーフィードバックの改善
}

// デバッグ用コンソールメッセージ
console.log("Application JavaScript loaded successfully") 