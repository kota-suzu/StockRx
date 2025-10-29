// ====================================================
// リアルタイム検索機能
// ====================================================
// CLAUDE.md準拠: ユーザビリティ向上とパフォーマンス最適化
// メタ認知: デバウンス・キャッシュ・エラーハンドリング統合

class RealtimeSearch {
  constructor(options = {}) {
    this.searchInput = options.searchInput || document.querySelector('[data-realtime-search="input"]')
    this.resultsContainer = options.resultsContainer || document.querySelector('[data-realtime-search="results"]')
    this.loadingIndicator = options.loadingIndicator || document.querySelector('[data-realtime-search="loading"]')
    this.noResultsMessage = options.noResultsMessage || document.querySelector('[data-realtime-search="no-results"]')
    
    // 設定オプション
    this.debounceDelay = options.debounceDelay || 300
    this.minQueryLength = options.minQueryLength || 2
    this.maxResults = options.maxResults || 50
    this.endpoint = options.endpoint || '/store/inventories'
    
    // 内部状態
    this.cache = new Map()
    this.controller = null
    this.debounceTimer = null
    this.isLoading = false
    
    this.init()
  }
  
  init() {
    if (!this.searchInput || !this.resultsContainer) {
      console.warn('RealtimeSearch: Required elements not found')
      return
    }
    
    this.bindEvents()
    this.setupKeyboardNavigation()
  }
  
