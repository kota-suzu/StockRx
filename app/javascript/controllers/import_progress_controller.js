// frozen_string_literal: true

import { Controller } from "@hotwired/stimulus"
import consumer from "@rails/actioncable"

// CSVインポート進捗表示のためのStimulusコントローラー（ActionCable統合版）
export default class extends Controller {
  static targets = ["bar", "status", "progressText", "completionMessage"]
  static values = { 
    jobId: String,
    adminId: Number,
    importType: String
  }
  
  // ActionCableコンシューマーとチャンネル
  consumer = null
  adminChannel = null
  
  // 接続時の初期化処理
  connect() {
    console.log("ImportProgressController connected")
    this.element.classList.remove("hidden")
    this.initializeProgress()
    this.setupActionCable()
  }
  
  // 切断時のクリーンアップ
  disconnect() {
    console.log("ImportProgressController disconnecting")
    this.cleanupActionCable()
  }
  
  // ============================================
  // ActionCable セットアップ
  // ============================================
  setupActionCable() {
    // ActionCableコンシューマーの初期化
    this.consumer = consumer

    // AdminChannelへの接続
    this.adminChannel = this.consumer.subscriptions.create(
      { 
        channel: "AdminChannel",
        admin_id: this.adminIdValue
      },
      {
        connected: () => this.onCableConnected(),
        disconnected: () => this.onCableDisconnected(),
        received: (data) => this.onMessageReceived(data)
      }
    )
  }
  
  // ActionCable接続成功時
  onCableConnected() {
    console.log("Connected to AdminChannel")
    
    // CSV インポート進捗追跡を開始
    if (this.hasJobIdValue && this.jobIdValue) {
      this.adminChannel.perform("track_csv_import", {
        job_id: this.jobIdValue
      })
    }
    
    this.updateStatus("WebSocket接続完了 - リアルタイム監視開始")
  }
  
  // ActionCable接続切断時
  onCableDisconnected() {
    console.log("Disconnected from AdminChannel")
    this.updateStatus("接続が切断されました - 再接続を試行中...")
  }
  
  // メッセージ受信時の処理
  onMessageReceived(data) {
    console.log("ActionCable message received:", data)
    
    switch (data.type) {
      case "connection_established":
        this.handleConnectionEstablished(data)
        break
      case "csv_import_progress":
        this.handleProgress(data)
        break
      case "csv_import_complete":
        this.handleCompletion(data)
        break
      case "csv_import_error":
        this.handleError(data)
        break
      case "csv_import_status":
        this.handleStatusUpdate(data)
        break
      case "csv_import_not_found":
        this.handleNotFound(data)
        break
      default:
        console.log("Unknown message type:", data.type)
    }
  }
  
  // ============================================
  // メッセージハンドラー
  // ============================================
  handleConnectionEstablished(data) {
    this.updateStatus("接続完了 - インポート状況を監視中...")
  }
  
  handleProgress(data) {
    const progress = data.progress || 0
    this.updateProgressBar(progress)
    this.updateStatus(`進捗: ${progress}% 完了`)
  }
  
  handleCompletion(data) {
    this.updateProgressBar(100)
    this.updateStatus("インポート完了!")
    
    // 完了メッセージを表示
    if (this.hasCompletionMessageTarget) {
      this.completionMessageTarget.textContent = data.message || "CSVインポートが正常に完了しました"
      this.completionMessageTarget.classList.remove("hidden")
    }
    
    // 5秒後に成功ページにリダイレクト
    setTimeout(() => {
      window.location.href = "/admin/inventories"
    }, 5000)
  }
  
  handleError(data) {
    this.updateStatus(`エラー: ${data.message}`)
    this.element.classList.add("border-red-500", "bg-red-50")
    
    // リトライ情報を表示
    if (data.retry_count < data.max_retries) {
      this.updateStatus(`エラー発生 - 自動リトライ中 (${data.retry_count}/${data.max_retries})`)
    } else {
      this.updateStatus("インポートに失敗しました。管理者にお問い合わせください。")
    }
  }
  
  handleStatusUpdate(data) {
    const progress = data.progress || 0
    const status = data.status || "unknown"
    
    this.updateProgressBar(progress)
    
    switch (status) {
      case "running":
        this.updateStatus(`処理中: ${progress}% 完了`)
        break
      case "completed":
        this.handleCompletion(data)
        break
      case "failed":
        this.handleError(data)
        break
      default:
        this.updateStatus(`状態: ${status}`)
    }
  }
  
