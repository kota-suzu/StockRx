# frozen_string_literal: true

namespace :counter_cache do
  desc "Counter Cacheの整合性チェックと修正"
  task integrity_check: :environment do
    puts "=== Counter Cache整合性チェック開始 ==="
    puts "実行時刻: #{Time.current}"
    puts

    results = {
      checked: 0,
      inconsistent: 0,
      fixed: 0,
      errors: []
    }

    # Store関連のCounter Cache整合性チェック
    check_store_counter_caches(results)

    # Inventory関連のCounter Cache整合性チェック
    check_inventory_counter_caches(results)

    # 結果レポート出力
    generate_integrity_report(results)
  end

  desc "Counter Cacheの強制リセット（全件）"
  task reset_all: :environment do
    puts "=== Counter Cache強制リセット開始 ==="
    puts "⚠️  この操作は全てのCounter Cacheを再計算します"
    
    if Rails.env.production?
      print "本番環境での実行です。続行しますか？ (y/N): "
      response = STDIN.gets.chomp.downcase
      unless response == 'y' || response == 'yes'
        puts "処理を中止しました。"
        exit
      end
    end

    reset_all_counter_caches
    puts "✅ Counter Cacheリセット完了"
  end

  desc "特定ストアのCounter Cacheをリセット"
  task :reset_store, [:store_id] => :environment do |t, args|
    store_id = args[:store_id]
    
    unless store_id
      puts "❌ エラー: store_idを指定してください"
      puts "使用例: rails counter_cache:reset_store[123]"
      exit 1
    end

    store = Store.find_by(id: store_id)
    unless store
      puts "❌ エラー: ID #{store_id} の店舗が見つかりません"
      exit 1
    end

    puts "店舗「#{store.display_name}」のCounter Cacheをリセットします..."
    reset_store_counter_cache(store)
    puts "✅ 完了"
  end

  desc "Counter Cache統計情報の表示"
  task stats: :environment do
    puts "=== Counter Cache統計情報 ==="
    puts "実行時刻: #{Time.current}"
    puts

    # Store統計
    puts "【Store Counter Cache統計】"
    Store.find_each do |store|
      actual_count = store.store_inventories.count
      cached_count = store.store_inventories_count
      status = actual_count == cached_count ? "✅" : "❌"
      
      puts "  #{status} #{store.display_name}: 実測#{actual_count} / Cache#{cached_count}"
    end
    puts

    # Inventory統計
    puts "【Inventory Counter Cache統計】"
    inconsistent_inventories = 0
    Inventory.includes(:batches, :inventory_logs, :shipments, :receipts).find_each do |inventory|
      checks = {
        batches: inventory.batches.count,
        inventory_logs: inventory.inventory_logs.count,
        shipments: inventory.shipments.count,
        receipts: inventory.receipts.count
      }
      
      cached = {
        batches: inventory.batches_count,
        inventory_logs: inventory.inventory_logs_count,
        shipments: inventory.shipments_count,
        receipts: inventory.receipts_count
      }
      
      inconsistent = checks.any? { |key, actual| actual != cached[key] }
      inconsistent_inventories += 1 if inconsistent
    end
    
    puts "  総Inventory数: #{Inventory.count}"
    puts "  Counter Cache不整合: #{inconsistent_inventories}件"
    puts
  end

  # プライベートメソッド
  private

  def check_store_counter_caches(results)
    puts "【Store Counter Cacheチェック】"
    
    Store.find_each do |store|
      results[:checked] += 1
      
      # store_inventories_count チェック
      actual_inventories = store.store_inventories.count
      if store.store_inventories_count != actual_inventories
        puts "  ❌ #{store.display_name}: store_inventories_count 不整合"
        puts "     実測: #{actual_inventories}, Cache: #{store.store_inventories_count}"
        
        results[:inconsistent] += 1
        fix_store_inventories_count(store, actual_inventories)
        results[:fixed] += 1
      end

      # pending_outgoing_transfers_count チェック
      actual_outgoing = store.outgoing_transfers.pending.count
      if store.pending_outgoing_transfers_count != actual_outgoing
        puts "  ❌ #{store.display_name}: pending_outgoing_transfers_count 不整合"
        puts "     実測: #{actual_outgoing}, Cache: #{store.pending_outgoing_transfers_count}"
        
        results[:inconsistent] += 1
        fix_pending_outgoing_count(store, actual_outgoing)
        results[:fixed] += 1
      end

      # pending_incoming_transfers_count チェック
      actual_incoming = store.incoming_transfers.pending.count
      if store.pending_incoming_transfers_count != actual_incoming
        puts "  ❌ #{store.display_name}: pending_incoming_transfers_count 不整合"
        puts "     実測: #{actual_incoming}, Cache: #{store.pending_incoming_transfers_count}"
        
        results[:inconsistent] += 1
        fix_pending_incoming_count(store, actual_incoming)
        results[:fixed] += 1
      end

      # low_stock_items_count チェック
      actual_low_stock = store.calculate_low_stock_items_count
      if store.low_stock_items_count != actual_low_stock
        puts "  ❌ #{store.display_name}: low_stock_items_count 不整合"
        puts "     実測: #{actual_low_stock}, Cache: #{store.low_stock_items_count}"
        
        results[:inconsistent] += 1
        fix_low_stock_count(store, actual_low_stock)
        results[:fixed] += 1
      end

    rescue => e
      error_msg = "Store #{store&.display_name || 'Unknown'}: #{e.message}"
      puts "  💥 エラー: #{error_msg}"
      results[:errors] << error_msg
    end
    
    puts "  ✅ Store Counter Cache チェック完了"
    puts
  end

  def check_inventory_counter_caches(results)
    puts "【Inventory Counter Cacheチェック】"
    
    inconsistent_count = 0
    
    Inventory.find_each do |inventory|
      results[:checked] += 1
      inventory_inconsistent = false

      # batches_count チェック
      actual_batches = inventory.batches.count
      if inventory.batches_count != actual_batches
        puts "  ❌ #{inventory.name}: batches_count 不整合 (実測: #{actual_batches}, Cache: #{inventory.batches_count})"
        results[:inconsistent] += 1
        inventory_inconsistent = true
        Inventory.reset_counters(inventory.id, :batches)
        results[:fixed] += 1
      end

      # inventory_logs_count チェック
      actual_logs = inventory.inventory_logs.count
      if inventory.inventory_logs_count != actual_logs
        puts "  ❌ #{inventory.name}: inventory_logs_count 不整合 (実測: #{actual_logs}, Cache: #{inventory.inventory_logs_count})"
        results[:inconsistent] += 1
        inventory_inconsistent = true
        Inventory.reset_counters(inventory.id, :inventory_logs)
        results[:fixed] += 1
      end

      # shipments_count チェック
      actual_shipments = inventory.shipments.count
      if inventory.shipments_count != actual_shipments
        puts "  ❌ #{inventory.name}: shipments_count 不整合 (実測: #{actual_shipments}, Cache: #{inventory.shipments_count})"
        results[:inconsistent] += 1
        inventory_inconsistent = true
        Inventory.reset_counters(inventory.id, :shipments)
        results[:fixed] += 1
      end

      # receipts_count チェック
      actual_receipts = inventory.receipts.count
      if inventory.receipts_count != actual_receipts
        puts "  ❌ #{inventory.name}: receipts_count 不整合 (実測: #{actual_receipts}, Cache: #{inventory.receipts_count})"
        results[:inconsistent] += 1
        inventory_inconsistent = true
        Inventory.reset_counters(inventory.id, :receipts)
        results[:fixed] += 1
      end

      inconsistent_count += 1 if inventory_inconsistent

    rescue => e
      error_msg = "Inventory #{inventory&.name || 'Unknown'}: #{e.message}"
      puts "  💥 エラー: #{error_msg}"
      results[:errors] << error_msg
    end
    
    puts "  ✅ Inventory Counter Cache チェック完了"
    puts "  不整合商品数: #{inconsistent_count}件"
    puts
  end

  def fix_store_inventories_count(store, correct_count)
    store.update_column(:store_inventories_count, correct_count)
  end

  def fix_pending_outgoing_count(store, correct_count)
    store.update_column(:pending_outgoing_transfers_count, correct_count)
  end

  def fix_pending_incoming_count(store, correct_count)
    store.update_column(:pending_incoming_transfers_count, correct_count)
  end

  def fix_low_stock_count(store, correct_count)
    store.update_column(:low_stock_items_count, correct_count)
  end

  def reset_all_counter_caches
    puts "Store Counter Cacheリセット中..."
    Store.reset_counters_safely
    
    puts "Inventory Counter Cacheリセット中..."
    Inventory.find_each do |inventory|
      Inventory.reset_counters(inventory.id, :batches, :inventory_logs, :shipments, :receipts)
    end
  end

  def reset_store_counter_cache(store)
    Store.reset_counters(store.id, :store_inventories)
    store.update_column(:pending_outgoing_transfers_count, store.outgoing_transfers.pending.count)
    store.update_column(:pending_incoming_transfers_count, store.incoming_transfers.pending.count)
    store.update_low_stock_items_count!
  end

  def generate_integrity_report(results)
    puts "=== 整合性チェック結果レポート ==="
    puts "チェック対象: #{results[:checked]}件"
    puts "不整合検出: #{results[:inconsistent]}件"
    puts "修正完了: #{results[:fixed]}件"
    
    if results[:errors].any?
      puts "エラー: #{results[:errors].count}件"
      results[:errors].each do |error|
        puts "  - #{error}"
      end
    end
    
    if results[:inconsistent] == 0
      puts "✅ 全てのCounter Cacheが正常です"
    else
      puts "⚠️  #{results[:inconsistent]}件の不整合を検出し、修正しました"
    end
    
    puts "完了時刻: #{Time.current}"
    puts "==="

    # ログファイルにも記録
    log_integrity_check_result(results)
  end

  def log_integrity_check_result(results)
    log_entry = {
      timestamp: Time.current.iso8601,
      checked: results[:checked],
      inconsistent: results[:inconsistent],
      fixed: results[:fixed],
      errors: results[:errors]
    }
    
    Rails.logger.info "Counter Cache Integrity Check: #{log_entry.to_json}"
  end
end

# ============================================
# TODO: 🟡 Phase 3（中）- Slack/Email通知機能
# 優先度: 中（運用監視強化）
# 実装内容:
#   - Counter Cache不整合時の自動Slack通知
#   - 週次レポートのメール配信
#   - 閾値を超える不整合時のアラート
# 期待効果: 問題の早期発見、運用負荷軽減
# ============================================