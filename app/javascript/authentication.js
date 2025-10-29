// 🔐 認証画面専用JavaScript - Bootstrap + Turbo対応
// CLAUDE.md準拠: インラインスクリプトの外部化でCSP対応とメンテナンス性向上
// メタ認知: 認証機能の確実な動作保証とセキュリティ強化

// Turbo対応のイベントリスナー設定
document.addEventListener('turbo:load', initializeAuthenticationPage);
document.addEventListener('DOMContentLoaded', initializeAuthenticationPage);

function initializeAuthenticationPage() {
  // 認証ページでない場合は処理を停止
  if (!document.querySelector('.gradient-bg') && !document.querySelector('#loginTabs')) {
    console.log('ℹ️ [Authentication] Not an authentication page, skipping initialization');
    return;
  }
  
  console.log('🔐 [Authentication] Authentication page detected, starting initialization...');
  
  // 即座にタブ機能を有効化（遅延なし）
  console.log('🔧 [Authentication] Starting immediate tab initialization...');
  initializeTabsImmediately();
  
  // Bootstrap Tab初期化（フォールバック）
  setTimeout(() => {
    console.log('🔧 [Authentication] Starting delayed Bootstrap tab initialization...');
    try {
      if (typeof bootstrap !== 'undefined' && bootstrap.Tab) {
        console.log('📦 [Authentication] Bootstrap available, using Bootstrap Tab implementation');
        initializeAuthTabs();
      } else {
        console.log('🔧 [Authentication] Bootstrap not available, using manual implementation');
        setupManualAuthTabs();
      }
    } catch (error) {
      console.error('❌ [Authentication] Bootstrap initialization failed:', error);
      setupManualAuthTabs();
    }
  }, 100);
  
  // パスコード認証機能の初期化
  console.log('📧 [Authentication] Initializing passcode authentication...');
  initializePasscodeAuth();
  
  // フォームバリデーション設定
  console.log('🔍 [Authentication] Setting up form validation...');
  initializeFormValidation();
  
  // 初期フォーカス設定
  console.log('🎯 [Authentication] Setting initial focus...');
  setInitialFocus();
  
  console.log('✅ [Authentication] All authentication features initialized successfully');
}

// 即座にタブ機能を有効化（最優先処理）
function initializeTabsImmediately() {
  const tabElements = document.querySelectorAll('[data-bs-toggle="tab"]');
  
  if (tabElements.length === 0) {
    console.log('ℹ️ No tab elements found for immediate initialization');
    return;
  }
  
  console.log(`🚀 [Authentication] Immediate tab initialization for ${tabElements.length} elements`);
  
  // 全てのタブ要素に即座にクリックイベントを設定
  tabElements.forEach((tabElement, index) => {
    console.log(`⚡ Setting up immediate handler for tab ${index + 1}: ${tabElement.id || 'unnamed'}`);
    
    // 既存のイベントリスナーを削除してクリーン状態にする
    const newElement = tabElement.cloneNode(true);
    tabElement.parentNode.replaceChild(newElement, tabElement);
    
    // 新しい要素にイベントリスナーを設定
    setupImmediateTabHandler(newElement);
  });
  
  console.log('✅ [Authentication] Immediate tab handlers set up successfully');
}

// 個別タブ要素の即座の設定
function setupImmediateTabHandler(tabElement) {
  // クリックイベント
  tabElement.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    console.log(`👆 [ImmediateTab] Click detected on: ${this.id || 'unnamed'}`);
    handleAuthTabToggle(this);
  });
  
  // キーボードイベント
  tabElement.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      console.log(`⌨️ [ImmediateTab] Keyboard activation on: ${this.id || 'unnamed'}`);
      handleAuthTabToggle(this);
    }
  });
  
  // マウスイベント（視覚的フィードバック）
  tabElement.addEventListener('mouseenter', function() {
    if (!this.classList.contains('active')) {
      this.style.backgroundColor = '#f8f9fa';
    }
  });
  
  tabElement.addEventListener('mouseleave', function() {
    if (!this.classList.contains('active')) {
      this.style.backgroundColor = '';
    }
  });
  
  console.log(`✅ [ImmediateTab] Handler set up for: ${tabElement.id || 'unnamed'}`);
}

