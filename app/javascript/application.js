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

// 認証画面専用JavaScript
// CLAUDE.md準拠: インラインスクリプト外部化でCSP対応
// メタ認知: 認証機能の分離でメンテナンス性向上
import "authentication"

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
  
  // 🔐 認証ページ判定（メタ認知: JavaScript初期化競合回避）
  // 横展開: 認証画面は専用のauthentication.jsで初期化
  if (isAuthenticationPage()) {
    console.log('🔐 Authentication page detected, delegating tab initialization to authentication.js');
    // 認証ページではタブ以外のコンポーネントのみ初期化
    initializeNonTabComponents();
    return;
  }
  
  // タブの初期化（一般ページ用）
  const tabElements = document.querySelectorAll('[data-bs-toggle="tab"]');
  if (tabElements.length > 0) {
    console.log(`📍 Found ${tabElements.length} tab elements`);
    
    tabElements.forEach((element, index) => {
      try {
        // 既存インスタンスの重複防止（Turbo互換性）
        const existingInstance = bootstrap.Tab.getInstance(element);
        if (existingInstance) {
          existingInstance.dispose();
        }
        
        // 新しいタブインスタンス作成
        const tab = new bootstrap.Tab(element);
        console.log(`✅ Tab ${index + 1} initialized: ${element.id || 'unnamed'}`);
        
      } catch (error) {
        console.error(`❌ Tab ${index + 1} initialization failed:`, error);
        // フォールバック設定（確実なタブ機能確保）
        setupManualTabForElement(element);
      }
    });
  } else {
    console.log('ℹ️ No tab elements found on this page');
  }
  
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
    console.log('ℹ️ No dropdown elements found on this page');
  }
  
  // ツールチップ・ポップオーバー初期化（共通関数使用）
  initializeTooltipsAndPopovers();
  
  console.log('🎯 Bootstrap components initialization completed');
  
  // TODO: 🟡 Phase 4（拡張）- 追加Bootstrapコンポーネント対応
  // 優先度: 中（機能拡張時）
  // 実装内容:
  //   - Modal自動初期化（CSVインポート進捗ダイアログなど）
  //   - Toast通知システム（成功・エラーメッセージ表示）
  //   - Offcanvas対応（モバイル向けサイドメニュー）
  // 横展開: 管理者画面・店舗画面で統一的なUI体験
}

// 個別要素用の手動タブ設定（フォールバック）
// CLAUDE.md準拠: 確実なフォールバック機能でタブ機能保証
function setupManualTabForElement(tabElement) {
  console.log('🔧 Setting up manual tab for:', tabElement.id || 'unnamed');
  
  tabElement.addEventListener('click', function(e) {
    e.preventDefault();
    handleTabToggle(this);
  });
  
  // キーボードアクセシビリティ
  tabElement.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      handleTabToggle(this);
    }
  });
}

// タブトグル処理の共通化
function handleTabToggle(tabElement) {
  const targetSelector = tabElement.getAttribute('data-bs-target') || tabElement.getAttribute('href');
  const targetPane = document.querySelector(targetSelector);
  
  if (!targetPane) {
    console.error('Tab target not found:', targetSelector);
    return;
  }
  
  // 同一グループの全タブを非アクティブ化
  const tabContainer = tabElement.closest('.nav-tabs');
  if (tabContainer) {
    tabContainer.querySelectorAll('.nav-link').forEach(tab => {
      tab.classList.remove('active');
      tab.setAttribute('aria-selected', 'false');
    });
    
    // 対応するタブパネルも非アクティブ化
    const allPanes = document.querySelectorAll('.tab-pane');
    allPanes.forEach(pane => {
      pane.classList.remove('show', 'active');
    });
  }
  
  // 選択されたタブをアクティブ化
  tabElement.classList.add('active');
  tabElement.setAttribute('aria-selected', 'true');
  
  // 対応するタブパネルをアクティブ化
  targetPane.classList.add('show', 'active');
  
  console.log(`👆 Manual tab activated: ${tabElement.id || 'unnamed'} -> ${targetSelector}`);
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
        console.log('🚪 Logout dropdown opened successfully');
      }
    } else {
      console.log(`👆 Manual dropdown closed: ${toggle.id || 'unnamed'}`);
    }
  } else {
    console.error('Dropdown menu not found for toggle:', toggle.id || 'unnamed');
  }
}

