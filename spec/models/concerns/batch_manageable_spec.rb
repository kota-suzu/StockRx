# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BatchManageable do
  # CLAUDE.md準拠: バッチ管理機能の包括的テスト
  # メタ認知: ロット管理による品質保証とトレーサビリティの検証
  # 横展開: 他のManageable系concernでも同様のテストパターン適用

  # テスト用のモデルクラス
  class TestBatchModel < ApplicationRecord
    self.table_name = 'inventories'
    include BatchManageable

    # batches_countメソッドの定義（concernで参照されているため）
    def batches_count
      batches.count
    end
  end

  let(:model) { TestBatchModel.create!(name: "Test Drug", quantity: 0, price: 1000) }
  let(:future_date) { Date.current + 1.year }
  let(:past_date) { Date.current - 1.day }
  let(:near_expiry_date) { Date.current + 15.days }

  describe "関連付け" do
    it "batchesを持つ" do
      expect(model).to respond_to(:batches)
    end

    it "削除時にbatchesも削除される" do
      model.add_batch(100, future_date)
      expect { model.destroy }.to change { Batch.count }.by(-1)
    end
  end

  describe "#add_batch" do
    context "有効なパラメータの場合" do
      it "新しいバッチを作成する" do
        expect {
          model.add_batch(100, future_date, "LOT001")
        }.to change { model.batches.count }.by(1)
      end

      it "正しい属性でバッチを作成する" do
        batch = model.add_batch(100, future_date, "LOT001")

        expect(batch.quantity).to eq(100)
        expect(batch.expires_on).to eq(future_date)
        expect(batch.lot_code).to eq("LOT001")
      end

      it "バッチ番号が未指定の場合、自動生成する" do
        batch = model.add_batch(100, future_date)

        expect(batch.lot_code).to match(/^BN-\d{8}-[A-F0-9]{6}$/)
      end

      it "総在庫量を同期する" do
        model.add_batch(100, future_date)
        model.add_batch(50, future_date)

        expect(model.reload.quantity).to eq(150)
      end
    end

    context "有効期限が未指定の場合" do
      it "有効期限なしでバッチを作成する" do
        batch = model.add_batch(100, nil)

        expect(batch.expires_on).to be_nil
      end
    end
  end

  describe "#consume_batch" do
    before do
      model.add_batch(100, future_date, "LOT001")
      model.add_batch(50, future_date + 1.month, "LOT002")
      model.add_batch(30, near_expiry_date, "LOT003")
    end

    context "有効な消費量の場合" do
      it "バッチから在庫を消費する" do
        result = model.consume_batch(80)

        expect(result).to be true
        expect(model.total_batch_quantity).to eq(100)
      end

      it "先に有効期限が近いバッチから消費する（FIFO）" do
        model.consume_batch(40)

        # 期限が近いLOT003(30)が先に消費され、次にLOT001から10消費
        lot3 = model.batches.find_by(lot_code: "LOT003")
        lot1 = model.batches.find_by(lot_code: "LOT001")

        expect(lot3.quantity).to eq(0)
        expect(lot1.quantity).to eq(90)
      end

      it "消費後に数量0のバッチを削除する" do
        expect {
          model.consume_batch(30)
        }.to change { model.batches.count }.by(-1)
      end

      it "総在庫量を同期する" do
        model.consume_batch(80)

        expect(model.reload.quantity).to eq(100)
      end
    end

    context "無効な消費量の場合" do
      it "0以下の場合はfalseを返す" do
        expect(model.consume_batch(0)).to be false
        expect(model.consume_batch(-10)).to be false
      end

      it "在庫を超える場合はfalseを返す" do
        expect(model.consume_batch(200)).to be false
      end

      it "在庫を変更しない" do
        expect {
          model.consume_batch(200)
        }.not_to change { model.total_batch_quantity }
      end
    end
  end

  describe "#total_batch_quantity" do
    it "全バッチの合計数量を返す" do
      model.add_batch(100, future_date)
      model.add_batch(50, future_date)

      expect(model.total_batch_quantity).to eq(150)
    end

    it "バッチがない場合は0を返す" do
      expect(model.total_batch_quantity).to eq(0)
    end
  end

  describe "#nearest_expiry_date" do
    it "最も近い有効期限を返す" do
      model.add_batch(100, future_date)
      model.add_batch(50, near_expiry_date)
      model.add_batch(30, future_date + 2.months)

      expect(model.nearest_expiry_date).to eq(near_expiry_date)
    end

    it "在庫0のバッチは除外する" do
      model.add_batch(100, future_date)
      batch = model.add_batch(50, near_expiry_date)
      batch.update!(quantity: 0)

      expect(model.nearest_expiry_date).to eq(future_date)
    end

    it "バッチがない場合はnilを返す" do
      expect(model.nearest_expiry_date).to be_nil
    end
  end

  describe "#expiring_batches" do
    before do
      model.add_batch(100, Date.current + 10.days, "EXPIRE10")
      model.add_batch(50, Date.current + 25.days, "EXPIRE25")
      model.add_batch(30, Date.current + 40.days, "EXPIRE40")
    end

    it "指定日数以内に期限切れになるバッチを返す" do
      expiring = model.expiring_batches(30)

      expect(expiring.count).to eq(2)
      expect(expiring.map(&:lot_code)).to include("EXPIRE10", "EXPIRE25")
    end

    it "デフォルトで30日以内のバッチを返す" do
      expiring = model.expiring_batches

      expect(expiring.count).to eq(2)
    end

    it "在庫0のバッチは除外する" do
      batch = model.batches.find_by(lot_code: "EXPIRE10")
      batch.update!(quantity: 0)

      expiring = model.expiring_batches
      expect(expiring.count).to eq(1)
    end

    it "有効期限順に並べる" do
      expiring = model.expiring_batches

      expect(expiring.first.lot_code).to eq("EXPIRE10")
      expect(expiring.last.lot_code).to eq("EXPIRE25")
    end
  end

  describe "#expired_batches" do
    before do
      model.add_batch(100, past_date, "EXPIRED")
      model.add_batch(50, future_date, "VALID")
    end

    it "期限切れのバッチを返す" do
      expired = model.expired_batches

      expect(expired.count).to eq(1)
      expect(expired.first.lot_code).to eq("EXPIRED")
    end

    it "在庫0の期限切れバッチは除外する" do
      batch = model.batches.find_by(lot_code: "EXPIRED")
      batch.update!(quantity: 0)

      expect(model.expired_batches.count).to eq(0)
    end
  end

  describe "after_saveコールバック" do
    it "quantity変更時に同期される" do
      model.add_batch(100, future_date)

      # 直接quantityを変更
      model.update!(quantity: 200)

      # バッチの合計と同期される
      expect(model.reload.quantity).to eq(100)
    end

    it "バッチが存在しない場合は同期しない" do
      # バッチなしで初期作成
      new_model = TestBatchModel.create!(name: "New Item", quantity: 50, price: 100)

      expect(new_model.quantity).to eq(50)
      expect(new_model.batches.count).to eq(0)
    end
  end

  describe "クラスメソッド" do
    let!(:model1) { TestBatchModel.create!(name: "Item 1", quantity: 0, price: 100) }
    let!(:model2) { TestBatchModel.create!(name: "Item 2", quantity: 0, price: 100) }
    let!(:model3) { TestBatchModel.create!(name: "Item 3", quantity: 0, price: 100) }

    before do
      model1.add_batch(100, Date.current + 10.days)
      model2.add_batch(50, Date.current + 40.days)
      model3.add_batch(30, past_date)
    end

    describe ".with_expiring_batches" do
      it "期限切れが近いバッチを持つモデルを返す" do
        items = TestBatchModel.with_expiring_batches(30)

        expect(items).to include(model1)
        expect(items).not_to include(model2)
      end

      it "在庫0のバッチは除外する" do
        model1.batches.first.update!(quantity: 0)

        items = TestBatchModel.with_expiring_batches(30)
        expect(items).not_to include(model1)
      end
    end

    describe ".batch_expiry_report" do
      it "バッチ期限レポートを生成する" do
        report = TestBatchModel.batch_expiry_report

        expect(report).to be_a(Hash)
        expect(report[:expired]).to be_present
        expect(report[:expiring_soon]).to be_present
        expect(report[:total_value_at_risk]).to be_present
      end
    end
  end

  describe "パフォーマンス" do
    it "大量のバッチでも高速に消費処理を行う" do
      100.times { |i| model.add_batch(10, future_date + i.days) }

      start_time = Time.current
      model.consume_batch(500)
      elapsed_time = Time.current - start_time

      expect(elapsed_time).to be < 0.5 # 500ms以内
    end
  end

  describe "データ整合性" do
    it "トランザクション内でバッチ操作を行う" do
      # エラーが発生した場合、ロールバックされることを確認
      allow_any_instance_of(Batch).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

      expect {
        model.add_batch(100, future_date) rescue nil
      }.not_to change { model.batches.count }
    end
  end
end