// Bootstrap タブ初期化（認証画面専用）
function initializeAuthTabs() {
  const tabElements = document.querySelectorAll('[data-bs-toggle="tab"]');
  
  if (tabElements.length === 0) {
    console.log('ℹ️ No tab elements found for Bootstrap initialization');
    return;
  }
  
  console.log(`🔐 [Authentication] Found ${tabElements.length} tab elements for Bootstrap initialization`);
  
  tabElements.forEach((element, index) => {
    try {
      // 既存インスタンス重複防止（確実な初期化のため）
      const existingInstance = bootstrap.Tab.getInstance(element);
      if (existingInstance) {
        console.log(`🔄 [Authentication] Disposing existing tab instance: ${element.id || 'unnamed'}`);
        existingInstance.dispose();
      }
      
      // 新しいTabインスタンス作成
      const tab = new bootstrap.Tab(element);
      console.log(`✅ [Authentication] Bootstrap Tab ${index + 1} initialized: ${element.id || 'unnamed'}`);
      
      // パスコードタブ特定ログ（重要な機能）
      if (element.id === 'passcode-tab') {
        console.log('🎯 [Authentication] Passcode tab Bootstrap initialized - critical feature ready');
      }
      
    } catch (error) {
      console.error(`❌ [Authentication] Tab ${index + 1} Bootstrap initialization failed:`, error);
      console.log(`🔧 [Authentication] Element ${index + 1} already has manual handler`);
    }
  });
  
  console.log('🎯 [Authentication] Bootstrap tabs initialization completed');
}

// 手動タブ機能（フォールバック）
function setupManualAuthTabs() {
  const tabElements = document.querySelectorAll('[data-bs-toggle="tab"]');
  
  console.log(`🔧 [Authentication] Setting up manual tabs for ${tabElements.length} elements`);
  
  tabElements.forEach((tabElement, index) => {
    console.log(`🔧 Setting up manual tab ${index + 1}: ${tabElement.id || 'unnamed'}`);
    setupManualTabForElement(tabElement);
  });
  
  console.log('✅ [Authentication] Manual auth tabs setup completed');
}

// 個別タブ要素の手動設定
function setupManualTabForElement(tabElement) {
  // 重複防止チェック
  if (tabElement.dataset.manualTabSetup === 'true') {
    console.log(`ℹ️ Manual tab already set up for: ${tabElement.id || 'unnamed'}`);
    return;
  }
  
  tabElement.addEventListener('click', function(e) {
    e.preventDefault();
    e.stopPropagation();
    console.log(`👆 [ManualTab] Click on: ${this.id || 'unnamed'}`);
    handleAuthTabToggle(this);
  });
  
  tabElement.addEventListener('keydown', function(e) {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      e.stopPropagation();
      console.log(`⌨️ [ManualTab] Keyboard on: ${this.id || 'unnamed'}`);
      handleAuthTabToggle(this);
    }
  });
  
  // 設定完了マーク
  tabElement.dataset.manualTabSetup = 'true';
  console.log(`✅ Manual tab set up for: ${tabElement.id || 'unnamed'}`);
}

