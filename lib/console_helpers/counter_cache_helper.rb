# frozen_string_literal: true

# Rails Consoleで使用するCounter Cacheヘルパー
# ============================================
# 開発時のCounter Cache管理を簡単にするためのヘルパーメソッド
# 
# 使用例:
#   reload_helpers                         # ヘルパーをリロード
#   check_all_counter_caches              # 全Counter Cacheをチェック
#   fix_all_counter_caches                # 全Counter Cacheを修正
#   store_stats("ST001")                  # 特定店舗の統計
#   inventory_counter_cache_summary       # Inventory Counter Cache概要
# ============================================

module CounterCacheHelper
  # 全Counter Cacheの整合性チェック
  def check_all_counter_caches
    puts "=== 全Counter Cache整合性チェック ==="
    puts "実行時刻: #{Time.current}"
    puts

    # Store Counter Cache
    puts "【Store Counter Cache】"
    store_inconsistencies = Store.check_counter_cache_integrity
    if store_inconsistencies.empty?
      puts "  ✅ 全てのStore Counter Cacheが整合しています"
    else
      puts "  ❌ #{store_inconsistencies.count}件の不整合を検出:"
      store_inconsistencies.each do |issue|
        puts "    - #{issue[:store]}: #{issue[:counter]} (実測: #{issue[:actual]}, Cache: #{issue[:cached]})"
      end
    end
    puts

    # Inventory Counter Cache概要
    puts "【Inventory Counter Cache】"
    inconsistent_count = 0
    Inventory.find_each do |inventory|
      actual_logs = inventory.inventory_logs.count
      if inventory.inventory_logs_count != actual_logs
        inconsistent_count += 1
        puts "  ❌ #{inventory.name}: inventory_logs不整合 (実測: #{actual_logs}, Cache: #{inventory.inventory_logs_count})"
      end
    end
    
    if inconsistent_count == 0
      puts "  ✅ 全てのInventory Counter Cacheが整合しています"
    else
      puts "  ❌ #{inconsistent_count}件のInventory Counter Cache不整合を検出"
    end
    
    puts
    puts "=== チェック完了 ==="
    
    {
      store_inconsistencies: store_inconsistencies.count,
      inventory_inconsistencies: inconsistent_count,
      total_issues: store_inconsistencies.count + inconsistent_count
    }
  end

  # 全Counter Cacheの修正
  def fix_all_counter_caches
    puts "=== 全Counter Cache修正開始 ==="
    puts "実行時刻: #{Time.current}"
    puts

    fixed_count = 0

    # Store Counter Cache修正
    puts "【Store Counter Cache修正】"
    Store.find_each do |store|
      inconsistencies = store.check_counter_cache_integrity
      if inconsistencies.any?
        puts "  🔧 #{store.display_name}: #{inconsistencies.count}件の不整合を修正中..."
        store.fix_counter_cache_integrity!
        fixed_count += inconsistencies.count
      end
    end

    # Inventory Counter Cache修正（自動リセット）
    puts "【Inventory Counter Cache修正】"
    Inventory.find_each do |inventory|
      begin
        Inventory.reset_counters(inventory.id, :batches, :inventory_logs, :shipments, :receipts)
      rescue => e
        puts "  ⚠️ #{inventory.name}: #{e.message}"
      end
    end

    puts "✅ Counter Cache修正完了（修正件数: #{fixed_count}件）"
    puts "=== 修正完了 ==="
    
    fixed_count
  end

  # 特定店舗の詳細統計
  def store_stats(store_code_or_id)
    store = if store_code_or_id.is_a?(String)
              Store.find_by(code: store_code_or_id.upcase)
            else
              Store.find(store_code_or_id)
            end

    unless store
      puts "❌ 店舗が見つかりません: #{store_code_or_id}"
      return
    end

    puts "=== #{store.display_name} Counter Cache統計 ==="
    puts "実行時刻: #{Time.current}"
    puts

    stats = store.counter_cache_stats
    inconsistencies = store.check_counter_cache_integrity

    stats.each do |key, data|
      status = data[:consistent] ? "✅" : "❌"
      puts "#{status} #{key.to_s.humanize}:"
      puts "   実測: #{data[:actual]}"
      puts "   Cache: #{data[:cached]}"
      puts "   整合性: #{data[:consistent] ? '正常' : '不整合'}"
      puts
    end

    if inconsistencies.any?
      puts "【修正方法】"
      puts "  この店舗のCounter Cacheを修正する場合:"
      puts "  store = Store.find(#{store.id})"
      puts "  store.fix_counter_cache_integrity!"
    else
      puts "✅ 全てのCounter Cacheが正常です"
    end
    
    puts "=== 統計完了 ==="
    
    stats
  end

  # Inventory Counter Cache概要
  def inventory_counter_cache_summary
    puts "=== Inventory Counter Cache概要 ==="
    puts "実行時刻: #{Time.current}"
    puts

    total_inventories = Inventory.count
    inconsistent_count = 0
    
    counter_types = %w[batches_count inventory_logs_count shipments_count receipts_count]
    
    counter_types.each do |counter_type|
      association = counter_type.gsub('_count', '').pluralize
      puts "【#{counter_type.humanize}】"
      
      Inventory.includes(association.to_sym).find_each do |inventory|
        actual_count = inventory.send(association).count
        cached_count = inventory.send(counter_type)
        
        if actual_count != cached_count
          puts "  ❌ #{inventory.name}: 実測#{actual_count} / Cache#{cached_count}"
          inconsistent_count += 1
        end
      end
      
      puts "  ✅ #{counter_type}チェック完了"
      puts
    end

    puts "【概要】"
    puts "  総Inventory数: #{total_inventories}"
    puts "  不整合件数: #{inconsistent_count}"
    puts "  整合率: #{((total_inventories - inconsistent_count).to_f / total_inventories * 100).round(2)}%"
    
    if inconsistent_count > 0
      puts
      puts "【修正方法】"
      puts "  全Inventory Counter Cacheをリセットする場合:"
      puts "  Inventory.find_each { |i| Inventory.reset_counters(i.id, :batches, :inventory_logs, :shipments, :receipts) }"
    end
    
    puts "=== 概要完了 ==="
    
    {
      total: total_inventories,
      inconsistent: inconsistent_count,
      consistency_rate: ((total_inventories - inconsistent_count).to_f / total_inventories * 100).round(2)
    }
  end

  # 最も問題のある店舗を特定
  def problematic_stores(limit = 5)
    puts "=== 問題のある店舗Top#{limit} ==="
    puts "実行時刻: #{Time.current}"
    puts

    store_issues = []
    
    Store.find_each do |store|
      inconsistencies = store.check_counter_cache_integrity
      if inconsistencies.any?
        store_issues << {
          store: store,
          issues: inconsistencies.count,
          details: inconsistencies
        }
      end
    end

    if store_issues.empty?
      puts "✅ 全ての店舗のCounter Cacheが正常です"
      return []
    end

    # 問題の多い順にソート
    store_issues.sort_by! { |issue| -issue[:issues] }
    top_issues = store_issues.first(limit)

    top_issues.each_with_index do |issue, index|
      store = issue[:store]
      puts "#{index + 1}. #{store.display_name} (#{issue[:issues]}件の不整合)"
      issue[:details].each do |detail|
        puts "   - #{detail[:counter]}: 実測#{detail[:actual]} / Cache#{detail[:cached]}"
      end
      puts
    end

    puts "【一括修正コマンド】"
    puts "fix_stores([#{top_issues.map { |i| i[:store].id }.join(', ')}])"
    puts "=== 分析完了 ==="
    
    top_issues
  end

  # 指定店舗のCounter Cache修正
  def fix_stores(store_ids)
    store_ids = [store_ids] unless store_ids.is_a?(Array)
    
    puts "=== 指定店舗Counter Cache修正 ==="
    puts "対象店舗: #{store_ids.join(', ')}"
    puts "実行時刻: #{Time.current}"
    puts

    fixed_total = 0

    store_ids.each do |store_id|
      store = Store.find(store_id)
      inconsistencies = store.check_counter_cache_integrity
      
      if inconsistencies.any?
        puts "🔧 #{store.display_name}: #{inconsistencies.count}件修正中..."
        store.fix_counter_cache_integrity!
        fixed_total += inconsistencies.count
        puts "  ✅ 修正完了"
      else
        puts "✅ #{store.display_name}: 修正不要"
      end
    end

    puts
    puts "✅ 全店舗修正完了（総修正件数: #{fixed_total}件）"
    puts "=== 修正完了 ==="
    
    fixed_total
  end

  # ヘルパーのリロード
  def reload_helpers
    load Rails.root.join('lib/console_helpers/counter_cache_helper.rb')
    puts "✅ Counter Cacheヘルパーをリロードしました"
    puts
    puts "【利用可能なコマンド】"
    puts "  check_all_counter_caches              # 全Counter Cacheチェック"
    puts "  fix_all_counter_caches                # 全Counter Cache修正"
    puts "  store_stats('ST001')                  # 特定店舗統計"
    puts "  inventory_counter_cache_summary       # Inventory概要"
    puts "  problematic_stores(5)                 # 問題店舗Top5"
    puts "  fix_stores([1, 2, 3])                # 指定店舗修正"
    puts "  reload_helpers                        # ヘルパーリロード"
    puts
  end
end

# Rails Consoleで自動的に利用可能にする
if defined?(Rails::Console)
  include CounterCacheHelper
  puts "📊 Counter Cacheヘルパーが利用可能です"
  puts "   help: reload_helpers"
end

# ============================================
# TODO: 🟡 Phase 3（中）- Webダッシュボード連携
# 優先度: 中（管理画面での視覚化）
# 実装内容:
#   - Counter Cache統計のJSON API
#   - リアルタイムダッシュボード表示
#   - 不整合アラートのWeb通知
# 期待効果: 運用時の問題発見・対応の効率化
# ============================================