  handleNotFound(data) {
    this.updateStatus("インポートジョブが見つかりません")
    this.element.classList.add("border-yellow-500", "bg-yellow-50")
  }
  
  // ============================================
  // UI更新メソッド
  // ============================================
  updateProgressBar(progress) {
    if (this.hasBarTarget) {
      this.barTarget.style.width = `${Math.min(progress, 100)}%`
    }
    
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = `${progress}%`
    }
  }
  
  updateStatus(message) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
    }
    console.log("Status update:", message)
  }
  
  initializeProgress() {
    this.updateProgressBar(0)
    this.updateStatus("初期化中...")
  }
  
  // ============================================
  // フォールバック処理
  // ============================================
  fallbackToPolling() {
    console.log("Falling back to polling method")
    this.updateStatus("通常モードで監視中...")
    
    // ポーリングによる進捗確認（フォールバック）
    if (this.hasJobIdValue && this.jobIdValue) {
      this.pollProgress()
    }
  }
  
  pollProgress() {
    if (!this.hasJobIdValue) return
    
    fetch(`/admin/job_statuses/${this.jobIdValue}`)
      .then(response => response.json())
      .then(data => {
        this.updateProgressBar(data.progress)
        this.updateStatus(`進捗: ${data.progress}% (ポーリング)`)
        
        if (data.progress < 100 && data.status !== "failed") {
          setTimeout(() => this.pollProgress(), 2000)
        } else if (data.progress >= 100) {
          this.updateStatus("インポート完了")
          setTimeout(() => {
            window.location.href = "/admin/inventories"
          }, 3000)
        }
      })
      .catch(error => {
        console.error('Polling error:', error)
        this.updateStatus('進捗確認でエラーが発生しました')
      })
  }
  
  // ============================================
  // クリーンアップ
  // ============================================
  cleanupActionCable() {
    if (this.adminChannel) {
      this.adminChannel.unsubscribe()
      this.adminChannel = null
    }
    
    if (this.consumer) {
      this.consumer.disconnect()
      this.consumer = null
    }
  }
}