// 認証タブ切り替え処理（改善版）
function handleAuthTabToggle(tabElement) {
  console.log(`🔄 [AuthTab] === Starting tab toggle for: ${tabElement.id || 'unnamed'} ===`);
  
  const targetSelector = tabElement.getAttribute('data-bs-target') || tabElement.getAttribute('href');
  console.log(`🔄 [AuthTab] Target selector: ${targetSelector}`);
  
  if (!targetSelector) {
    console.error('❌ [AuthTab] No target selector found');
    return;
  }
  
  const targetPane = document.querySelector(targetSelector);
  console.log(`🔄 [AuthTab] Target pane found: ${!!targetPane}`);
  
  if (!targetPane) {
    console.error(`❌ [AuthTab] Target pane not found: ${targetSelector}`);
    return;
  }
  
  try {
    // 同一グループの全タブを非アクティブ化
    const tabContainer = tabElement.closest('.nav-tabs');
    if (tabContainer) {
      console.log('🔄 [AuthTab] Deactivating all tabs in container');
      const allTabs = tabContainer.querySelectorAll('.nav-link');
      allTabs.forEach(tab => {
        tab.classList.remove('active');
        tab.setAttribute('aria-selected', 'false');
        tab.style.backgroundColor = ''; // マウスオーバー色をリセット
        console.log(`  ➖ Deactivated: ${tab.id || 'unnamed'}`);
      });
      
      // 対応するタブパネルも非アクティブ化
      const allPanes = document.querySelectorAll('.tab-pane');
      allPanes.forEach(pane => {
        pane.classList.remove('show', 'active');
        console.log(`  ➖ Pane deactivated: ${pane.id || 'unnamed'}`);
      });
    }
    
    // 選択されたタブをアクティブ化
    tabElement.classList.add('active');
    tabElement.setAttribute('aria-selected', 'true');
    console.log(`✅ [AuthTab] Tab activated: ${tabElement.id || 'unnamed'}`);
    
    // 対応するタブパネルをアクティブ化
    targetPane.classList.add('show', 'active');
    console.log(`✅ [AuthTab] Pane activated: ${targetPane.id || 'unnamed'}`);
    
    // パスコードタブアクティベーション特定処理
    if (tabElement.id === 'passcode-tab') {
      console.log('🎯 [AuthTab] === PASSCODE TAB ACTIVATED ===');
      
      // パスコード入力フィールドにフォーカス（UX向上）
      setTimeout(() => {
        const emailField = targetPane.querySelector('input[type="email"]');
        if (emailField) {
          emailField.focus();
          console.log('📧 [AuthTab] Passcode email field focused');
        } else {
          console.log('⚠️ [AuthTab] Passcode email field not found');
        }
      }, 100);
      
      // パスコードフォームのリセット
      resetPasscodeForm();
    }
    
    // パスワードタブアクティベーション特定処理
    if (tabElement.id === 'password-tab') {
      console.log('🔑 [AuthTab] === PASSWORD TAB ACTIVATED ===');
      
      setTimeout(() => {
        const emailField = targetPane.querySelector('input[type="email"]');
        if (emailField) {
          emailField.focus();
          console.log('📧 [AuthTab] Password email field focused');
        }
      }, 100);
    }
    
    console.log(`✅ [AuthTab] === Tab switch completed successfully: ${tabElement.id || 'unnamed'} ===`);
    
  } catch (error) {
    console.error('❌ [AuthTab] Tab toggle failed:', error);
  }
}

// パスコード認証機能の初期化
function initializePasscodeAuth() {
  const passcodeRequestForm = document.getElementById('passcode-request-form');
  if (passcodeRequestForm) {
    passcodeRequestForm.addEventListener('submit', handlePasscodeRequest);
  }

  // パスコード入力フィールドの処理
  const passcodeField = document.querySelector('input[name="temp_password_verification[temp_password]"]');
  if (passcodeField) {
    setupPasscodeField(passcodeField);
  }
}

