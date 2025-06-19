# frozen_string_literal: true

# ============================================
# Modern UI v2 - Rails Helper
# ============================================
# 新しいUIコンポーネントを簡単に使用するための
# Railsヘルパーメソッド集
# ============================================

module ModernUiHelper
  # ============================================
  # Glassmorphism Components
  # ============================================

  # Glassmorphismカードコンポーネント
  # @param options [Hash] オプション設定
  # @option options [Integer] :blur ブラー強度 (default: 10)
  # @option options [Float] :opacity 背景の透明度 (default: 0.1)
  # @option options [Boolean] :interactive インタラクティブ効果 (default: true)
  # @option options [String] :class 追加のCSSクラス
  def glass_card(options = {}, &block)
    defaults = {
      blur: 10,
      opacity: 0.1,
      interactive: true,
      class: "",
      header: nil,
      footer: nil
    }
    opts = defaults.merge(options)

    classes = [ "glass-card", opts[:class] ]
    classes << "glass-card-interactive" if opts[:interactive]

    content_tag(:div,
      class: classes.join(" "),
      data: {
        controller: "glassmorphism",
        glassmorphism_blur_value: opts[:blur],
        glassmorphism_opacity_value: opts[:opacity],
        glassmorphism_interactive_value: opts[:interactive]
      }
    ) do
      content = []

      # Header
      if opts[:header]
        content << content_tag(:div, class: "glass-card-header") do
          opts[:header].is_a?(String) ? content_tag(:h3, opts[:header]) : opts[:header]
        end
      end

      # Body
      content << content_tag(:div, class: "glass-card-body", &block)

      # Footer
      if opts[:footer]
        content << content_tag(:div, class: "glass-card-footer") do
          opts[:footer]
        end
      end

      safe_join(content)
    end
  end

  # ============================================
  # Button Components
  # ============================================

  # モダンボタンコンポーネント
  # @param text [String] ボタンテキスト
  # @param options [Hash] オプション設定
  def modern_button(text, options = {})
    defaults = {
      variant: "primary",
      size: "md",
      gradient: true,
      ripple: true,
      glow: false,
      icon: nil,
      icon_position: "left",
      loading: false,
      disabled: false,
      class: "",
      data: {},
      type: "button"
    }
    opts = defaults.merge(options)

    # Build CSS classes
    classes = [ "btn-modern", "btn-#{opts[:variant]}" ]
    classes << "btn-#{opts[:size]}" unless opts[:size] == "md"
    classes << "btn-gradient" if opts[:gradient]
    classes << "btn-ripple" if opts[:ripple]
    classes << "btn-glow" if opts[:glow]
    classes << "btn-loading" if opts[:loading]
    classes << "btn-icon-only" if text.blank? && opts[:icon]
    classes << opts[:class]

    # Build data attributes
    data_attrs = opts[:data].dup
    data_attrs[:controller] = [ data_attrs[:controller], "ripple" ].compact.join(" ") if opts[:ripple]

    # Build content
    content = []
    if opts[:icon] && opts[:icon_position] == "left"
      content << content_tag(:i, "", class: opts[:icon])
    end
    content << text if text.present?
    if opts[:icon] && opts[:icon_position] == "right"
      content << content_tag(:i, "", class: opts[:icon])
    end

    button_tag(
      safe_join(content),
      class: classes.join(" "),
      data: data_attrs,
      type: opts[:type],
      disabled: opts[:disabled] || opts[:loading]
    )
  end

  # ボタンへのリンク
  def modern_link_button(text, url, options = {})
    opts = options.dup
    opts[:class] = [ opts[:class], "btn-modern", "btn-#{opts[:variant] || 'primary'}" ].join(" ")
    link_to text, url, opts
  end

  # ============================================
  # Theme Components
  # ============================================

  # テーマ切り替えボタン
  def theme_toggle_button(options = {})
    defaults = {
      size: "md",
      variant: "ghost",
      class: "",
      persist: true
    }
    opts = defaults.merge(options)

    content_tag(:div,
      data: {
        controller: "theme",
        theme_persist_value: opts[:persist]
      }
    ) do
      modern_button("",
        icon: "bi bi-sun-fill",
        variant: opts[:variant],
        size: opts[:size],
        class: opts[:class],
        gradient: false,
        data: {
          theme_target: "toggle icon",
          action: "click->theme#toggle"
        }
      )
    end
  end

  # ============================================
  # Layout Components
  # ============================================

  # モダンコンテナー
  def modern_container(options = {}, &block)
    defaults = {
      size: "default", # default, narrow, wide, full
      class: ""
    }
    opts = defaults.merge(options)

    classes = [ "container-modern" ]
    classes << "container-#{opts[:size]}" unless opts[:size] == "default"
    classes << opts[:class]

    content_tag(:div, class: classes.join(" "), &block)
  end

  # グリッドレイアウト
  def modern_grid(cols: 3, gap: 4, options: {}, &block)
    classes = [ "grid-modern", "grid-cols-#{cols}", "gap-#{gap}", options[:class] ].compact

    content_tag(:div, class: classes.join(" "), &block)
  end

  # ============================================
  # Utility Components
  # ============================================

  # ローディングスピナー
  def loading_spinner(size: "md", color: "primary")
    classes = [ "loading-spinner", "spinner-#{size}", "text-#{color}" ]
    content_tag(:span, "", class: classes.join(" "))
  end

  # ローディングドット
  def loading_dots(color: "primary")
    content_tag(:div, class: "loading-dots text-#{color}") do
      3.times.map { content_tag(:span) }.join.html_safe
    end
  end

  # スケルトンローダー
  def skeleton_loader(width: "100%", height: "1em", rounded: false)
    styles = "width: #{width}; height: #{height};"
    classes = [ "skeleton" ]
    classes << "rounded" if rounded

    content_tag(:div, "", class: classes.join(" "), style: styles)
  end

  # グラデーションテキスト
  def gradient_text(text, gradient: "primary", tag: :span)
    content_tag(tag, text, class: "gradient-text gradient-#{gradient}")
  end

  # ============================================
  # Page Components
  # ============================================

  # ページヘッダー
  def modern_page_header(title:, subtitle: nil, actions: nil)
    content_tag(:div, class: "page-header glass-surface mb-6 p-6") do
      content = []

      # Title section
      content << content_tag(:div, class: "page-header-content") do
        header_content = []
        header_content << content_tag(:h1, title, class: "gradient-text mb-2")
        header_content << content_tag(:p, subtitle, class: "text-secondary") if subtitle
        safe_join(header_content)
      end

      # Actions section
      if actions
        content << content_tag(:div, class: "page-header-actions", &actions)
      end

      safe_join(content)
    end
  end

  # 統計カード
  def stat_card(label:, value:, icon: nil, trend: nil, trend_value: nil)
    glass_card(class: "stat-card") do
      content = []

      # Header with icon
      content << content_tag(:div, class: "flex-modern flex-between mb-2") do
        header_content = []
        header_content << content_tag(:span, label, class: "text-secondary text-sm")
        header_content << content_tag(:i, "", class: "#{icon} text-primary") if icon
        safe_join(header_content)
      end

      # Value
      content << content_tag(:div, value, class: "text-2xl font-bold mb-2")

      # Trend
      if trend && trend_value
        trend_class = trend == :up ? "text-success" : "text-danger"
        trend_icon = trend == :up ? "bi-arrow-up" : "bi-arrow-down"

        content << content_tag(:div, class: "text-sm #{trend_class}") do
          trend_content = []
          trend_content << content_tag(:i, "", class: "bi #{trend_icon}")
          trend_content << content_tag(:span, " #{trend_value}")
          safe_join(trend_content)
        end
      end

      safe_join(content)
    end
  end
end

# TODO: Phase 4 - 追加ヘルパー実装
# - フォームコンポーネント（glass_form_for等）
# - データテーブルコンポーネント
# - モーダル・ドロワーコンポーネント
# - AIアシスタントUIコンポーネント
