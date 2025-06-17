# frozen_string_literal: true

require "rails_helper"

# TODO: 🟡 Phase 3 - 管理画面への統合に伴うテスト移行（CLAUDE.md準拠）
# 優先度: 中（テストの一貫性向上）
# 実装内容:
#   - このテストファイルの内容を spec/requests/admin_controllers/inventories_spec.rb に統合
#   - 重複するテストケースの整理
#   - 削除予定: 2025年Q1（統合完了後）
# 期待効果: テストコードの重複削除、保守性向上
RSpec.describe "Inventories", type: :request do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
  end
  let(:valid_attributes) do
    {
      name: "テスト医薬品",
      status: "active",
      quantity: 100,
      price: 1500
    }
  end

  let(:invalid_attributes) do
    {
      name: "",
      quantity: -10,
      price: -100
    }
  end

  describe "GET /inventories" do
    it "returns a success response" do
      get admin_inventories_path
      expect(response).to have_http_status(:ok)
    end

    context "with JSON format" do
      it "returns JSON response" do
        get admin_inventories_path, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to match(/application\/json/)
      end
    end
  end

  describe "GET /inventories/:id" do
    context "when the inventory exists" do
      let(:inventory) { Inventory.create!(valid_attributes) }

      it "returns a success response" do
        get admin_inventory_path(inventory)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when the inventory does not exist" do
      it "returns 404 for non-existent resource" do
        get admin_inventory_path(id: "non-existent-id")
        expect(response).to have_http_status(:not_found)
      end

      context "with JSON format" do
        it "returns proper JSON error response" do
          get admin_inventory_path(id: "non-existent-id"), headers: { "Accept" => "application/json" }
          expect(response).to have_http_status(:not_found)

          json = JSON.parse(response.body)
          expect(json["success"]).to be false
          expect(json["message"]).to be_present
          expect(json["metadata"]["type"]).to eq("not_found")
        end
      end
    end
  end

  describe "POST /inventories" do
    context "with valid parameters" do
      it "creates a new inventory" do
        expect {
          post admin_inventories_path, params: { inventory: valid_attributes }
        }.to change(Inventory, :count).by(1)

        expect(response).to have_http_status(:found) # redirect after creation
      end

      context "with JSON format" do
        it "returns created status" do
          post admin_inventories_path,
               params: { inventory: valid_attributes },
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:created)
          json = JSON.parse(response.body)
          expect(json["name"]).to eq(valid_attributes[:name])
        end
      end
    end

    context "with invalid parameters" do
      it "does not create a new inventory" do
        expect {
          post admin_inventories_path, params: { inventory: invalid_attributes }
        }.not_to change(Inventory, :count)
      end

      context "with JSON format" do
        it "returns validation error" do
          post admin_inventories_path,
               params: { inventory: invalid_attributes },
               headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:unprocessable_entity)

          json = JSON.parse(response.body)
          expect(json["code"]).to eq("validation_error")
          expect(json).to have_key("message")
          expect(json).to have_key("details")
          expect(json["details"]).to be_an(Array)
        end
      end
    end

    context "with missing parameters" do
      it "returns bad request" do
        post admin_inventories_path,
             params: { invalid_root: { name: "test" } },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:bad_request)

        json = JSON.parse(response.body)
        expect(json["success"]).to be false
        expect(json["message"]).to be_present
      end
    end
  end

  describe "PATCH /inventories/:id" do
    let(:inventory) { Inventory.create!(valid_attributes) }
    let(:new_attributes) { { name: "更新された医薬品名" } }

    context "with valid parameters" do
      it "updates the inventory" do
        patch admin_inventory_path(inventory), params: { inventory: new_attributes }
        inventory.reload
        expect(inventory.name).to eq("更新された医薬品名")
      end
    end

    context "with invalid parameters" do
      it "does not update the inventory" do
        patch admin_inventory_path(inventory),
              params: { inventory: { name: "" } },
              headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("validation_error")
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        patch admin_inventory_path(id: "non-existent-id"),
              params: { inventory: new_attributes }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /inventories/:id" do
    let!(:inventory) { Inventory.create!(valid_attributes) }

    context "when the inventory exists" do
      it "destroys the inventory" do
        # CLAUDE.md準拠: メタ認知 - dependent: :restrict_with_errorを考慮
        # 横展開確認: 削除前に関連するすべての制約レコードをクリア
        inventory.audit_logs.destroy_all      # Auditable concern
        inventory.inventory_logs.destroy_all  # InventoryLoggable concern
        
        expect {
          delete admin_inventory_path(inventory)
        }.to change(Inventory, :count).by(-1)
      end

      context "with JSON format" do
        it "returns no content status" do
          # CLAUDE.md準拠: メタ認知 - dependent: :restrict_with_errorを考慮
          # 横展開確認: 削除前に関連するすべての制約レコードをクリア
          inventory.audit_logs.destroy_all      # Auditable concern
          inventory.inventory_logs.destroy_all  # InventoryLoggable concern
          
          delete admin_inventory_path(inventory),
                 headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:no_content)
        end
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        delete admin_inventory_path(id: "non-existent-id")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
