import { Controller } from "@hotwired/stimulus"

// CSVインポート進捗表示のためのStimulusコントローラー
export default class extends Controller {
  static targets = ["bar", "status"]
  static values = { jobId: String }
  
  // 接続時の初期化処理
  connect() {
    this.element.classList.remove("hidden")
    this.setupEventSource()
  }
  
  // 切断時のクリーンアップ
  disconnect() {
    if (this.eventSource) {
      this.eventSource.close()
    }
  }
  
  // Server-Sent Events（SSE）のセットアップ
  setupEventSource() {
    // インポートジョブのステータスを取得するために、
    // 現在は未実装のため、代替としてポーリングを使用
    this.pollProgress()
  }
  
  // 進捗状況をポーリングで取得（実際の実装では、ActionCable/SSEを使用する方が望ましい）
  pollProgress() {
    // デモンストレーション用に進捗をシミュレート
    this.simulateProgress()
    
    // 実際の実装では、以下のようにAPIエンドポイントにポーリングします
    /*
    if (this.hasJobIdValue) {
      fetch(`/admin/job_statuses/${this.jobIdValue}`)
        .then(response => response.json())
        .then(data => {
          this.updateProgress(data.progress)
          if (data.progress < 100) {
            setTimeout(() => this.pollProgress(), 1000)
          } else {
            this.completeProgress()
          }
        })
        .catch(error => {
          console.error('Error fetching progress:', error)
          this.statusTarget.textContent = 'エラーが発生しました。ページをリロードしてください。'
        })
    }
    */
  }
  
  // 進捗表示のアップデート
  updateProgress(progress) {
    this.barTarget.style.width = `${progress}%`
    this.statusTarget.textContent = `${progress}% 完了...`
    
    if (progress >= 100) {
      this.completeProgress()
    }
  }
  
  // 進捗完了時の処理
  completeProgress() {
    this.statusTarget.textContent = "処理が完了しました！"
    this.barTarget.classList.add("bg-green-600")
    
    // 3秒後に進捗表示を隠す
    setTimeout(() => {
      this.element.classList.add("hidden")
    }, 3000)
  }
  
  // 開発用: 進捗をシミュレートする（実際の実装では不要）
  simulateProgress() {
    const currentWidth = parseInt(this.barTarget.style.width || "0")
    if (currentWidth < 100) {
      // ランダムに進捗を進める（5-15%ずつ）
      const increment = Math.floor(Math.random() * 10) + 5
      const newProgress = Math.min(currentWidth + increment, 100)
      
      this.updateProgress(newProgress)
      
      // 次の更新まで少し待機
      if (newProgress < 100) {
        setTimeout(() => this.simulateProgress(), 800)
      }
    }
  }
} 