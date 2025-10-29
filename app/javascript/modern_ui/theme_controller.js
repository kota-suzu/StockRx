// ============================================
// Modern UI v2 - Theme Controller
// ============================================
// Stimulus Controller for theme management
// Handles light/dark mode switching and persistence
// ============================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "icon"]
  static values = { 
    current: String,
    persist: { type: Boolean, default: true }
  }

  // セキュリティ: 許可されたテーマのホワイトリスト
  static allowedThemes = ['light', 'dark', 'system']

  connect() {
    // Initialize theme on connect
    this.initializeTheme()
    
    // Listen for system theme changes
    this.mediaQuery = window.matchMedia('(prefers-color-scheme: dark)')
    this.mediaQuery.addEventListener('change', this.handleSystemThemeChange.bind(this))
    
    // Add transition class for smooth theme switching
    document.documentElement.classList.add('theme-transition')
  }

  disconnect() {
    // Clean up event listener
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener('change', this.handleSystemThemeChange.bind(this))
    }
  }

  initializeTheme() {
    let theme = this.currentValue

    // Check localStorage if persist is enabled
    if (this.persistValue) {
      const storedTheme = this.sanitizeTheme(localStorage.getItem('theme'))
      if (storedTheme) {
        theme = storedTheme
      }
    }

    // If no theme is set, check system preference
    if (!theme) {
      theme = this.getSystemTheme()
    }

    // Apply the theme
    this.setTheme(theme, false)
  }

  // セキュリティ: テーマ値のサニタイズ
  sanitizeTheme(theme) {
    if (!theme || typeof theme !== 'string') return null
    
    const sanitized = theme.toLowerCase().trim()
    return this.constructor.allowedThemes.includes(sanitized) ? sanitized : null
  }

  toggle() {
    const newTheme = this.currentValue === 'light' ? 'dark' : 'light'
    this.setTheme(newTheme)
    
    // Add a ripple effect on toggle
    this.addRippleEffect()
  }

  setTheme(theme, animate = true) {
    // セキュリティ: テーマ値の検証
    const sanitizedTheme = this.sanitizeTheme(theme)
    if (!sanitizedTheme) {
      console.error('Invalid theme value:', theme)
      return
    }

    // Update DOM
    document.documentElement.setAttribute('data-theme', sanitizedTheme)
    
    // Update controller value
    this.currentValue = sanitizedTheme
    
    // Persist to localStorage if enabled
    if (this.persistValue) {
      try {
        localStorage.setItem('theme', sanitizedTheme)
      } catch (e) {
        console.warn('Failed to save theme preference:', e)
      }
    }
    
    // Update toggle button icon if exists
    this.updateToggleIcon(sanitizedTheme)
    
    // Dispatch custom event
    this.dispatch('changed', { detail: { theme: sanitizedTheme } })
    
    // Add animation class
    if (animate) {
      document.documentElement.classList.add('theme-changing')
      setTimeout(() => {
        document.documentElement.classList.remove('theme-changing')
      }, 300)
    }
  }

  setLightTheme() {
    this.setTheme('light')
  }

  setDarkTheme() {
    this.setTheme('dark')
  }

  setSystemTheme() {
    const theme = this.getSystemTheme()
    this.setTheme(theme)
  }

  getSystemTheme() {
    return this.mediaQuery.matches ? 'dark' : 'light'
  }

  handleSystemThemeChange(e) {
    // Only update if current theme is 'system' or not set
    if (!this.currentValue || this.currentValue === 'system') {
      const theme = e.matches ? 'dark' : 'light'
      this.setTheme(theme)
    }
  }

  updateToggleIcon(theme) {
    if (!this.hasIconTarget) return
    
    // Update icon based on theme
    const iconClass = theme === 'dark' ? 'bi-moon-stars-fill' : 'bi-sun-fill'
    this.iconTarget.className = `bi ${iconClass}`
  }

  addRippleEffect() {
    if (!this.hasToggleTarget) return
    
    const button = this.toggleTarget
    const rect = button.getBoundingClientRect()
    const ripple = document.createElement('span')
    
    ripple.className = 'theme-ripple'
    ripple.style.width = ripple.style.height = Math.max(rect.width, rect.height) + 'px'
    ripple.style.left = '50%'
    ripple.style.top = '50%'
    
    button.appendChild(ripple)
    
    setTimeout(() => {
      ripple.remove()
    }, 600)
  }

  // Public methods for external control
  get isDark() {
    return this.currentValue === 'dark'
  }

  get isLight() {
    return this.currentValue === 'light'
  }
}

// ============================================
// CSS for theme ripple effect
// ============================================
const style = document.createElement('style')
style.textContent = `
  .theme-ripple {
    position: absolute;
    border-radius: 50%;
    transform: translate(-50%, -50%) scale(0);
    animation: theme-ripple 600ms ease-out;
    background: currentColor;
    opacity: 0.3;
    pointer-events: none;
  }

  @keyframes theme-ripple {
    to {
      transform: translate(-50%, -50%) scale(4);
      opacity: 0;
    }
  }

  .theme-changing * {
    transition: none !important;
  }
`
document.head.appendChild(style)

// TODO: Phase 4 - 高度なテーマ機能
// - カスタムテーマカラー選択
// - テーマプリセット管理
// - テーマのインポート/エクスポート
// - アニメーション設定の永続化