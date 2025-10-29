# frozen_string_literal: true

RSpec.shared_examples 'admin authorization required' do
  context 'when not authenticated' do
    before do
      sign_out :admin if defined?(current_admin)
    end

    it 'redirects to login page' do
      subject
      expect(response).to redirect_to(new_admin_session_path)
    end

    it 'sets flash alert' do
      subject
      expect(flash[:alert]).to eq('続行するにはログインしてください。')
    end
  end

  context 'when authenticated as admin' do
    let(:admin) { create(:admin, :headquarters_admin) }

    before do
      sign_in admin
    end

    it 'allows access' do
      subject
      expect(response).to have_http_status(:success)
    end
  end
end

RSpec.shared_examples 'headquarters admin only' do
  context 'when authenticated as store manager' do
    let(:store) { create(:store) }
    let(:admin) { create(:admin, :store_manager, store: store) }

    before do
      sign_in admin
    end

    it 'returns forbidden status' do
      subject
      expect(response).to have_http_status(:forbidden)
    end
  end

  context 'when authenticated as headquarters admin' do
    let(:admin) { create(:admin, :headquarters_admin) }

    before do
      sign_in admin
    end

    it 'allows access' do
      subject
      expect(response).to have_http_status(:success)
    end
  end
end

RSpec.shared_examples 'store manager authorization' do
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }

  context 'when accessing own store' do
    let(:admin) { create(:admin, :store_manager, store: store) }

    before do
      sign_in admin
    end

    it 'allows access' do
      subject
      expect(response).to have_http_status(:success)
    end
  end

  context 'when accessing other store' do
    let(:admin) { create(:admin, :store_manager, store: other_store) }

    before do
      sign_in admin
    end

    it 'returns forbidden status' do
      subject
      expect(response).to have_http_status(:forbidden)
    end
  end
end

# ==============================================================================
# Transfer Authorization Tests - ブランチカバレッジ向上のための包括テスト
# ==============================================================================

RSpec.shared_examples 'transfer modification authorization' do
  let(:source_store) { create(:store) }
  let(:target_store) { create(:store) }
  let(:requester) { create(:admin, :store_manager, store: source_store) }
  let(:other_admin) { create(:admin, :store_manager, store: target_store) }
  let(:headquarters_admin) { create(:admin, :headquarters_admin) }

  context 'when transfer is pending' do
    let(:transfer) { create(:inter_store_transfer, :pending, requested_by: requester, source_store: source_store) }

    context 'as headquarters admin' do
      before { sign_in headquarters_admin }

      it 'allows modification' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be true
      end
    end

    context 'as transfer requester' do
      before { sign_in requester }

      it 'allows modification' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be true
      end
    end

    context 'as source store manager' do
      let(:source_manager) { create(:admin, :store_manager, store: source_store) }
      before { sign_in source_manager }

      it 'allows modification' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be true
      end
    end

    context 'as unrelated admin' do
      before { sign_in other_admin }

      it 'denies modification' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be false
      end
    end
  end

  context 'when transfer is approved' do
    let(:transfer) { create(:inter_store_transfer, :approved, requested_by: requester, source_store: source_store) }

    context 'as headquarters admin' do
      before { sign_in headquarters_admin }

      it 'allows modification' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be true
      end
    end

    context 'as requester' do
      before { sign_in requester }

      it 'allows modification' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be true
      end
    end
  end

  context 'when transfer is completed' do
    let(:transfer) { create(:inter_store_transfer, :completed, requested_by: requester, source_store: source_store) }

    context 'as headquarters admin' do
      before { sign_in headquarters_admin }

      it 'denies modification for completed transfers' do
        expect(controller.send(:can_modify_transfer?, transfer)).to be false
      end
    end
  end
end

RSpec.shared_examples 'transfer cancellation authorization' do
  let(:source_store) { create(:store) }
  let(:requester) { create(:admin, :store_manager, store: source_store) }
  let(:other_admin) { create(:admin, :store_manager) }
  let(:headquarters_admin) { create(:admin, :headquarters_admin) }

  context 'when transfer can be cancelled' do
    let(:transfer) { create(:inter_store_transfer, :pending, requested_by: requester) }

    before do
      allow(transfer).to receive(:can_be_cancelled?).and_return(true)
    end

    context 'as headquarters admin' do
      before { sign_in headquarters_admin }

      it 'allows cancellation' do
        expect(controller.send(:can_cancel_transfer?, transfer)).to be true
      end
    end

    context 'as transfer requester' do
      before { sign_in requester }

      it 'allows cancellation' do
        expect(controller.send(:can_cancel_transfer?, transfer)).to be true
      end
    end

    context 'as unrelated admin' do
      before { sign_in other_admin }

      it 'denies cancellation' do
        expect(controller.send(:can_cancel_transfer?, transfer)).to be false
      end
    end
  end

  context 'when transfer cannot be cancelled' do
    let(:transfer) { create(:inter_store_transfer, :completed, requested_by: requester) }

    before do
      allow(transfer).to receive(:can_be_cancelled?).and_return(false)
    end

    context 'as headquarters admin' do
      before { sign_in headquarters_admin }

      it 'denies cancellation' do
        expect(controller.send(:can_cancel_transfer?, transfer)).to be false
      end
    end

    context 'as requester' do
      before { sign_in requester }

      it 'denies cancellation' do
        expect(controller.send(:can_cancel_transfer?, transfer)).to be false
      end
    end
  end