// パスコード送信処理
function handlePasscodeRequest(e) {
  e.preventDefault();
  
  const formData = new FormData(this);
  const email = formData.get('email');
  
  if (!email) {
    showAlert('メールアドレスを入力してください', 'warning');
    return;
  }
  
  console.log('📧 Requesting passcode for:', email);
  
  // パスコード送信処理（JSON API使用）
  fetch(this.action, {
    method: 'POST',
    body: formData,
    headers: {
      'X-Requested-With': 'XMLHttpRequest',
      'Accept': 'application/json',
      'Content-Type': 'application/x-www-form-urlencoded',
      'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').getAttribute('content')
    }
  })
  .then(response => {
    console.log('📡 Response status:', response.status);
    console.log('📡 Response headers:', response.headers);
    
    // HTTPステータスをチェック
    if (!response.ok) {
      console.error(`❌ HTTP Error: ${response.status} ${response.statusText}`);
      
      // レスポンスがJSONかHTMLかをチェック
      const contentType = response.headers.get('content-type');
      if (contentType && contentType.includes('application/json')) {
        return response.json().then(data => {
          throw new Error(data.error || `サーバーエラー (${response.status})`);
        });
      } else {
        throw new Error(`ネットワークエラー: ${response.status} ${response.statusText}`);
      }
    }
    
    // レスポンスタイプの確認
    const contentType = response.headers.get('content-type');
    console.log('📡 Content-Type:', contentType);
    
    if (contentType && contentType.includes('application/json')) {
      return response.json();
    } else {
      // HTMLレスポンス（リダイレクト）の場合
      console.log('🔄 HTML response detected, likely redirect');
      return response.text().then(html => {
        // 成功と見なす（メール送信完了後のリダイレクト）
        return { 
          success: true, 
          message: '一時パスワードを送信しました。メールをご確認ください。',
          redirect_url: response.url 
        };
      });
    }
  })
  .then(data => {
    console.log('✅ Response data:', data);
    
    if (data.success) {
      console.log('✅ Passcode sent successfully');
      
      // redirect_urlが提供された場合はリダイレクト
      if (data.redirect_url) {
        console.log('🔗 Redirecting to:', data.redirect_url);
        window.location.href = data.redirect_url;
        return;
      }
      
      // Step 2を表示（フォールバック）
      const step1 = document.getElementById('passcode-step1');
      const step2 = document.getElementById('passcode-step2');
      
      if (step1 && step2) {
        step1.style.display = 'none';
        step2.style.display = 'block';
        
        const emailField = document.getElementById('passcode_verify_email');
        if (emailField) {
          emailField.value = email;
        }
        
        // パスコード入力フィールドにフォーカス
        const passcodeField = document.querySelector('#passcode-verify-form input[name="temp_password_verification[temp_password]"]');
        if (passcodeField) {
          passcodeField.focus();
        }
      }
      
      // 成功メッセージを表示
      showAlert(data.message || '一時パスワードを送信しました。メールをご確認ください。', 'success');
      
    } else {
      console.warn('⚠️ Request failed:', data.error);
      showAlert(data.error || data.message || 'パスコードの送信に失敗しました', 'error');
    }
  })
  .catch(error => {
    console.error('💥 Request error:', error);
    
    // より具体的なエラーメッセージ
    let errorMessage = 'ネットワークエラーが発生しました';
    
    if (error.message) {
      if (error.message.includes('Failed to fetch')) {
        errorMessage = 'インターネット接続を確認してください';
      } else if (error.message.includes('500')) {
        errorMessage = 'サーバーエラーが発生しました。しばらくしてからお試しください';
      } else if (error.message.includes('404')) {
        errorMessage = 'ページが見つかりません。ページを更新してお試しください';
      } else {
        errorMessage = error.message;
      }
    }
    
    showAlert(errorMessage, 'error');
  });
}

// パスコード入力フィールドの設定
function setupPasscodeField(passcodeField) {
  // 入力値の自動フォーマット
  passcodeField.addEventListener('input', function(e) {
    // 数字以外を削除
    this.value = this.value.replace(/[^0-9]/g, '');
    
    // 6桁入力完了時の視覚フィードバック
    if (this.value.length === 6) {
      this.classList.add('border-success');
      this.classList.remove('border-secondary');
      console.log('✅ 6-digit passcode entered');
    } else {
      this.classList.remove('border-success');
      this.classList.add('border-secondary');
    }
  });

  // ペースト時の処理
  passcodeField.addEventListener('paste', function(e) {
    e.preventDefault();
    const pastedText = (e.clipboardData || window.clipboardData).getData('text');
    const numbers = pastedText.replace(/[^0-9]/g, '').slice(0, 6);
    this.value = numbers;
    
    // inputイベントをトリガー
    const event = new Event('input', { bubbles: true });
    this.dispatchEvent(event);
    
    console.log('📋 Passcode pasted and formatted');
  });
  
  // フォーカス時に全選択
  passcodeField.addEventListener('focus', function() {
    this.select();
  });
}

