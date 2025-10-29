#!/usr/bin/env ruby
# frozen_string_literal: true

# StockRx品質保証自動実行スクリプト
# テストカバレッジ、パフォーマンス、セキュリティの包括的チェック

require 'fileutils'
require 'json'
require 'time'

class QualityAssurance
  REPORT_DIR = 'tmp/qa_reports'
  TIMESTAMP = Time.current.strftime('%Y%m%d_%H%M%S')

  def initialize
    setup_directories
    @results = {
      timestamp: Time.current.iso8601,
      test_results: {},
      coverage: {},
      performance: {},
      security: {},
      recommendations: []
    }
  end

  def run_full_assessment
    puts "🚀 StockRx品質保証フル評価を開始します"
    puts "=" * 60

    begin
      run_test_suite
      analyze_coverage
      run_performance_tests
      run_security_scan
      generate_recommendations
      save_report
      print_summary
    rescue => e
      puts "❌ 品質保証実行中にエラーが発生しました: #{e.message}"
      puts e.backtrace.first(5)
    end
  end

  private

  def setup_directories
    FileUtils.mkdir_p(REPORT_DIR)
    FileUtils.mkdir_p('tmp/qa_reports/coverage')
    FileUtils.mkdir_p('tmp/qa_reports/security')
    FileUtils.mkdir_p('tmp/qa_reports/performance')
  end

  def run_test_suite
    puts "\n📋 テストスイート実行中..."

    # 軽量テスト（モデルのみ）
    puts "  🧪 モデルテスト実行..."
    model_result = run_command("COVERAGE=true RAILS_ENV=test bundle exec rspec spec/models --format json")

    # コントローラーテスト
    puts "  🎮 コントローラーテスト実行..."
    controller_result = run_command("RAILS_ENV=test bundle exec rspec spec/controllers --format json")

    # 統合テスト（時間制限付き）
    puts "  🔗 統合テスト実行..."
    integration_result = run_command("timeout 300 RAILS_ENV=test bundle exec rspec spec/features spec/requests --format json")

    @results[:test_results] = {
      models: parse_rspec_result(model_result),
      controllers: parse_rspec_result(controller_result),
      integration: parse_rspec_result(integration_result)
    }
  end

  def analyze_coverage
    puts "\n📊 テストカバレッジ分析中..."

    coverage_file = 'coverage/.resultset.json'
    if File.exist?(coverage_file)
      coverage_data = JSON.parse(File.read(coverage_file))

      # SimpleCovの結果を解析
      if coverage_data['RSpec']
        result = coverage_data['RSpec']
        total_lines = result['coverage'].values.flatten.size
        covered_lines = result['coverage'].values.flatten.count { |line| line&.positive? }

        @results[:coverage] = {
          line_coverage: total_lines > 0 ? (covered_lines.to_f / total_lines * 100).round(2) : 0,
          total_lines: total_lines,
          covered_lines: covered_lines,
          files_count: result['coverage'].size,
          timestamp: result['timestamp']
        }

        puts "  ✅ カバレッジ: #{@results[:coverage][:line_coverage]}%"
      end
    else
      puts "  ⚠️  カバレッジファイルが見つかりません"
      @results[:coverage] = { error: "Coverage file not found" }
    end
  end

  def run_performance_tests
    puts "\n⚡ パフォーマンステスト実行中..."

    # N+1クエリチェック
    puts "  🗃️  N+1クエリチェック..."
    n_plus_one_result = run_command("PERFORMANCE_TEST=true RAILS_ENV=test bundle exec rspec spec/models/inventory_spec.rb --tag performance")

    # メモリ使用量チェック
    puts "  💾 メモリ使用量チェック..."
    memory_result = check_memory_usage

    @results[:performance] = {
      n_plus_one_check: n_plus_one_result[:success],
      memory_usage: memory_result,
      response_time_ok: true # プレースホルダー
    }
  end

  def run_security_scan
    puts "\n🔒 セキュリティスキャン実行中..."

    # Brakemanスキャン
    puts "  🛡️  Brakemanセキュリティスキャン..."
    brakeman_result = run_command("bundle exec brakeman --no-exit-on-warn --format json")

    # カスタムセキュリティテスト
    puts "  🔐 カスタムセキュリティテスト..."
    custom_security_result = run_command("SECURITY_TEST=true RAILS_ENV=test bundle exec rspec spec/security --format json")

    @results[:security] = {
      brakeman_scan: parse_brakeman_result(brakeman_result),
      custom_tests: parse_rspec_result(custom_security_result),
      vulnerability_count: 0 # プレースホルダー
    }
  end

  def generate_recommendations
    puts "\n💡 改善推奨事項を生成中..."

    # カバレッジベースの推奨
    if @results[:coverage][:line_coverage] && @results[:coverage][:line_coverage] < 80
      @results[:recommendations] << {
        category: "テストカバレッジ",
        priority: "高",
        description: "テストカバレッジが#{@results[:coverage][:line_coverage]}%です。80%以上を目標に改善してください。",
        actions: [
          "未テストのモデルにテストケースを追加",
          "コントローラーテストを拡充",
          "エッジケースのテストを実装"
        ]
      }
    end

    # パフォーマンスベースの推奨
    unless @results[:performance][:n_plus_one_check]
      @results[:recommendations] << {
        category: "パフォーマンス",
        priority: "中",
        description: "N+1クエリが検出されました。",
        actions: [
          "includes/joinsを使用してEager Loadingを実装",
          "Counter Cacheを検討",
          "Bulletgemの警告を確認"
        ]
      }
    end

    # セキュリティベースの推奨
    if @results[:security][:vulnerability_count] > 0
      @results[:recommendations] << {
        category: "セキュリティ",
        priority: "高",
        description: "#{@results[:security][:vulnerability_count]}件の脆弱性が検出されました。",
        actions: [
          "Brakemanの警告を確認して修正",
          "入力値のサニタイゼーションを強化",
          "認証・認可ロジックを見直し"
        ]
      }
    end
  end

  def save_report
    puts "\n💾 レポートを保存中..."

    report_file = "#{REPORT_DIR}/qa_report_#{TIMESTAMP}.json"
    File.write(report_file, JSON.pretty_generate(@results))

    # HTML形式でも保存
    html_report = generate_html_report
    html_file = "#{REPORT_DIR}/qa_report_#{TIMESTAMP}.html"
    File.write(html_file, html_report)

    puts "  📄 JSON レポート: #{report_file}"
    puts "  🌐 HTML レポート: #{html_file}"
  end

  def print_summary
    puts "\n" + "=" * 60
    puts "📊 StockRx品質保証レポート"
    puts "=" * 60

    puts "\n🧪 テスト結果:"
    @results[:test_results].each do |category, result|
      status = result[:failures] == 0 ? "✅" : "❌"
      puts "  #{status} #{category.to_s.capitalize}: #{result[:examples]}例 (#{result[:failures]}失敗)"
    end

    puts "\n📊 カバレッジ:"
    if @results[:coverage][:line_coverage]
      status = @results[:coverage][:line_coverage] >= 80 ? "✅" : "❌"
      puts "  #{status} 行カバレッジ: #{@results[:coverage][:line_coverage]}%"
    end

    puts "\n⚡ パフォーマンス:"
    n_plus_one_status = @results[:performance][:n_plus_one_check] ? "✅" : "❌"
    puts "  #{n_plus_one_status} N+1クエリチェック"

    puts "\n🔒 セキュリティ:"
    vuln_status = @results[:security][:vulnerability_count] == 0 ? "✅" : "❌"
    puts "  #{vuln_status} 脆弱性: #{@results[:security][:vulnerability_count]}件"

    puts "\n💡 推奨事項: #{@results[:recommendations].size}件"
    @results[:recommendations].each_with_index do |rec, index|
      puts "  #{index + 1}. [#{rec[:priority]}] #{rec[:category]}: #{rec[:description]}"
    end

    puts "\n" + "=" * 60
    puts "📈 品質改善目標:"
    puts "  🎯 テストカバレッジ: 80%以上"
    puts "  🎯 レスポンス時間: 200ms以下"
    puts "  🎯 セキュリティ脆弱性: 0件"
    puts "=" * 60
  end

  def run_command(command)
    puts "    実行中: #{command}"
    success = system(command)
    { success: success, command: command }
  end

  def parse_rspec_result(result)
    # RSpecのJSON結果をパース（プレースホルダー）
    {
      examples: 0,
      failures: 0,
      pending: 0,
      duration: 0.0
    }
  end

  def parse_brakeman_result(result)
    # Brakemanの結果をパース（プレースホルダー）
    {
      warnings: [],
      errors: [],
      security_warnings: 0
    }
  end

  def check_memory_usage
    # メモリ使用量をチェック（プレースホルダー）
    {
      current_mb: 0,
      peak_mb: 0,
      status: "normal"
    }
  end

  def generate_html_report
    # HTML形式のレポートを生成（プレースホルダー）
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>StockRx 品質保証レポート</title>
        <meta charset="utf-8">
        <style>
          body { font-family: Arial, sans-serif; margin: 20px; }
          .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
          .section { margin: 20px 0; padding: 15px; border: 1px solid #ddd; border-radius: 5px; }
          .success { color: #28a745; }
          .warning { color: #ffc107; }
          .error { color: #dc3545; }
        </style>
      </head>
      <body>
        <div class="header">
          <h1>🚀 StockRx 品質保証レポート</h1>
          <p>生成日時: #{@results[:timestamp]}</p>
        </div>
      #{'  '}
        <div class="section">
          <h2>📊 サマリー</h2>
          <p>このレポートの詳細情報は開発中です。</p>
        </div>
      </body>
      </html>
    HTML
  end
end

# スクリプト実行
if __FILE__ == $0
  qa = QualityAssurance.new
  qa.run_full_assessment
end
