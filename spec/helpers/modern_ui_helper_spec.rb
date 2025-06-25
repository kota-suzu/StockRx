# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ModernUiHelper, type: :helper do
  # CLAUDE.md準拠: Modern UIヘルパーの包括的テスト
  # メタ認知: UIコンポーネントの一貫性とStimulus統合の検証
  # 横展開: 他のUIヘルパーでも同様のテストパターン適用

  # ============================================
  # glass_card メソッドのテスト
  # ============================================

  describe "#glass_card" do
    context "基本的な使用" do
      it "デフォルトのglassカードを生成する" do
        result = helper.glass_card { "Content" }

        expect(result).to include("glass-card")
        expect(result).to include("glass-card-interactive")
        expect(result).to include("Content")
        expect(result).to be_html_safe
      end

      it "適切なdata属性を設定する" do
        result = helper.glass_card { "Content" }

        expect(result).to include('data-controller="glassmorphism"')
        expect(result).to include('data-glassmorphism-blur-value="10"')
        expect(result).to include('data-glassmorphism-opacity-value="0.1"')
        expect(result).to include('data-glassmorphism-interactive-value="true"')
      end

      it "カードボディが正しく配置される" do
        result = helper.glass_card { "Body Content" }

        expect(result).to include('<div class="glass-card-body">Body Content</div>')
      end
    end

    context "カスタムオプション" do
      it "blur値をカスタマイズできる" do
        result = helper.glass_card(blur: 20) { "Content" }
        expect(result).to include('data-glassmorphism-blur-value="20"')
      end

      it "opacity値をカスタマイズできる" do
        result = helper.glass_card(opacity: 0.5) { "Content" }
        expect(result).to include('data-glassmorphism-opacity-value="0.5"')
      end

      it "インタラクティブ効果を無効化できる" do
        result = helper.glass_card(interactive: false) { "Content" }

        expect(result).not_to include("glass-card-interactive")
        expect(result).to include('data-glassmorphism-interactive-value="false"')
      end

      it "追加のCSSクラスを適用できる" do
        result = helper.glass_card(class: "custom-class") { "Content" }
        expect(result).to include("glass-card custom-class")
      end
    end

    context "ヘッダー・フッター" do
      it "文字列ヘッダーをh3タグで囲む" do
        result = helper.glass_card(header: "Card Title") { "Content" }

        expect(result).to include('<div class="glass-card-header">')
        expect(result).to include('<h3>Card Title</h3>')
      end

      it "HTMLヘッダーをそのまま使用する" do
        header_html = '<span class="badge">New</span>'
        result = helper.glass_card(header: header_html.html_safe) { "Content" }

        expect(result).to include('<div class="glass-card-header">')
        expect(result).to include('<span class="badge">New</span>')
      end

      it "フッターを追加できる" do
        result = helper.glass_card(footer: "Footer Content") { "Body" }

        expect(result).to include('<div class="glass-card-footer">')
        expect(result).to include('Footer Content')
      end

      it "ヘッダー、ボディ、フッターの順序が正しい" do
        result = helper.glass_card(
          header: "Header",
          footer: "Footer"
        ) { "Body" }

        # 順序を確認
        header_pos = result.index("glass-card-header")
        body_pos = result.index("glass-card-body")
        footer_pos = result.index("glass-card-footer")

        expect(header_pos).to be < body_pos
        expect(body_pos).to be < footer_pos
      end
    end
  end

  # ============================================
  # modern_button メソッドのテスト
  # ============================================

  describe "#modern_button" do
    context "基本的な使用" do
      it "デフォルトのモダンボタンを生成する" do
        result = helper.modern_button("Click Me")

        expect(result).to include("btn-modern")
        expect(result).to include("btn-primary")
        expect(result).to include("btn-gradient")
        expect(result).to include("btn-ripple")
        expect(result).to include("Click Me")
        expect(result).to include('type="button"')
      end

      it "rippleコントローラーを設定する" do
        result = helper.modern_button("Click")
        expect(result).to include('data-controller="ripple"')
      end
    end

    context "バリアントオプション" do
      %w[primary secondary success danger warning info].each do |variant|
        it "#{variant}バリアントを適用する" do
          result = helper.modern_button("Button", variant: variant)
          expect(result).to include("btn-#{variant}")
        end
      end
    end

    context "サイズオプション" do
      it "デフォルトサイズ(md)ではサイズクラスを追加しない" do
        result = helper.modern_button("Button", size: "md")
        expect(result).not_to include("btn-md")
      end

      %w[sm lg xl].each do |size|
        it "#{size}サイズクラスを追加する" do
          result = helper.modern_button("Button", size: size)
          expect(result).to include("btn-#{size}")
        end
      end
    end

    context "視覚効果オプション" do
      it "グラデーションを無効化できる" do
        result = helper.modern_button("Button", gradient: false)
        expect(result).not_to include("btn-gradient")
      end

      it "リップル効果を無効化できる" do
        result = helper.modern_button("Button", ripple: false)
        expect(result).not_to include("btn-ripple")
        expect(result).not_to include('data-controller="ripple"')
      end

      it "グロー効果を有効化できる" do
        result = helper.modern_button("Button", glow: true)
        expect(result).to include("btn-glow")
      end
    end

    context "アイコンオプション" do
      it "左側にアイコンを配置する" do
        result = helper.modern_button("Save", icon: "bi bi-save")

        expect(result).to include('<i class="bi bi-save"></i>')
        expect(result).to match(/<i[^>]*>.*<\/i>Save/)
      end

      it "右側にアイコンを配置する" do
        result = helper.modern_button("Next", icon: "bi bi-arrow-right", icon_position: "right")

        expect(result).to include('<i class="bi bi-arrow-right"></i>')
        expect(result).to match(/Next<i[^>]*>/)
      end

      it "アイコンのみのボタンを作成する" do
        result = helper.modern_button("", icon: "bi bi-gear")

        expect(result).to include("btn-icon-only")
        expect(result).to include('<i class="bi bi-gear"></i>')
      end
    end

    context "状態オプション" do
      it "ローディング状態を適用する" do
        result = helper.modern_button("Loading", loading: true)

        expect(result).to include("btn-loading")
        expect(result).to include('disabled="disabled"')
      end

      it "無効化状態を適用する" do
        result = helper.modern_button("Disabled", disabled: true)
        expect(result).to include('disabled="disabled"')
      end
    end

    context "データ属性とカスタムオプション" do
      it "カスタムdata属性を追加できる" do
        result = helper.modern_button("Click", data: { turbo_confirm: "Are you sure?" })
        expect(result).to include('data-turbo-confirm="Are you sure?"')
      end

      it "既存のcontrollerにrippleを追加する" do
        result = helper.modern_button("Click", data: { controller: "custom" })
        expect(result).to include('data-controller="custom ripple"')
      end

      it "カスタムtypeを設定できる" do
        result = helper.modern_button("Submit", type: "submit")
        expect(result).to include('type="submit"')
      end
    end
  end

  # ============================================
  # modern_link_button メソッドのテスト
  # ============================================

  describe "#modern_link_button" do
    it "リンクボタンを生成する" do
      result = helper.modern_link_button("Go to Home", "/", variant: "secondary")

      expect(result).to include('href="/"')
      expect(result).to include("btn-modern")
      expect(result).to include("btn-secondary")
      expect(result).to include("Go to Home")
    end

    it "追加のクラスを適用できる" do
      result = helper.modern_link_button("Link", "/path", class: "custom-class", variant: "danger")

      expect(result).to include("custom-class")
      expect(result).to include("btn-modern")
      expect(result).to include("btn-danger")
    end
  end

  # ============================================
  # theme_toggle_button メソッドのテスト
  # ============================================

  describe "#theme_toggle_button" do
    it "テーマ切り替えボタンを生成する" do
      result = helper.theme_toggle_button

      expect(result).to include('data-controller="theme"')
      expect(result).to include('data-theme-persist-value="true"')
      expect(result).to include('data-theme-target="toggle icon"')
      expect(result).to include('data-action="click->theme#toggle"')
      expect(result).to include("bi bi-sun-fill")
    end

    it "persist設定を無効化できる" do
      result = helper.theme_toggle_button(persist: false)
      expect(result).to include('data-theme-persist-value="false"')
    end

    it "カスタムサイズとバリアントを適用できる" do
      result = helper.theme_toggle_button(size: "sm", variant: "outline")

      expect(result).to include("btn-sm")
      expect(result).to include("btn-outline")
    end
  end

  # ============================================
  # modern_container メソッドのテスト
  # ============================================

  describe "#modern_container" do
    it "デフォルトコンテナーを生成する" do
      result = helper.modern_container { "Content" }

      expect(result).to include("container-modern")
      expect(result).not_to include("container-default")
      expect(result).to include("Content")
    end

    %w[narrow wide full].each do |size|
      it "#{size}サイズのコンテナーを生成する" do
        result = helper.modern_container(size: size) { "Content" }
        expect(result).to include("container-#{size}")
      end
    end

    it "追加のクラスを適用できる" do
      result = helper.modern_container(class: "mt-4") { "Content" }
      expect(result).to include("container-modern mt-4")
    end
  end

  # ============================================
  # modern_grid メソッドのテスト
  # ============================================

  describe "#modern_grid" do
    it "デフォルトグリッドを生成する" do
      result = helper.modern_grid { "Grid Content" }

      expect(result).to include("grid-modern")
      expect(result).to include("grid-cols-3")
      expect(result).to include("gap-4")
    end

    it "カスタム列数とギャップを設定できる" do
      result = helper.modern_grid(cols: 4, gap: 6) { "Content" }

      expect(result).to include("grid-cols-4")
      expect(result).to include("gap-6")
    end

    it "追加のオプションを適用できる" do
      result = helper.modern_grid(options: { class: "custom-grid" }) { "Content" }
      expect(result).to include("custom-grid")
    end
  end

  # ============================================
  # ユーティリティコンポーネントのテスト
  # ============================================

  describe "#loading_spinner" do
    it "デフォルトのローディングスピナーを生成する" do
      result = helper.loading_spinner

      expect(result).to include("loading-spinner")
      expect(result).to include("spinner-md")
      expect(result).to include("text-primary")
    end

    it "カスタムサイズと色を設定できる" do
      result = helper.loading_spinner(size: "lg", color: "danger")

      expect(result).to include("spinner-lg")
      expect(result).to include("text-danger")
    end
  end

  describe "#loading_dots" do
    it "3つのドットを含むローディング表示を生成する" do
      result = helper.loading_dots

      expect(result).to include("loading-dots")
      expect(result).to include("text-primary")
      expect(result.scan(/<span><\/span>/).count).to eq(3)
    end

    it "カスタム色を設定できる" do
      result = helper.loading_dots(color: "success")
      expect(result).to include("text-success")
    end
  end

  describe "#skeleton_loader" do
    it "デフォルトのスケルトンローダーを生成する" do
      result = helper.skeleton_loader

      expect(result).to include("skeleton")
      expect(result).to include('style="width: 100%; height: 1em;"')
    end

    it "カスタムサイズを設定できる" do
      result = helper.skeleton_loader(width: "200px", height: "40px")
      expect(result).to include('style="width: 200px; height: 40px;"')
    end

    it "角丸オプションを適用できる" do
      result = helper.skeleton_loader(rounded: true)
      expect(result).to include("skeleton rounded")
    end
  end

  describe "#gradient_text" do
    it "グラデーションテキストを生成する" do
      result = helper.gradient_text("Gradient Text")

      expect(result).to include("gradient-text")
      expect(result).to include("gradient-primary")
      expect(result).to include("Gradient Text")
      expect(result).to match(/<span[^>]*>/)
    end

    it "カスタムグラデーションとタグを設定できる" do
      result = helper.gradient_text("Title", gradient: "success", tag: :h1)

      expect(result).to include("gradient-success")
      expect(result).to match(/<h1[^>]*>/)
    end
  end

  # ============================================
  # ページコンポーネントのテスト
  # ============================================

  describe "#modern_page_header" do
    it "基本的なページヘッダーを生成する" do
      result = helper.modern_page_header(title: "Dashboard")

      expect(result).to include("page-header")
      expect(result).to include("glass-surface")
      expect(result).to include('<h1 class="gradient-text mb-2">Dashboard</h1>')
    end

    it "サブタイトルを含むヘッダーを生成する" do
      result = helper.modern_page_header(
        title: "Dashboard",
        subtitle: "Welcome back!"
      )

      expect(result).to include('<p class="text-secondary">Welcome back!</p>')
    end

    it "アクションセクションを含むヘッダーを生成する" do
      actions = lambda { '<button>Action</button>'.html_safe }
      result = helper.modern_page_header(
        title: "Dashboard",
        actions: actions
      )

      expect(result).to include('<div class="page-header-actions">')
      expect(result).to include('<button>Action</button>')
    end
  end

  describe "#stat_card" do
    it "基本的な統計カードを生成する" do
      result = helper.stat_card(label: "Total Sales", value: "$1,234")

      expect(result).to include("stat-card")
      expect(result).to include("Total Sales")
      expect(result).to include("$1,234")
    end

    it "アイコン付き統計カードを生成する" do
      result = helper.stat_card(
        label: "Revenue",
        value: "$5,000",
        icon: "bi bi-cash"
      )

      expect(result).to include('<i class="bi bi-cash text-primary"></i>')
    end

    it "トレンド情報を表示する" do
      result = helper.stat_card(
        label: "Growth",
        value: "150%",
        trend: :up,
        trend_value: "+25%"
      )

      expect(result).to include("text-success")
      expect(result).to include("bi-arrow-up")
      expect(result).to include("+25%")
    end

    it "下降トレンドを表示する" do
      result = helper.stat_card(
        label: "Costs",
        value: "$800",
        trend: :down,
        trend_value: "-10%"
      )

      expect(result).to include("text-danger")
      expect(result).to include("bi-arrow-down")
      expect(result).to include("-10%")
    end
  end

  # ============================================
  # パフォーマンステスト
  # ============================================

  describe "performance tests" do
    it "glass_card は高速に生成される" do
      start_time = Time.current
      100.times do
        helper.glass_card { "Content" }
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "modern_button は高速に生成される" do
      start_time = Time.current
      100.times do
        helper.modern_button("Button", icon: "bi bi-save", variant: "success")
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end

    it "stat_card は高速に生成される" do
      start_time = Time.current
      100.times do
        helper.stat_card(
          label: "Test",
          value: "100",
          icon: "bi bi-graph",
          trend: :up,
          trend_value: "+10%"
        )
      end
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 100 # 100ms以内
    end
  end

  # ============================================
  # HTML安全性テスト
  # ============================================

  describe "HTML safety" do
    it "glass_card の結果はHTML安全" do
      result = helper.glass_card { "Content" }
      expect(result).to be_html_safe
    end

    it "modern_button の結果はHTML安全" do
      result = helper.modern_button("Click")
      expect(result).to be_html_safe
    end

    it "loading_dots の結果はHTML安全" do
      result = helper.loading_dots
      expect(result).to be_html_safe
    end

    it "gradient_text の結果はHTML安全" do
      result = helper.gradient_text("Text")
      expect(result).to be_html_safe
    end
  end

  # ============================================
  # XSS対策テスト
  # ============================================

  describe "XSS protection" do
    it "modern_button でユーザー入力をエスケープする" do
      malicious_text = '<script>alert("XSS")</script>'
      result = helper.modern_button(malicious_text)

      expect(result).not_to include('<script>')
      expect(result).to include('&lt;script&gt;')
    end

    it "gradient_text でユーザー入力をエスケープする" do
      malicious_text = '<img src=x onerror=alert("XSS")>'
      result = helper.gradient_text(malicious_text)

      expect(result).not_to include('<img')
      expect(result).to include('&lt;img')
    end

    it "stat_card でユーザー入力をエスケープする" do
      result = helper.stat_card(
        label: '<script>alert("XSS")</script>',
        value: '<div onload="alert()">'
      )

      expect(result).not_to include('<script>')
      expect(result).not_to include('onload=')
    end
  end

  # ============================================
  # エッジケースのテスト
  # ============================================

  describe "edge cases" do
    it "glass_card は空のブロックでも動作する" do
      expect { helper.glass_card { } }.not_to raise_error
    end

    it "modern_button は空文字列でも動作する" do
      result = helper.modern_button("")
      expect(result).to be_present
    end

    it "stat_card はnilトレンドでも動作する" do
      result = helper.stat_card(
        label: "Test",
        value: "100",
        trend: nil,
        trend_value: nil
      )

      expect(result).to be_present
      expect(result).not_to include("bi-arrow")
    end
  end

  # ============================================
  # アクセシビリティテスト
  # ============================================

  describe "accessibility (ARIA attributes)" do
    it "loading_spinner は適切なaria-label属性を持つべき" do
      # TODO: Phase 4 - ヘルパーメソッドにARIA属性追加後に実装
      # result = helper.loading_spinner
      # expect(result).to include('aria-label="読み込み中"')
      pending "ARIA属性の実装待ち"
    end

    it "theme_toggle_button は適切なaria-label属性を持つべき" do
      # TODO: Phase 4 - ヘルパーメソッドにARIA属性追加後に実装
      # result = helper.theme_toggle_button
      # expect(result).to include('aria-label="テーマ切り替え"')
      pending "ARIA属性の実装待ち"
    end

    it "stat_card のトレンドアイコンは適切なaria-hidden属性を持つべき" do
      # TODO: Phase 4 - 装飾的アイコンのアクセシビリティ改善
      # result = helper.stat_card(label: "Test", value: "100", trend: :up, trend_value: "+10%")
      # expect(result).to include('aria-hidden="true"')
      pending "装飾的要素のARIA属性実装待ち"
    end
  end

  # ============================================
  # Turbo統合テスト
  # ============================================

  describe "Turbo integration" do
    it "modern_button はTurbo準拠のdata属性を適切に処理する" do
      result = helper.modern_button("Delete",
        data: {
          turbo_method: :delete,
          turbo_confirm: "本当に削除しますか？"
        }
      )

      expect(result).to include('data-turbo-method="delete"')
      expect(result).to include('data-turbo-confirm="本当に削除しますか？"')
    end

    it "modern_link_button はTurboフレーム指定を適切に処理する" do
      result = helper.modern_link_button("Load", "/path",
        data: { turbo_frame: "modal" }
      )

      expect(result).to include('data-turbo-frame="modal"')
    end

    it "glass_card はTurbo永続化属性を適切に処理する" do
      result = helper.glass_card(
        data: { turbo_permanent: true }
      ) { "Persistent Content" }

      expect(result).to include('data-turbo-permanent="true"')
    end
  end

  # ============================================
  # CSPコンプライアンステスト
  # ============================================

  describe "CSP (Content Security Policy) compliance" do
    it "インラインスタイルを使用しない（skeleton_loader除く）" do
      # skeleton_loaderは動的サイズのため例外
      methods_without_inline_styles = [
        helper.glass_card { "Content" },
        helper.modern_button("Click"),
        helper.theme_toggle_button,
        helper.loading_spinner,
        helper.loading_dots
      ]

      methods_without_inline_styles.each do |result|
        expect(result).not_to include('style=')
      end
    end

    it "skeleton_loader のインラインスタイルは必要最小限" do
      result = helper.skeleton_loader
      # widthとheightのみ許可
      expect(result).to match(/style="width: \d+(%|px); height: \d+(\.\d+)?(em|px);"/)
      expect(result).not_to include('background')
      expect(result).not_to include('color')
    end

    it "イベントハンドラ属性を使用しない" do
      all_components = [
        helper.glass_card { "Content" },
        helper.modern_button("Click"),
        helper.modern_link_button("Link", "/"),
        helper.theme_toggle_button,
        helper.stat_card(label: "Test", value: "100")
      ]

      all_components.each do |result|
        expect(result).not_to include('onclick=')
        expect(result).not_to include('onload=')
        expect(result).not_to include('onerror=')
      end
    end
  end

  # ============================================
  # 追加エッジケーステスト
  # ============================================

  describe "additional edge cases" do
    it "modern_button は非常に長いテキストでも適切に処理される" do
      long_text = "あ" * 100
      result = helper.modern_button(long_text)

      expect(result).to include(long_text)
      expect(result).to be_html_safe
    end

    it "stat_card は非常に大きな数値でも適切に処理される" do
      result = helper.stat_card(
        label: "Revenue",
        value: "¥999,999,999,999,999"
      )

      expect(result).to include("¥999,999,999,999,999")
      expect(result).to be_html_safe
    end

    it "glass_card はネストされたHTMLブロックでも動作する" do
      result = helper.glass_card do
        helper.glass_card(class: "nested") { "Nested Content" }
      end

      expect(result).to include("glass-card")
      expect(result).to include("nested")
      expect(result).to include("Nested Content")
    end

    it "gradient_text は改行を含むテキストでも動作する" do
      multiline_text = "Line 1\nLine 2\nLine 3"
      result = helper.gradient_text(multiline_text)

      expect(result).to include(multiline_text)
      expect(result).to be_html_safe
    end
  end

  # ============================================
  # Stimulus統合テスト
  # ============================================

  describe "Stimulus integration" do
    it "glass_card は正しいStimulus設定を持つ" do
      result = helper.glass_card { "Content" }

      # Stimulusコントローラー
      expect(result).to include('data-controller="glassmorphism"')

      # Stimulus values
      expect(result).to include('data-glassmorphism-blur-value')
      expect(result).to include('data-glassmorphism-opacity-value')
      expect(result).to include('data-glassmorphism-interactive-value')
    end

    it "theme_toggle_button は正しいStimulus設定を持つ" do
      result = helper.theme_toggle_button

      # Stimulusコントローラー
      expect(result).to include('data-controller="theme"')

      # Stimulus targets
      expect(result).to include('data-theme-target="toggle icon"')

      # Stimulus actions
      expect(result).to include('data-action="click->theme#toggle"')
    end

    it "modern_button のripple効果は正しく設定される" do
      result = helper.modern_button("Click")

      # Rippleコントローラー
      expect(result).to include('data-controller="ripple"')
    end
  end
end