  bindEvents() {
    // 入力イベント（デバウンス付き）
    this.searchInput.addEventListener('input', (e) => {
      this.handleInput(e.target.value.trim())
    })
    
    // フォーカス・ブラー
    this.searchInput.addEventListener('focus', () => {
      this.showResults()
    })
    
    this.searchInput.addEventListener('blur', (e) => {
      // 結果クリック時のブラーを遅延
      setTimeout(() => this.hideResults(), 150)
    })
    
    // ESCキーで結果を閉じる
    this.searchInput.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        this.hideResults()
        this.searchInput.blur()
      }
    })
  }
  
  handleInput(query) {
    clearTimeout(this.debounceTimer)
    
    if (query.length < this.minQueryLength) {
      this.hideResults()
      return
    }
    
    this.debounceTimer = setTimeout(() => {
      this.performSearch(query)
    }, this.debounceDelay)
  }
  
  async performSearch(query) {
    // リクエストキャンセル
    if (this.controller) {
      this.controller.abort()
    }
    
    // キャッシュチェック
    if (this.cache.has(query)) {
      this.displayResults(this.cache.get(query), query)
      return
    }
    
    this.controller = new AbortController()
    this.setLoading(true)
    
    try {
      const url = new URL(this.endpoint, window.location.origin)
      url.searchParams.set('q', query)
      url.searchParams.set('format', 'json')
      url.searchParams.set('per_page', this.maxResults)
      
      const response = await fetch(url, {
        signal: this.controller.signal,
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }
      
      const data = await response.json()
      
      // 結果をキャッシュ
      this.cache.set(query, data)
      
      // キャッシュサイズ制限
      if (this.cache.size > 100) {
        const firstKey = this.cache.keys().next().value
        this.cache.delete(firstKey)
      }
      
      this.displayResults(data, query)
      
    } catch (error) {
      if (error.name !== 'AbortError') {
        console.error('検索エラー:', error)
        this.displayError('検索中にエラーが発生しました')
      }
    } finally {
      this.setLoading(false)
      this.controller = null
    }
  }
  
  displayResults(data, query) {
    const results = data.inventories || data
    
    if (!Array.isArray(results) || results.length === 0) {
      this.displayNoResults(query)
      return
    }
    
    const html = this.renderResults(results, query)
    this.resultsContainer.innerHTML = html
    this.showResults()
    
    // 結果アイテムのクリックイベント
    this.bindResultEvents()
  }
  
  renderResults(results, query) {
    const highlightQuery = (text) => {
      if (!text || !query) return text
      const regex = new RegExp(`(${query})`, 'gi')
      return text.replace(regex, '<mark>$1</mark>')
    }
    
    return `
      <div class="search-results-list">
        ${results.slice(0, this.maxResults).map(item => `
          <div class="search-result-item" data-inventory-id="${item.id}">
            <div class="d-flex justify-content-between align-items-start">
              <div class="result-content">
                <h6 class="result-title mb-1">
                  ${highlightQuery(item.name)}
                </h6>
                <div class="result-details">
                  <small class="text-muted">
                    SKU: <code>${highlightQuery(item.sku || '-')}</code>
                  </small>
                  ${item.manufacturer ? `
                    <small class="text-muted ms-2">
                      メーカー: ${highlightQuery(item.manufacturer)}
                    </small>
                  ` : ''}
                </div>
              </div>
              <div class="result-status">
                ${this.renderStockStatus(item.quantity)}
              </div>
            </div>
          </div>
        `).join('')}
        ${results.length > this.maxResults ? `
          <div class="search-result-more text-center py-2">
            <small class="text-muted">
              他 ${results.length - this.maxResults} 件...
            </small>
          </div>
        ` : ''}
      </div>
    `
  }
  
  renderStockStatus(quantity) {
    const qty = parseInt(quantity) || 0
    
    if (qty === 0) {
      return '<span class="badge bg-danger">在庫なし</span>'
    } else if (qty < 10) {
      return '<span class="badge bg-warning">少</span>'
    } else {
      return '<span class="badge bg-success">有</span>'
    }
  }
  
  displayNoResults(query) {
    this.resultsContainer.innerHTML = `
      <div class="search-no-results text-center py-4">
        <i class="bi bi-search text-muted mb-2" style="font-size: 2rem;"></i>
        <p class="text-muted mb-0">
          「${query}」の検索結果はありません
        </p>
      </div>
    `
    this.showResults()
  }
  
  displayError(message) {
    this.resultsContainer.innerHTML = `
      <div class="search-error text-center py-4">
        <i class="bi bi-exclamation-triangle text-warning mb-2" style="font-size: 2rem;"></i>
        <p class="text-muted mb-0">${message}</p>
      </div>
    `
    this.showResults()
  }
  
  showResults() {
    this.resultsContainer.style.display = 'block'
    this.resultsContainer.setAttribute('aria-hidden', 'false')
  }
  
  hideResults() {
    this.resultsContainer.style.display = 'none'
    this.resultsContainer.setAttribute('aria-hidden', 'true')
  }
  
  setLoading(loading) {
    this.isLoading = loading
    
    if (this.loadingIndicator) {
      this.loadingIndicator.style.display = loading ? 'block' : 'none'
    }
    
    // 検索アイコンの切り替え
    const searchIcon = this.searchInput.parentElement.querySelector('.search-icon')
    if (searchIcon) {
      if (loading) {
        searchIcon.className = 'search-icon spinner-border spinner-border-sm text-primary'
      } else {
        searchIcon.className = 'search-icon bi bi-search text-muted'
      }
    }
  }
  
  bindResultEvents() {
    const resultItems = this.resultsContainer.querySelectorAll('.search-result-item')
    
    resultItems.forEach(item => {
      item.addEventListener('click', (e) => {
        const inventoryId = item.dataset.inventoryId
        this.handleResultClick(inventoryId, item)
      })
      
      // キーボードナビゲーション
      item.setAttribute('tabindex', '0')
      item.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          item.click()
        }
      })
    })
  }
  
  handleResultClick(inventoryId, element) {
    // 選択状態の表示
    element.classList.add('selected')
    
    // 検索入力に選択した商品名を設定
    const title = element.querySelector('.result-title').textContent.trim()
    this.searchInput.value = title
    
    // 結果を隠す
    this.hideResults()
    
    // カスタムイベント発火
    this.searchInput.dispatchEvent(new CustomEvent('realtime-search:select', {
      detail: { inventoryId, title, element }
    }))
  }
  
  setupKeyboardNavigation() {
    this.searchInput.addEventListener('keydown', (e) => {
      const items = this.resultsContainer.querySelectorAll('.search-result-item')
      if (items.length === 0) return
      
      const currentFocus = this.resultsContainer.querySelector('.search-result-item:focus')
      let index = Array.from(items).indexOf(currentFocus)
      
      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault()
          index = index < items.length - 1 ? index + 1 : 0
          items[index].focus()
          break
          
        case 'ArrowUp':
          e.preventDefault()
          index = index > 0 ? index - 1 : items.length - 1
          items[index].focus()
          break
          
        case 'Enter':
          if (currentFocus) {
            e.preventDefault()
            currentFocus.click()
          }
          break
      }
    })
  }
  
  // 公開メソッド
  clearCache() {
    this.cache.clear()
  }
  
  updateEndpoint(newEndpoint) {
    this.endpoint = newEndpoint
    this.clearCache()
  }
  
  destroy() {
    if (this.controller) {
      this.controller.abort()
    }
    clearTimeout(this.debounceTimer)
    this.clearCache()
  }
}

