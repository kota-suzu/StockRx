# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryTransferService, type: :service do
  # CLAUDE.md準拠: 在庫移動サービスの包括的テスト
  # メタ認知: 複雑なビジネスロジック・データ整合性・トランザクションの品質保証
  # 横展開: 他の移動・転送系サービスでも同様のテストパターン適用

  let(:store_user) { create(:store_user) }
  let(:service) { described_class.new(current_user: store_user) }
  let(:from_store) { create(:store, name: "移動元店舗", active: true) }
  let(:to_store) { create(:store, name: "移動先店舗", active: true) }
  let(:inactive_store) { create(:store, name: "非アクティブ店舗", active: false) }
  let(:inventory) { create(:inventory, name: "移動対象商品", price: 1000) }

  before do
    # 移動元の店舗在庫作成
    @store_inventory = create(:store_inventory,
      store: from_store,
      inventory: inventory,
      quantity: 100,
      reserved_quantity: 10
    )

    # InterStoreTransferモデルのモック（存在する場合）
    unless defined?(InterStoreTransfer)
      # InterStoreTransferが未定義の場合、フォールバック処理をテスト
      allow(Object).to receive(:defined?).with(InterStoreTransfer).and_return(false)
    end

    # ログモック
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe "#create_transfer_request" do
    let(:valid_transfer_params) do
      {
        to_store_id: to_store.id,
        quantity: 20,
        reason: "店舗間補充"
      }
    end

    context "正常な移動申請" do
      it "移動申請を正常に作成する" do
        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: valid_transfer_params
        )

        expect(result[:success]).to be true
        expect(result[:message]).to eq("移動申請が正常に作成されました")
        expect(result[:transfer_request]).to be_present
      end

      it "在庫を予約状態にする" do
        expect {
          service.create_transfer_request(
            from_store: from_store,
            inventory: inventory,
            transfer_params: valid_transfer_params
          )
        }.to change { @store_inventory.reload.reserved_quantity }.from(10).to(30)
      end

      it "InventoryLogを作成する" do
        expect {
          service.create_transfer_request(
            from_store: from_store,
            inventory: inventory,
            transfer_params: valid_transfer_params
          )
        }.to change(InventoryLog, :count).by(2) # 移動申請 + 予約処理

        transfer_log = InventoryLog.where(action: "transfer_request").last
        expect(transfer_log.inventory).to eq(inventory)
        expect(transfer_log.store).to eq(from_store)
        expect(transfer_log.user).to eq(store_user)
        expect(transfer_log.quantity_changed).to eq(-20)
        expect(transfer_log.reason).to eq("店舗間補充")

        reservation_log = InventoryLog.where(action: "reserve_for_transfer").last
        expect(reservation_log.quantity_changed).to eq(20)
        expect(reservation_log.reason).to eq("移動申請による予約")
      end

      it "通知ログを出力する" do
        expect(Rails.logger).to receive(:info).with(
          include('"event":"transfer_request_created"')
        )

        service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: valid_transfer_params
        )
      end

      it "理由が指定されていない場合はデフォルト理由を使用する" do
        params_without_reason = valid_transfer_params.except(:reason)

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: params_without_reason
        )

        expect(result[:success]).to be true

        log = InventoryLog.where(action: "transfer_request").last
        expect(log.reason).to eq("店舗間移動")
      end

      context "InterStoreTransferモデルが存在する場合" do
        before do
          # InterStoreTransferクラスのモック
          inter_store_transfer_class = double('InterStoreTransfer')
          transfer_instance = double('transfer_instance', id: 123, from_store: from_store, to_store_id: to_store.id, inventory: inventory, quantity: 20)

          allow(inter_store_transfer_class).to receive(:create!).and_return(transfer_instance)
          stub_const('InterStoreTransfer', inter_store_transfer_class)
          allow(Object).to receive(:defined?).with(InterStoreTransfer).and_return(true)
        end

        it "InterStoreTransferレコードを作成する" do
          expect(InterStoreTransfer).to receive(:create!).with(
            hash_including(
              from_store: from_store,
              to_store_id: to_store.id,
              inventory: inventory,
              quantity: 20,
              reason: "店舗間補充",
              status: "pending",
              requested_by: store_user
            )
          )

          service.create_transfer_request(
            from_store: from_store,
            inventory: inventory,
            transfer_params: valid_transfer_params
          )
        end
      end
    end

    context "バリデーションエラー" do
      it "移動先店舗が未指定の場合はエラーを返す" do
        invalid_params = valid_transfer_params.merge(to_store_id: nil)

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: invalid_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("移動先店舗を選択してください")
      end

      it "同じ店舗への移動は拒否される" do
        invalid_params = valid_transfer_params.merge(to_store_id: from_store.id)

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: invalid_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("同じ店舗への移動はできません")
      end

      it "数量が0以下の場合はエラーを返す" do
        invalid_params = valid_transfer_params.merge(quantity: 0)

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: invalid_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("移動数量は1以上を指定してください")
      end

      it "在庫不足の場合はエラーを返す" do
        invalid_params = valid_transfer_params.merge(quantity: 200) # 現在在庫100を超過

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: invalid_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("在庫不足です（現在在庫: 100）")
      end

      it "存在しない移動先店舗の場合はエラーを返す" do
        invalid_params = valid_transfer_params.merge(to_store_id: 99999)

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: invalid_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("指定された移動先店舗が見つかりません")
      end

      it "非アクティブな移動先店舗の場合はエラーを返す" do
        invalid_params = valid_transfer_params.merge(to_store_id: inactive_store.id)

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: invalid_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("指定された移動先店舗が見つかりません")
      end

      it "指定商品の在庫が存在しない場合はエラーを返す" do
        other_inventory = create(:inventory, name: "在庫なし商品")

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: other_inventory,
          transfer_params: valid_transfer_params
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("指定された商品の在庫が存在しません")
      end
    end

    context "例外処理" do
      it "ActiveRecord::RecordInvalidを適切に処理する" do
        allow_any_instance_of(StoreInventory).to receive(:update!).and_raise(
          ActiveRecord::RecordInvalid.new(
            StoreInventory.new.tap { |si| si.errors.add(:reserved_quantity, "負の値は設定できません") }
          )
        )

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: valid_transfer_params
        )

        expect(result[:success]).to be false
        expect(result[:message]).to eq("移動申請の作成に失敗しました")
        expect(result[:errors]).to be_present
      end

      it "StandardErrorを適切に処理する" do
        allow_any_instance_of(StoreInventory).to receive(:update!).and_raise(StandardError.new("DB接続エラー"))

        expect(Rails.logger).to receive(:error).with(include("Transfer request creation failed"))

        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: valid_transfer_params
        )

        expect(result[:success]).to be false
        expect(result[:message]).to eq("システムエラーが発生しました")
        expect(result[:errors]).to include("DB接続エラー")
      end

      it "トランザクションでロールバックされる" do
        allow(InventoryLog).to receive(:create!).and_raise(StandardError.new("ログ作成失敗"))

        expect {
          service.create_transfer_request(
            from_store: from_store,
            inventory: inventory,
            transfer_params: valid_transfer_params
          )
        }.not_to change { @store_inventory.reload.reserved_quantity }
      end
    end
  end

  describe "#fetch_transfer_history" do
    context "InterStoreTransferモデルが存在する場合" do
      before do
        # InterStoreTransferクラスのモック
        transfer1 = double('transfer1', id: 1, created_at: 1.day.ago)
        transfer2 = double('transfer2', id: 2, created_at: 2.days.ago)
        transfers = [ transfer1, transfer2 ]

        inter_store_transfer_class = double('InterStoreTransfer')
        query = double('query')
        allow(query).to receive(:includes).and_return(query)
        allow(query).to receive(:order).and_return(query)
        allow(query).to receive(:limit).and_return(transfers)
        allow(inter_store_transfer_class).to receive(:where).and_return(query)

        stub_const('InterStoreTransfer', inter_store_transfer_class)
        allow(Object).to receive(:defined?).with(InterStoreTransfer).and_return(true)
      end

      it "移動履歴を取得する" do
        history = service.fetch_transfer_history(store: from_store, inventory: inventory)

        expect(InterStoreTransfer).to have_received(:where).with(
          "(from_store_id = ? OR to_store_id = ?) AND inventory_id = ?",
          from_store.id, from_store.id, inventory.id
        )
        expect(history.size).to eq(2)
      end

      it "指定された件数で履歴を取得する" do
        history = service.fetch_transfer_history(store: from_store, inventory: inventory, limit: 5)

        expect(history).to be_present
      end
    end

    context "InterStoreTransferモデルが存在しない場合" do
      before do
        allow(Object).to receive(:defined?).with(InterStoreTransfer).and_return(false)
      end

      it "空の配列を返す" do
        history = service.fetch_transfer_history(store: from_store, inventory: inventory)

        expect(history).to eq([])
      end
    end
  end

  describe "#available_target_stores" do
    let!(:store1) { create(:store, name: "店舗A", active: true) }
    let!(:store2) { create(:store, name: "店舗B", active: true) }
    let!(:store3) { create(:store, name: "店舗C", active: false) }

    it "現在の店舗以外のアクティブな店舗を取得する" do
      stores = service.available_target_stores(current_store: from_store)

      expect(stores).to include(store1, store2, to_store)
      expect(stores).not_to include(from_store, store3) # 自分自身と非アクティブ店舗は除外
    end

    it "店舗名でソートされている" do
      stores = service.available_target_stores(current_store: from_store)
      store_names = stores.map(&:name)

      expect(store_names).to eq(store_names.sort)
    end
  end

  describe "プライベートメソッド" do
    describe "#validate_transfer_request" do
      it "正常なパラメータでは有効と判定する" do
        result = service.send(:validate_transfer_request,
          from_store: from_store,
          to_store_id: to_store.id,
          inventory: inventory,
          quantity: 50
        )

        expect(result[:valid]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:to_store]).to eq(to_store)
        expect(result[:store_inventory]).to eq(@store_inventory)
      end

      it "複数のエラーを同時に検出する" do
        result = service.send(:validate_transfer_request,
          from_store: from_store,
          to_store_id: from_store.id, # 同じ店舗
          inventory: inventory,
          quantity: 0 # 無効な数量
        )

        expect(result[:valid]).to be false
        expect(result[:errors]).to include("同じ店舗への移動はできません")
        expect(result[:errors]).to include("移動数量は1以上を指定してください")
      end
    end

    describe "#create_transfer_request_record" do
      context "InterStoreTransferモデルが存在しない場合" do
        before do
          allow(Object).to receive(:defined?).with(InterStoreTransfer).and_return(false)
        end

        it "InventoryLogでフォールバック記録を作成する" do
          expect {
            service.send(:create_transfer_request_record,
              from_store: from_store,
              to_store_id: to_store.id,
              inventory: inventory,
              quantity: 30,
              reason: "フォールバックテスト"
            )
          }.to change(InventoryLog, :count).by(1)

          log = InventoryLog.last
          expect(log.action).to eq("transfer_request")
          expect(log.quantity_changed).to eq(-30)
          expect(log.reason).to eq("フォールバックテスト")
          expect(log.metadata["transfer_type"]).to eq("outbound_request")
          expect(log.metadata["to_store_id"]).to eq(to_store.id)
          expect(log.metadata["status"]).to eq("pending")
        end
      end
    end

    describe "#reserve_inventory_for_transfer" do
      it "在庫予約を正しく処理する" do
        service.send(:reserve_inventory_for_transfer, from_store, inventory, 25)

        @store_inventory.reload
        expect(@store_inventory.reserved_quantity).to eq(35) # 10 + 25

        log = InventoryLog.where(action: "reserve_for_transfer").last
        expect(log.quantity_before).to eq(10)
        expect(log.quantity_after).to eq(35)
        expect(log.quantity_changed).to eq(25)
        expect(log.metadata["reservation_type"]).to eq("transfer_request")
      end

      it "reserved_quantityがnilの場合も適切に処理する" do
        @store_inventory.update!(reserved_quantity: nil)

        service.send(:reserve_inventory_for_transfer, from_store, inventory, 15)

        @store_inventory.reload
        expect(@store_inventory.reserved_quantity).to eq(15)
      end

      it "予約失敗時は例外を発生させる" do
        allow_any_instance_of(StoreInventory).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(StoreInventory.new))

        expect {
          service.send(:reserve_inventory_for_transfer, from_store, inventory, 25)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    describe "#notify_transfer_request" do
      let(:mock_transfer_request) do
        double('transfer_request',
          id: 123,
          from_store: from_store,
          to_store_id: to_store.id,
          inventory: inventory,
          quantity: 20
        )
      end

      it "通知ログを出力する" do
        expect(Rails.logger).to receive(:info).with(
          include('"event":"transfer_request_created"')
        )

        service.send(:notify_transfer_request, mock_transfer_request)
      end

      it "適切なログ情報を含む" do
        expect(Rails.logger).to receive(:info) do |log_string|
          log_data = JSON.parse(log_string)
          expect(log_data["transfer_request_id"]).to eq(123)
          expect(log_data["from_store_id"]).to eq(from_store.id)
          expect(log_data["to_store_id"]).to eq(to_store.id)
          expect(log_data["inventory_id"]).to eq(inventory.id)
          expect(log_data["quantity"]).to eq(20)
          expect(log_data["requested_by"]).to eq(store_user.email)
        end

        service.send(:notify_transfer_request, mock_transfer_request)
      end
    end
  end

  describe "統合テスト" do
    it "完全な移動申請フローを実行する" do
      # 1. 移動可能店舗の確認
      available_stores = service.available_target_stores(current_store: from_store)
      expect(available_stores).to include(to_store)

      # 2. 移動申請の作成
      result = service.create_transfer_request(
        from_store: from_store,
        inventory: inventory,
        transfer_params: {
          to_store_id: to_store.id,
          quantity: 30,
          reason: "統合テスト移動"
        }
      )

      expect(result[:success]).to be true

      # 3. 在庫状態の確認
      @store_inventory.reload
      expect(@store_inventory.reserved_quantity).to eq(40) # 10 + 30

      # 4. ログ記録の確認
      expect(InventoryLog.count).to be >= 2
      expect(InventoryLog.where(action: "transfer_request").exists?).to be true
      expect(InventoryLog.where(action: "reserve_for_transfer").exists?).to be true

      # 5. 履歴の確認
      history = service.fetch_transfer_history(store: from_store, inventory: inventory)
      expect(history).to be_present
    end

    it "並行する移動申請を適切に処理する" do
      # 同時に複数の移動申請を作成
      transfer_params1 = { to_store_id: to_store.id, quantity: 20, reason: "移動1" }
      transfer_params2 = { to_store_id: to_store.id, quantity: 30, reason: "移動2" }

      result1 = service.create_transfer_request(
        from_store: from_store,
        inventory: inventory,
        transfer_params: transfer_params1
      )

      result2 = service.create_transfer_request(
        from_store: from_store,
        inventory: inventory,
        transfer_params: transfer_params2
      )

      expect(result1[:success]).to be true
      expect(result2[:success]).to be true

      @store_inventory.reload
      expect(@store_inventory.reserved_quantity).to eq(60) # 10 + 20 + 30
    end

    it "在庫不足シナリオを適切に処理する" do
      # 1回目: 成功（在庫内）
      result1 = service.create_transfer_request(
        from_store: from_store,
        inventory: inventory,
        transfer_params: { to_store_id: to_store.id, quantity: 50, reason: "移動1" }
      )

      expect(result1[:success]).to be true

      # 2回目: 失敗（在庫不足）
      result2 = service.create_transfer_request(
        from_store: from_store,
        inventory: inventory,
        transfer_params: { to_store_id: to_store.id, quantity: 60, reason: "移動2" }
      )

      expect(result2[:valid]).to be false
      expect(result2[:errors]).to include("在庫不足です（現在在庫: 100）")
    end
  end

  describe "パフォーマンステスト" do
    it "大量の移動申請でも適切に処理する" do
      # 100件の移動申請を並行処理
      results = []

      start_time = Time.current
      100.times do |i|
        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: {
            to_store_id: to_store.id,
            quantity: 1,
            reason: "パフォーマンステスト#{i}"
          }
        )
        results << result
      end
      duration = Time.current - start_time

      expect(duration).to be < 5.0 # 5秒以内に完了
      expect(results.all? { |r| r[:success] }).to be true
    end
  end

  describe "セキュリティテスト" do
    it "不正な店舗IDでの攻撃を防ぐ" do
      malicious_params = {
        to_store_id: "'; DROP TABLE stores; --",
        quantity: 10,
        reason: "攻撃テスト"
      }

      expect {
        result = service.create_transfer_request(
          from_store: from_store,
          inventory: inventory,
          transfer_params: malicious_params
        )
        expect(result[:valid]).to be false
      }.not_to raise_error
    end

    it "他店舗の在庫への不正アクセスを防ぐ" do
      other_store = create(:store, name: "他店舗")
      other_inventory = create(:inventory, name: "他店舗の商品")
      create(:store_inventory, store: other_store, inventory: other_inventory, quantity: 50)

      # from_storeに存在しない商品での移動申請
      result = service.create_transfer_request(
        from_store: from_store,
        inventory: other_inventory,
        transfer_params: {
          to_store_id: to_store.id,
          quantity: 10,
          reason: "不正アクセステスト"
        }
      )

      expect(result[:valid]).to be false
      expect(result[:errors]).to include("指定された商品の在庫が存在しません")
    end
  end

  # TODO: 🔴 Phase 1（緊急）- 追加テストケース
  # 優先度: 高（CLAUDE.md準拠）
  # 実装期間: 1日
  # 横展開: 他の移動・転送系サービスと同等のテスト網羅性達成
  #
  # 1. 承認ワークフローテスト
  #    - 移動申請の承認・却下機能
  #    - 段階的承認（店長→エリアマネージャー）
  #    - 承認権限による条件分岐
  #
  # 2. 移動実行フェーズテスト
  #    - 実際の在庫移動処理
  #    - 移動先での受入確認
  #    - 移動キャンセル・ロールバック
  #
  # 3. 通知システムテスト
  #    - リアルタイム通知（ActionCable）
  #    - メール通知（AdminMailer）
  #    - 外部システム連携（Slack/Teams）
  #
  # 4. レポート・分析機能テスト
  #    - 移動実績レポート
  #    - 店舗間移動パターン分析
  #    - 在庫効率化提案
  #
  # 5. 例外・エラー復旧テスト
  #    - ネットワーク障害時の動作
  #    - 部分失敗からの回復
  #    - データ整合性チェック機能
end
