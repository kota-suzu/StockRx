# frozen_string_literal: true

# 品質ゲート設定
# StockRx品質保証改善計画に基づく自動品質チェック
module QualityGates
  class Coverage
    # 品質ゲートのしきい値
    MINIMUM_LINE_COVERAGE = 80.0
    MINIMUM_BRANCH_COVERAGE = 60.0
    RECOMMENDED_LINE_COVERAGE = 85.0
    RECOMMENDED_BRANCH_COVERAGE = 70.0

    def self.check_coverage
      return true unless defined?(SimpleCov)

      result = SimpleCov.result
      line_coverage = result.covered_percent
      branch_coverage = result.branch_coverage_percent if result.respond_to?(:branch_coverage_percent)

      puts "\n" + "="*50
      puts "品質ゲート評価結果"
      puts "="*50

      # 行カバレッジチェック
      puts "行カバレッジ: #{line_coverage.round(2)}%"
      line_status = if line_coverage >= RECOMMENDED_LINE_COVERAGE
                      "✅ 推奨レベル"
      elsif line_coverage >= MINIMUM_LINE_COVERAGE
                      "⚠️  最低レベル"
      else
                      "❌ 不合格"
      end
      puts "  └ #{line_status} (最低: #{MINIMUM_LINE_COVERAGE}%, 推奨: #{RECOMMENDED_LINE_COVERAGE}%)"

      # ブランチカバレッジチェック
      if branch_coverage
        puts "ブランチカバレッジ: #{branch_coverage.round(2)}%"
        branch_status = if branch_coverage >= RECOMMENDED_BRANCH_COVERAGE
                          "✅ 推奨レベル"
        elsif branch_coverage >= MINIMUM_BRANCH_COVERAGE
                          "⚠️  最低レベル"
        else
                          "❌ 不合格"
        end
        puts "  └ #{branch_status} (最低: #{MINIMUM_BRANCH_COVERAGE}%, 推奨: #{RECOMMENDED_BRANCH_COVERAGE}%)"
      end

      # 品質ゲート判定
      passing = line_coverage >= MINIMUM_LINE_COVERAGE
      if branch_coverage
        passing = passing && branch_coverage >= MINIMUM_BRANCH_COVERAGE
      end

      puts "\n品質ゲート結果: #{passing ? '✅ 合格' : '❌ 不合格'}"
      puts "="*50

      passing
    end
  end

  class Performance
    # パフォーマンスしきい値
    MAX_QUERIES_PER_REQUEST = 5
    MAX_RESPONSE_TIME_MS = 200

    def self.setup_bullet_checks
      return unless defined?(Bullet)

      Bullet.enable = true
      Bullet.bullet_logger = true
      Bullet.raise = true # テスト環境ではN+1で例外を発生
    end

    def self.check_n_plus_one
      # N+1クエリチェック（Bulletと連動）
      setup_bullet_checks
      puts "N+1クエリ検出: 有効化"
    end
  end

  class Security
    # セキュリティチェック
    def self.run_security_scan
      puts "\n" + "="*50
      puts "セキュリティスキャン実行中..."
      puts "="*50

      # Brakeman実行
      system("bundle exec brakeman --no-exit-on-warn --no-exit-on-error -q")

      puts "セキュリティスキャン完了"
      puts "="*50
    end
  end
end

# RSpec設定に品質ゲートを統合
RSpec.configure do |config|
  # テスト開始時の設定
  config.before(:suite) do
    QualityGates::Performance.check_n_plus_one
  end

  # テスト終了時の品質ゲートチェック
  config.after(:suite) do
    if ENV['COVERAGE'] == 'true'
      passed = QualityGates::Coverage.check_coverage

      # カバレッジが不足している場合の詳細情報
      unless passed
        puts "\n品質改善のための推奨アクション:"
        puts "1. 未テストのモデルにテストケースを追加"
        puts "2. コントローラーテストを拡充"
        puts "3. エッジケースのテストを実装"
        puts "4. 統合テストを追加"
        puts "\n詳細: /coverage/index.html を参照"
      end
    end

    # セキュリティスキャンを定期実行
    QualityGates::Security.run_security_scan if ENV['SECURITY_SCAN'] == 'true'
  end
end
