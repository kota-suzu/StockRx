# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InterStoreTransfer, type: :model do
  # CLAUDE.md準拠: 店舗間在庫移動の包括的テスト
  # メタ認知: 複雑な承認フローとポリモーフィック関連の品質保証
  # 横展開: 他の承認系モデルでも同様のテストパターン適用

  let(:source_store) { create(:store, name: '渋谷店') }
  let(:destination_store) { create(:store, name: '新宿店') }
  let(:inventory) { create(:inventory, name: 'アスピリン錠100mg', price: 1000) }
  let(:admin_user) { create(:admin, name: '管理者太郎') }
  let(:store_user) { create(:store_user, store: source_store, name: '店舗スタッフ') }

  # 移動元に在庫を準備
  let!(:source_inventory) do
    create(:store_inventory,
      store: source_store,
      inventory: inventory,
      quantity: 100,
      reserved_quantity: 0,
      safety_stock_level: 20
    )
  end

  describe 'associations' do
    it { should belong_to(:source_store).class_name('Store') }
    it { should belong_to(:destination_store).class_name('Store') }
    it { should belong_to(:inventory) }

    # ポリモーフィック関連付け：AdminとStoreUserの両方に対応
    it { should belong_to(:requested_by) }
    it { should belong_to(:approved_by).optional }
    it { should belong_to(:shipped_by).optional }
    it { should belong_to(:completed_by).optional }
    it { should belong_to(:cancelled_by).optional }
  end

  describe 'validations' do
    subject { build(:inter_store_transfer, source_store: source_store, destination_store: destination_store) }

    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_presence_of(:reason) }
    it { should validate_length_of(:reason).is_at_most(1000) }
    it { should validate_length_of(:notes).is_at_most(2000).allow_blank }

    describe 'requested_delivery_date validation' do
      it 'accepts future dates' do
        transfer = build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_delivery_date: 3.days.from_now
        )
        expect(transfer).to be_valid
      end

      it 'rejects past dates' do
        transfer = build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_delivery_date: 1.day.ago
        )
        expect(transfer).not_to be_valid
        expect(transfer.errors[:requested_delivery_date]).to include('は今日より後の日付を指定してください')
      end

      it 'rejects today' do
        transfer = build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_delivery_date: Date.current
        )
        expect(transfer).not_to be_valid
      end

      it 'allows nil' do
        transfer = build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_delivery_date: nil
        )
        expect(transfer).to be_valid
      end
    end

    describe 'custom validations' do
      describe 'different_stores' do
        it 'requires different source and destination stores' do
          transfer = build(:inter_store_transfer,
            source_store: source_store,
            destination_store: source_store,
            inventory: inventory,
            requested_by: admin_user
          )
          expect(transfer).not_to be_valid
          expect(transfer.errors[:destination_store]).to include('移動元と移動先は異なる店舗である必要があります')
        end
      end

      describe 'sufficient_source_stock' do
        it 'validates sufficient stock at source' do
          transfer = build(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            inventory: inventory,
            quantity: 150, # More than available
            requested_by: admin_user
          )
          expect(transfer).not_to be_valid
          expect(transfer.errors[:quantity]).to include('移動元の利用可能在庫が不足しています')
        end

        it 'allows transfer within available stock' do
          transfer = build(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            inventory: inventory,
            quantity: 50,
            requested_by: admin_user
          )
          expect(transfer).to be_valid
        end

        it 'considers reserved quantity' do
          source_inventory.update!(reserved_quantity: 60)
          transfer = build(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            inventory: inventory,
            quantity: 50, # Available is 40
            requested_by: admin_user
          )
          expect(transfer).not_to be_valid
        end
      end

      describe 'valid_status_transition' do
        let(:transfer) { create(:inter_store_transfer, source_store: source_store, destination_store: destination_store) }

        context 'from pending' do
          it 'allows transition to approved' do
            transfer.status = :approved
            expect(transfer).to be_valid
          end

          it 'allows transition to rejected' do
            transfer.status = :rejected
            expect(transfer).to be_valid
          end

          it 'allows transition to cancelled' do
            transfer.status = :cancelled
            expect(transfer).to be_valid
          end

          it 'prevents direct transition to completed' do
            transfer.status = :completed
            expect(transfer).not_to be_valid
            expect(transfer.errors[:status]).to include(/無効なステータス変更/)
          end
        end

        context 'from approved' do
          before { transfer.update!(status: :approved) }

          it 'allows transition to in_transit' do
            transfer.status = :in_transit
            expect(transfer).to be_valid
          end

          it 'allows transition to completed' do
            transfer.status = :completed
            expect(transfer).to be_valid
          end

          it 'allows transition to cancelled' do
            transfer.status = :cancelled
            expect(transfer).to be_valid
          end

          it 'prevents transition back to pending' do
            transfer.status = :pending
            expect(transfer).not_to be_valid
          end
        end

        context 'from completed' do
          before { transfer.update!(status: :approved) } # First valid transition
          before { transfer.update!(status: :completed) }

          it 'prevents any status change' do
            [ :pending, :approved, :rejected, :in_transit, :cancelled ].each do |status|
              transfer.status = status
              expect(transfer).not_to be_valid
            end
          end
        end
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(
      pending: 0,
      approved: 1,
      rejected: 2,
      in_transit: 3,
      completed: 4,
      cancelled: 5
    ).backed_by_column_of_type(:integer) }

    it { should define_enum_for(:priority).with_values(
      normal: 0,
      urgent: 1,
      emergency: 2
    ).backed_by_column_of_type(:integer) }
  end

  describe 'callbacks' do
    describe 'before_validation :set_requested_at' do
      it 'sets requested_at on create' do
        transfer = build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_at: nil
        )
        transfer.save!
        expect(transfer.requested_at).to be_present
        expect(transfer.requested_at).to be_within(1.second).of(Time.current)
      end

      it 'preserves existing requested_at' do
        custom_time = 2.hours.ago
        transfer = build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_at: custom_time
        )
        transfer.save!
        expect(transfer.requested_at).to eq(custom_time)
      end
    end

    describe 'after_create :reserve_source_stock' do
      it 'reserves stock at source store' do
        expect {
          create(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            inventory: inventory,
            quantity: 30,
            requested_by: admin_user
          )
        }.to change { source_inventory.reload.reserved_quantity }.from(0).to(30)
      end
    end

    describe 'after_update :handle_status_change' do
      let(:transfer) do
        create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          inventory: inventory,
          quantity: 20,
          requested_by: admin_user
        )
      end

      it 'logs approval' do
        expect(Rails.logger).to receive(:info).with(/移動申請が承認されました/)
        transfer.update!(status: :approved)
      end

      it 'releases reserved stock on rejection' do
        expect {
          transfer.update!(status: :rejected)
        }.to change { source_inventory.reload.reserved_quantity }.from(20).to(0)
      end

      it 'releases reserved stock on cancellation' do
        expect {
          transfer.update!(status: :cancelled)
        }.to change { source_inventory.reload.reserved_quantity }.from(20).to(0)
      end

      it 'logs completion' do
        transfer.update!(status: :approved)
        expect(Rails.logger).to receive(:info).with(/移動が完了しました/)
        transfer.update!(status: :completed)
      end
    end

    describe 'before_destroy :release_reserved_stock' do
      it 'releases reserved stock if cancellable' do
        transfer = create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          inventory: inventory,
          quantity: 25,
          requested_by: admin_user
        )

        expect {
          transfer.destroy
        }.to change { source_inventory.reload.reserved_quantity }.from(25).to(0)
      end

      it 'does not release stock if not cancellable' do
        transfer = create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          inventory: inventory,
          quantity: 25,
          requested_by: admin_user,
          status: :approved
        )
        transfer.update!(status: :completed)
        source_inventory.update!(reserved_quantity: 0)

        transfer.destroy
        expect(source_inventory.reload.reserved_quantity).to eq(0)
      end
    end

    describe 'after_commit :update_store_pending_counts' do
      it 'updates source store pending count on create' do
        expect {
          create(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            requested_by: admin_user
          )
        }.to change { source_store.reload.pending_outgoing_transfers_count }.by(1)
      end

      it 'updates destination store pending count on create' do
        expect {
          create(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            requested_by: admin_user
          )
        }.to change { destination_store.reload.pending_incoming_transfers_count }.by(1)
      end

      it 'updates counts on status change' do
        transfer = create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_by: admin_user
        )

        expect {
          transfer.update!(status: :approved)
        }.to change { source_store.reload.pending_outgoing_transfers_count }.by(-1)
      end

      it 'updates counts on destroy' do
        transfer = create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_by: admin_user
        )

        expect(source_store.reload.pending_outgoing_transfers_count).to eq(1)
        expect(destination_store.reload.pending_incoming_transfers_count).to eq(1)

        expect {
          transfer.destroy!
        }.to change { source_store.reload.pending_outgoing_transfers_count }.by(-1)
          .and change { destination_store.reload.pending_incoming_transfers_count }.by(-1)
      end
    end
  end

  describe 'scopes' do
    let!(:transfer1) do
      create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        inventory: inventory,
        requested_by: admin_user,
        status: :pending,
        priority: :urgent
      )
    end

    let!(:transfer2) do
      create(:inter_store_transfer,
        source_store: destination_store,
        destination_store: source_store,
        inventory: inventory,
        requested_by: store_user,
        status: :approved,
        priority: :normal
      )
    end

    let!(:transfer3) do
      other_store = create(:store)
      create(:inter_store_transfer,
        source_store: source_store,
        destination_store: other_store,
        inventory: inventory,
        requested_by: admin_user,
        approved_by: admin_user,
        status: :approved,
        priority: :emergency
      )
    end

    describe '.by_source_store' do
      it 'filters by source store' do
        expect(InterStoreTransfer.by_source_store(source_store)).to include(transfer1, transfer3)
        expect(InterStoreTransfer.by_source_store(source_store)).not_to include(transfer2)
      end
    end

    describe '.by_destination_store' do
      it 'filters by destination store' do
        expect(InterStoreTransfer.by_destination_store(destination_store)).to include(transfer1)
        expect(InterStoreTransfer.by_destination_store(destination_store)).not_to include(transfer2, transfer3)
      end
    end

    describe '.by_store' do
      it 'filters by either source or destination store' do
        expect(InterStoreTransfer.by_store(source_store)).to include(transfer1, transfer2, transfer3)
        expect(InterStoreTransfer.by_store(destination_store)).to include(transfer1, transfer2)
      end
    end

    describe '.by_inventory' do
      it 'filters by inventory' do
        other_inventory = create(:inventory)
        other_transfer = create(:inter_store_transfer,
          inventory: other_inventory,
          source_store: source_store,
          destination_store: destination_store
        )

        expect(InterStoreTransfer.by_inventory(inventory)).to include(transfer1, transfer2, transfer3)
        expect(InterStoreTransfer.by_inventory(inventory)).not_to include(other_transfer)
      end
    end

    describe '.by_requestor' do
      it 'filters by polymorphic requestor (admin)' do
        expect(InterStoreTransfer.by_requestor(admin_user)).to include(transfer1, transfer3)
        expect(InterStoreTransfer.by_requestor(admin_user)).not_to include(transfer2)
      end

      it 'filters by polymorphic requestor (store user)' do
        expect(InterStoreTransfer.by_requestor(store_user)).to include(transfer2)
        expect(InterStoreTransfer.by_requestor(store_user)).not_to include(transfer1, transfer3)
      end
    end

    describe '.by_approver' do
      it 'filters by approver' do
        expect(InterStoreTransfer.by_approver(admin_user)).to include(transfer3)
        expect(InterStoreTransfer.by_approver(admin_user)).not_to include(transfer1, transfer2)
      end
    end

    describe '.recent' do
      it 'orders by requested_at desc' do
        old_transfer = create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_at: 1.week.ago
        )

        recent_transfers = InterStoreTransfer.recent
        expect(recent_transfers.first.requested_at).to be > recent_transfers.last.requested_at
        expect(recent_transfers.last).to eq(old_transfer)
      end
    end

    describe '.by_priority' do
      it 'filters by priority' do
        expect(InterStoreTransfer.by_priority(:urgent)).to include(transfer1)
        expect(InterStoreTransfer.by_priority(:normal)).to include(transfer2)
        expect(InterStoreTransfer.by_priority(:emergency)).to include(transfer3)
      end
    end

    describe '.active' do
      it 'returns pending, approved, and in_transit transfers' do
        expect(InterStoreTransfer.active).to include(transfer1, transfer2, transfer3)

        # Create completed transfer
        completed = create(:inter_store_transfer, status: :approved)
        completed.update!(status: :completed)
        expect(InterStoreTransfer.active).not_to include(completed)
      end
    end

    describe '.completed_transfers' do
      it 'returns completed, cancelled, and rejected transfers' do
        completed = create(:inter_store_transfer, status: :approved)
        completed.update!(status: :completed)
        cancelled = create(:inter_store_transfer, status: :cancelled)
        rejected = create(:inter_store_transfer, status: :rejected)

        expect(InterStoreTransfer.completed_transfers).to include(completed, cancelled, rejected)
        expect(InterStoreTransfer.completed_transfers).not_to include(transfer1, transfer2, transfer3)
      end
    end
  end

  describe 'instance methods' do
    let(:transfer) do
      create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        inventory: inventory,
        quantity: 30,
        requested_by: admin_user
      )
    end

    describe '#status_text' do
      it 'returns Japanese text for status' do
        expect(transfer.status_text).to eq('承認待ち')

        transfer.status = :approved
        expect(transfer.status_text).to eq('承認済み')

        transfer.status = :rejected
        expect(transfer.status_text).to eq('却下')

        transfer.status = :in_transit
        expect(transfer.status_text).to eq('移動中')

        transfer.status = :completed
        expect(transfer.status_text).to eq('完了')

        transfer.status = :cancelled
        expect(transfer.status_text).to eq('キャンセル')
      end
    end

    describe '#priority_text' do
      it 'returns Japanese text for priority' do
        expect(transfer.priority_text).to eq('通常')

        transfer.priority = :urgent
        expect(transfer.priority_text).to eq('緊急')

        transfer.priority = :emergency
        expect(transfer.priority_text).to eq('非常時')
      end
    end

    describe '#transfer_summary' do
      it 'returns formatted transfer summary' do
        expected = "#{source_store.display_name} → #{destination_store.display_name}: #{inventory.name} × #{transfer.quantity}"
        expect(transfer.transfer_summary).to eq(expected)
      end
    end

    describe '#processing_time' do
      it 'calculates time between request and completion' do
        transfer.update!(status: :approved)
        transfer.update!(
          status: :completed,
          completed_at: transfer.requested_at + 2.hours
        )

        expect(transfer.processing_time).to eq(2.hours)
      end

      it 'returns nil if not completed' do
        expect(transfer.processing_time).to be_nil
      end

      it 'returns nil if requested_at is nil' do
        transfer.update!(status: :approved)
        transfer.update!(status: :completed, completed_at: Time.current)
        transfer.update_column(:requested_at, nil)

        expect(transfer.processing_time).to be_nil
      end
    end

    describe '#approvable?' do
      it 'returns true for pending with sufficient stock' do
        expect(transfer.approvable?).to be true
      end

      it 'returns false if not pending' do
        transfer.update!(status: :approved)
        expect(transfer.approvable?).to be false
      end

      it 'returns false if insufficient stock' do
        source_inventory.update!(quantity: 20)
        expect(transfer.approvable?).to be false
      end
    end

    describe '#rejectable?' do
      it 'returns true for pending' do
        expect(transfer.rejectable?).to be true
      end

      it 'returns false if not pending' do
        transfer.update!(status: :approved)
        expect(transfer.rejectable?).to be false
      end
    end

    describe '#can_be_cancelled?' do
      it 'returns true for pending' do
        expect(transfer.can_be_cancelled?).to be true
      end

      it 'returns true for approved' do
        transfer.update!(status: :approved)
        expect(transfer.can_be_cancelled?).to be true
      end

      it 'returns false for completed' do
        transfer.update!(status: :approved)
        transfer.update!(status: :completed)
        expect(transfer.can_be_cancelled?).to be false
      end

      it 'returns false for rejected' do
        transfer.update!(status: :rejected)
        expect(transfer.can_be_cancelled?).to be false
      end
    end

    describe '#can_be_cancelled_by?' do
      context 'with admin user' do
        it 'allows cancellation by requesting admin' do
          expect(transfer.can_be_cancelled_by?(admin_user)).to be true
        end

        it 'allows cancellation by headquarters admin' do
          hq_admin = create(:admin, :headquarters_admin)
          expect(transfer.can_be_cancelled_by?(hq_admin)).to be true
        end

        it 'prevents cancellation by other admin' do
          other_admin = create(:admin)
          expect(transfer.can_be_cancelled_by?(other_admin)).to be false
        end
      end

      context 'with store user' do
        let(:store_transfer) do
          create(:inter_store_transfer,
            source_store: source_store,
            destination_store: destination_store,
            requested_by: store_user
          )
        end

        it 'allows cancellation by store user from same store if pending' do
          expect(store_transfer.can_be_cancelled_by?(store_user)).to be true
        end

        it 'prevents cancellation by store user from different store' do
          other_store_user = create(:store_user, store: destination_store)
          expect(store_transfer.can_be_cancelled_by?(other_store_user)).to be false
        end

        it 'prevents cancellation by store user if approved' do
          store_transfer.update!(status: :approved)
          expect(store_transfer.can_be_cancelled_by?(store_user)).to be false
        end
      end
    end

    describe '#cancel_by!' do
      it 'cancels transfer and releases stock' do
        expect {
          result = transfer.cancel_by!(admin_user)
          expect(result).to be true
        }.to change { transfer.reload.status }.from('pending').to('cancelled')
          .and change { source_inventory.reload.reserved_quantity }.from(30).to(0)
      end

      it 'records cancelling admin in cancelled_by' do
        transfer.cancel_by!(admin_user)
        expect(transfer.reload.cancelled_by).to eq(admin_user)
      end

      it 'keeps cancelled_by nil when store user cancels' do
        store_transfer = create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          inventory: inventory,
          quantity: 10,
          requested_by: store_user
        )

        expect(store_transfer.cancel_by!(store_user)).to be true
        expect(store_transfer.reload.cancelled_by).to be_nil
      end

      it 'returns false if not cancellable by user' do
        other_admin = create(:admin)
        result = transfer.cancel_by!(other_admin)
        expect(result).to be false
        expect(transfer.reload.status).to eq('pending')
      end

      it 'handles validation errors gracefully' do
        allow(transfer).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        result = transfer.cancel_by!(admin_user)
        expect(result).to be false
      end
    end

    describe '#completable?' do
      it 'returns true for approved' do
        transfer.update!(status: :approved)
        expect(transfer.completable?).to be true
      end

      it 'returns true for in_transit' do
        transfer.update!(status: :approved)
        transfer.update!(status: :in_transit)
        expect(transfer.completable?).to be true
      end

      it 'returns false for pending' do
        expect(transfer.completable?).to be false
      end
    end

    describe '#sufficient_stock_available?' do
      it 'returns true when stock is sufficient' do
        expect(transfer.sufficient_stock_available?).to be true
      end

      it 'returns false when stock is insufficient' do
        source_inventory.update!(quantity: 20, reserved_quantity: 10)
        expect(transfer.sufficient_stock_available?).to be false
      end

      it 'returns false when source inventory does not exist' do
        source_inventory.destroy
        expect(transfer.sufficient_stock_available?).to be false
      end
    end

    describe '#approve!' do
      it 'approves transfer with timestamp' do
        freeze_time do
          result = transfer.approve!(admin_user)

          expect(result).to be true
          expect(transfer.reload.status).to eq('approved')
          expect(transfer.approved_by).to eq(admin_user)
          expect(transfer.approved_at).to eq(Time.current)
        end
      end

      it 'returns false if not approvable' do
        transfer.update!(status: :approved)
        transfer.update!(status: :completed)
        result = transfer.approve!(admin_user)

        expect(result).to be false
        expect(transfer.reload.status).to eq('completed')
      end

      it 'handles validation errors' do
        allow(transfer).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        result = transfer.approve!(admin_user)

        expect(result).to be false
      end
    end

    describe '#reject!' do
      let(:rejection_reason) { '在庫不足のため' }

      it 'rejects transfer and releases stock' do
        result = transfer.reject!(admin_user, rejection_reason)

        expect(result).to be true
        expect(transfer.reload.status).to eq('rejected')
        expect(transfer.approved_by).to eq(admin_user)
        expect(transfer.approved_at).to be_present
        expect(transfer.reason).to include(rejection_reason)
        expect(source_inventory.reload.reserved_quantity).to eq(0)
      end

      it 'appends rejection reason to existing reason' do
        original_reason = transfer.reason
        transfer.reject!(admin_user, rejection_reason)

        expect(transfer.reload.reason).to include(original_reason)
        expect(transfer.reason).to include('【却下理由】')
        expect(transfer.reason).to include(rejection_reason)
      end

      it 'returns false if not rejectable' do
        transfer.update!(status: :approved)
        result = transfer.reject!(admin_user, rejection_reason)

        expect(result).to be false
      end
    end

    describe '#execute_transfer!' do
      before { transfer.update!(status: :approved) }

      context 'when destination inventory exists' do
        let!(:destination_inventory) do
          create(:store_inventory,
            store: destination_store,
            inventory: inventory,
            quantity: 50,
            reserved_quantity: 0
          )
        end

        it 'transfers inventory between stores' do
          result = transfer.execute_transfer!

          expect(result).to be true
          expect(transfer.reload.status).to eq('completed')
          expect(transfer.completed_at).to be_present

          # Source inventory updated
          source_inventory.reload
          expect(source_inventory.quantity).to eq(70) # 100 - 30
          expect(source_inventory.reserved_quantity).to eq(0) # Released

          # Destination inventory updated
          destination_inventory.reload
          expect(destination_inventory.quantity).to eq(80) # 50 + 30
        end
      end

      context 'when destination inventory does not exist' do
        it 'creates destination inventory and transfers' do
          expect {
            result = transfer.execute_transfer!
            expect(result).to be true
          }.to change(StoreInventory, :count).by(1)

          destination_inventory = StoreInventory.find_by(
            store: destination_store,
            inventory: inventory
          )

          expect(destination_inventory).to be_present
          expect(destination_inventory.quantity).to eq(30)
          expect(destination_inventory.reserved_quantity).to eq(0)
          expect(destination_inventory.safety_stock_level).to eq(5)
        end
      end

      it 'returns false if not completable' do
        transfer.update!(status: :pending)
        result = transfer.execute_transfer!

        expect(result).to be false
        expect(source_inventory.reload.quantity).to eq(100)
      end

      it 'handles transaction errors' do
        allow_any_instance_of(StoreInventory).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

        expect(Rails.logger).to receive(:error).with(/移動実行エラー/)

        result = transfer.execute_transfer!
        expect(result).to be false
        expect(transfer.reload.status).to eq('approved')
      end
    end
  end

  describe 'class methods' do
    let(:hq_admin) { create(:admin, :headquarters_admin) }
    let(:area_admin) { create(:admin) }
    let(:store3) { create(:store) }

    before do
      area_admin.stores << [ source_store, destination_store ]
    end

    let!(:transfers) do
      [
        create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_by: admin_user
        ),
        create(:inter_store_transfer,
          source_store: destination_store,
          destination_store: store3,
          requested_by: admin_user
        ),
        create(:inter_store_transfer,
          source_store: store3,
          destination_store: source_store,
          requested_by: admin_user
        )
      ]
    end

    describe '.accessible_to_admin' do
      it 'returns all transfers for headquarters admin' do
        result = InterStoreTransfer.accessible_to_admin(hq_admin)
        expect(result).to include(*transfers)
      end

      it 'returns only accessible store transfers for area admin' do
        result = InterStoreTransfer.accessible_to_admin(area_admin)
        expect(result).to include(transfers[0], transfers[1], transfers[2])
      end
    end

    describe '.accessible_by_store' do
      it 'returns transfers involving the store' do
        result = InterStoreTransfer.accessible_by_store(source_store)
        expect(result).to include(transfers[0], transfers[2])
        expect(result).not_to include(transfers[1])
      end
    end

    describe '.store_transfer_stats' do
      before do
        # Create completed transfers
        create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          status: :approved,
          requested_at: 10.days.ago,
        ).update!(status: :completed, completed_at: 8.days.ago)

        create(:inter_store_transfer,
          source_store: destination_store,
          destination_store: source_store,
          status: :approved,
          requested_at: 5.days.ago,
        ).update!(status: :completed, completed_at: 3.days.ago)

        # Old transfer (outside period)
        create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          requested_at: 40.days.ago
        )
      end

      it 'calculates store transfer statistics' do
        stats = InterStoreTransfer.store_transfer_stats(source_store)

        expect(stats[:outgoing_count]).to eq(2) # Including pending
        expect(stats[:incoming_count]).to eq(2)
        expect(stats[:outgoing_completed]).to eq(1)
        expect(stats[:incoming_completed]).to eq(1)
        expect(stats[:pending_approvals]).to eq(1)
        expect(stats[:average_processing_time]).to be > 0
      end

      it 'respects period parameter' do
        stats = InterStoreTransfer.store_transfer_stats(source_store, 3.days.ago..)

        expect(stats[:outgoing_count]).to eq(0)
        expect(stats[:incoming_count]).to eq(1)
      end
    end

    describe '.transfer_analytics' do
      before do
        # Create various transfers
        create_list(:inter_store_transfer, 3,
          source_store: source_store,
          destination_store: destination_store,
          priority: :urgent,
          status: :approved
        )

        create_list(:inter_store_transfer, 2,
          source_store: source_store,
          destination_store: destination_store,
          priority: :emergency,
          status: :approved
        ).each { |t| t.update!(status: :completed) }

        create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          status: :rejected
        )
      end

      it 'provides comprehensive analytics' do
        analytics = InterStoreTransfer.transfer_analytics

        expect(analytics[:total_requests]).to be >= 6
        expect(analytics[:approval_rate]).to be > 0
        expect(analytics[:average_quantity]).to be > 0
        expect(analytics[:by_priority]).to be_a(Hash)
        expect(analytics[:by_status]).to be_a(Hash)
        expect(analytics[:top_requested_items]).to be_a(Hash)
      end

      it 'calculates approval rate correctly' do
        # Reset to known state
        InterStoreTransfer.destroy_all

        create_list(:inter_store_transfer, 3, status: :approved)
        create_list(:inter_store_transfer, 2, status: :approved).each { |t| t.update!(status: :completed) }
        create_list(:inter_store_transfer, 5, status: :rejected)

        analytics = InterStoreTransfer.transfer_analytics
        expect(analytics[:approval_rate]).to eq(50.0) # 5 out of 10
      end
    end
  end

  # ポリモーフィック関連のテスト
  describe 'polymorphic associations' do
    it 'accepts Admin as requested_by' do
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        requested_by: admin_user
      )

      expect(transfer.requested_by).to eq(admin_user)
      expect(transfer.requested_by_type).to eq('Admin')
    end

    it 'accepts StoreUser as requested_by' do
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        requested_by: store_user
      )

      expect(transfer.requested_by).to eq(store_user)
      expect(transfer.requested_by_type).to eq('StoreUser')
    end

    it 'handles different user types for different actions' do
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        requested_by: store_user
      )

      transfer.approve!(admin_user)

      expect(transfer.requested_by).to eq(store_user)
      expect(transfer.approved_by).to eq(admin_user)
      expect(transfer.approved_by_type).to eq('Admin')
    end
  end

  # パフォーマンステスト
  describe 'performance' do
    it 'handles bulk transfers efficiently' do
      transfers = []

      start_time = Time.current
      100.times do
        transfers << build(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store
        )
      end
      InterStoreTransfer.import(transfers) if defined?(InterStoreTransfer.import)
      elapsed_time = (Time.current - start_time) * 1000

      expect(elapsed_time).to be < 5000 # Under 5 seconds
    end

    it 'avoids N+1 queries when loading associations' do
      create_list(:inter_store_transfer, 5,
        source_store: source_store,
        destination_store: destination_store
      )

      expect {
        InterStoreTransfer.includes(
          :source_store, :destination_store, :inventory, :requested_by
        ).each do |transfer|
          transfer.source_store.name
          transfer.destination_store.name
          transfer.inventory.name
          transfer.requested_by.name if transfer.requested_by
        end
      }.not_to exceed_query_limit(6)
    end
  end

  # セキュリティテスト
  describe 'security' do
    it 'sanitizes reason input' do
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        reason: '<script>alert("XSS")</script>在庫調整'
      )

      # アプリケーション層でのサニタイズを想定
      expect(transfer.reason).to include('在庫調整')
    end

    it 'prevents unauthorized status changes' do
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store
      )

      # Direct status manipulation should be validated
      transfer.status = :completed
      expect(transfer).not_to be_valid
    end
  end

  # 統合シナリオテスト
  describe 'integration scenarios' do
    it 'handles complete transfer lifecycle' do
      # 1. Create transfer request
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        inventory: inventory,
        quantity: 40,
        requested_by: store_user,
        priority: :urgent,
        reason: '新宿店の在庫不足対応'
      )

      expect(source_inventory.reload.reserved_quantity).to eq(40)

      # 2. Admin approves
      expect(transfer.approve!(admin_user)).to be true
      expect(transfer.reload.status).to eq('approved')

      # 3. Mark as in transit
      transfer.update!(status: :in_transit)

      # 4. Execute transfer
      expect(transfer.execute_transfer!).to be true

      # 5. Verify final state
      transfer.reload
      expect(transfer.status).to eq('completed')
      expect(transfer.completed_at).to be_present

      source_inventory.reload
      expect(source_inventory.quantity).to eq(60)
      expect(source_inventory.reserved_quantity).to eq(0)

      dest_inventory = StoreInventory.find_by(
        store: destination_store,
        inventory: inventory
      )
      expect(dest_inventory.quantity).to eq(40)
    end

    it 'handles rejection flow correctly' do
      # 1. Create transfer
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        inventory: inventory,
        quantity: 80,
        requested_by: store_user
      )

      # 2. Admin rejects
      expect(transfer.reject!(admin_user, '数量が多すぎるため')).to be true

      # 3. Verify state
      transfer.reload
      expect(transfer.status).to eq('rejected')
      expect(transfer.reason).to include('数量が多すぎるため')
      expect(source_inventory.reload.reserved_quantity).to eq(0)
    end

    it 'handles cancellation by requestor' do
      # 1. Store user creates request
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        inventory: inventory,
        quantity: 25,
        requested_by: store_user
      )

      # 2. Store user cancels
      expect(transfer.cancel_by!(store_user)).to be true

      # 3. Verify state
      expect(transfer.reload.status).to eq('cancelled')
      expect(source_inventory.reload.reserved_quantity).to eq(0)
    end
  end

  # エッジケース
  describe 'edge cases' do
    it 'handles concurrent transfers safely' do
      # Create multiple transfers for same inventory
      transfers = 3.times.map do
        create(:inter_store_transfer,
          source_store: source_store,
          destination_store: destination_store,
          inventory: inventory,
          quantity: 30,
          requested_by: admin_user
        )
      end

      # Total reserved should not exceed available
      expect(source_inventory.reload.reserved_quantity).to eq(90)
      expect(source_inventory.quantity).to eq(100)
    end

    it 'handles store deletion gracefully' do
      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        requested_by: admin_user
      )

      # Stores should not be deletable with active transfers
      expect { source_store.destroy }.not_to change(Store, :count)
      expect { destination_store.destroy }.not_to change(Store, :count)
    end

    it 'handles very large transfer quantities' do
      source_inventory.update!(quantity: 999_999_999)

      transfer = create(:inter_store_transfer,
        source_store: source_store,
        destination_store: destination_store,
        inventory: inventory,
        quantity: 500_000_000,
        requested_by: admin_user
      )

      expect(transfer).to be_valid
      transfer.update!(status: :approved)
      expect(transfer.execute_transfer!).to be true
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
