namespace :performance do
  desc "1万行のCSVファイルを生成"
  task generate_csv: :environment do
    require_relative "../../test/fixtures/files/generate_test_csv"
  end

  desc "CSVインポートのパフォーマンスをテスト"
  task test_csv_import: :environment do
    csv_path = Rails.root.join("test/fixtures/files/large_inventory.csv")

    unless File.exist?(csv_path)
      puts "CSVファイルが見つかりません。先に rake performance:generate_csv を実行してください。"
      exit 1
    end

    # 古いレコードをクリーンアップ（オプショナル）
    if ENV["CLEAN_DB"] == "true"
      puts "データベースをクリーンアップ中..."
      Inventory.delete_all
      puts "完了。"
    end

    # 初期レコード数を記録
    initial_count = Inventory.count
    puts "現在のインベントリ数: #{initial_count}"

    # 計測開始
    puts "#{csv_path} からのインポート開始..."
    start_time = Time.current

    # 標準のバッチサイズでインポート
    result = Inventory.import_from_csv(csv_path, batch_size: 1000)

    # 計測終了
    end_time = Time.current
    duration = (end_time - start_time).round(2)

    # 結果を表示
    puts "インポート完了："
    puts "  処理時間: #{duration} 秒"
    puts "  成功件数: #{result[:imported]}"
    puts "  失敗件数: #{result[:invalid].size}"
    puts "  現在のインベントリ数: #{Inventory.count} (#{Inventory.count - initial_count} 件追加)"

    # 結果検証
    if duration < 30
      puts "✅ 目標達成！ 1万行を30秒以内 (#{duration}秒) でインポートしました"
    else
      puts "❌ 目標未達成： 1万行のインポートに#{duration}秒かかりました (目標: 30秒以内)"
      puts "  性能向上のために以下を検討してください："
      puts "  - バッチサイズの最適化 (現在: 1000)"
      puts "  - activerecord-import gemの使用"
      puts "  - データベースインデックスの最適化"
    end
  end

  desc "異なるバッチサイズでのCSVインポートパフォーマンス比較"
  task benchmark_batch_sizes: :environment do
    csv_path = Rails.root.join("test/fixtures/files/large_inventory.csv")

    unless File.exist?(csv_path)
      puts "CSVファイルが見つかりません。先に rake performance:generate_csv を実行してください。"
      exit 1
    end

    # テスト前にデータベースをクリーンアップ
    puts "データベースをクリーンアップ中..."
    Inventory.delete_all
    puts "完了。"

    batch_sizes = [ 100, 500, 1000, 2000, 5000 ]
    results = {}

    batch_sizes.each do |batch_size|
      Inventory.delete_all # 各テスト前にクリーンアップ

      puts "バッチサイズ #{batch_size} でテスト中..."
      start_time = Time.current

      # インポート実行
      result = Inventory.import_from_csv(csv_path, batch_size: batch_size)

      duration = (Time.current - start_time).round(2)
      results[batch_size] = {
        duration: duration,
        valid_count: result[:imported],
        invalid_count: result[:invalid].size
      }

      puts "  処理時間: #{duration} 秒"
      puts "  成功件数: #{result[:imported]}"

      # 次のテストの前に少し待機
      sleep 1
    end

    # 結果の要約を表示
    puts "\nバッチサイズごとのパフォーマンス比較："
    puts "------------------------"
    puts "バッチサイズ | 処理時間(秒) | 成功件数"
    puts "------------------------"
    batch_sizes.each do |batch_size|
      data = results[batch_size]
      puts sprintf("%11d | %12.2f | %8d", batch_size, data[:duration], data[:valid_count])
    end
    puts "------------------------"

    # 最速のバッチサイズを特定
    fastest = results.min_by { |_, data| data[:duration] }
    puts "\n最速のバッチサイズ: #{fastest[0]} (#{fastest[1][:duration]}秒)"
  end
end