end

# ==============================================================================
# Inventory Log Access Authorization Tests
# ==============================================================================

RSpec.shared_examples 'inventory log access authorization' do
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }
  let(:inventory) { create(:inventory) }
  let(:store_inventory) { create(:store_inventory, store: store, inventory: inventory) }
  let(:headquarters_admin) { create(:admin, :headquarters_admin) }
  let(:store_admin) { create(:admin, :store_manager, store: store) }
  let(:other_store_admin) { create(:admin, :store_manager, store: other_store) }

  context 'as headquarters admin' do
    before { sign_in headquarters_admin }

    it 'allows access to any inventory logs' do
      expect(controller.send(:can_access_inventory_logs?, inventory)).to be true
    end

    it 'allows access to general inventory logs' do
      expect(controller.send(:can_access_inventory_logs?)).to be true
    end
  end

  context 'as store admin with store access' do
    before do
      sign_in store_admin
      store_inventory # Create association
    end

    it 'allows access to own store inventory logs' do
      expect(controller.send(:can_access_inventory_logs?, inventory)).to be true
    end

    it 'allows access to general logs for own store' do
      expect(controller.send(:can_access_inventory_logs?)).to be true
    end
  end

  context 'as store admin without store access' do
    before { sign_in other_store_admin }

    it 'denies access to other store inventory logs' do
      expect(controller.send(:can_access_inventory_logs?, inventory)).to be false
    end
  end

  context 'as admin without store assignment' do
    let(:unassigned_admin) { create(:admin, store: nil) }
    before { sign_in unassigned_admin }

    it 'denies access to inventory logs' do
      expect(controller.send(:can_access_inventory_logs?, inventory)).to be false
    end
  end
end

# ==============================================================================
# Authorization Enforcement Tests - redirect behavior
# ==============================================================================

RSpec.shared_examples 'authorization enforcement with redirects' do
  let(:store) { create(:store) }
  let(:other_store) { create(:store) }
  let(:admin) { create(:admin, :store_manager, store: store) }
  let(:headquarters_admin) { create(:admin, :headquarters_admin) }

  describe '#authorize_headquarters_admin!' do
    context 'when not headquarters admin' do
      before { sign_in admin }

      it 'redirects to admin root with alert' do
        controller.send(:authorize_headquarters_admin!)
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to eq('この操作は本部管理者のみ実行可能です。')
      end
    end

    context 'when headquarters admin' do
      before { sign_in headquarters_admin }

      it 'does not redirect' do
        expect(controller.send(:authorize_headquarters_admin!)).to be_nil
        expect(response).not_to be_redirect
      end
    end
  end

  describe '#authorize_store_management!' do
    before { sign_in admin }

    context 'when can manage store' do
      it 'does not redirect for own store' do
        expect(controller.send(:authorize_store_management!, store)).to be_nil
        expect(response).not_to be_redirect
      end
    end

    context 'when cannot manage store' do
      it 'redirects with alert for other store' do
        controller.send(:authorize_store_management!, other_store)
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to eq('この店舗を管理する権限がありません。')
      end
    end
  end

  describe '#authorize_store_view!' do
    before { sign_in admin }

    context 'when can view store' do
      it 'does not redirect for own store' do
        expect(controller.send(:authorize_store_view!, store)).to be_nil
        expect(response).not_to be_redirect
      end
    end

    context 'when cannot view store' do
      it 'redirects with alert for restricted store' do
        controller.send(:authorize_store_view!, other_store)
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to eq('この店舗を閲覧する権限がありません。')
      end
    end
  end

  describe '#authorize_audit_log_access!' do
    context 'when not headquarters admin' do
      before { sign_in admin }

      it 'redirects with audit access denied message' do
        controller.send(:authorize_audit_log_access!)
        expect(response).to redirect_to(admin_root_path)
        expect(flash[:alert]).to eq('監査ログへのアクセス権限がありません。本部管理者権限が必要です。')
      end
    end

    context 'when headquarters admin' do
      before { sign_in headquarters_admin }

      it 'does not redirect' do
        expect(controller.send(:authorize_audit_log_access!)).to be_nil
        expect(response).not_to be_redirect
      end
    end
  end
end
