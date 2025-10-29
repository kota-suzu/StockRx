# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InventoryLoggable do
  # CLAUDE.md準拠: 在庫ログ機能の包括的テスト
  # メタ認知: 監査証跡の完全性と在庫管理の中核機能の品質保証
  # 横展開: 他のLoggable系concernでも同様のテストパターン適用

  # テスト用のモデルクラス
  class TestInventoryModel < ApplicationRecord
    self.table_name = 'inventories'
    include InventoryLoggable
  end

  let(:model) { TestInventoryModel.create!(name: "Test Item", quantity: 100, price: 1000) }
  let(:admin) { create(:admin) }

  before do
    # Current.userの設定
    Current.user = admin if defined?(Current)
  end

  after do
    Current.reset if defined?(Current)
  end

  describe "関連付け" do
    it "inventory_logsを持つ" do
      expect(model).to respond_to(:inventory_logs)
    end

    it "親レコード削除時にinventory_logsは保護される" do
      model.log_operation("add", 10)
      expect(model.inventory_logs.count).to eq(1)

      expect { model.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
      expect(model.inventory_logs.count).to eq(1)
    end
  end

  describe "#log_operation" do
    context "有効なパラメータの場合" do
      it "在庫ログを作成する" do
        expect {
          model.log_operation("add", 10, "Test note", admin.id)
        }.to change { model.inventory_logs.count }.by(1)
      end

      it "正しい属性で在庫ログを作成する" do
        model.log_operation("add", 10, "Test note", admin.id)
        log = model.inventory_logs.last

        expect(log.delta).to eq(10)
        expect(log.operation_type).to eq("add")
        expect(log.previous_quantity).to eq(90)
        expect(log.current_quantity).to eq(100)
        expect(log.user_id).to eq(admin.id)
        expect(log.note).to eq("Test note")
      end

      it "user_idが未指定の場合、Current.userを使用する" do
        model.log_operation("add", 10)
        log = model.inventory_logs.last

        expect(log.user_id).to eq(admin.id)
      end

      it "noteが未指定の場合、デフォルトメッセージを使用する" do
        model.log_operation("custom", 10)
        log = model.inventory_logs.last

        expect(log.note).to eq("手動記録: custom")
      end
    end

    context "異常系" do
      it "無効なデータでもエラーを発生させる" do
        expect {
          model.log_operation(nil, nil)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe "#adjust_quantity" do
    context "数量増加の場合" do
      it "数量を更新し、addタイプのログを作成する" do
        expect {
          model.adjust_quantity(150, "調整テスト")
        }.to change { model.quantity }.from(100).to(150)

        log = model.inventory_logs.last
        expect(log.operation_type).to eq("add")
        expect(log.delta).to eq(50)
      end
    end

    context "数量減少の場合" do
      it "数量を更新し、removeタイプのログを作成する" do
        expect {
          model.adjust_quantity(70, "在庫減少")
        }.to change { model.quantity }.from(100).to(70)

        log = model.inventory_logs.last
        expect(log.operation_type).to eq("remove")
        expect(log.delta).to eq(-30)
      end
    end

    context "数量変更がない場合" do
      it "何も処理しない" do
        expect {
          model.adjust_quantity(100)
        }.not_to change { model.inventory_logs.count }
      end
    end

    context "トランザクション" do
      it "エラー時にロールバックされる" do
        allow(model).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)

        expect {
          model.adjust_quantity(150) rescue nil
        }.not_to change { model.quantity }

        expect(model.inventory_logs.count).to eq(0)
      end
    end
  end

  describe "#add_stock" do
    context "有効な数量の場合" do
      it "在庫を増加させる" do
        expect {
          model.add_stock(25, "入荷")
        }.to change { model.quantity }.from(100).to(125)
      end

      it "入庫ログを作成する" do
        model.add_stock(25, "入荷")
        log = model.inventory_logs.last

        expect(log.operation_type).to eq("add")
        expect(log.delta).to eq(25)
        expect(log.note).to eq("入荷")
      end

      it "trueを返す" do
        expect(model.add_stock(25)).to be true
      end
    end

    context "無効な数量の場合" do
      it "0以下の場合はfalseを返す" do
        expect(model.add_stock(0)).to be false
        expect(model.add_stock(-10)).to be false
      end

      it "在庫を変更しない" do
        expect {
          model.add_stock(0)
        }.not_to change { model.quantity }
      end
    end

    context "noteが未指定の場合" do
      it "デフォルトのnoteを使用する" do
        model.add_stock(10)
        expect(model.inventory_logs.last.note).to eq("入庫処理")
      end
    end
  end

  describe "#remove_stock" do
    context "有効な数量の場合" do
      it "在庫を減少させる" do
        expect {
          model.remove_stock(30, "出荷")
        }.to change { model.quantity }.from(100).to(70)
      end

      it "出庫ログを作成する" do
        model.remove_stock(30, "出荷")
        log = model.inventory_logs.last

        expect(log.operation_type).to eq("remove")
        expect(log.delta).to eq(-30)
        expect(log.note).to eq("出荷")
      end

      it "trueを返す" do
        expect(model.remove_stock(30)).to be true
      end
    end

    context "無効な数量の場合" do
      it "0以下の場合はfalseを返す" do
        expect(model.remove_stock(0)).to be false
        expect(model.remove_stock(-10)).to be false
      end

      it "在庫量を超える場合はfalseを返す" do
        expect(model.remove_stock(150)).to be false
      end

      it "在庫を変更しない" do
        expect {
          model.remove_stock(150)
        }.not_to change { model.quantity }
      end
    end

    context "noteが未指定の場合" do
      it "デフォルトのnoteを使用する" do
        model.remove_stock(10)
        expect(model.inventory_logs.last.note).to eq("出庫処理")
      end
    end
  end

  describe "after_saveコールバック" do
    context "quantityが変更された場合" do
      it "自動的にログを作成する" do
        expect {
          model.update!(quantity: 120)
        }.to change { model.inventory_logs.count }.by(1)
      end

      it "正しい内容でログを作成する" do
        model.update!(quantity: 80)
        log = model.inventory_logs.last

        expect(log.delta).to eq(-20)
        expect(log.operation_type).to eq("remove")
        expect(log.previous_quantity).to eq(100)
        expect(log.current_quantity).to eq(80)
        expect(log.note).to eq("自動記録：数量変更")
      end

      it "増加の場合はaddタイプ" do
        model.update!(quantity: 150)
        expect(model.inventory_logs.last.operation_type).to eq("add")
      end

      it "減少の場合はremoveタイプ" do
        model.update!(quantity: 50)
        expect(model.inventory_logs.last.operation_type).to eq("remove")
      end
    end

    context "quantityが変更されない場合" do
      it "ログを作成しない" do
        expect {
          model.update!(name: "Updated Name")
        }.not_to change { model.inventory_logs.count }
      end
    end

    context "エラーハンドリング" do
      it "ログ作成エラーが発生してもレコード保存は成功する" do
        allow_any_instance_of(InventoryLog).to receive(:save!).and_raise(StandardError)

        expect(Rails.logger).to receive(:error).with(/在庫ログ記録エラー/)

        expect {
          model.update!(quantity: 120)
        }.to change { model.quantity }.to(120)
      end
    end
  end

  describe "クラスメソッド" do
    describe ".recent_operations" do
      before do
        model.add_stock(10)
        model.remove_stock(5)
        model.adjust_quantity(110)
      end

      it "最近の操作を返す" do
        operations = TestInventoryModel.recent_operations(2)
        expect(operations.count).to eq(2)
      end

      it "デフォルトで50件まで返す" do
        60.times { |i| model.add_stock(1, "Stock #{i}") }
        operations = TestInventoryModel.recent_operations
        expect(operations.count).to eq(50)
      end
    end

    describe ".with_low_stock" do
      let!(:low_stock_item) { TestInventoryModel.create!(name: "Low Stock", quantity: 5, price: 100) }
      let!(:normal_stock_item) { TestInventoryModel.create!(name: "Normal Stock", quantity: 100, price: 100) }

      it "在庫が少ない商品を返す" do
        low_stock = TestInventoryModel.with_low_stock(10)
        expect(low_stock).to include(low_stock_item)
        expect(low_stock).not_to include(normal_stock_item)
      end
    end

    describe ".operation_summary" do
      before do
        model.add_stock(100)
        model.remove_stock(30)
        model.adjust_quantity(200)
      end

      it "操作タイプごとの集計を返す" do
        summary = TestInventoryModel.operation_summary
        expect(summary).to be_a(Hash)
        expect(summary["add"]).to be_present
        expect(summary["remove"]).to be_present
      end
    end
  end

  describe "パフォーマンス" do
    it "大量のログがあっても高速に動作する" do
      100.times { |i| model.add_stock(1, "Bulk #{i}") }

      start_time = Time.current
      model.inventory_logs.recent.limit(10).to_a
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 0.1 # 100ms以内
    end
  end

  describe "並行処理" do
    it "同時更新でもデータ整合性が保たれる" do
      # 楽観的ロックのテスト
      model1 = TestInventoryModel.find(model.id)
      model2 = TestInventoryModel.find(model.id)

      model1.add_stock(10)

      expect {
        model2.add_stock(20)
      }.to raise_error(ActiveRecord::StaleObjectError)
    end
  end

  # ============================================
  # Branch Coverage Enhancement - 分岐網羅拡張
  # ============================================
  # CLAUDE.md準拠: C1カバレッジ80%達成のための詳細分岐テスト
  # メタ認知: InventoryLoggableの全分岐パターンをカバー
  # 横展開: 他のconcernでも同様の詳細分岐テスト適用

  describe "private method branch coverage" do
    describe "#determine_operation_type" do
      let(:test_instance) { model }

      it "returns 'add' for positive delta" do
        result = test_instance.send(:determine_operation_type, 10)
        expect(result).to eq("add")
      end

      it "returns 'remove' for negative delta" do
        result = test_instance.send(:determine_operation_type, -5)
        expect(result).to eq("remove")
      end

      it "returns 'adjust' for zero delta" do
        result = test_instance.send(:determine_operation_type, 0)
        expect(result).to eq("adjust")
      end
    end

    describe "#log_inventory_changes error handling" do
      it "handles InventoryLog creation failure gracefully" do
        # quantity変更を発生させる
        original_quantity = model.quantity

        # InventoryLogのcreate!で例外を発生させる
        allow_any_instance_of(InventoryLog).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(InventoryLog.new))
        allow(Rails.logger).to receive(:error)

        # エラーログが出力されることを確認
        expect(Rails.logger).to receive(:error).with(/在庫ログ記録エラー/)

        # メインの更新は成功すること
        expect {
          model.update!(quantity: original_quantity + 50)
        }.to change { model.quantity }.to(original_quantity + 50)
      end

      it "handles StandardError in log creation" do
        allow_any_instance_of(InventoryLog).to receive(:save!).and_raise(StandardError.new("Database connection lost"))
        allow(Rails.logger).to receive(:error)

        expect(Rails.logger).to receive(:error).with(/在庫ログ記録エラー: Database connection lost/)

        # メインの更新は成功すること
        expect {
          model.update!(quantity: model.quantity + 25)
        }.not_to raise_error
      end

      it "handles ActiveRecord::ConnectionTimeoutError" do
        allow_any_instance_of(InventoryLog).to receive(:save!).and_raise(ActiveRecord::ConnectionTimeoutError)
        allow(Rails.logger).to receive(:error)

        expect(Rails.logger).to receive(:error).with(/在庫ログ記録エラー/)

        expect {
          model.update!(quantity: model.quantity + 15)
        }.not_to raise_error
      end
    end

    describe "Current class handling" do
      context "when Current class is not defined" do
        before do
          # Currentクラスが未定義の場合をシミュレート
          stub_const("Current", nil) if defined?(Current)
          allow(Object).to receive(:defined?).with(Current).and_return(false)
        end

        it "handles missing Current class in log_operation" do
          expect {
            model.log_operation("test", 10)
          }.not_to raise_error

          log = model.inventory_logs.last
          expect(log.user_id).to be_nil
        end

        it "handles missing Current class in automatic logging" do
          expect {
            model.update!(quantity: model.quantity + 30)
          }.not_to raise_error

          log = model.inventory_logs.last
          expect(log.user_id).to be_nil
        end
      end

      context "when Current class exists but doesn't respond to user" do
        before do
          stub_const("Current", Class.new)
          allow(Current).to receive(:respond_to?).with(:user).and_return(false)
        end

        it "handles Current without user method" do
          expect {
            model.log_operation("test", 5)
          }.not_to raise_error

          log = model.inventory_logs.last
          expect(log.user_id).to be_nil
        end
      end

      context "when Current.user returns nil" do
        before do
          if defined?(Current)
            allow(Current).to receive(:user).and_return(nil)
          end
        end

        it "handles nil Current.user" do
          model.log_operation("test", 8)
          log = model.inventory_logs.last
          expect(log.user_id).to be_nil
        end
      end
    end
  end

  describe "class methods branch coverage" do
    describe ".create_bulk_inventory_logs" do
      let(:test_records) do
        [
          double("record1", quantity: 100),
          double("record2", quantity: 200),
          double("record3", quantity: 300)
        ]
      end

      context "with PostgreSQL-style array results" do
        it "handles array of arrays format" do
          # PostgreSQL形式: [[id1], [id2], [id3]]
          inserted_ids = [ [ 1001 ], [ 1002 ], [ 1003 ] ]

          expect(InventoryLog).to receive(:insert_all).with(
            array_including(
              hash_including(
                inventory_id: 1001,
                delta: 100,
                operation_type: "add",
                previous_quantity: 0,
                current_quantity: 100,
                note: "CSVインポートによる登録"
              )
            ),
            record_timestamps: true
          )

          TestInventoryModel.create_bulk_inventory_logs(test_records, inserted_ids)
        end
      end

      context "with MySQL-style simple array results" do
        it "handles simple array format" do
          # MySQL形式: [id1, id2, id3]
          inserted_ids = [ 2001, 2002, 2003 ]

          expect(InventoryLog).to receive(:insert_all).with(
            array_including(
              hash_including(
                inventory_id: 2001,
                delta: 100,
                operation_type: "add"
              ),
              hash_including(
                inventory_id: 2002,
                delta: 200,
                operation_type: "add"
              ),
              hash_including(
                inventory_id: 2003,
                delta: 300,
                operation_type: "add"
              )
            ),
            record_timestamps: true
          )

          TestInventoryModel.create_bulk_inventory_logs(test_records, inserted_ids)
        end
      end

      context "with empty parameters" do
        it "returns early for blank records" do
          expect(InventoryLog).not_to receive(:insert_all)

          TestInventoryModel.create_bulk_inventory_logs([], [ 1, 2, 3 ])
        end

        it "returns early for blank inserted_ids" do
          expect(InventoryLog).not_to receive(:insert_all)

          TestInventoryModel.create_bulk_inventory_logs(test_records, [])
        end

        it "returns early for both blank" do
          expect(InventoryLog).not_to receive(:insert_all)

          TestInventoryModel.create_bulk_inventory_logs([], [])
        end

        it "returns early for nil records" do
          expect(InventoryLog).not_to receive(:insert_all)

          TestInventoryModel.create_bulk_inventory_logs(nil, [ 1, 2, 3 ])
        end

        it "returns early for nil inserted_ids" do
          expect(InventoryLog).not_to receive(:insert_all)

          TestInventoryModel.create_bulk_inventory_logs(test_records, nil)
        end
      end

      context "with empty log_entries array" do
        it "skips insert_all when log_entries is empty" do
          # レコードはあるが、何らかの理由でlog_entriesが空の場合
          allow_any_instance_of(Array).to receive(:present?).and_return(false)

          expect(InventoryLog).not_to receive(:insert_all)

          TestInventoryModel.create_bulk_inventory_logs(test_records, [ 1, 2, 3 ])
        end
      end
    end

    describe ".create_bulk_logs" do
      it "delegates to create_bulk_inventory_logs" do
        test_records = [ double("record", quantity: 50) ]
        inserted_ids = [ 9999 ]

        expect(TestInventoryModel).to receive(:create_bulk_inventory_logs).with(test_records, inserted_ids)

        TestInventoryModel.create_bulk_logs(test_records, inserted_ids)
      end
    end

    describe ".recent_operations edge cases" do
      it "handles custom limit properly" do
        # 複数の操作を作成
        5.times { |i| model.add_stock(1, "Operation #{i}") }

        operations = TestInventoryModel.recent_operations(3)
        expect(operations.limit_value).to eq(3)
      end

      it "includes proper associations" do
        model.add_stock(10)

        operations = TestInventoryModel.recent_operations(1)
        expect(operations.includes_values).to include(:inventory_logs)
      end
    end

    describe ".operation_summary edge cases" do
      it "handles custom date ranges" do
        # 過去の操作を作成
        travel_to(2.days.ago) do
          model.add_stock(100, "Old operation")
        end

        # 最近の操作を作成
        model.remove_stock(50, "Recent operation")

        # 昨日から今日までの範囲でテスト
        summary = TestInventoryModel.operation_summary(1.day.ago, Time.current)

        expect(summary.to_sql).to include("BETWEEN")
      end
    end
  end

  describe "edge case branch coverage" do
    describe "saved_change_to_quantity handling" do
      it "handles nil previous quantity" do
        # 新規レコード作成時のケース
        new_model = TestInventoryModel.new(name: "New Item", quantity: 150, price: 500)

        expect {
          new_model.save!
        }.to change { new_model.inventory_logs.count }.by(1)

        log = new_model.inventory_logs.last
        expect(log.previous_quantity).to eq(0) # nilから0に変換される
        expect(log.current_quantity).to eq(150)
        expect(log.delta).to eq(150)
      end

      it "handles zero delta after calculation" do
        # quantity変更があったが、計算結果がゼロになるケース
        original_quantity = model.quantity

        # saved_change_to_quantityが存在するようにモック
        allow(model).to receive(:saved_change_to_quantity?).and_return(true)
        allow(model).to receive(:saved_change_to_quantity).and_return([ original_quantity, original_quantity ])

        expect {
          model.send(:log_inventory_changes)
        }.not_to change { model.inventory_logs.count }
      end
    end

    describe "transaction rollback scenarios" do
      it "rolls back add_stock on update failure" do
        original_quantity = model.quantity

        # updateで例外を発生させる
        allow(model).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(model))

        expect {
          model.add_stock(25) rescue nil
        }.not_to change { model.reload.quantity }

        expect(model.inventory_logs.count).to eq(0)
      end

      it "rolls back remove_stock on update failure" do
        original_quantity = model.quantity

        allow(model).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(model))

        expect {
          model.remove_stock(30) rescue nil
        }.not_to change { model.reload.quantity }

        expect(model.inventory_logs.count).to eq(0)
      end

      it "rolls back adjust_quantity on update failure" do
        original_quantity = model.quantity

        allow(model).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(model))

        expect {
          model.adjust_quantity(200) rescue nil
        }.not_to change { model.reload.quantity }

        expect(model.inventory_logs.count).to eq(0)
      end
    end

    describe "boundary value testing" do
      it "handles exactly zero stock removal" do
        expect(model.remove_stock(0)).to be false
        expect(model.inventory_logs.count).to eq(0)
      end

      it "handles negative stock addition" do
        expect(model.add_stock(-1)).to be false
        expect(model.inventory_logs.count).to eq(0)
      end

      it "handles removal of exactly available quantity" do
        current_quantity = model.quantity

        expect {
          result = model.remove_stock(current_quantity)
          expect(result).to be true
        }.to change { model.quantity }.to(0)

        log = model.inventory_logs.last
        expect(log.delta).to eq(-current_quantity)
        expect(log.current_quantity).to eq(0)
      end

      it "handles removal exceeding available quantity by 1" do
        current_quantity = model.quantity

        expect(model.remove_stock(current_quantity + 1)).to be false
        expect(model.reload.quantity).to eq(current_quantity)
        expect(model.inventory_logs.count).to eq(0)
      end
    end

    describe "association loading optimization" do
      it "doesn't create unnecessary queries when logs are preloaded" do
        model_with_logs = TestInventoryModel.includes(:inventory_logs).find(model.id)

        query_count = 0
        callback = ->(_, _, _, _, payload) { query_count += 1 if payload[:sql] && !payload[:sql].include?('SCHEMA') }

        ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
          model_with_logs.add_stock(5)
        end

        # プリロード済みなので追加のSELECTクエリは最小限
        expect(query_count).to be <= 3 # UPDATE, INSERT, 追加クエリ最小限
      end
    end
  end
end