// TODO: 🔴 Phase 2（必須）- タブ機能フォールバック強化
// 優先度: 高（基本機能）
// 実装内容:
//   - ✅ Bootstrap Tab初期化追加完了
//   - ⏳ キーボードナビゲーション強化（矢印キー対応）
//   - ⏳ ARIA属性の完全対応
//   - ⏳ アニメーション効果の追加
// 横展開: 全ての認証画面で統一的なタブ動作
// 期待効果: パスコードログイン機能の確実な動作保証

// TODO: 🟡 Phase 3（改善）- ログイン体験向上
// 優先度: 中（ユーザー体験）
// 実装内容:
//   - パスコード自動フォーカス機能
//   - フォーム送信状態の視覚的フィードバック
//   - エラーメッセージの改善
//   - ローディングインジケーター追加
// 期待効果: ユーザビリティ向上、操作ミス防止

// ============================================
// 認証ページ判定とタブ初期化競合回避機能
// ============================================
// CLAUDE.md準拠: メタ認知 - JavaScript初期化の重複防止
// 横展開: 認証画面専用初期化の確実な分離

// 認証ページ判定関数
function isAuthenticationPage() {
  // 複数の判定条件で確実な認証ページ検出
  return !!(
    document.querySelector('.gradient-bg') ||        // 店舗ログイン画面
    document.querySelector('#loginTabs') ||          // 認証タブ
    document.querySelector('.auth-page') ||          // 明示的な認証ページクラス
    document.querySelector('#passcode-tab') ||       // パスコードタブ
    window.location.pathname.includes('/sign_in') || // ログインパス
    window.location.pathname.includes('/auth')       // 認証関連パス
  );
}

// 非タブコンポーネント初期化（認証ページ用）
function initializeNonTabComponents() {
  console.log('🔐 Initializing non-tab components for authentication page...');
  
  // ドロップダウンの初期化（認証ページでも必要な場合）
  const dropdownElements = document.querySelectorAll('.dropdown-toggle');
  if (dropdownElements.length > 0) {
    console.log(`📍 Found ${dropdownElements.length} dropdown elements on auth page`);
    
    dropdownElements.forEach((element, index) => {
      try {
        const existingInstance = bootstrap.Dropdown.getInstance(element);
        if (existingInstance) {
          existingInstance.dispose();
        }
        
        const dropdown = new bootstrap.Dropdown(element);
        console.log(`✅ Auth page dropdown ${index + 1} initialized: ${element.id || 'unnamed'}`);
        
      } catch (error) {
        console.error(`❌ Auth page dropdown ${index + 1} initialization failed:`, error);
        setupManualDropdownForElement(element);
      }
    });
  }
  
  // ツールチップ・ポップオーバー初期化（認証ページでも使用される可能性）
  initializeTooltipsAndPopovers();
  
  console.log('✅ Non-tab components initialized for authentication page');
}

// ツールチップ・ポップオーバー初期化（共通関数）
function initializeTooltipsAndPopovers() {
  // ツールチップの初期化
  const tooltipElements = document.querySelectorAll('[data-bs-toggle="tooltip"]');
  if (tooltipElements.length > 0) {
    tooltipElements.forEach(element => {
      try {
        const existingInstance = bootstrap.Tooltip.getInstance(element);
        if (existingInstance) {
          existingInstance.dispose();
        }
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
        const existingInstance = bootstrap.Popover.getInstance(element);
        if (existingInstance) {
          existingInstance.dispose();
        }
        new bootstrap.Popover(element);
      } catch (error) {
        console.error('Popover initialization failed:', error);
      }
    });
    console.log(`✅ ${popoverElements.length} popovers initialized`);
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