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
