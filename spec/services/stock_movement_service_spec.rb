# frozen_string_literal: true

require 'rails_helper'

# ============================================================================
# StockMovementServiceテスト
# ============================================================================
# 目的:
#   - 在庫移動分析サービスの基本機能テスト
#   - 時系列データ処理の正確性確認
#   - リアルタイム分析機能の検証
#
# 設計思想:
#   - InventoryLogを基にしたテストデータ生成
#   - 時系列パターンのテスト
#   - 移動分析ロジックの精度検証
#
# 横展開確認:
#   - InventoryReportServiceテストとの一貫性
#   - ログデータ固有のテストパターン
#   - パフォーマンステストの統一
# ============================================================================

RSpec.describe StockMovementService, type: :service do
  # ============================================================================
  # テスト用データセットアップ
  # ============================================================================

  let(:target_month) { Date.current.beginning_of_month }
  let!(:inventories) { create_list(:inventory, 10) }
  let!(:admin) { create(:admin) }

  before do
    # 多様な移動パターンのログデータを作成
    create_diverse_movement_logs
  end

  # ============================================================================
  # 正常系テスト - 月次分析
  # ============================================================================

  describe '.monthly_analysis' do
    subject { described_class.monthly_analysis(target_month) }

    it '正常な月次分析データを返すこと' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:target_date)
      expect(subject).to have_key(:total_movements)
      expect(subject).to have_key(:movement_breakdown)
      expect(subject).to have_key(:top_active_items)
      expect(subject).to have_key(:movement_trends)
      expect(subject).to have_key(:velocity_analysis)
      expect(subject).to have_key(:seasonal_patterns)
      expect(subject).to have_key(:movement_efficiency)
    end

    it '対象月が正確に記録されること' do
      expect(subject[:target_date]).to eq(target_month)
    end

    it '総移動数が正の整数であること' do
      expect(subject[:total_movements]).to be_a(Integer)
      expect(subject[:total_movements]).to be >= 0
    end

    it '移動内訳データが適切な構造であること' do
      breakdown = subject[:movement_breakdown]
      expect(breakdown).to be_an(Array)

      breakdown.each do |movement|
        expect(movement).to have_key(:type)
        expect(movement).to have_key(:count)
        expect(movement).to have_key(:percentage)
        expect(movement[:percentage]).to be_between(0, 100)
      end
    end

    it 'アクティブアイテムランキングが適切であること' do
      active_items = subject[:top_active_items]
      expect(active_items).to be_an(Array)

      active_items.each do |item|
        expect(item).to have_key(:inventory_id)
        expect(item).to have_key(:name)
        expect(item).to have_key(:movement_count)
        expect(item).to have_key(:activity_score)
        expect(item[:movement_count]).to be >= 0
        expect(item[:activity_score]).to be_between(0, 100)
      end
    end

    context 'オプション設定がある場合' do
      let(:options) { { include_details: true } }

      it 'オプションが適切に処理されること' do
        result = described_class.monthly_analysis(target_month, options)
        expect(result).to be_a(Hash)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - 速度分析
  # ============================================================================

  describe '.velocity_analysis' do
    context '全在庫を対象とする場合' do
      subject { described_class.velocity_analysis }

      it '速度分析データを返すこと' do
        expect(subject).to be_a(Hash)
        expect(subject).to have_key(:analysis_period)
        expect(subject).to have_key(:fast_moving_items)
        expect(subject).to have_key(:slow_moving_items)
        expect(subject).to have_key(:average_turnover)
        expect(subject).to have_key(:movement_distribution)
      end

      it '分析期間が適切に設定されること' do
        expect(subject[:analysis_period]).to eq(StockMovementService::ANALYSIS_PERIOD_DAYS)
      end

      it '平均回転率が数値であること' do
        expect(subject[:average_turnover]).to be_a(Numeric)
        expect(subject[:average_turnover]).to be >= 0
      end
    end

    context '特定在庫を対象とする場合' do
      let(:target_inventory_ids) { inventories.first(3).map(&:id) }

      subject { described_class.velocity_analysis(target_inventory_ids) }

      it '指定された在庫のみが分析対象となること' do
        expect(subject).to be_a(Hash)
        expect(subject[:fast_moving_items]).to be_an(Array)
        expect(subject[:slow_moving_items]).to be_an(Array)
      end
    end

    context 'カスタム期間を指定する場合' do
      let(:custom_period) { 60 } # 60日間

      subject { described_class.velocity_analysis(nil, custom_period) }

      it 'カスタム期間が適用されること' do
        expect(subject[:analysis_period]).to eq(custom_period)
      end
    end
  end

  # ============================================================================
  # 正常系テスト - リアルタイム活動監視
  # ============================================================================

  describe '.real_time_activity' do
    subject { described_class.real_time_activity }

    it 'リアルタイム活動データを返すこと' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:period_hours)
      expect(subject).to have_key(:recent_movements)
      expect(subject).to have_key(:activity_heatmap)
      expect(subject).to have_key(:alert_items)
      expect(subject).to have_key(:movement_summary)
    end

    it 'デフォルト監視期間が24時間であること' do
      expect(subject[:period_hours]).to eq(24)
    end

    it '直近の移動データが適切な構造であること' do
      recent_movements = subject[:recent_movements]
      expect(recent_movements).to be_an(Array)

      recent_movements.each do |movement|
        expect(movement).to have_key(:inventory_name)
        expect(movement).to have_key(:operation_type)
        expect(movement).to have_key(:quantity_change)
        expect(movement).to have_key(:created_at)
        expect(movement).to have_key(:time_ago)
      end
    end

    it 'アクティビティヒートマップが24時間 x 7日の構造であること' do
      heatmap = subject[:activity_heatmap]
      expect(heatmap).to be_an(Array)
      expect(heatmap.length).to eq(24) # 24時間

      heatmap.each do |hour_data|
        expect(hour_data).to have_key(:hour)
        expect(hour_data).to have_key(:daily_activity)
        expect(hour_data[:daily_activity].length).to eq(7) # 7日間
      end
    end

    context 'カスタム監視期間を指定する場合' do
      let(:custom_hours) { 48 }

      subject { described_class.real_time_activity(custom_hours) }

      it 'カスタム期間が適用されること' do
        expect(subject[:period_hours]).to eq(custom_hours)
      end
    end
  end

  # ============================================================================
  # 異常系テスト - バリデーション
  # ============================================================================

  describe 'バリデーション' do
    context '無効な引数を渡した場合' do
      it 'target_monthが文字列の場合エラーを発生させること' do
        expect {
          described_class.monthly_analysis("2024-01-01")
        }.to raise_error(ArgumentError, "target_month must be a Date object")
      end

      it 'target_monthが未来の日付の場合エラーを発生させること' do
        future_date = Date.current + 1.month
        expect {
          described_class.monthly_analysis(future_date)
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
        allow(InventoryLog).to receive(:where).and_raise(StandardError.new("Database error"))
      end

      it 'AnalysisErrorを発生させること' do
        expect {
          described_class.monthly_analysis(target_month)
        }.to raise_error(StockMovementService::AnalysisError, /月次移動分析エラー/)
      end

      it 'エラーログが出力されること' do
        expect(Rails.logger).to receive(:error).with(/Error in monthly analysis/)

        expect {
          described_class.monthly_analysis(target_month)
        }.to raise_error(StockMovementService::AnalysisError)
      end
    end
  end

  # ============================================================================
  # 境界値テスト
  # ============================================================================

  describe '境界値テスト' do
    context '移動ログが存在しない場合' do
      before do
        InventoryLog.destroy_all
      end

      it 'ゼロ値のデータを適切に処理すること' do
        result = described_class.monthly_analysis(target_month)

        expect(result[:total_movements]).to eq(0)
        expect(result[:top_active_items]).to be_empty
      end

      it 'リアルタイム分析でも適切に処理されること' do
        result = described_class.real_time_activity

        expect(result[:recent_movements]).to be_empty
        expect(result[:movement_summary][:total_movements]).to eq(0)
      end
    end

    context '単一の移動ログのみ存在する場合' do
      before do
        InventoryLog.destroy_all
        create(:inventory_log,
               inventory: inventories.first,
               user_id: admin.id,
               operation_type: 'receive',
               delta: 10,
               previous_quantity: 90,
               current_quantity: 100,
               created_at: target_month + 1.day)
      end

      it '単一データでも正常に処理されること' do
        result = described_class.monthly_analysis(target_month)

        expect(result[:total_movements]).to eq(1)
        expect(result[:top_active_items].length).to eq(1)
      end
    end
  end

  # ============================================================================
  # パフォーマンステスト
  # ============================================================================

  describe 'パフォーマンス' do
    it 'SQLクエリ数が適切であること' do
      # TODO: 🟡 Phase 2（中）- クエリ数監視テストの実装
      # 優先度: 中（パフォーマンス最適化）
      # 実装内容: Bullet gem または database_queries gem を使用したクエリ数監視
      # 理由: N+1クエリ問題の継続的監視が重要

      pending "クエリ数監視機能の実装が必要"

      # 実際の実装予定:
      # - クエリ数カウンタの実装
      # - 許容範囲（15クエリ以下）の検証
      # - パフォーマンス回帰の自動検知

      fail "実装が必要"
    end

    it '適切な応答時間内で処理されること' do
      start_time = Time.current
      described_class.monthly_analysis(target_month)
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 2.seconds
    end
  end

  # ============================================================================
  # 時系列データテスト
  # ============================================================================

  describe '時系列データ処理' do
    before do
      create_time_series_logs
    end

    it 'トレンド方向を正確に判定すること' do
      result = described_class.monthly_analysis(target_month)
      trends = result[:movement_trends]

      expect(trends).to have_key(:trend_direction)
      expect(%w[increasing decreasing stable]).to include(trends[:trend_direction])
    end

    it '日別データが適切に集計されること' do
      result = described_class.monthly_analysis(target_month)
      daily_data = result[:movement_trends][:daily_data]

      expect(daily_data).to be_an(Array)
      daily_data.each do |day|
        expect(day).to have_key(:date)
        expect(day).to have_key(:movements)
        expect(day[:movements]).to be >= 0
      end
    end

    private

    def create_time_series_logs
      # 月初から月末まで段階的に移動ログを作成
      (target_month..target_month.end_of_month).each_with_index do |date, index|
        movement_count = (index % 3) + 1 # 1-3の範囲で変動

        movement_count.times do
          create(:inventory_log,
                 inventory: inventories.sample,
                 user_id: admin.id,
                 operation_type: %w[receive remove adjust].sample,
                 delta: rand(1..10),
                 previous_quantity: rand(0..100),
                 current_quantity: rand(0..100),
                 created_at: date + rand(0..23).hours)
        end
      end
    end
  end

  # ============================================================================
  # ヘルパーメソッド
  # ============================================================================

  private

  def create_diverse_movement_logs
    # 多様な操作タイプのログを作成（InventoryLogモデルの実際のOPERATION_TYPESに対応）
    operation_types = %w[add remove adjust ship receive]

    inventories.each do |inventory|
      # 各在庫に対して複数の移動ログを作成
      rand(3..8).times do
        create(:inventory_log,
               inventory: inventory,
               user_id: admin.id,
               operation_type: operation_types.sample,
               delta: rand(-20..20),
               previous_quantity: rand(0..100),
               current_quantity: rand(0..100),
               created_at: target_month + rand(0..30).days + rand(0..23).hours)
      end
    end

    # 高頻度アクティブアイテムの作成
    active_inventory = inventories.first
    15.times do
      create(:inventory_log,
             inventory: active_inventory,
             user_id: admin.id,
             operation_type: 'remove',
             delta: -1,
             previous_quantity: rand(10..100),
             current_quantity: rand(9..99),
             created_at: target_month + rand(0..30).days)
    end
  end

  # ============================================================================
  # 横展開確認項目（メタ認知的チェックリスト）
  # ============================================================================

  # TODO: 🟢 Phase 3（推奨）- 時系列テストパターンの標準化
  # - 他の時系列処理サービスとの統一パターン
  # - 季節性分析テストの実装
  # - 移動パターン検出テストの強化

  # TODO: 🟡 Phase 2（中）- ログデータ品質テスト
  # - 不正なログデータの処理テスト
  # - データ整合性チェックの実装
  # - 操作タイプ標準化のテスト

  # TODO: 🟢 Phase 3（推奨）- リアルタイム機能の詳細テスト
  # - WebSocket連携のモックテスト
  # - アラート閾値の動的調整テスト
  # - 異常パターン検知の精度テスト
end