// フォームバリデーション設定
function initializeFormValidation() {
  const forms = document.querySelectorAll('.needs-validation');
  Array.from(forms).forEach(function(form) {
    form.addEventListener('submit', function(event) {
      if (!form.checkValidity()) {
        event.preventDefault();
        event.stopPropagation();
      }
      form.classList.add('was-validated');
    });
  });
}

// 初期フォーカス設定
function setInitialFocus() {
  // パスワードログインタブがアクティブな場合、メールフィールドにフォーカス
  const passwordTab = document.getElementById('password-tab');
  const passwordLoginPane = document.getElementById('password-login');
  
  if (passwordTab && passwordTab.classList.contains('active')) {
    setTimeout(() => {
      const emailField = passwordLoginPane.querySelector('input[type="email"]');
      if (emailField) {
        emailField.focus();
      }
    }, 100);
  }
}

// パスコードフォームをリセットする関数
function resetPasscodeForm() {
  console.log('🔄 Resetting passcode form');
  document.getElementById('passcode-step2').style.display = 'none';
  document.getElementById('passcode-step1').style.display = 'block';
  
  const form = document.getElementById('passcode-request-form');
  if (form) {
    form.reset();
    const emailField = form.querySelector('input[type="email"]');
    if (emailField) {
      emailField.focus();
    }
  }
}

// アラート表示関数
function showAlert(message, type = 'info') {
  console.log(`🔔 Alert [${type}]: ${message}`);
  
  // Bootstrap Toast が利用可能な場合は使用
  if (typeof bootstrap !== 'undefined' && bootstrap.Toast) {
    showBootstrapToast(message, type);
    return;
  }
  
  // フォールバック: 改良されたアラート表示
  showCustomAlert(message, type);
}

// Bootstrap Toast表示
function showBootstrapToast(message, type) {
  try {
    // Toast用のHTMLを動的生成
    const toastHtml = `
      <div class="toast align-items-center text-white bg-${getBootstrapColorClass(type)} border-0" 
           role="alert" aria-live="assertive" aria-atomic="true">
        <div class="d-flex">
          <div class="toast-body">
            ${escapeHtml(message)}
          </div>
          <button type="button" class="btn-close btn-close-white me-2 m-auto" 
                  data-bs-dismiss="toast" aria-label="Close"></button>
        </div>
      </div>
    `;
    
    // Toast コンテナを取得または作成
    let toastContainer = document.getElementById('toast-container');
    if (!toastContainer) {
      toastContainer = document.createElement('div');
      toastContainer.id = 'toast-container';
      toastContainer.className = 'toast-container position-fixed top-0 end-0 p-3';
      toastContainer.style.zIndex = '9999';
      document.body.appendChild(toastContainer);
    }
    
    // Toast要素を追加
    toastContainer.insertAdjacentHTML('beforeend', toastHtml);
    const toastElement = toastContainer.lastElementChild;
    
    // Bootstrap Toast インスタンス作成・表示
    const toast = new bootstrap.Toast(toastElement, {
      autohide: true,
      delay: type === 'error' ? 8000 : 5000
    });
    
    toast.show();
    
    // 表示後に要素を削除
    toastElement.addEventListener('hidden.bs.toast', () => {
      toastElement.remove();
    });
    
    console.log('✅ Bootstrap Toast displayed');
    
  } catch (error) {
    console.error('❌ Bootstrap Toast error:', error);
    showCustomAlert(message, type);
  }
}

