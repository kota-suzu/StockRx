# frozen_string_literal: true

# Branch Coverage Helper - 分岐カバレッジ追跡支援モジュール
# CLAUDE.md準拠: 各Claude Codeが使用する共通インターフェース
module BranchCoverageHelper
  extend self

  PROGRESS_DIR = 'coverage/progress'

  # ファイル単位の分岐カバレッジを取得
  def branch_coverage_for(file_path)
    return {} unless File.exist?(file_path)

    # SimpleCovの結果から分岐情報を抽出
    if defined?(SimpleCov) && SimpleCov.result
      file_coverage = SimpleCov.result.files.find { |f| f.filename.include?(file_path) }
      return {} unless file_coverage

      {
        total_branches: file_coverage.total_branches.length,
        covered_branches: file_coverage.covered_branches.length,
        missed_branches: file_coverage.missed_branches.length,
        coverage_percent: file_coverage.branches_coverage_percent
      }
    else
      {}
    end
  end

  # 進捗報告用メソッド
  def report_progress(claude_code_id, file_path, covered_branches, total_branches)
    progress_data = {
      claude_code_id: claude_code_id,
      file: file_path,
      covered_branches: covered_branches,
      total_branches: total_branches,
      branch_coverage: total_branches > 0 ? (covered_branches.to_f / total_branches * 100).round(2) : 0.0,
      timestamp: Time.now.iso8601
    }

    # ファイルに保存
    FileUtils.mkdir_p(PROGRESS_DIR)
    progress_file = File.join(PROGRESS_DIR, "cc#{claude_code_id}_progress.json")
    File.write(progress_file, progress_data.to_json)

    # コンソールにも出力
    puts "📊 CC##{claude_code_id} Progress: #{file_path} - #{progress_data[:branch_coverage]}% (#{covered_branches}/#{total_branches})"

    progress_data
  end

  # 未カバーの分岐を特定
  def identify_uncovered_branches(file_path)
    coverage_data = branch_coverage_for(file_path)
    return [] if coverage_data.empty?

    # SimpleCovから詳細な分岐情報を取得
    if defined?(SimpleCov) && SimpleCov.result
      file_coverage = SimpleCov.result.files.find { |f| f.filename.include?(file_path) }
      return [] unless file_coverage

      file_coverage.missed_branches.map do |branch|
        {
          line: branch.start_line,
          type: branch.type,
          coverage: branch.coverage
        }
      end
    else
      []
    end
  end

  # 統合レポート生成用のデータ収集
  def collect_all_progress
    Dir.glob(File.join(PROGRESS_DIR, "*.json")).map do |file|
      JSON.parse(File.read(file))
    rescue JSON::ParserError
      nil
    end.compact
  end

  # 現在の総合カバレッジを計算
  def calculate_total_coverage
    all_progress = collect_all_progress
    return 0.0 if all_progress.empty?

    total_covered = all_progress.sum { |p| p['covered_branches'] || 0 }
    total_branches = all_progress.sum { |p| p['total_branches'] || 0 }

    return 0.0 if total_branches == 0

    (total_covered.to_f / total_branches * 100).round(2)
  end

  # カバレッジ目標達成状況を確認
  def check_coverage_target(target = 70.0)
    current = calculate_total_coverage
    {
      current_coverage: current,
      target_coverage: target,
      achieved: current >= target,
      remaining: (target - current).round(2)
    }
  end
end