// CSS スタイル
const style = document.createElement('style')
style.textContent = `
  .search-results-container {
    position: relative;
    width: 100%;
  }
  
  .search-results-dropdown {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    background: white;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
    box-shadow: 0 10px 25px rgba(0, 0, 0, 0.1);
    z-index: 1050;
    max-height: 400px;
    overflow-y: auto;
    display: none;
  }
  
  .search-result-item {
    padding: 0.75rem 1rem;
    border-bottom: 1px solid #f3f4f6;
    cursor: pointer;
    transition: background-color 0.2s ease;
  }
  
  .search-result-item:last-child {
    border-bottom: none;
  }
  
  .search-result-item:hover,
  .search-result-item:focus {
    background-color: #f8fafc;
    outline: none;
  }
  
  .search-result-item.selected {
    background-color: #e0f2fe;
  }
  
  .result-title {
    color: #1f2937;
    font-weight: 500;
  }
  
  .result-details {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  
  .search-no-results,
  .search-error {
    padding: 2rem 1rem;
  }
  
  .search-result-more {
    background-color: #f9fafb;
    border-top: 1px solid #f3f4f6;
  }
  
  mark {
    background-color: #fef3c7;
    color: #92400e;
    padding: 0.125rem 0.25rem;
    border-radius: 0.25rem;
  }
  
  .search-icon {
    position: absolute;
    right: 0.75rem;
    top: 50%;
    transform: translateY(-50%);
    pointer-events: none;
  }
  
  @media (max-width: 768px) {
    .search-results-dropdown {
      max-height: 300px;
    }
    
    .search-result-item {
      padding: 1rem 0.75rem;
    }
    
    .result-details {
      flex-direction: column;
      gap: 0.25rem;
    }
  }
`
document.head.appendChild(style)

// グローバル初期化
window.RealtimeSearch = RealtimeSearch

// 自動初期化（DOMContentLoaded後）
document.addEventListener('DOMContentLoaded', () => {
  const searchInputs = document.querySelectorAll('[data-realtime-search="input"]')
  
  searchInputs.forEach(input => {
    if (!input.dataset.realtimeSearchInitialized) {
      new RealtimeSearch({
        searchInput: input,
        resultsContainer: input.closest('.search-results-container')?.querySelector('[data-realtime-search="results"]'),
        endpoint: input.dataset.searchEndpoint || '/store/inventories'
      })
      input.dataset.realtimeSearchInitialized = 'true'
    }
  })
})

// Turbo対応
document.addEventListener('turbo:load', () => {
  const event = new Event('DOMContentLoaded')
  document.dispatchEvent(event)
})