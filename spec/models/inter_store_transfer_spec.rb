# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InterStoreTransfer, type: :model do
  describe 'associations' do
    it { should belong_to(:source_store).class_name('Store') }
    it { should belong_to(:destination_store).class_name('Store') }
    it { should belong_to(:inventory) }
    it { should belong_to(:requested_by).class_name('Admin') }
    it { should belong_to(:approved_by).class_name('Admin').optional }
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(
      pending: 0, approved: 1, rejected: 2, in_transit: 3, completed: 4, cancelled: 5
    ) }
    it { should define_enum_for(:priority).with_values(
      normal: 0, urgent: 1, emergency: 2
    ) }
  end

  describe 'validations' do
    subject { build(:inter_store_transfer) }

    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_presence_of(:reason) }
    it { should validate_length_of(:reason).is_at_most(1000) }
    # NOTE: requested_atはbefore_validationコールバックで自動設定されるため、
    # presence validationのテストは実際には意味がない
    # it { should validate_presence_of(:requested_at) }

    describe 'custom validations' do
      describe 'different_stores' do
        it 'allows different source and destination stores' do
          source_store = create(:store)
          destination_store = create(:store)
          inventory = create(:inventory)
          create(:store_inventory, store: source_store, inventory: inventory, quantity: 100)
          transfer = build(:inter_store_transfer,
                           source_store: source_store,
                           destination_store: destination_store,
                           inventory: inventory,
                           quantity: 10,
                           requested_by: create(:admin))
          expect(transfer).to be_valid
        end

        it 'rejects same source and destination stores' do
          store = create(:store)
          transfer = build(:inter_store_transfer, source_store: store, destination_store: store)
          expect(transfer).not_to be_valid
          expect(transfer.errors[:destination_store]).to include('移動元と移動先は異なる店舗である必要があります')
        end
      end

      describe 'sufficient_source_stock' do
        let(:source_store) { create(:store) }
        let(:inventory) { create(:inventory) }

        context 'when sufficient stock exists' do
          before do
            create(:store_inventory, store: source_store, inventory: inventory, quantity: 10, reserved_quantity: 2)
          end

          it 'allows transfer within available quantity' do
            transfer = build(:inter_store_transfer, source_store: source_store, inventory: inventory, quantity: 5)
            expect(transfer).to be_valid
          end
        end

        context 'when insufficient stock exists' do
          before do
            create(:store_inventory, store: source_store, inventory: inventory, quantity: 10, reserved_quantity: 8)
          end

          it 'rejects transfer exceeding available quantity' do
            transfer = build(:inter_store_transfer, source_store: source_store, inventory: inventory, quantity: 5)
            expect(transfer).not_to be_valid
            expect(transfer.errors[:quantity]).to include('移動元の利用可能在庫が不足しています')
          end
        end

        context 'when no stock record exists' do
          it 'rejects transfer' do
            # StoreInventoryレコードを作成せずにInterStoreTransferを直接構築
            transfer = InterStoreTransfer.new(
              source_store: source_store,
              destination_store: create(:store),
              inventory: inventory,
              quantity: 1,
              reason: '在庫不足のため移動が必要です',
              requested_by: create(:admin)
            )
            expect(transfer).not_to be_valid
            expect(transfer.errors[:quantity]).to include('移動元の利用可能在庫が不足しています')
          end
        end
      end

      describe 'valid_status_transition' do
        let(:transfer) { create(:inter_store_transfer, status: :pending) }

        it 'allows valid transitions from pending' do
          %w[approved rejected cancelled].each do |new_status|
            transfer.status = new_status
            expect(transfer).to be_valid
          end
        end

        it 'rejects invalid transitions from completed' do
          # 正しいステータス遷移で完了状態にする
          transfer.update!(status: :approved)
          transfer.update!(status: :completed)

          transfer.status = :pending
          expect(transfer).not_to be_valid
          expect(transfer.errors[:status]).to include('無効なステータス変更です: completed → pending')
        end

        it 'allows valid transitions from approved' do
          transfer.update!(status: :approved)
          %w[in_transit cancelled completed].each do |new_status|
            transfer.status = new_status
            expect(transfer).to be_valid
          end
        end
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation :set_requested_at' do
      it 'sets requested_at on create when not provided' do
        transfer = build(:inter_store_transfer, requested_at: nil)
        transfer.validate
        expect(transfer.requested_at).to be_present
      end

      it 'does not override existing requested_at' do
        custom_time = 1.hour.ago.round
        transfer = build(:inter_store_transfer, requested_at: custom_time)
        transfer.validate
        expect(transfer.requested_at).to eq(custom_time)
      end
    end

    describe 'after_create :reserve_source_stock' do
      let(:source_store) { create(:store) }
      let(:inventory) { create(:inventory) }
      let!(:store_inventory) { create(:store_inventory, store: source_store, inventory: inventory, quantity: 10, reserved_quantity: 2) }

      it 'increases reserved_quantity in source store' do
        expect {
          create(:inter_store_transfer, source_store: source_store, inventory: inventory, quantity: 3)
        }.to change { store_inventory.reload.reserved_quantity }.from(2).to(5)
      end
    end

    describe 'after_update :handle_status_change' do
      let(:source_store) { create(:store) }
      let(:inventory) { create(:inventory) }
      let(:transfer) { create(:inter_store_transfer, source_store: source_store, inventory: inventory, quantity: 3) }
      let(:store_inventory) { StoreInventory.find_by(store: source_store, inventory: inventory) }

      it 'releases reserved stock when cancelled' do
        transfer # Ensure transfer is created
        store_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)

        expect {
          transfer.update!(status: :cancelled)
        }.to change { store_inventory.reload.reserved_quantity }.by(-3)
      end

      it 'releases reserved stock when rejected' do
        transfer # Ensure transfer is created
        store_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)

        expect {
          transfer.update!(status: :rejected)
        }.to change { store_inventory.reload.reserved_quantity }.by(-3)
      end

      it 'logs approval information' do
        expect(Rails.logger).to receive(:info).with("移動申請が承認されました: #{transfer.id}")
        transfer.update!(status: :approved)
      end

      it 'logs completion information' do
        transfer.update!(status: :approved)
        expect(Rails.logger).to receive(:info).with("移動が完了しました: #{transfer.id}")
        transfer.update!(status: :completed)
      end
    end
  end

  describe 'scopes' do
    let!(:store1) { create(:store) }
    let!(:store2) { create(:store) }
    let!(:store3) { create(:store) }
    let!(:inventory) { create(:inventory) }
    let!(:admin) { create(:admin) }

    let!(:transfer1) { create(:inter_store_transfer, source_store: store1, destination_store: store2, status: :pending, priority: :normal) }
    let!(:transfer2) { create(:inter_store_transfer, source_store: store2, destination_store: store3, status: :approved, priority: :urgent) }
    let!(:transfer3) { create(:inter_store_transfer, source_store: store1, destination_store: store3, status: :completed, priority: :emergency) }
    let!(:transfer4) { create(:inter_store_transfer, source_store: store3, destination_store: store1, status: :rejected) }

    describe '.by_source_store' do
      it 'returns transfers from specified store' do
        expect(InterStoreTransfer.by_source_store(store1)).to include(transfer1, transfer3)
        expect(InterStoreTransfer.by_source_store(store1)).not_to include(transfer2, transfer4)
      end
    end

    describe '.by_destination_store' do
      it 'returns transfers to specified store' do
        expect(InterStoreTransfer.by_destination_store(store3)).to include(transfer2, transfer3)
        expect(InterStoreTransfer.by_destination_store(store3)).not_to include(transfer1, transfer4)
      end
    end

    describe '.by_store' do
      it 'returns transfers involving specified store (source or destination)' do
        expect(InterStoreTransfer.by_store(store1)).to include(transfer1, transfer3, transfer4)
        expect(InterStoreTransfer.by_store(store1)).not_to include(transfer2)
      end
    end

    describe '.by_priority' do
      it 'returns transfers with specified priority' do
        expect(InterStoreTransfer.by_priority(:urgent)).to include(transfer2)
        expect(InterStoreTransfer.by_priority(:urgent)).not_to include(transfer1, transfer3)
      end
    end

    describe '.active' do
      it 'returns transfers with active statuses' do
        expect(InterStoreTransfer.active).to include(transfer1, transfer2)
        expect(InterStoreTransfer.active).not_to include(transfer3, transfer4)
      end
    end

    describe '.completed_transfers' do
      it 'returns transfers with final statuses' do
        expect(InterStoreTransfer.completed_transfers).to include(transfer3, transfer4)
        expect(InterStoreTransfer.completed_transfers).not_to include(transfer1, transfer2)
      end
    end
  end

  describe 'instance methods' do
    let(:source_store) { create(:store, name: '中央薬局') }
    let(:destination_store) { create(:store, name: '西口薬局') }
    let(:inventory) { create(:inventory, name: 'アスピリン100mg') }
    let(:admin) { create(:admin) }
    let(:transfer) { create(:inter_store_transfer,
      source_store: source_store,
      destination_store: destination_store,
      inventory: inventory,
      quantity: 5,
      requested_by: admin
    ) }

    describe 'status and priority text methods' do
      describe '#status_text' do
        it 'returns Japanese text for each status' do
          status_translations = {
            'pending' => '承認待ち',
            'approved' => '承認済み',
            'rejected' => '却下',
            'in_transit' => '移動中',
            'completed' => '完了',
            'cancelled' => 'キャンセル'
          }

          status_translations.each do |status, text|
            transfer.status = status
            expect(transfer.status_text).to eq(text)
          end
        end
      end

      describe '#priority_text' do
        it 'returns Japanese text for each priority' do
          priority_translations = {
            'normal' => '通常',
            'urgent' => '緊急',
            'emergency' => '非常時'
          }

          priority_translations.each do |priority, text|
            transfer.priority = priority
            expect(transfer.priority_text).to eq(text)
          end
        end
      end
    end

    describe '#transfer_summary' do
      it 'returns formatted transfer description' do
        expected = "#{source_store.code} - 中央薬局 → #{destination_store.code} - 西口薬局: アスピリン100mg × 5"
        expect(transfer.transfer_summary).to eq(expected)
      end
    end

    describe '#processing_time' do
      it 'returns nil when not completed' do
        expect(transfer.processing_time).to be_nil
      end

      it 'calculates processing time when completed' do
        start_time = 2.hours.ago
        end_time = 1.hour.ago

        # 正しいステータス遷移で完了状態にする
        transfer.update!(status: :approved)
        transfer.update!(status: :completed, completed_at: end_time, requested_at: start_time)

        expect(transfer.processing_time).to be_within(1.second).of(1.hour)
      end
    end

    describe 'state check methods' do
      describe '#approvable?' do
        it 'returns true for pending transfers with sufficient stock' do
          create(:store_inventory, store: source_store, inventory: inventory, quantity: 10, reserved_quantity: 0)
          expect(transfer.approvable?).to be true
        end

        it 'returns false for non-pending transfers' do
          transfer.update!(status: :approved)
          expect(transfer.approvable?).to be false
        end

        it 'returns false when insufficient stock' do
          # transferが作成されるとファクトリによって在庫が作成される
          transfer # Ensure transfer is created and StoreInventory exists
          store_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)
          store_inventory.update!(quantity: 3, reserved_quantity: 2)  # available: 1, needed: 5
          expect(transfer.approvable?).to be false
        end
      end

      describe '#rejectable?' do
        it 'returns true for pending transfers' do
          expect(transfer.rejectable?).to be true
        end

        it 'returns false for non-pending transfers' do
          transfer.update!(status: :approved)
          expect(transfer.rejectable?).to be false
        end
      end

      describe '#can_be_cancelled?' do
        it 'returns true for pending and approved transfers' do
          expect(transfer.can_be_cancelled?).to be true

          transfer.update!(status: :approved)
          expect(transfer.can_be_cancelled?).to be true
        end

        it 'returns false for other statuses' do
          # 正しいステータス遷移で完了状態にする
          transfer.update!(status: :approved)
          transfer.update!(status: :completed)
          expect(transfer.can_be_cancelled?).to be false
        end
      end

      describe '#completable?' do
        it 'returns true for approved and in_transit transfers' do
          transfer.update!(status: :approved)
          expect(transfer.completable?).to be true

          transfer.update!(status: :in_transit)
          expect(transfer.completable?).to be true
        end

        it 'returns false for other statuses' do
          expect(transfer.completable?).to be false
        end
      end
    end

    describe 'workflow action methods' do
      let(:approver) { create(:admin) }
      let(:store_inventory) { StoreInventory.find_by(store: source_store, inventory: inventory) }

      describe '#approve!' do
        context 'when approvable' do
          it 'updates status and approver information' do
            expect(transfer.approve!(approver)).to be true

            transfer.reload
            expect(transfer.status).to eq('approved')
            expect(transfer.approved_by).to eq(approver)
            expect(transfer.approved_at).to be_present
          end
        end

        context 'when not approvable' do
          before do
            # 正しいステータス遷移で完了状態にする
            transfer.update!(status: :approved)
            transfer.update!(status: :completed)
          end

          it 'returns false and does not update' do
            expect(transfer.approve!(approver)).to be false
            expect(transfer.approved_by).to be_nil
          end
        end
      end

      describe '#reject!' do
        let(:rejection_reason) { '在庫不足のため' }

        context 'when rejectable' do
          it 'updates status and adds rejection reason' do
            original_reason = transfer.reason
            expect(transfer.reject!(approver, rejection_reason)).to be true

            transfer.reload
            expect(transfer.status).to eq('rejected')
            expect(transfer.approved_by).to eq(approver)
            expect(transfer.approved_at).to be_present
            expect(transfer.reason).to include(original_reason)
            expect(transfer.reason).to include(rejection_reason)
          end

          it 'releases reserved stock' do
            transfer # Ensure transfer is created
            store_inventory = StoreInventory.find_by(store: source_store, inventory: inventory)

            expect {
              transfer.reject!(approver, rejection_reason)
            }.to change { store_inventory.reload.reserved_quantity }.by(-5) # Release transfer quantity
          end
        end

        context 'when not rejectable' do
          before do
            # 正しいステータス遷移で完了状態にする
            transfer.update!(status: :approved)
            transfer.update!(status: :completed)
          end

          it 'returns false and does not update' do
            expect(transfer.reject!(approver, rejection_reason)).to be false
          end
        end
      end

      describe '#execute_transfer!' do
        let(:destination_store_inventory) { create(:store_inventory, store: destination_store, inventory: inventory, quantity: 3) }

        before do
          transfer.update!(status: :approved)
        end

        context 'when completable and valid' do
          it 'transfers inventory between stores' do
            destination_store_inventory # Create destination inventory

            expect(transfer.execute_transfer!).to be true

            store_inventory.reload
            destination_store_inventory.reload
            transfer.reload

            expect(store_inventory.quantity).to eq(20) # 25 - 5 (factory creates quantity + 20 = 5 + 20 = 25)
            expect(store_inventory.reserved_quantity).to eq(0) # All reserved stock released
            expect(destination_store_inventory.quantity).to eq(8) # 3 + 5
            expect(transfer.status).to eq('completed')
            expect(transfer.completed_at).to be_present
          end

          it 'creates destination inventory if it does not exist' do
            expect {
              transfer.execute_transfer!
            }.to change { StoreInventory.where(store: destination_store, inventory: inventory).count }.from(0).to(1)

            new_inventory = StoreInventory.find_by(store: destination_store, inventory: inventory)
            expect(new_inventory.quantity).to eq(5)
            expect(new_inventory.safety_stock_level).to eq(5)
          end
        end

        context 'when not completable' do
          before do
            # Transfer is already in pending status, which is not completable
            # No status change needed as pending is not completable
          end

          it 'returns false and does not transfer' do
            # Transfer is already approved, change to pending to make it not completable
            # but this is invalid status transition, so create a new pending transfer
            initial_quantity = store_inventory.reload.quantity

            pending_transfer = create(:inter_store_transfer,
                                     source_store: source_store,
                                     inventory: inventory,
                                     quantity: 5,
                                     status: :pending)

            expect(pending_transfer.execute_transfer!).to be false
            expect(store_inventory.reload.quantity).to eq(initial_quantity) # unchanged
          end
        end

        context 'when transfer fails due to validation errors' do
          before do
            # Force a validation error by setting insufficient inventory
            # We need to make source inventory have insufficient available quantity for the transfer
            store_inventory.update!(quantity: 3, reserved_quantity: 1)  # available: 2, needed: 5
          end

          it 'returns false and logs error' do
            expect(Rails.logger).to receive(:error).with(/移動実行エラー/)
            expect(transfer.execute_transfer!).to be false
          end
        end
      end
    end
  end

  describe 'class methods' do
    let!(:store1) { create(:store) }
    let!(:store2) { create(:store) }
    let!(:store3) { create(:store) }
    let!(:inventory1) { create(:inventory) }
    let!(:inventory2) { create(:inventory) }

    let!(:completed_transfer1) { create(:inter_store_transfer,
      source_store: store1,
      destination_store: store2,
      inventory: inventory1,
      status: :completed,
      requested_at: 5.days.ago,
      completed_at: 4.days.ago
    ) }

    let!(:completed_transfer2) { create(:inter_store_transfer,
      source_store: store1,
      destination_store: store3,
      inventory: inventory2,
      status: :completed,
      requested_at: 3.days.ago,
      completed_at: 2.days.ago
    ) }

    let!(:pending_transfer) { create(:inter_store_transfer,
      source_store: store1,
      destination_store: store2,
      status: :pending,
      requested_at: 1.day.ago
    ) }

    describe '.store_transfer_stats' do
      it 'returns comprehensive transfer statistics for a store' do
        stats = InterStoreTransfer.store_transfer_stats(store1, 7.days.ago..)

        expect(stats[:outgoing_count]).to eq(3) # all transfers from store1
        expect(stats[:incoming_count]).to eq(0) # no transfers to store1
        expect(stats[:outgoing_completed]).to eq(2) # completed transfers
        expect(stats[:pending_approvals]).to eq(1) # pending transfer
        expect(stats[:average_processing_time]).to be > 0
      end
    end

    describe '.transfer_analytics' do
      before do
        # Add a rejected transfer for more comprehensive testing
        create(:inter_store_transfer,
          source_store: store2,
          destination_store: store1,
          status: :rejected,
          priority: :urgent,
          requested_at: 2.days.ago
        )
      end

      it 'returns analytical data for transfers in period' do
        # Get the IDs of our specific test transfers
        our_transfer_ids = [ completed_transfer1.id, completed_transfer2.id, pending_transfer.id ]

        # Add the rejected transfer created in before block
        rejected_transfer = InterStoreTransfer.where(
          source_store: store2,
          destination_store: store1,
          status: :rejected
        ).first
        our_transfer_ids << rejected_transfer.id if rejected_transfer

        # Use specific time period that only includes our test data
        analytics = InterStoreTransfer.transfer_analytics(6.days.ago..Time.current)

        # Count only transfers in our time period with our store IDs
        our_stores = [ store1.id, store2.id, store3.id ]
        actual_transfers = InterStoreTransfer.where(
          requested_at: 6.days.ago..Time.current,
          source_store_id: our_stores
        ).or(
          InterStoreTransfer.where(
            requested_at: 6.days.ago..Time.current,
            destination_store_id: our_stores
          )
        )

        expect(actual_transfers.count).to eq(4) # Verify our assumption
        expect(analytics[:total_requests]).to be >= 4
        expect(analytics[:approval_rate]).to be > 0
        expect(analytics[:average_quantity]).to be > 0
        expect(analytics[:by_priority]).to include('normal', 'urgent')
        expect(analytics[:by_status]).to include('completed', 'pending', 'rejected')
        expect(analytics[:top_requested_items]).to be_present
      end
    end

    describe 'private helper methods' do
      describe '.calculate_approval_rate' do
        let(:transfers) { InterStoreTransfer.where(id: [ completed_transfer1.id, completed_transfer2.id, pending_transfer.id ]) }

        it 'calculates approval rate correctly' do
          rate = InterStoreTransfer.calculate_approval_rate(transfers)
          expected_rate = (2.0 / 3.0 * 100).round(2) # 2 completed out of 3 total
          expect(rate).to eq(expected_rate)
        end

        it 'returns 0 for empty collection' do
          rate = InterStoreTransfer.calculate_approval_rate(InterStoreTransfer.none)
          expect(rate).to eq(0.0)
        end
      end

      describe '.calculate_average_processing_time' do
        let(:completed_transfers) { InterStoreTransfer.where(id: [ completed_transfer1.id, completed_transfer2.id ]) }

        it 'calculates average processing time correctly' do
          avg_time = InterStoreTransfer.calculate_average_processing_time(completed_transfers)
          expect(avg_time).to be_within(1.second).of(1.day) # Both transfers took 1 day each
        end

        it 'returns 0 for empty collection' do
          avg_time = InterStoreTransfer.calculate_average_processing_time(InterStoreTransfer.none)
          expect(avg_time).to eq(0.0)
        end
      end
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(create(:inter_store_transfer)).to be_valid
    end

    it 'has working traits' do
      expect(create(:inter_store_transfer, :pending)).to be_valid
      expect(create(:inter_store_transfer, :approved)).to be_valid
      expect(create(:inter_store_transfer, :completed)).to be_valid
      expect(create(:inter_store_transfer, :urgent)).to be_valid
      expect(create(:inter_store_transfer, :emergency)).to be_valid
    end
  end

  # TODO: Phase 2以降で実装予定のテスト
  #
  # 🔴 Phase 2 優先実装項目:
  # 1. 自動承認機能テスト
  #    - 承認ルールエンジンによる自動判定
  #    - 金額・数量・優先度による条件分岐
  #    - エスカレーション機能の動作確認
  #    期待効果: 単純な移動申請の処理時間90%短縮
  #
  # 2. 通知機能テスト
  #    - NotificationService統合テスト
  #    - メール・Slack通知の送信確認
  #    - 通知タイミングとコンテンツの検証
  #    期待効果: 関係者への確実な情報共有
  #
  # 🟡 Phase 3 重要実装項目:
  # 3. バッチ移動機能テスト
  #    - 複数商品の一括移動申請
  #    - 定期移動スケジュール機能
  #    - テンプレート機能の動作確認
  #    期待効果: 大量移動作業の効率化
  #
  # 4. 配送追跡機能テスト
  #    - 配送業者API連携
  #    - リアルタイム配送状況更新
  #    - 配送完了の自動ステータス更新
  #    期待効果: 配送過程の可視化と自動化
  #
  # 🟢 Phase 4 推奨実装項目:
  # 5. 高度な分析機能テスト
  #    - 移動パターン分析・予測
  #    - 店舗間効率性指標算出
  #    - AI活用の移動提案機能
  #    期待効果: データドリブンな最適化提案
end