// ============================================
// TODO: 機能拡張計画（優先度：中）
// REF: doc/remaining_tasks.md - ユーザビリティ向上
// ============================================
// 1. 進捗表示の視覚的改善（優先度：中）
//    - CSS アニメーション効果の追加
//    - より詳細な状態表示機能
//    - エラー時の視覚的フィードバック強化
//    - 段階別プログレスバー（準備→処理→完了）
//
// function enhanceProgressVisuals() {
//   // プログレスバーにアニメーション追加
//   this.barTarget.style.transition = 'width 0.3s ease-in-out'
//   
//   // 段階別色分け
//   const progress = parseInt(this.progressTextTarget.textContent)
//   if (progress < 30) {
//     this.barTarget.className = 'h-2 bg-yellow-500 rounded-full transition-all'
//   } else if (progress < 70) {
//     this.barTarget.className = 'h-2 bg-blue-500 rounded-full transition-all'
//   } else {
//     this.barTarget.className = 'h-2 bg-green-500 rounded-full transition-all'
//   }
// }
//
// 2. ユーザビリティ向上（優先度：高）
//    - キャンセル機能の実装
//    - 一時停止・再開機能
//    - 詳細ログの表示機能
//    - エラー詳細の展開表示
//
// function addCancelFunctionality() {
//   // キャンセルボタンの追加
//   const cancelButton = document.createElement('button')
//   cancelButton.textContent = 'インポート中止'
//   cancelButton.className = 'btn btn-danger'
//   cancelButton.onclick = () => this.cancelImport()
//   
//   this.element.appendChild(cancelButton)
// }
//
// function cancelImport() {
//   if (confirm('インポートを中止しますか？')) {
//     fetch(`/admin/imports/${this.jobIdValue}/cancel`, { method: 'DELETE' })
//       .then(() => {
//         this.updateStatus('インポートが中止されました')
//         window.location.href = '/admin/inventories'
//       })
//   }
// }
//
// 3. マルチインポート対応（優先度：中）
//    - 複数ファイルの同時インポート
//    - インポート履歴の表示
//    - バッチ処理状況の一覧表示
//    - 優先度設定機能
//
// function handleMultipleImports() {
//   const importQueue = []
//   
//   // キューにインポートタスクを追加
//   this.addToQueue = (file, priority = 'normal') => {
//     importQueue.push({ file, priority, status: 'pending' })
//     this.updateQueueDisplay()
//   }
//   
//   // キューの表示更新
//   this.updateQueueDisplay = () => {
//     const queueElement = document.getElementById('import-queue')
//     queueElement.innerHTML = importQueue.map(item => 
//       `<div class="queue-item">${item.file.name} - ${item.status}</div>`
//     ).join('')
//   }
// }
//
// 4. 国際化・アクセシビリティ対応（優先度：低）
//    - 多言語メッセージ対応
//    - ローカライゼーション
//    - 文化圏別UI調整
//    - スクリーンリーダー対応
//
// function setupInternationalization() {
//   // 言語設定の取得
//   const locale = document.documentElement.lang || 'ja'
//   
//   // メッセージの多言語化
//   const messages = {
//     ja: {
//       initializing: '初期化中...',
//       connecting: '接続中...',
//       processing: '処理中',
//       completed: '完了',
//       error: 'エラー'
//     },
//     en: {
//       initializing: 'Initializing...',
//       connecting: 'Connecting...',
//       processing: 'Processing',
//       completed: 'Completed',
//       error: 'Error'
//     }
//   }
//   
//   this.getMessage = (key) => messages[locale]?.[key] || messages.ja[key]
// }
//
// 5. エラー処理・復旧機能の強化（優先度：高）
//    - 自動リトライ機能
//    - 部分インポート対応
//    - エラーレポート生成
//    - 手動復旧機能
//
// function enhanceErrorHandling() {
//   let retryCount = 0
//   const maxRetries = 3
//   
//   this.handleErrorWithRetry = (error) => {
//     retryCount++
//     
//     if (retryCount <= maxRetries) {
//       this.updateStatus(`エラー発生 - リトライ中 (${retryCount}/${maxRetries})`)
//       setTimeout(() => this.retryImport(), 5000)
//     } else {
//       this.showErrorDetails(error)
//       this.offerManualRecovery()
//     }
//   }
//   
//   this.showErrorDetails = (error) => {
//     const errorModal = document.createElement('div')
//     errorModal.innerHTML = `
//       <div class="error-details">
//         <h3>エラー詳細</h3>
//         <pre>${JSON.stringify(error, null, 2)}</pre>
//         <button onclick="this.downloadErrorReport(error)">
//           エラーレポートをダウンロード
//         </button>
//       </div>
//     `
//     document.body.appendChild(errorModal)
//   }
// }
//
// 6. パフォーマンス最適化（優先度：中）
//    - WebWorker による非同期処理
//    - メモリ使用量の最適化
//    - ネットワーク効率化
//    - キャッシュ機能
//
// function optimizePerformance() {
//   // WebWorker の活用
//   if (window.Worker) {
//     const worker = new Worker('/assets/import-worker.js')
//     
//     worker.postMessage({
//       type: 'process_data',
//       data: this.importData
//     })
//     
//     worker.onmessage = (event) => {
//       const { type, progress, result } = event.data
//       if (type === 'progress') {
//         this.updateProgressBar(progress)
//       }
//     }
//   }
//   
//   // メモリ効率化
//   this.cleanupUnusedData = () => {
//     // 不要なデータの削除
//     delete this.processedData
//     delete this.temporaryCache
//   }
// }
//
// 7. セキュリティ強化（優先度：高）
//    - CSRF トークン検証
//    - 入力値サニタイゼーション
//    - ファイル形式検証
//    - サイズ制限チェック
//
// function enhanceSecurity() {
//   // CSRF トークンの取得と検証
//   const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
//   
//   this.secureRequest = (url, options = {}) => {
//     return fetch(url, {
//       ...options,
//       headers: {
//         'X-CSRF-Token': csrfToken,
//         'Content-Type': 'application/json',
//         ...options.headers
//       }
//     })
//   }
//   
//   // ファイル検証
//   this.validateFile = (file) => {
//     const allowedTypes = ['text/csv', 'application/vnd.ms-excel']
//     const maxSize = 10 * 1024 * 1024 // 10MB
//     
//     if (!allowedTypes.includes(file.type)) {
//       throw new Error('許可されていないファイル形式です')
//     }
//     
//     if (file.size > maxSize) {
//       throw new Error('ファイルサイズが制限を超えています')
//     }
//   }
// } 