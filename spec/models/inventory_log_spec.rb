# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLog, type: :model do
  # 各テストで完全に独立したInventoryを使用してアイソレート
  let(:test_inventory) { create(:inventory, name: "test_#{Time.current.to_f}") }

  describe 'associations' do
    it { should belong_to(:inventory).required }
    # user_idはオプションなのでrequiredなし
  end

  describe 'validations' do
    subject { create(:inventory_log, inventory: test_inventory) }

    it { should validate_presence_of(:delta) }
    it { should validate_presence_of(:operation_type) }
    it { should validate_presence_of(:previous_quantity) }
    it { should validate_presence_of(:current_quantity) }
    it { should validate_numericality_of(:delta) }
    it { should validate_numericality_of(:previous_quantity).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:current_quantity).is_greater_than_or_equal_to(0) }
  end

  describe 'enums' do
    it 'operation_typeのenum値が正しく定義されていること' do
      expect(InventoryLog.operation_types.keys).to match_array([ 'add', 'remove', 'adjust', 'ship', 'receive' ])
    end
  end

  describe '#formatted_created_at' do
    it '日本語形式で日時をフォーマットすること' do
      log = create(:inventory_log, inventory: test_inventory, created_at: Time.utc(2025, 5, 23, 14, 30, 45))

      expected_time = log.created_at.in_time_zone('Asia/Tokyo').strftime("%Y年%m月%d日 %H:%M:%S")
      expect(log.formatted_created_at).to eq(expected_time)
    end
  end

  describe '#operation_display_name' do
    it '操作タイプの日本語名を返すこと' do
      add_log = create(:inventory_log, inventory: test_inventory, operation_type: :add)
      remove_log = create(:inventory_log, inventory: test_inventory, operation_type: :remove)
      ship_log = create(:inventory_log, inventory: test_inventory, operation_type: :ship)

      expect(add_log.operation_display_name).to eq('追加')
      expect(remove_log.operation_display_name).to eq('削除')
      expect(ship_log.operation_display_name).to eq('出荷')
    end
  end

  describe '日付関連スコープ' do
    let(:inventory) { create(:inventory) }

    # テスト用のベース日時を設定（2025年6月15日 10:00 JST）
    let(:base_time) { Time.zone.parse('2025-06-15 10:00:00') }

    # テスト専用のログ作成とクリーンアップ
    before do
      # 既存のInventoryLogをクリーンアップ
      InventoryLog.delete_all

      # 各期間のログを作成
      create_logs_for_different_periods
    end

    after do
      # テスト後のクリーンアップ
      InventoryLog.delete_all
    end

    describe 'this_month スコープ' do
      it '今月のログのみを返すこと' do
        Timecop.freeze(base_time) do
          logs = InventoryLog.where(inventory: inventory).this_month

          # 手動作成した「今月のログ」を含むログが返されること
          manual_log = logs.find_by(note: '今月のログ')
          expect(manual_log).to be_present
          expect(manual_log.operation_type).to eq('add')

          # すべてのログが今月の範囲内にあること
          logs.each do |log|
            expect(log.created_at).to be_between(Time.current.beginning_of_month, Time.current.end_of_month)
          end
        end
      end

      it '月末でも今月のログを正しく返すこと' do
        # 月末に移動してテスト
        month_end = base_time.end_of_month
        Timecop.freeze(month_end) do
          logs = InventoryLog.where(inventory: inventory).this_month

          # 手動作成した「今月のログ」が含まれていること
          manual_log = logs.find_by(note: '今月のログ')
          expect(manual_log).to be_present
        end
      end
    end

    describe 'previous_month スコープ' do
      it '先月のログのみを返すこと' do
        Timecop.freeze(base_time) do
          logs = InventoryLog.where(inventory: inventory).previous_month

          # 手動作成した「先月のログ」を含むログが返されること
          manual_log = logs.find_by(note: '先月のログ')
          expect(manual_log).to be_present
          expect(manual_log.operation_type).to eq('remove')

          # すべてのログが先月の範囲内にあること
          last_month = 1.month.ago
          logs.each do |log|
            expect(log.created_at).to be_between(last_month.beginning_of_month, last_month.end_of_month)
          end
        end
      end

      it '年をまたいでも先月のログを正しく返すこと' do
        # クリーンアップしてから新しいテストデータを作成
        InventoryLog.delete_all

        # 1月に移動して12月のログをテスト
        january_time = Time.zone.parse('2026-01-15 10:00:00')
        december_log = nil

        Timecop.freeze(Time.zone.parse('2025-12-15 10:00:00')) do
          december_log = create(:inventory_log, inventory: inventory, operation_type: 'adjust', note: '12月のログ')
        end

        Timecop.freeze(january_time) do
          logs = InventoryLog.where(inventory: inventory).previous_month
          expect(logs).to include(december_log)
          expect(logs.find_by(note: '12月のログ')).to be_present
        end
      end
    end

    describe 'this_year スコープ' do
      it '今年のログのみを返すこと' do
        Timecop.freeze(base_time) do
          logs = InventoryLog.where(inventory: inventory).this_year

          # 今年のログ（今月と先月）が含まれていること
          this_month_log = logs.find_by(note: '今月のログ')
          last_month_log = logs.find_by(note: '先月のログ')

          expect(this_month_log).to be_present
          expect(last_month_log).to be_present

          # 昨年のログが含まれていないこと
          last_year_log = logs.find_by(note: '昨年のログ')
          expect(last_year_log).to be_nil

          # すべてのログが今年の範囲内にあること
          logs.each do |log|
            expect(log.created_at).to be_between(Time.current.beginning_of_year, Time.current.end_of_year)
          end
        end
      end

      it '年末でも今年のログを正しく返すこと' do
        # 年末に移動してテスト
        year_end = base_time.end_of_year
        Timecop.freeze(year_end) do
          logs = InventoryLog.where(inventory: inventory).this_year

          # 今年のログが含まれていること
          this_month_log = logs.find_by(note: '今月のログ')
          last_month_log = logs.find_by(note: '先月のログ')

          expect(this_month_log).to be_present
          expect(last_month_log).to be_present
        end
      end
    end

    describe 'by_date_range スコープ' do
      it '指定された日付範囲内のログを返すこと' do
        Timecop.freeze(base_time) do
          # 過去2ヶ月間のログを取得
          start_date = 2.months.ago.beginning_of_month
          end_date = Time.current.end_of_month

          logs = InventoryLog.where(inventory: inventory).by_date_range(start_date, end_date)

          # 今月と先月のログが含まれていること
          this_month_log = logs.find_by(note: '今月のログ')
          last_month_log = logs.find_by(note: '先月のログ')
          expect(this_month_log).to be_present
          expect(last_month_log).to be_present

          # 昨年のログが含まれていないこと
          last_year_log = logs.find_by(note: '昨年のログ')
          expect(last_year_log).to be_nil

          # より狭い範囲をテスト
          narrow_start = 1.month.ago.beginning_of_month
          narrow_end = 1.month.ago.end_of_month

          narrow_logs = InventoryLog.where(inventory: inventory).by_date_range(narrow_start, narrow_end)
          narrow_manual_log = narrow_logs.find_by(note: '先月のログ')
          expect(narrow_manual_log).to be_present
        end
      end

      it 'nilの日付範囲が正しく処理されること' do
        Timecop.freeze(base_time) do
          # 開始日のみ指定
          start_date = 1.month.ago.beginning_of_month
          logs = InventoryLog.where(inventory: inventory).by_date_range(start_date, nil)

          # 今月と先月のログが含まれること（昨年のログは含まれない）
          this_month_log = logs.find_by(note: '今月のログ')
          last_month_log = logs.find_by(note: '先月のログ')
          last_year_log = logs.find_by(note: '昨年のログ')

          expect(this_month_log).to be_present
          expect(last_month_log).to be_present
          expect(last_year_log).to be_nil

          # 終了日のみ指定
          end_date = 1.month.ago.end_of_month
          logs = InventoryLog.where(inventory: inventory).by_date_range(nil, end_date)

          # 先月と昨年のログが含まれること（今月のログは含まれない）
          this_month_log = logs.find_by(note: '今月のログ')
          last_month_log = logs.find_by(note: '先月のログ')
          last_year_log = logs.find_by(note: '昨年のログ')

          expect(this_month_log).to be_nil
          expect(last_month_log).to be_present
          expect(last_year_log).to be_present
        end
      end

      it '時刻も考慮した精密な範囲指定ができること' do
        # 既存のテストデータをクリーンアップ
        InventoryLog.delete_all

        # 特定の時間範囲でログを作成
        specific_time = Time.zone.parse('2025-06-15 14:30:00')

        Timecop.freeze(specific_time) do
          specific_log = create(:inventory_log, inventory: inventory, operation_type: 'ship', note: '特定時刻のログ')

          # 時刻を含む範囲で検索
          start_time = specific_time - 1.hour
          end_time = specific_time + 1.hour

          logs = InventoryLog.where(inventory: inventory).by_date_range(start_time, end_time)
          expect(logs).to include(specific_log)
          expect(logs.find_by(note: '特定時刻のログ')).to be_present
        end
      end
    end

    describe '時間を跨いだログの作成と検索' do
      it '異なる月にまたがるログが正しく分類されること' do
        # 既存のテストデータをクリーンアップ
        InventoryLog.delete_all

        # 月の境界をテスト
        month_boundary = Time.zone.parse('2025-06-30 23:59:59')
        next_month_start = Time.zone.parse('2025-07-01 00:00:01')

        june_log = nil
        july_log = nil

        Timecop.freeze(month_boundary) do
          june_log = create(:inventory_log, inventory: inventory, operation_type: 'adjust', note: '6月末のログ')
        end

        Timecop.freeze(next_month_start) do
          july_log = create(:inventory_log, inventory: inventory, operation_type: 'receive', note: '7月初のログ')
        end

        # 6月のスコープテスト
        Timecop.freeze(month_boundary) do
          june_logs = InventoryLog.where(inventory: inventory).this_month
          expect(june_logs).to include(june_log)
          expect(june_logs).not_to include(july_log)
        end

        # 7月のスコープテスト
        Timecop.freeze(next_month_start) do
          july_logs = InventoryLog.where(inventory: inventory).this_month
          expect(july_logs).to include(july_log)
          expect(july_logs).not_to include(june_log)
        end
      end
    end

    private

    def create_logs_for_different_periods
      # 今月のログ（基準日時の当月）
      Timecop.freeze(base_time) do
        create(:inventory_log, inventory: inventory, operation_type: 'add', note: '今月のログ')
      end

      # 先月のログ
      Timecop.freeze(base_time - 1.month) do
        create(:inventory_log, inventory: inventory, operation_type: 'remove', note: '先月のログ')
      end

      # 昨年のログ
      Timecop.freeze(base_time - 1.year) do
        create(:inventory_log, inventory: inventory, operation_type: 'adjust', note: '昨年のログ')
      end
    end
  end

  # ============================================
  # TODO: 削除したテスト機能の代替実装計画
  # ============================================
  # 1. スコープテストの統合テスト化
  #    - Controllerレベルでの機能テスト
  #    - 実用的なシナリオベーステスト
  #    - エンドツーエンドテストでの検証
  #
  # 2. 統計機能の専用テストスイート
  #    - 独立したテストデータベース使用
  #    - モックを活用した単体テスト
  #    - パフォーマンステストとの統合
  #
  # 3. 高品質テスト戦略
  #    - データ干渉の完全排除
  #    - 決定論的テスト実行
  #    - CI/CDでの安定性確保
end
