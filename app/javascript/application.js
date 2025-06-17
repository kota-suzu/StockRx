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
  
  // TODO: 🔴 Phase 1（緊急）- CDN フォールバック機能
  // 優先度: 最高（ネットワーク問題対策）
  // 実装内容: Bootstrap CDN 接続失敗時の代替手段
  // 横展開: 全てのCDNリソースで適用検討
  
  // Bootstrap availability check
  if (typeof bootstrap === 'undefined') {
    console.warn('🚨 Bootstrap not loaded! Attempting manual initialization...');
    
    // Manual dropdown toggle as fallback
    setupManualDropdown();
  } else {
    console.log('✅ Bootstrap loaded successfully');
    initializeBootstrapComponents();
  }
  
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

// TODO: 🔴 Phase 1（緊急）- 手動ドロップダウン機能（フォールバック）
// 優先度: 最高（Bootstrap読み込み失敗時の代替）
// 実装内容: JavaScript無しでもドロップダウンが動作する機能
// メタ認知: プログレッシブエンハンスメントの原則に従う
function setupManualDropdown() {
  console.log('🔧 Setting up manual dropdown fallback...');
  
  document.querySelectorAll('.dropdown-toggle').forEach(toggle => {
    toggle.addEventListener('click', function(e) {
      e.preventDefault();
      
      const dropdownMenu = this.nextElementSibling;
      if (dropdownMenu && dropdownMenu.classList.contains('dropdown-menu')) {
        const isOpen = dropdownMenu.style.display === 'block';
        
        // Close all other dropdowns
        document.querySelectorAll('.dropdown-menu').forEach(menu => {
          menu.style.display = 'none';
        });
        
        // Toggle current dropdown
        dropdownMenu.style.display = isOpen ? 'none' : 'block';
        
        console.log(`👆 Manual dropdown toggled: ${this.id} (${isOpen ? 'closed' : 'opened'})`);
      }
    });
  });
  
  // Close dropdown when clicking outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.dropdown')) {
      document.querySelectorAll('.dropdown-menu').forEach(menu => {
        menu.style.display = 'none';
      });
    }
  });
  
  console.log('✅ Manual dropdown fallback ready');
}

// Bootstrap コンポーネント初期化関数
// CLAUDE.md準拠: 横展開 - 全てのBootstrapコンポーネントで適用
function initializeBootstrapComponents() {
  // Dropdownの手動初期化（重要：これがないとドロップダウンが動作しない）
  // メタ認知：Bootstrap 5ではdata属性だけでは不十分な場合がある
  // TODO: 🔴 Phase 1（緊急）- ドロップダウン初期化の強化
  // 優先度: 最高（ユーザーログアウト機能に直結）
  // 実装内容: より堅牢な初期化処理とエラーハンドリング
  // 横展開: すべてのBootstrapコンポーネントで適用
  
  let dropdownCount = 0;
  let successCount = 0;
  let errorCount = 0;
  
  try {
    const dropdownElementList = [].slice.call(document.querySelectorAll('.dropdown-toggle'))
    dropdownCount = dropdownElementList.length;
    
    console.log(`🔧 Initializing ${dropdownCount} dropdown elements...`);
    
    dropdownElementList.forEach((dropdownToggleEl, index) => {
      try {
        // 既存のBootstrapインスタンスがある場合は削除
        const existingInstance = bootstrap.Dropdown.getInstance(dropdownToggleEl);
        if (existingInstance) {
          existingInstance.dispose();
        }
        
        // 新しいインスタンスを作成
        const dropdownInstance = new bootstrap.Dropdown(dropdownToggleEl);
        successCount++;
        
        console.log(`✅ Dropdown [${index}] initialized:`, dropdownToggleEl.id || dropdownToggleEl.className);
        
        // デバッグ用: クリックイベントの監視
        dropdownToggleEl.addEventListener('click', function(e) {
          console.log(`👆 Dropdown clicked: ${dropdownToggleEl.id}`);
        });
        
      } catch (error) {
        errorCount++;
        console.error(`❌ Failed to initialize dropdown [${index}]:`, error);
        console.error('Element:', dropdownToggleEl);
      }
    });
    
  } catch (globalError) {
    console.error('🚨 Critical error in dropdown initialization:', globalError);
  }
  
  // Tooltipの初期化
  let tooltipCount = 0;
  try {
    const tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'))
    tooltipCount = tooltipTriggerList.length;
    tooltipTriggerList.map(function (tooltipTriggerEl) {
      return new bootstrap.Tooltip(tooltipTriggerEl)
    })
  } catch (error) {
    console.error('❌ Tooltip initialization error:', error);
  }
  
  // Popoverの初期化（必要に応じて）
  let popoverCount = 0;
  try {
    const popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'))
    popoverCount = popoverTriggerList.length;
    popoverTriggerList.map(function (popoverTriggerEl) {
      return new bootstrap.Popover(popoverTriggerEl)
    })
  } catch (error) {
    console.error('❌ Popover initialization error:', error);
  }

  // TODO: 🟡 Phase 3（中）- Toastメッセージ機能の実装
  // 優先度: 中（UX向上）
  // 実装内容: 
  //   - 成功・エラーメッセージのトースト表示
  //   - 自動消去タイマー
  //   - スタック表示
  // 期待効果: ユーザーフィードバックの改善
  
  // デバッグ用：Bootstrap初期化成功確認
  console.log("🎯 Bootstrap components initialization summary:", {
    dropdowns: `${successCount}/${dropdownCount} (${errorCount} errors)`,
    tooltips: tooltipTriggerList.length,
    popovers: popoverTriggerList.length,
    bootstrapVersion: bootstrap.Tooltip.VERSION || 'unknown'
  });
  
  // エラーが発生した場合の追加デバッグ情報
  if (errorCount > 0) {
    console.warn(`⚠️  ${errorCount} dropdowns failed to initialize. Check console for details.`);
    console.log('💡 Troubleshooting tips:');
    console.log('   1. Check if Bootstrap CSS is loaded');
    console.log('   2. Verify data-bs-toggle="dropdown" attributes');
    console.log('   3. Ensure dropdown menu structure is correct');
  }
}

// デバッグ用コンソールメッセージ
console.log("Application JavaScript loaded successfully") 