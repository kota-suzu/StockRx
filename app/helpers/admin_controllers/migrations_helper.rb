# frozen_string_literal: true

# マイグレーション管理画面ヘルパー
#
# CLAUDE.md準拠の設計:
# - 可読性向上
# - 国際化対応
# - セキュリティ配慮
module AdminControllers::MigrationsHelper
  # ============================================
  # ステータス表示関連
  # ============================================

  # ステータスアイコンを返す
  def status_icon(status)
    case status.to_s
    when "pending"
      "⏳"
    when "running"
      "🔄"
    when "completed"
      "✅"
    when "failed"
      "❌"
    when "rolled_back"
      "↩️"
    when "paused"
      "⏸️"
    when "cancelled"
      "🚫"
    else
      "❓"
    end
  end

  # ステータス文字列を日本語化
  def humanize_status(status)
    case status.to_s
    when "pending"
      "実行待ち"
    when "running"
      "実行中"
    when "completed"
      "完了"
    when "failed"
      "失敗"
    when "rolled_back"
      "ロールバック済み"
    when "paused"
      "一時停止"
    when "cancelled"
      "キャンセル"
    else
      status.to_s.humanize
    end
  end

  # ステータスに応じたCSSクラスを返す
  def status_class(status)
    case status.to_s
    when "pending"
      "text-muted"
    when "running"
      "text-info"
    when "completed"
      "text-success"
    when "failed"
      "text-danger"
    when "rolled_back"
      "text-warning"
    when "paused"
      "text-warning"
    when "cancelled"
      "text-secondary"
    else
      "text-muted"
    end
  end

  # ============================================
  # 時間表示関連
  # ============================================

  # 実行時間をフォーマット
  def format_duration(duration)
    return "N/A" unless duration

    total_seconds = duration.to_i

    if total_seconds < 60
      "#{total_seconds}秒"
    elsif total_seconds < 3600
      minutes = total_seconds / 60
      seconds = total_seconds % 60
      "#{minutes}分#{seconds}秒"
    else
      hours = total_seconds / 3600
      minutes = (total_seconds % 3600) / 60
      "#{hours}時間#{minutes}分"
    end
  end

  # マイグレーション実行時間をフォーマット（エイリアス）
  def format_execution_duration(duration)
    format_duration(duration)
  end

  # 推定時刻から現在時刻までの時間を表示
  def format_duration_from_now(time)
    return "N/A" unless time && time > Time.current

    duration = time - Time.current
    format_duration(duration)
  end

  # 相対時刻表示
  def time_ago_in_words_japanese(time)
    return "N/A" unless time

    distance = Time.current - time

    case distance
    when 0..59
      "#{distance.to_i}秒前"
    when 60..3599
      "#{(distance / 60).to_i}分前"
    when 3600..86399
      "#{(distance / 3600).to_i}時間前"
    else
      "#{(distance / 86400).to_i}日前"
    end
  end

  # ============================================
  # 数値フォーマット関連
  # ============================================

  # レコード数を適切な単位で表示
  def format_record_count(count)
    return "0" unless count && count > 0

    if count >= 1_000_000
      "#{(count / 1_000_000.0).round(1)}M"
    elsif count >= 1_000
      "#{(count / 1_000.0).round(1)}K"
    else
      number_with_delimiter(count)
    end
  end

  # 処理速度を表示
  def format_records_per_second(rps)
    return "N/A" unless rps && rps >= 0

    if rps >= 1000
      "#{(rps / 1000.0).round(1)}K/秒"
    else
      "#{rps.round(1)}/秒"
    end
  end

  # パーセンテージを表示
  def format_percentage(value, precision: 1)
    return "0%" unless value

    "#{value.round(precision)}%"
  end

  # ============================================
  # プログレスバー関連
  # ============================================

  # プログレスバーのHTML生成
  def progress_bar(percentage, options = {})
    percentage = [ percentage.to_f, 100.0 ].min
    css_class = options[:class] || "progress-bar"
    show_text = options[:show_text] != false

    color_class = case percentage
    when 0..30
                    "bg-danger"
    when 31..70
                    "bg-warning"
    else
                    "bg-success"
    end

    content_tag :div, class: "progress #{options[:wrapper_class]}" do
      content_tag :div, class: "#{css_class} #{color_class}",
                        style: "width: #{percentage}%",
                        "aria-valuenow" => percentage,
                        "aria-valuemin" => "0",
                        "aria-valuemax" => "100" do
        show_text ? "#{percentage.round(1)}%" : ""
      end
    end
  end

  # システムメトリクス用プログレスバー
  def system_metric_bar(value, max_value, label)
    percentage = (value.to_f / max_value * 100).round(1)

    color_class = case percentage
    when 0..50
                    "bg-success"
    when 51..80
                    "bg-warning"
    else
                    "bg-danger"
    end

    content_tag :div, class: "metric-bar-container" do
      concat content_tag(:div, label, class: "metric-label")
      concat content_tag(:div, class: "progress") do
        content_tag :div, "#{percentage}%",
                    class: "progress-bar #{color_class}",
                    style: "width: #{percentage}%"
      end
    end
  end

  # ============================================
  # アラート関連
  # ============================================

  # アラートレベルを判定
  def alert_level_for_metrics(cpu_usage, memory_usage, records_per_second)
    return "success" unless cpu_usage || memory_usage || records_per_second

    if (cpu_usage && cpu_usage > 90) ||
       (memory_usage && memory_usage > 95) ||
       (records_per_second && records_per_second < 10)
      "danger"
    elsif (cpu_usage && cpu_usage > 70) ||
          (memory_usage && memory_usage > 80) ||
          (records_per_second && records_per_second < 100)
      "warning"
    else
      "success"
    end
  end

  # アラートメッセージを生成
  def generate_alert_message(cpu_usage, memory_usage, records_per_second)
    alerts = []

    alerts << "CPU使用率が高い (#{cpu_usage.round(1)}%)" if cpu_usage && cpu_usage > 80
    alerts << "メモリ使用率が高い (#{memory_usage.round(1)}%)" if memory_usage && memory_usage > 85
    alerts << "処理速度が低下 (#{records_per_second.round(1)}/秒)" if records_per_second && records_per_second < 50

    alerts.empty? ? nil : alerts.join(", ")
  end

  # ============================================
  # 設定値表示関連
  # ============================================

  # 設定値を適切にフォーマット
  def format_config_value(key, value)
    case key.to_s
    when "batch_size"
      "#{number_with_delimiter(value)} レコード/バッチ"
    when "cpu_threshold", "memory_threshold"
      "#{value}%"
    when "max_retries"
      "#{value} 回"
    when "timeout"
      "#{value} 秒"
    when /.*_at$/
      value.is_a?(String) ? Time.parse(value).strftime("%Y/%m/%d %H:%M") : value&.strftime("%Y/%m/%d %H:%M")
    else
      value.to_s
    end
  rescue
    value.to_s
  end

  # ============================================
  # フェーズ表示関連
  # ============================================

  # フェーズ名を日本語化
  def humanize_phase(phase)
    case phase.to_s
    when "initialization"
      "初期化"
    when "schema_change"
      "スキーマ変更"
    when "data_migration"
      "データ移行"
    when "index_creation"
      "インデックス作成"
    when "validation"
      "検証"
    when "cleanup"
      "クリーンアップ"
    when "rollback"
      "ロールバック"
    else
      phase.to_s.humanize
    end
  end

  # フェーズアイコンを返す
  def phase_icon(phase)
    case phase.to_s
    when "initialization"
      "🔧"
    when "schema_change"
      "🏗️"
    when "data_migration"
      "📊"
    when "index_creation"
      "🗂️"
    when "validation"
      "✅"
    when "cleanup"
      "🧹"
    when "rollback"
      "↩️"
    else
      "📋"
    end
  end

  # ============================================
  # ユーティリティ
  # ============================================

  # マイグレーション実行可能性チェック
  def migration_executable?(execution)
    execution.can_execute? && (current_admin.respond_to?(:can_execute_migrations?) ? current_admin.can_execute_migrations? : true)
  end

  # システム状態バッジを生成
  def system_status_badge(metrics)
    return "N/A" unless metrics

    cpu_usage = metrics["cpu_usage"] || metrics[:cpu_usage]
    memory_usage = metrics["memory_usage"] || metrics[:memory_usage]
    records_per_second = metrics["records_per_second"] || metrics[:records_per_second]

    level = alert_level_for_metrics(cpu_usage, memory_usage, records_per_second)

    case level
    when "danger"
      content_tag :span, "危険", class: "badge badge-danger"
    when "warning"
      content_tag :span, "警告", class: "badge badge-warning"
    else
      content_tag :span, "正常", class: "badge badge-success"
    end
  end

  # 危険な操作の確認メッセージ
  def dangerous_operation_message(operation)
    case operation.to_s
    when "rollback"
      "このマイグレーションをロールバックしますか？\n\n⚠️ この操作は元に戻せません。\n⚠️ データが失われる可能性があります。\n⚠️ 十分に確認してから実行してください。"
    when "cancel"
      "このマイグレーションをキャンセルしますか？\n\n実行中の処理は停止され、データが不整合な状態になる可能性があります。"
    when "force_release"
      "このロックを強制解放しますか？\n\n⚠️ 他のプロセスがマイグレーションを実行中の場合、データ破損の原因となります。"
    else
      "この操作を実行しますか？"
    end
  end

  # JSONデータを安全に表示
  def safe_json_display(json_data, max_length: 100)
    return "N/A" unless json_data

    if json_data.is_a?(Hash) || json_data.is_a?(Array)
      json_string = JSON.pretty_generate(json_data)
    else
      json_string = json_data.to_s
    end

    if json_string.length > max_length
      truncate(json_string, length: max_length, omission: "... (#{json_string.length - max_length} 文字省略)")
    else
      json_string
    end
  rescue JSON::GeneratorError
    "表示できません"
  end
end

# ============================================
# 設計ノート（CLAUDE.md準拠）
# ============================================

# 1. 国際化対応
#    - 日本語表示メソッドの提供
#    - 将来的なi18n対応準備
#    - ユーザビリティ向上

# 2. セキュリティ配慮
#    - XSS対策（適切なエスケープ）
#    - JSONデータの安全な表示
#    - 危険操作の明確な警告

# 3. パフォーマンス考慮
#    - 複雑な計算のキャッシュ化検討
#    - ビューでの重複処理排除
#    - 効率的な文字列操作

# TODO: 拡張実装予定
# - [MEDIUM] 多言語対応（i18n統合）
# - [MEDIUM] ダークモード対応
# - [LOW] カスタムフォーマット設定
# - [LOW] アクセシビリティ向上
