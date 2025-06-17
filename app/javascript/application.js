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
// CLAUDE.md準拠: ベストプラクティス - レイアウトファイルでの初期化を優先
document.addEventListener("turbo:load", () => {
  // 🔴 Phase 3（緊急）- 一時的に初期化を無効化
  // 理由: レイアウトファイルでの強制初期化と競合を避ける
  // TODO: デバッグ完了後に復元
  
  // Bootstrap 可用性確認のみ（初期化はレイアウト側で実行）
  if (typeof bootstrap !== 'undefined') {
    console.log('📦 Application.js: Bootstrap available, initialization handled by layout');
  } else {
    console.warn('⚠️ Application.js: Bootstrap not available');
    setupManualDropdown();
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

// 手動ドロップダウン機能（フォールバック）
// CLAUDE.md準拠: シンプルで確実なフォールバック実装
function setupManualDropdown() {
  console.log('🔧 Setting up manual dropdown fallback...');
  
  // 各ドロップダウンに手動機能を設定
  document.querySelectorAll('.dropdown-toggle').forEach(toggle => {
    setupManualDropdownForElement(toggle);
  });
  
  // 外部クリック時にドロップダウンを閉じる
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.dropdown')) {
      document.querySelectorAll('.dropdown-menu').forEach(menu => {
        menu.classList.remove('show');
        menu.style.display = 'none';
      });
    }
  });
  
  console.log('✅ Manual dropdown fallback ready');
}

// Bootstrap コンポーネント初期化関数
// CLAUDE.md準拠: シンプルで確実な初期化アプローチ
function initializeBootstrapComponents() {
  console.log('🔧 Initializing Bootstrap components...');
  
  // ドロップダウンの初期化
  const dropdownElements = document.querySelectorAll('.dropdown-toggle');
  if (dropdownElements.length > 0) {
    console.log(`📍 Found ${dropdownElements.length} dropdown elements`);
    
    dropdownElements.forEach((element, index) => {
      try {
        // 既存インスタンスの重複防止
        const existingInstance = bootstrap.Dropdown.getInstance(element);
        if (existingInstance) {
          existingInstance.dispose();
        }
        
        // 新しいドロップダウンインスタンス作成
        new bootstrap.Dropdown(element);
        console.log(`✅ Dropdown ${index + 1} initialized: ${element.id || 'unnamed'}`);
        
      } catch (error) {
        console.error(`❌ Dropdown ${index + 1} initialization failed:`, error);
        // フォールバック設定
        setupManualDropdownForElement(element);
      }
    });
  }
  
  // ツールチップの初期化
  const tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"]');
  if (tooltipElements.length > 0) {
    tooltipElements.forEach(element => {
      try {
        new bootstrap.Tooltip(element);
      } catch (error) {
        console.error('Tooltip initialization failed:', error);
      }
    });
    console.log(`✅ ${tooltipElements.length} tooltips initialized`);
  }
  
  // ポップオーバーの初期化
  const popoverElements = document.querySelectorAll('[data-bs-toggle="popover"]');
  if (popoverElements.length > 0) {
    popoverElements.forEach(element => {
      try {
        new bootstrap.Popover(element);
      } catch (error) {
        console.error('Popover initialization failed:', error);
      }
    });
    console.log(`✅ ${popoverElements.length} popovers initialized`);
  }
  
  console.log('🎯 Bootstrap components initialization completed');
}

// 個別要素用の手動ドロップダウン設定
// CLAUDE.md準拠: シンプルで確実なフォールバック機能
function setupManualDropdownForElement(toggle) {
  console.log('🔧 Setting up manual dropdown for:', toggle.id || 'unnamed');
  
  toggle.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    
    // ドロップダウンメニューを探す（親要素内）
    const parent = this.closest('.dropdown');
    const dropdownMenu = parent ? parent.querySelector('.dropdown-menu') : this.nextElementSibling;
    
    if (dropdownMenu && dropdownMenu.classList.contains('dropdown-menu')) {
      const isCurrentlyOpen = dropdownMenu.classList.contains('show');
      
      // 全てのドロップダウンを閉じる
      document.querySelectorAll('.dropdown-menu').forEach(menu => {
        menu.classList.remove('show');
        menu.style.display = 'none';
      });
      
      // 現在のドロップダウンをトグル
      if (!isCurrentlyOpen) {
        dropdownMenu.classList.add('show');
        dropdownMenu.style.display = 'block';
        console.log(`👆 Manual dropdown opened: ${this.id || 'unnamed'}`);
      } else {
        console.log(`👆 Manual dropdown closed: ${this.id || 'unnamed'}`);
      }
    }
  });
}

// デバッグ用コンソールメッセージ
console.log("Application JavaScript loaded successfully") 