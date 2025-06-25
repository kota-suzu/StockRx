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
end
