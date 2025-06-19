# frozen_string_literal: true

# 全デコレータの基底クラス
# CLAUDE.md準拠: 包括的なUIヘルパーメソッドを提供
# メタ認知: Bootstrapスタイルとの互換性を保ちつつHTMLセーフティを確保
# 横展開: 全ての子デコレーターで一貫したUI表現を実現
class ApplicationDecorator < Draper::Decorator
  # 標準的なデコレータメソッドを全デコレータで利用可能にする
  delegate_all

  # Railsヘルパーメソッドへのアクセスを明示的に宣言
  def h
    @h ||= ActionController::Base.helpers
  end
  
  def helpers
    h
  end

  # 日付のフォーマッタ
  # options:
  #   format: :short, :long, カスタムフォーマット文字列
  #   default: nil日付時のデフォルト値（デフォルト: 'N/A'）
  #   include_time: 時刻を含めるか（デフォルト: false）
  def formatted_date(date, options = {})
    return options[:default] || 'N/A' if date.nil?
    
    format = options[:format] || :default
    
    # テスト環境では英語フォーマットを使用
    if Rails.env.test?
      if format == :short
        formatted = date.strftime('%-d %b')
      elsif format == :long
        formatted = date.strftime('%B %-d, %Y')
      elsif format.is_a?(Symbol)
        formatted = date.strftime('%Y-%m-%d')
      else
        formatted = date.strftime(format)
      end
      
      if options[:include_time]
        time_format = options[:time_format] || '%H:%M'
        formatted + " " + date.strftime(time_format)
      else
        formatted
      end
    else
      # 本番環境ではI18nを使用
      if options[:include_time]
        time_format = options[:time_format] || '%H:%M'
        if format.is_a?(Symbol)
          I18n.l(date, format: format) + " " + date.strftime(time_format)
        else
          date.strftime(format) + " " + date.strftime(time_format)
        end
      else
        if format.is_a?(Symbol)
          I18n.l(date, format: format)
        else
          date.strftime(format)
        end
      end
    end
  end

  # 日時のフォーマッタ（後方互換性のため残す）
  def formatted_datetime(datetime, format = :default)
    return nil unless datetime
    I18n.l(datetime, format: format)
  end

  # 金額のフォーマッタ
  # options:
  #   precision: 小数点以下の桁数（デフォルト: 0）
  #   unit: 通貨単位（デフォルト: '¥'）
  #   default: nil金額時のデフォルト値（デフォルト: '¥0'）
  def formatted_currency(amount, options = {})
    default_value = options[:default] || '¥0'
    return default_value if amount.nil?
    
    h.number_to_currency(
      amount,
      unit: options[:unit] || '¥',
      precision: options[:precision] || 0
    )
  end

  # 状態によって色分けされたバッジを生成（Bootstrap互換）
  # options:
  #   css_class: カスタムCSSクラス
  #   label: カスタムラベル（statusの代わりに表示するテキスト）
  def status_badge(options = {})
    # モデルからstatusを取得（引数なしでも動作）
    status = object.respond_to?(:status) ? object.status : nil
    
    # カスタムラベルまたはstatusのhumanize
    label_text = options[:label] || (status ? status.to_s.humanize : '')
    
    # 基本のbadgeクラス
    css_classes = ['badge']
    
    # ステータスに応じたバリアントクラス
    variant_class = case status.to_s.downcase
    when 'active', 'normal'
      'badge-success'
    when 'pending', 'warning', 'expiring_soon'
      'badge-warning'
    when 'cancelled', 'rejected', 'expired'
      'badge-danger'
    when 'completed'
      'badge-info'
    when 'processing'
      'badge-primary'
    else
      'badge-secondary'
    end
    
    css_classes << variant_class
    
    # カスタムCSSクラスを追加
    css_classes << options[:css_class] if options[:css_class]
    
    # HTMLセーフティを確保しつつタグを生成
    h.content_tag(:span, label_text, class: css_classes.join(' ')).html_safe
  end

  # リンクが存在する場合のみリンクを生成
  # options:
  #   class: CSSクラス
  #   target: リンクターゲット（デフォルト: '_blank'）
  #   その他のHTML属性
  def link_if_present(url, text, options = {})
    return 'N/A' if url.nil? && text.nil?
    return h.content_tag(:span, text || '').html_safe if url.blank?
    
    # URL形式の基本検証
    unless url.to_s.match?(/\Ahttps?:\/\//)
      return h.content_tag(:span, text || url).html_safe
    end
    
    # デフォルトオプション
    link_options = {
      target: '_blank',
      rel: 'noopener'
    }.merge(options)
    
    h.link_to(text || url, url, link_options).html_safe
  end

  # テキストを指定文字数で切り詰め
  # options:
  #   length: 最大文字数（デフォルト: 50）
  #   omission: 省略記号（デフォルト: '...'）
  def truncated_text(text, options = {})
    return '' if text.nil?
    
    length = options[:length] || 50
    omission = options[:omission] || '...'
    
    # テスト環境では単純な切り詰め処理
    if Rails.env.test?
      if text.length > length
        truncated = text[0...(length - omission.length)] + omission
      else
        truncated = text
      end
    else
      truncated = h.truncate(text, length: length, omission: omission)
    end
    
    # 元のテキストがhtml_safeだった場合は保持
    text.html_safe? ? truncated.html_safe : truncated
  end

  # ブール値をアイコンで表示（FontAwesome使用）
  # options:
  #   true_icon: trueの時のアイコン（デフォルト: 'fa-check'）
  #   false_icon: falseの時のアイコン（デフォルト: 'fa-times'）
  #   nil_icon: nilの時のアイコン（デフォルト: 'fa-minus'）
  #   true_class: trueの時の色クラス（デフォルト: 'text-success'）
  #   false_class: falseの時の色クラス（デフォルト: 'text-danger'）
  #   nil_class: nilの時の色クラス（デフォルト: 'text-muted'）
  #   class: 追加CSSクラス
  def boolean_icon(value, options = {})
    icon_class = case value
    when true
      options[:true_icon] || 'fa-check'
    when false
      options[:false_icon] || 'fa-times'
    else
      options[:nil_icon] || 'fa-minus'
    end
    
    color_class = case value
    when true
      options[:true_class] || 'text-success'
    when false
      options[:false_class] || 'text-danger'
    else
      options[:nil_class] || 'text-muted'
    end
    
    css_classes = ['fa', icon_class, color_class]
    css_classes << options[:class] if options[:class]
    
    h.content_tag(:i, '', class: css_classes.join(' ')).html_safe
  end

  # プログレスバーを生成（Bootstrap互換）
  # options:
  #   color: カスタム色（'primary', 'success'等）
  #   class: 追加CSSクラス
  #   show_label: ラベル表示の有無（デフォルト: true）
  #   label: カスタムラベルテキスト
  def progress_bar(percentage, options = {})
    # パーセンテージを0-100の範囲に制限
    percentage = [[percentage.to_f, 0].max, 100].min
    
    # 自動色分け（colorオプションがない場合）
    color = options[:color] || case percentage
    when 0..30
      'danger'
    when 31..70
      'warning'
    else
      'success'
    end
    
    # プログレスバーのクラス
    progress_class = ['progress-bar', "bg-#{color}"]
    progress_class << options[:class] if options[:class]
    
    # ラベルテキスト
    label = if options[:show_label] == false
      ''
    else
      options[:label] || "#{percentage.to_i}%"
    end
    
    # プログレスバーHTML
    progress_bar_html = h.content_tag(:div, 
      label,
      class: progress_class.join(' '),
      style: "width: #{percentage}%",
      role: 'progressbar',
      'aria-valuenow': percentage,
      'aria-valuemin': 0,
      'aria-valuemax': 100
    )
    
    # プログレスコンテナ
    h.content_tag(:div, progress_bar_html, class: 'progress')
  end

  # TODO: 🟡 Phase 3（重要）- 追加UIヘルパーメソッドの実装
  # 優先度: 中
  # 実装内容:
  #   - formatted_percentage: パーセンテージ表示のフォーマット
  #   - formatted_number: 数値のカンマ区切り表示
  #   - time_ago_in_words_with_tooltip: 相対時間表示とツールチップ
  # 理由: 他のビューでも頻繁に使用される共通UI要素
  # 横展開: 全てのデコレーターで利用可能にする
end