// カスタムアラート表示（フォールバック）
function showCustomAlert(message, type) {
  // カスタムアラートボックスを作成
  const alertBox = document.createElement('div');
  alertBox.className = `alert alert-${getBootstrapColorClass(type)} alert-dismissible fade show position-fixed`;
  alertBox.style.cssText = 'top: 20px; left: 50%; transform: translateX(-50%); z-index: 9999; min-width: 300px; max-width: 500px;';
  alertBox.setAttribute('role', 'alert');
  
  alertBox.innerHTML = `
    ${escapeHtml(message)}
    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
  `;
  
  document.body.appendChild(alertBox);
  
  // 自動削除
  setTimeout(() => {
    if (alertBox.parentNode) {
      alertBox.classList.remove('show');
      setTimeout(() => alertBox.remove(), 150);
    }
  }, type === 'error' ? 8000 : 5000);
  
  console.log('✅ Custom alert displayed');
}

// Bootstrap カラークラス取得
function getBootstrapColorClass(type) {
  switch (type) {
    case 'success': return 'success';
    case 'error': return 'danger';
    case 'warning': return 'warning';
    case 'info': return 'info';
    default: return 'primary';
  }
}

// HTML エスケープ
function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// グローバル関数として公開（HTMLから呼び出し可能にする）
window.resetPasscodeForm = resetPasscodeForm;

// 🔥 緊急修正: 直接タブハンドラー追加（Bootstrap回避）
function addDirectTabHandlers() {
  console.log('🔧 [Authentication] Adding direct tab handlers...');
  
  const passcodeTab = document.getElementById('passcode-tab');
  const passwordTab = document.getElementById('password-tab');
  
  if (passcodeTab) {
    // 既存のイベントリスナーをクリア
    passcodeTab.removeAttribute('data-bs-toggle');
    
    // 直接クリックハンドラーを追加
    passcodeTab.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      console.log('🎯 [DirectHandler] Passcode tab clicked!');
      handleAuthTabToggle(this);
    });
    
    console.log('✅ [DirectHandler] Direct handler added to passcode tab');
  } else {
    console.error('❌ [DirectHandler] Passcode tab not found!');
  }
  
  if (passwordTab) {
    // 既存のイベントリスナーをクリア
    passwordTab.removeAttribute('data-bs-toggle');
    
    // 直接クリックハンドラーを追加
    passwordTab.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      console.log('🔑 [DirectHandler] Password tab clicked!');
      handleAuthTabToggle(this);
    });
    
    console.log('✅ [DirectHandler] Direct handler added to password tab');
  } else {
    console.error('❌ [DirectHandler] Password tab not found!');
  }
}

// デバッグ用: タブクリック診断機能
function addClickDiagnostics() {
  const passcodeTab = document.getElementById('passcode-tab');
  const passwordTab = document.getElementById('password-tab');
  
  if (passcodeTab) {
    console.log('🔍 [Debug] Passcode tab element found:', passcodeTab);
    console.log('🔍 [Debug] Passcode tab computed style:', window.getComputedStyle(passcodeTab));
    
    // 直接クリックリスナーを追加して診断
    passcodeTab.addEventListener('click', function(e) {
      console.log('🔍 [Debug] Passcode tab CLICKED!', e);
      console.log('🔍 [Debug] Event target:', e.target);
      console.log('🔍 [Debug] Current target:', e.currentTarget);
    }, true); // キャプチャフェーズで確実に捕捉
    
    // マウスイベントも監視
    passcodeTab.addEventListener('mouseenter', () => {
      console.log('🔍 [Debug] Mouse entered passcode tab');
    });
    
    passcodeTab.addEventListener('mouseleave', () => {
      console.log('🔍 [Debug] Mouse left passcode tab');
    });
    
    console.log('✅ [Debug] Click diagnostics added to passcode tab');
  } else {
    console.error('❌ [Debug] Passcode tab element NOT FOUND!');
  }
  
  if (passwordTab) {
    passwordTab.addEventListener('click', function(e) {
      console.log('🔍 [Debug] Password tab clicked for comparison', e);
    }, true);
    console.log('✅ [Debug] Click diagnostics added to password tab');
  }
}

// 診断機能を遅延実行
setTimeout(() => {
  console.log('🔍 [Debug] Running click diagnostics...');
  addClickDiagnostics();
}, 500);

console.log("✅ Authentication JavaScript module loaded successfully");