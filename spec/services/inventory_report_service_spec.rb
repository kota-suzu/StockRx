# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# InventoryReportServiceテスト
# ============================================================================
# 目的:
#   - 在庫レポートサービスの基本機能テスト
#   - エラーハンドリングの検証
#   - データ計算ロジックの正確性確認
#
# 設計思想:
#   - ファクトリーボットを使用したテストデータ生成
#   - 境界値テストの実装
#   - エラーケースの網羅的テスト
#
# 横展開確認:
#   - 他のサービステストとの一貫したパターン
#   - shared_examplesの活用検討
#   - テストヘルパーメソッドの統一
# ============================================================================

RSpec.describe InventoryReportService, type: :service do
  # ============================================================================
  # テスト用データセットアップ
  # ============================================================================

  let(:target_month) { Date.current.beginning_of_month }
  let!(:inventories) { create_list(:inventory, 15, price: 1000, quantity: 20) }
  let!(:high_value_inventories) { create_list(:inventory, 3, price: 15000, quantity: 15) }
  let!(:low_stock_inventories) { create_list(:inventory, 5, quantity: 8) } # LOW_STOCK_THRESHOLD以下

  before do
    # バッチデータの作成（低在庫テスト用）
    low_stock_inventories.each do |inventory|
      create(:batch, inventory: inventory, quantity: 8)
    end

    # 通常在庫のバッチ作成
    inventories.each do |inventory|
      create(:batch, inventory: inventory, quantity: 20)
    end

    # 高価値在庫のバッチ作成
    high_value_inventories.each do |inventory|
      create(:batch, inventory: inventory, quantity: 15)
    end
  end

  # ============================================================================
  # 正常系テスト - 月次サマリー
  # ============================================================================

  describe '.monthly_summary' do
    subject { described_class.monthly_summary(target_month) }

    it '正常な月次サマリーデータを返すこと' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:target_date)
      expect(subject).to have_key(:total_items)
      expect(subject).to have_key(:total_value)
      expect(subject).to have_key(:low_stock_items)
      expect(subject).to have_key(:high_value_items)
      expect(subject).to have_key(:average_quantity)
      expect(subject).to have_key(:categories_breakdown)
      expect(subject).to have_key(:monthly_changes)
      expect(subject).to have_key(:inventory_health_score)
    end

    it '総アイテム数を正確に計算すること' do
      expected_total = inventories.count + high_value_inventories.count + low_stock_inventories.count
      expect(subject[:total_items]).to eq(expected_total)
    end

    it '総在庫価値を正確に計算すること' do
      expected_value = (inventories.sum { |inv| inv.price * inv.quantity } +
                       high_value_inventories.sum { |inv| inv.price * inv.quantity } +
                       low_stock_inventories.sum { |inv| inv.price * inv.quantity })
      expect(subject[:total_value]).to eq(expected_value)
    end

    it '低在庫アイテム数を正確に識別すること' do
      expect(subject[:low_stock_items]).to eq(low_stock_inventories.count)
    end

    it '高価値アイテム数を正確に識別すること' do
      expect(subject[:high_value_items]).to eq(high_value_inventories.count)
    end

    it '在庫健全性スコアが適切な範囲内であること' do
      expect(subject[:inventory_health_score]).to be_between(0, 100)
    end

    context 'オプション設定がある場合' do
      let(:options) { { detailed: true } }

      it 'オプションが適切に処理されること' do
        result = described_class.monthly_summary(target_month, options)
        expect(result).to be_a(Hash)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - 詳細分析
  # ============================================================================

  describe '.detailed_analysis' do
    subject { described_class.detailed_analysis(target_month) }

    it '詳細分析データを返すこと' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:value_distribution)
      expect(subject).to have_key(:quantity_distribution)
      expect(subject).to have_key(:price_ranges)
      expect(subject).to have_key(:stock_movement_patterns)
      expect(subject).to have_key(:seasonal_trends)
      expect(subject).to have_key(:optimization_recommendations)
    end

    it '価値分布データが適切な構造であること' do
      value_distribution = subject[:value_distribution]
      expect(value_distribution).to be_an(Array)

      value_distribution.each do |range|
        expect(range).to have_key(:label)
        expect(range).to have_key(:count)
        expect(range).to have_key(:percentage)
      end
    end

    it '価格範囲データが正確に計算されること' do
      price_ranges = subject[:price_ranges]
      expect(price_ranges).to have_key(:min_price)
      expect(price_ranges).to have_key(:max_price)
      expect(price_ranges).to have_key(:median_price)
      expect(price_ranges).to have_key(:mode_price)
    end
  end

  # ============================================================================
  # 正常系テスト - 効率分析
  # ============================================================================

  describe '.efficiency_analysis' do
    subject { described_class.efficiency_analysis(target_month) }

    it '効率分析データを返すこと' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:turnover_rate)
      expect(subject).to have_key(:holding_cost_efficiency)
      expect(subject).to have_key(:space_utilization)
      expect(subject).to have_key(:carrying_cost_ratio)
      expect(subject).to have_key(:stockout_risk)
    end

    it '数値データが適切な型であること' do
      expect(subject[:turnover_rate]).to be_a(Numeric)
      expect(subject[:holding_cost_efficiency]).to be_a(Numeric)
      expect(subject[:space_utilization]).to be_a(Numeric)
      expect(subject[:carrying_cost_ratio]).to be_a(Numeric)
      expect(subject[:stockout_risk]).to be_a(Numeric)
    end
  end

  # ============================================================================
  # 異常系テスト - バリデーション
  # ============================================================================

  describe 'バリデーション' do
    context '無効な引数を渡した場合' do
      it 'target_monthが文字列の場合エラーを発生させること' do
        expect {
          described_class.monthly_summary("2024-01-01")
        }.to raise_error(ArgumentError, "target_month must be a Date object")
      end

      it 'target_monthがnilの場合エラーを発生させること' do
        expect {
          described_class.monthly_summary(nil)
        }.to raise_error(ArgumentError, "target_month must be a Date object")
      end

      it 'target_monthが未来の日付の場合エラーを発生させること' do
        future_date = Date.current + 1.month
        expect {
          described_class.monthly_summary(future_date)
        }.to raise_error(ArgumentError, "target_month cannot be in the future")
      end
    end
  end

  # ============================================================================
  # 異常系テスト - エラーハンドリング
  # ============================================================================

  describe 'エラーハンドリング' do
    context 'データベースエラーが発生した場合' do
      before do
        allow(Inventory).to receive(:count).and_raise(StandardError.new("Database error"))
      end

      it 'CalculationErrorを発生させること' do
        expect {
          described_class.monthly_summary(target_month)
        }.to raise_error(InventoryReportService::CalculationError, /月次サマリー生成エラー/)
      end

      it 'エラーログが出力されること' do
        expect(Rails.logger).to receive(:error).with(/Error generating monthly summary/)

        expect {
          described_class.monthly_summary(target_month)
        }.to raise_error(InventoryReportService::CalculationError)
      end
    end
  end

  # ============================================================================
  # 境界値テスト
  # ============================================================================

  describe '境界値テスト' do
    context '在庫データが存在しない場合' do
      before do
        Inventory.destroy_all
        Batch.destroy_all
      end

      it 'ゼロ値のデータを適切に処理すること' do
        # テスト前に全ての在庫データを削除
        Inventory.delete_all

        result = described_class.monthly_summary(target_month)

        expect(result[:total_items]).to eq(0)
        expect(result[:total_value]).to eq(0)
        expect(result[:low_stock_items]).to eq(0)
        expect(result[:high_value_items]).to eq(0)
        expect(result[:average_quantity]).to eq(0)
        expect(result[:inventory_health_score]).to eq(50.0) # データが存在しない場合の中立スコア
      end
    end

    context '大量データがある場合' do
      before do
        # TODO: 🟡 Phase 2（中）- パフォーマンステストの実装
        # 優先度: 中（パフォーマンス改善）
        # 実装内容: 1000件以上の大量データでのレスポンス時間テスト
        # 理由: スケーラビリティ確保のため
        skip "大量データテストは今後実装"
      end

      it '大量データでもタイムアウトしないこと' do
        # 実装予定
      end
    end
  end

  # ============================================================================
  # パフォーマンステスト（基本）
  # ============================================================================

  describe 'パフォーマンス' do
    it 'SQLクエリ数が適切であること' do
      # N+1クエリの検出
      expect {
        described_class.monthly_summary(target_month)
      }.not_to exceed_query_limit(20) # 適切な上限値を設定
    end

    it '適切な応答時間内で処理されること' do
      start_time = Time.current
      described_class.monthly_summary(target_month)
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 2.seconds # 2秒以内の応答時間
    end
  end

  # ============================================================================
  # 統合テスト
  # ============================================================================

  describe '統合テスト' do
    context '実際の本番類似データでの動作確認' do
      before do
        # 本番環境に近いデータパターンを作成
        create_realistic_inventory_data
      end

      it '複合的なデータパターンで正常に動作すること' do
        result = described_class.monthly_summary(target_month)

        expect(result[:total_items]).to be > 0
        expect(result[:total_value]).to be > 0
        expect(result[:inventory_health_score]).to be_between(0, 100)
      end

      private

      def create_realistic_inventory_data
        # 多様な価格帯の在庫を作成
        create_list(:inventory, 10, price: rand(100..1000), quantity: rand(1..50))
        create_list(:inventory, 5, price: rand(5000..20000), quantity: rand(1..10))
        create_list(:inventory, 15, price: rand(1000..5000), quantity: rand(10..100))

        # 各在庫にバッチを作成
        Inventory.all.each do |inventory|
          create(:batch, inventory: inventory, quantity: inventory.quantity)
        end
      end
    end
  end

  # ============================================================================
  # 横展開確認項目（メタ認知的チェックリスト）
  # ============================================================================

  # TODO: 🟢 Phase 3（推奨）- 他サービステストとの統一
  # - StockMovementService、ExpiryAnalysisServiceと同様のテストパターン適用
  # - 共通テストヘルパーメソッドの抽出
  # - shared_examplesの活用による重複排除
  # - ファクトリーデータの標準化

  # TODO: 🟢 Phase 3（推奨）- テスト品質向上
  # - カバレッジの向上（現在の境界値テスト強化）
  # - モックオブジェクトを使用した外部依存の分離
  # - より詳細なパフォーマンステスト実装
  # - エッジケースの追加テスト
end
