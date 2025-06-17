# frozen_string_literal: true

require "rails_helper"

RSpec.describe StoreInventoriesHelper, type: :helper do
  describe "#store_type_icon" do
    it "薬局の場合、処方箋アイコンを返す" do
      expect(helper.store_type_icon("pharmacy")).to eq("fas fa-prescription-bottle-alt")
    end

    it "倉庫の場合、倉庫アイコンを返す" do
      expect(helper.store_type_icon("warehouse")).to eq("fas fa-warehouse")
    end

    it "本社の場合、ビルアイコンを返す" do
      expect(helper.store_type_icon("headquarters")).to eq("fas fa-building")
    end

    it "その他の場合、標準の店舗アイコンを返す" do
      expect(helper.store_type_icon("other")).to eq("fas fa-store")
    end
  end

  describe "#stock_status_badge" do
    it "在庫0の場合、在庫切れバッジを返す" do
      result = helper.stock_status_badge(0)
      expect(result).to include("在庫切れ")
      expect(result).to include("bg-danger")
    end

    it "在庫1-10の場合、在庫少バッジを返す" do
      result = helper.stock_status_badge(5)
      expect(result).to include("在庫少")
      expect(result).to include("bg-warning")
    end

    it "在庫11以上の場合、在庫ありバッジを返す" do
      result = helper.stock_status_badge(50)
      expect(result).to include("在庫あり")
      expect(result).to include("bg-success")
    end
  end

  describe "#sort_link" do
    let(:store) { create(:store) }

    before do
      assign(:store, store)
      allow(helper).to receive(:request).and_return(
        double(query_parameters: { "page" => "1" })
      )
    end

    context "現在ソートされていない列の場合" do
      before do
        allow(helper).to receive(:params).and_return(
          ActionController::Parameters.new(sort: nil, direction: nil)
        )
      end

      it "昇順へのリンクを生成する" do
        result = helper.sort_link("商品名", "inventories.name")
        expect(result).to include("fa-sort")
        expect(result).to include("direction=asc")
      end
    end

    context "現在昇順でソートされている列の場合" do
      before do
        allow(helper).to receive(:params).and_return(
          ActionController::Parameters.new(sort: "inventories.name", direction: "asc")
        )
      end

      it "降順へのリンクを生成する" do
        result = helper.sort_link("商品名", "inventories.name")
        expect(result).to include("fa-sort-up")
        expect(result).to include("direction=desc")
      end
    end

    context "現在降順でソートされている列の場合" do
      before do
        allow(helper).to receive(:params).and_return(
          ActionController::Parameters.new(sort: "inventories.name", direction: "desc")
        )
      end

      it "昇順へのリンクを生成する" do
        result = helper.sort_link("商品名", "inventories.name")
        expect(result).to include("fa-sort-down")
        expect(result).to include("direction=asc")
      end
    end
  end

  describe "#public_stock_display" do
    it "在庫0の場合、'在庫なし'を返す" do
      expect(helper.public_stock_display(0)).to eq("在庫なし")
    end

    it "在庫1-5の場合、'残りわずか'を返す" do
      expect(helper.public_stock_display(3)).to eq("残りわずか")
    end

    it "在庫6-20の場合、'在庫少'を返す" do
      expect(helper.public_stock_display(15)).to eq("在庫少")
    end

    it "在庫21以上の場合、'在庫あり'を返す" do
      expect(helper.public_stock_display(100)).to eq("在庫あり")
    end
  end

  describe "#last_updated_display" do
    it "日時がnilの場合、'データなし'を返す" do
      expect(helper.last_updated_display(nil)).to eq("データなし")
    end

    it "日時が指定された場合、相対時間を表示する" do
      time = 2.hours.ago
      result = helper.last_updated_display(time)
      expect(result).to include("2時間前")
      expect(result).to include("data-bs-toggle=\"tooltip\"")
    end
  end

  # TODO: Phase 3 - 追加のヘルパーメソッドテスト
  #   - 国際化対応のテスト
  #   - アクセシビリティ属性のテスト
  #   - エッジケースのカバレッジ向上
end
