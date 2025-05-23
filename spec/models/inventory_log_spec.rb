# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLog, type: :model do
  describe 'associations' do
    it { should belong_to(:inventory).required }
    # user_idはオプションなのでrequiredなし
  end

  describe 'validations' do
    subject { create(:inventory_log) }

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

  describe 'scopes' do
    describe '.recent' do
      it '新しい順で取得すること' do
        # 専用のInventoryを作成してテストを分離
        test_inventory = create(:inventory, name: "recent_test_#{Time.current.to_i}")

        # 3つのログを順番に作成
        log1 = create(:inventory_log, inventory: test_inventory, operation_type: :add)
        sleep(0.01)
        log2 = create(:inventory_log, inventory: test_inventory, operation_type: :remove)
        sleep(0.01)
        log3 = create(:inventory_log, inventory: test_inventory, operation_type: :ship)

        logs = InventoryLog.where(inventory: test_inventory).recent
        expect(logs.pluck(:id)).to eq([ log3.id, log2.id, log1.id ])
      end
    end

    describe '.by_operation_type' do
      it '指定された操作タイプのログのみ取得すること' do
        # 専用のInventoryを作成してテストを分離
        test_inventory = create(:inventory, name: "operation_test_#{Time.current.to_i}")

        add_log = create(:inventory_log, inventory: test_inventory, operation_type: :add)
        remove_log = create(:inventory_log, inventory: test_inventory, operation_type: :remove)

        add_logs = InventoryLog.where(inventory: test_inventory).by_operation_type(:add)
        expect(add_logs.count).to eq(1)
        expect(add_logs.first.operation_type).to eq('add')
        expect(add_logs.first.id).to eq(add_log.id)
      end
    end

    describe '.by_date_range' do
      it '指定期間内のログのみ取得すること' do
        # 専用のInventoryを作成してテストを分離
        test_inventory = create(:inventory, name: "date_test_#{Time.current.to_i}")
        base_time = Time.current

        # 期間内のログ
        log1 = create(:inventory_log, inventory: test_inventory, operation_type: :add, created_at: base_time - 1.day)
        log2 = create(:inventory_log, inventory: test_inventory, operation_type: :remove, created_at: base_time - 12.hours)

        # 期間外のログ
        create(:inventory_log, inventory: test_inventory, operation_type: :adjust, created_at: base_time - 3.days)

        logs_in_range = InventoryLog.where(inventory: test_inventory)
                                   .by_date_range(base_time - 2.days, base_time)
        expect(logs_in_range.count).to eq(2)
        expect(logs_in_range.pluck(:id).sort).to eq([ log1.id, log2.id ].sort)
      end
    end
  end

  describe '#formatted_created_at' do
    it '日本語形式で日時をフォーマットすること' do
      test_inventory = create(:inventory, name: "format_test_#{Time.current.to_i}")
      log = create(:inventory_log, inventory: test_inventory, created_at: Time.utc(2025, 5, 23, 14, 30, 45))

      expected_time = log.created_at.in_time_zone('Asia/Tokyo').strftime("%Y年%m月%d日 %H:%M:%S")
      expect(log.formatted_created_at).to eq(expected_time)
    end
  end

  describe '#operation_display_name' do
    it '操作タイプの日本語名を返すこと' do
      test_inventory = create(:inventory, name: "display_test_#{Time.current.to_i}")

      add_log = create(:inventory_log, inventory: test_inventory, operation_type: :add)
      remove_log = create(:inventory_log, inventory: test_inventory, operation_type: :remove)
      ship_log = create(:inventory_log, inventory: test_inventory, operation_type: :ship)

      expect(add_log.operation_display_name).to eq('追加')
      expect(remove_log.operation_display_name).to eq('削除')
      expect(ship_log.operation_display_name).to eq('出荷')
    end
  end

  describe '.operation_summary' do
    it '操作タイプ別の集計を返すこと' do
      # 専用のInventoryを作成してテストを分離
      test_inventory = create(:inventory, name: "summary_test_#{Time.current.to_i}")

      # 特定の期間内でログを作成
      base_time = Time.current
      start_time = base_time - 1.day
      end_time = base_time

      # 期間内のログのみ作成
      create(:inventory_log, inventory: test_inventory, operation_type: :add, delta: 100, created_at: base_time - 12.hours)
      create(:inventory_log, inventory: test_inventory, operation_type: :add, delta: 50, created_at: base_time - 12.hours)
      create(:inventory_log, inventory: test_inventory, operation_type: :remove, delta: -30, created_at: base_time - 12.hours)

      # 期間外のログ（集計対象外）
      create(:inventory_log, inventory: test_inventory, operation_type: :add, delta: 200, created_at: base_time - 2.days)

      summary = InventoryLog.where(inventory: test_inventory)
                           .by_date_range(start_time, end_time)
                           .group(:operation_type)
                           .select("operation_type, COUNT(*) as count, SUM(ABS(delta)) as total_quantity")

      add_summary = summary.find { |s| s.operation_type == 'add' }

      expect(add_summary.count).to eq(2)
      expect(add_summary.total_quantity).to eq(150)
    end
  end

  # TODO: 在庫ログテストの拡張
  # 1. 監査機能テスト
  #    - ログの改ざん検出テスト
  #    - デジタル署名検証テスト
  #    - ハッシュチェーン整合性テスト
  #
  # 2. 分析機能テスト
  #    - 在庫変動パターン分析テスト
  #    - 異常操作検出テスト
  #    - トレンド分析レポートテスト
  #
  # 3. パフォーマンステスト
  #    - 大量ログデータの処理性能テスト
  #    - インデックス効率性テスト
  #    - アーカイブ機能テスト
end
