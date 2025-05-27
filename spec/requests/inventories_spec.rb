# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Inventories", type: :request do
  let(:valid_attributes) do
    {
      name: "テスト医薬品",
      category: "prescription",
      unit: "錠",
      quantity: 100,
      minimum_stock: 10,
      price: 1500
    }
  end

  let(:invalid_attributes) do
    {
      name: "",
      category: "invalid_category",
      unit: "",
      quantity: -10,
      minimum_stock: -5,
      price: -100
    }
  end

  describe "GET /inventories" do
    it "returns a success response" do
      get inventories_path
      expect(response).to have_http_status(:ok)
    end

    context "with JSON format" do
      it "returns JSON response" do
        get inventories_path, headers: { "Accept" => "application/json" }
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to match(/application\/json/)
      end
    end
  end

  describe "GET /inventories/:id" do
    context "when the inventory exists" do
      let(:inventory) { Inventory.create!(valid_attributes) }

      it "returns a success response" do
        get inventory_path(inventory)
        expect(response).to have_http_status(:ok)
      end
    end

    context "when the inventory does not exist" do
      it "returns 404 for non-existent resource" do
        get inventory_path(id: "non-existent-id")
        expect(response).to have_http_status(:not_found)
      end

      context "with JSON format" do
        it "returns proper JSON error response" do
          get inventory_path(id: "non-existent-id"), headers: { "Accept" => "application/json" }
          expect(response).to have_http_status(:not_found)

          json = JSON.parse(response.body)
          expect(json["code"]).to eq("resource_not_found")
          expect(json).to have_key("message")
        end
      end
    end
  end

  describe "POST /inventories" do
    context "with valid parameters" do
      it "creates a new inventory" do
        expect {
          post inventories_path, params: { inventory: valid_attributes }
        }.to change(Inventory, :count).by(1)

        expect(response).to have_http_status(:found) # redirect after creation
      end

      context "with JSON format" do
        it "returns created status" do
          post inventories_path,
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
          post inventories_path, params: { inventory: invalid_attributes }
        }.not_to change(Inventory, :count)
      end

      context "with JSON format" do
        it "returns validation error" do
          post inventories_path,
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
        post inventories_path,
             params: { invalid_root: { name: "test" } },
             headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:bad_request)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("parameter_missing")
        expect(json).to have_key("message")
      end
    end
  end

  describe "PATCH /inventories/:id" do
    let(:inventory) { Inventory.create!(valid_attributes) }
    let(:new_attributes) { { name: "更新された医薬品名" } }

    context "with valid parameters" do
      it "updates the inventory" do
        patch inventory_path(inventory), params: { inventory: new_attributes }
        inventory.reload
        expect(inventory.name).to eq("更新された医薬品名")
      end
    end

    context "with invalid parameters" do
      it "does not update the inventory" do
        patch inventory_path(inventory),
              params: { inventory: { name: "" } },
              headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("validation_error")
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        patch inventory_path(id: "non-existent-id"),
              params: { inventory: new_attributes }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /inventories/:id" do
    let!(:inventory) { Inventory.create!(valid_attributes) }

    context "when the inventory exists" do
      it "destroys the inventory" do
        expect {
          delete inventory_path(inventory)
        }.to change(Inventory, :count).by(-1)
      end

      context "with JSON format" do
        it "returns no content status" do
          delete inventory_path(inventory),
                 headers: { "Accept" => "application/json" }

          expect(response).to have_http_status(:no_content)
        end
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        delete inventory_path(id: "non-existent-id")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
