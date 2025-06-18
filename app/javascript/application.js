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
// CLAUDE.md準拠: ベストプラクティス - 確実なBootstrap初期化実装
document.addEventListener("turbo:load", () => {
  // 🔧 Bootstrap初期化の復活（CLAUDE.md準拠修正）
  // メタ認知: ユーザビリティ向上のため、ドロップダウン機能は必須
  // 横展開: 管理者画面・店舗画面で一貫した動作確保
  
  if (typeof bootstrap !== 'undefined') {
    console.log('📦 Application.js: Bootstrap available, initializing components...');
    initializeBootstrapComponents();
  } else {
    console.warn('⚠️ Application.js: Bootstrap not available, using fallback');
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
// CLAUDE.md準拠: 確実で堅牢な初期化アプローチ
function initializeBootstrapComponents() {
  console.log('🔧 Initializing Bootstrap components...');
  
  // ドロップダウンの初期化（メタ認知: ログアウト機能に必須）
  const dropdownElements = document.querySelectorAll('.dropdown-toggle');
  if (dropdownElements.length > 0) {
    console.log(`📍 Found ${dropdownElements.length} dropdown elements`);
    
    dropdownElements.forEach((element, index) => {
      try {
        // 既存インスタンスの重複防止（Turbo互換性）
        const existingInstance = bootstrap.Dropdown.getInstance(element);
        if (existingInstance) {
          existingInstance.dispose();
        }
        
        // 新しいドロップダウンインスタンス作成
        const dropdown = new bootstrap.Dropdown(element);
        console.log(`✅ Dropdown ${index + 1} initialized: ${element.id || 'unnamed'}`);
        
        // デバッグ: ログアウトボタン特定
        if (element.id === 'userDropdown') {
          console.log('🎯 User dropdown (logout functionality) initialized successfully');
        }
        
      } catch (error) {
        console.error(`❌ Dropdown ${index + 1} initialization failed:`, error);
        // フォールバック設定（確実なログアウト機能確保）
        setupManualDropdownForElement(element);
      }
    });
  } else {
    console.warn('⚠️ No dropdown elements found');
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
  
  // TODO: 🟡 Phase 4（拡張）- 追加Bootstrapコンポーネント対応
  // 優先度: 中（機能拡張時）
  // 実装内容:
  //   - Modal自動初期化（CSVインポート進捗ダイアログなど）
  //   - Toast通知システム（成功・エラーメッセージ表示）
  //   - Offcanvas対応（モバイル向けサイドメニュー）
  // 横展開: 管理者画面・店舗画面で統一的なUI体験
}

// 個別要素用の手動ドロップダウン設定
// CLAUDE.md準拠: 確実なフォールバック機能でログアウト機能保証
function setupManualDropdownForElement(toggle) {
  console.log('🔧 Setting up manual dropdown for:', toggle.id || 'unnamed');
  
  // アクセシビリティ強化: キーボード操作対応
  toggle.setAttribute('aria-haspopup', 'true');
  toggle.setAttribute('aria-expanded', 'false');
  
  // クリックイベント
  toggle.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    handleDropdownToggle(this);
  });
  
  // キーボードイベント（エンターキー・スペースキー対応）
  toggle.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleDropdownToggle(this);
    }
  });
}

// ドロップダウントグル処理の共通化
// CLAUDE.md準拠: メタ認知 - ログアウト機能の確実な動作保証
function handleDropdownToggle(toggle) {
  // ドロップダウンメニューを探す（親要素内）
  const parent = toggle.closest('.dropdown');
  const dropdownMenu = parent ? parent.querySelector('.dropdown-menu') : toggle.nextElementSibling;
  
  if (dropdownMenu && dropdownMenu.classList.contains('dropdown-menu')) {
    const isCurrentlyOpen = dropdownMenu.classList.contains('show');
    
    // 全てのドロップダウンを閉じる
    document.querySelectorAll('.dropdown-menu').forEach(menu => {
      menu.classList.remove('show');
      menu.style.display = 'none';
      // ARIAステートの更新
      const relatedToggle = menu.closest('.dropdown')?.querySelector('.dropdown-toggle');
      if (relatedToggle) {
        relatedToggle.setAttribute('aria-expanded', 'false');
      }
    });
    
    // 現在のドロップダウンをトグル
    if (!isCurrentlyOpen) {
      dropdownMenu.classList.add('show');
      dropdownMenu.style.display = 'block';
      toggle.setAttribute('aria-expanded', 'true');
      console.log(`👆 Manual dropdown opened: ${toggle.id || 'unnamed'}`);
      
      // ログアウト機能特定ログ
      if (toggle.id === 'userDropdown') {
        console.log('🎯 User dropdown (logout) opened via manual fallback');
      }
    } else {
      toggle.setAttribute('aria-expanded', 'false');
      console.log(`👆 Manual dropdown closed: ${toggle.id || 'unnamed'}`);
    }
  }
}

// デバッグ用コンソールメッセージ
console.log("✅ Application JavaScript loaded successfully");
console.log("🔧 Bootstrap dropdown functionality enabled for logout feature");

// TODO: 🔴 Phase 5（完了後）- Bootstrap初期化の継続監視
// 優先度: 高（品質保証）
// 実装内容:
//   - 各ページでBootstrap初期化成功の監視
//   - ドロップダウン機能エラーの自動検出と修復
//   - パフォーマンス影響の監視（初期化時間など）
// 横展開: ユーザビリティテストでの確認項目に追加 