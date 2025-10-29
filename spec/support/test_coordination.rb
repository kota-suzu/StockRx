# frozen_string_literal: true

require 'json'
require 'fileutils'

# TestCoordination - 10個のClaude Code間の進捗管理システム
# CLAUDE.md準拠: PM/PLの役割として全体進捗を統括
class TestCoordination
  COVERAGE_LOG_PATH = 'coverage/coordination.log'
  PROGRESS_PATH = 'coverage/progress'
  CONSOLIDATED_REPORT = 'coverage/consolidated_report.json'

  # カバレッジ目標
  COVERAGE_TARGETS = {
    phase_1: 20.0,  # 第1フェーズ目標
    phase_2: 40.0,  # 第2フェーズ目標
    phase_3: 70.0   # 最終目標
  }.freeze

  # ファイル別の担当割り当て
  FILE_ASSIGNMENTS = {
    1 => { file: 'coordination', role: 'coordinator' },
    2 => { file: 'inventory_search_form.rb', branches: 143 },
    3 => { file: 'search_query.rb', branches: 107 },
    4 => { file: 'application_helper.rb', branches: 102 },
    5 => { file: 'application_controller.rb', branches: 87 },
    6 => { file: 'inventory.rb', branches: 77 },
    7 => { file: 'csv_export_service.rb', branches: 76 },
    8 => { file: 'inventories_controller.rb', branches: 73 },
    9 => { file: 'stores_controller.rb', branches: 63 },
    10 => { file: 'quality_assurance', role: 'qa' }
  }.freeze

  def initialize
    FileUtils.mkdir_p(PROGRESS_PATH)
    @start_time = Time.now
    @target_coverage = COVERAGE_TARGETS[:phase_3]
    @current_phase = :phase_1
  end

  # 進捗モニタリングを開始（非同期）
  def start_monitoring
    Thread.new do
      loop do
        generate_progress_report
        check_phase_completion
        sleep 30 # 30秒ごとに進捗確認
      end
    end
  end

  # 各Claude Codeの進捗を収集
  def collect_progress
    Dir.glob("#{PROGRESS_PATH}/*.json").map do |file|
      JSON.parse(File.read(file))
    rescue JSON::ParserError
      nil
    end.compact
  end

  # 統合進捗レポートを生成
  def generate_progress_report
    progress_data = collect_progress
    current = calculate_total_coverage(progress_data)

    report = {
      timestamp: Time.now.iso8601,
      current_coverage: current,
      current_phase: @current_phase,
      phase_target: COVERAGE_TARGETS[@current_phase],
      final_target: @target_coverage,
      elapsed_time: format_duration(Time.now - @start_time),
      claude_code_status: build_status_summary(progress_data),
      uncovered_files: identify_priority_files(progress_data),
      recommendations: generate_recommendations(current, progress_data)
    }

    File.write(CONSOLIDATED_REPORT, JSON.pretty_generate(report))
    display_progress_summary(report)

    report
  end

  # フェーズ完了をチェック
  def check_phase_completion
    current = calculate_total_coverage(collect_progress)

    case @current_phase
    when :phase_1
      if current >= COVERAGE_TARGETS[:phase_1]
        @current_phase = :phase_2
        notify_phase_completion(:phase_1, current)
      end
    when :phase_2
      if current >= COVERAGE_TARGETS[:phase_2]
        @current_phase = :phase_3
        notify_phase_completion(:phase_2, current)
      end
    when :phase_3
      if current >= COVERAGE_TARGETS[:phase_3]
        notify_target_achieved(current)
      end
    end
  end

  private

  # 総合カバレッジを計算
  def calculate_total_coverage(progress_data)
    return 0.0 if progress_data.empty?

    total_covered = progress_data.sum { |p| p['covered_branches'] || 0 }
    total_branches = progress_data.sum { |p| p['total_branches'] || 0 }

    return 0.0 if total_branches == 0

    (total_covered.to_f / total_branches * 100).round(2)
  end

  # Claude Code別のステータスサマリーを構築
  def build_status_summary(progress_data)
    FILE_ASSIGNMENTS.map do |cc_id, assignment|
      progress = progress_data.find { |p| p['claude_code_id'] == cc_id }

      if progress
        {
          id: cc_id,
          file: assignment[:file],
          coverage: progress['branch_coverage'],
          status: determine_status(progress['branch_coverage']),
          last_update: progress['timestamp']
        }
      else
        {
          id: cc_id,
          file: assignment[:file],
          coverage: 0.0,
          status: 'not_started',
          last_update: nil
        }
      end
    end
  end

  # カバレッジに基づくステータス判定
  def determine_status(coverage)
    case coverage
    when 0 then 'not_started'
    when 1..30 then 'in_progress'
    when 31..60 then 'progressing'
    when 61..90 then 'nearly_complete'
    else 'completed'
    end
  end

  # 優先的に対応すべきファイルを特定
  def identify_priority_files(progress_data)
    FILE_ASSIGNMENTS.select do |cc_id, assignment|
      next false if assignment[:role] # コーディネーターやQAは除外

      progress = progress_data.find { |p| p['claude_code_id'] == cc_id }
      coverage = progress ? progress['branch_coverage'] : 0

      coverage < 50 # 50%未満のファイルを優先対象とする
    end.map do |cc_id, assignment|
      {
        claude_code: cc_id,
        file: assignment[:file],
        total_branches: assignment[:branches]
      }
    end
  end

  # 推奨事項を生成
  def generate_recommendations(current_coverage, progress_data)
    recommendations = []

    # フェーズ別の推奨事項
    case @current_phase
    when :phase_1
      recommendations << "基本的な条件分岐のテストに集中してください"
      recommendations << "各ファイルで最低20%のカバレッジを目指しましょう"
    when :phase_2
      recommendations << "複雑な条件の組み合わせテストを追加してください"
      recommendations << "エッジケースの考慮を始めましょう"
    when :phase_3
      recommendations << "残りの未カバー分岐を特定して対応してください"
      recommendations << "パフォーマンステストも考慮しましょう"
    end

    # 遅れているClaude Codeへの推奨
    slow_progress = progress_data.select { |p| (p['branch_coverage'] || 0) < 30 }
    if slow_progress.any?
      recommendations << "CC##{slow_progress.map { |p| p['claude_code_id'] }.join(', ')}の進捗が遅れています。支援が必要か確認してください。"
    end

    recommendations
  end

  # 進捗サマリーを表示
  def display_progress_summary(report)
    puts "\n" + "="*80
    puts "📊 Branch Coverage Progress Report - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "="*80
    puts "Current Coverage: #{report[:current_coverage]}% / Target: #{report[:final_target]}%"
    puts "Current Phase: #{report[:current_phase]} (Target: #{report[:phase_target]}%)"
    puts "Elapsed Time: #{report[:elapsed_time]}"
    puts "\nClaude Code Status:"

    report[:claude_code_status].each do |status|
      emoji = case status[:status]
      when 'completed' then '✅'
      when 'nearly_complete' then '🔵'
      when 'progressing' then '🟡'
      when 'in_progress' then '🟠'
      else '⭕'
      end

      puts "  #{emoji} CC##{status[:id]}: #{status[:file]} - #{status[:coverage]}%"
    end

    if report[:recommendations].any?
      puts "\n📝 Recommendations:"
      report[:recommendations].each { |rec| puts "  • #{rec}" }
    end

    puts "="*80 + "\n"
  end

  # フェーズ完了を通知
  def notify_phase_completion(phase, coverage)
    puts "\n🎉 Phase #{phase} completed! Current coverage: #{coverage}%"
    puts "Moving to next phase: #{@current_phase}"
  end

  # 目標達成を通知
  def notify_target_achieved(coverage)
    puts "\n🎊 Target achieved! Final coverage: #{coverage}%"
    puts "Mission completed in #{format_duration(Time.now - @start_time)}"
  end

  # 時間をフォーマット
  def format_duration(seconds)
    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    "#{hours}h #{minutes}m"
  end
end

# 自動実行設定（requireされた時点で開始）
if ENV['COVERAGE_COORDINATION'] == 'true'
  coordinator = TestCoordination.new
  coordinator.start_monitoring
  puts "📊 Test Coordination started. Monitoring progress..."
end
