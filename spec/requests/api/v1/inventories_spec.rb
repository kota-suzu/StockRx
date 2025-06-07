# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Inventories", type: :request do
  let(:admin) { create(:admin) }

  before do
    sign_in admin
  end

  let(:valid_attributes) do
    {
      name: "API Test Medicine",
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
      category: "invalid",
      quantity: -10
    }
  end

  let(:headers) do
    { "Accept" => "application/json", "Content-Type" => "application/json" }
  end

  describe "GET /api/v1/inventories" do
    let!(:inventories) { create_list(:inventory, 3) }

    it "returns all inventories" do
      get api_v1_inventories_path, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to match(/application\/json/)

      json = JSON.parse(response.body)
      expect(json.size).to eq(3)
    end
  end

  describe "GET /api/v1/inventories/:id" do
    context "when the inventory exists" do
      let(:inventory) { create(:inventory) }

      it "returns the inventory" do
        get api_v1_inventory_path(inventory), headers: headers

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["id"]).to eq(inventory.id)
        expect(json["name"]).to eq(inventory.name)
      end
    end

    context "when the inventory does not exist" do
      it "returns 404 with proper error format" do
        get api_v1_inventory_path(id: "non-existent"), headers: headers

        expect(response).to have_http_status(:not_found)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("resource_not_found")
        expect(json["message"]).to be_present
      end
    end
  end

  describe "POST /api/v1/inventories" do
    context "with valid parameters" do
      it "creates a new inventory" do
        expect {
          post api_v1_inventories_path,
               params: { inventory: valid_attributes }.to_json,
               headers: headers
        }.to change(Inventory, :count).by(1)

        expect(response).to have_http_status(:created)

        json = JSON.parse(response.body)
        expect(json["name"]).to eq(valid_attributes[:name])
      end
    end

    context "with invalid parameters" do
      it "returns validation error" do
        post api_v1_inventories_path,
             params: { inventory: invalid_attributes }.to_json,
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("validation_error")
        expect(json["message"]).to be_present
        expect(json["details"]).to be_an(Array)
      end
    end

    context "with missing required parameter" do
      it "returns bad request" do
        post api_v1_inventories_path,
             params: { wrong_root: valid_attributes }.to_json,
             headers: headers

        expect(response).to have_http_status(:bad_request)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("parameter_missing")
        expect(json["message"]).to be_present
      end
    end
  end

  describe "PUT /api/v1/inventories/:id" do
    let(:inventory) { create(:inventory) }
    let(:new_attributes) { { name: "Updated Medicine Name" } }

    context "with valid parameters" do
      it "updates the inventory" do
        put api_v1_inventory_path(inventory),
            params: { inventory: new_attributes }.to_json,
            headers: headers

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json["name"]).to eq(new_attributes[:name])

        inventory.reload
        expect(inventory.name).to eq(new_attributes[:name])
      end
    end

    context "with invalid parameters" do
      it "returns validation error" do
        put api_v1_inventory_path(inventory),
            params: { inventory: { name: "" } }.to_json,
            headers: headers

        expect(response).to have_http_status(:unprocessable_entity)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("validation_error")
        expect(json["details"]).to be_an(Array)
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        put api_v1_inventory_path(id: "non-existent"),
            params: { inventory: new_attributes }.to_json,
            headers: headers

        expect(response).to have_http_status(:not_found)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("resource_not_found")
      end
    end
  end

  describe "DELETE /api/v1/inventories/:id" do
    let!(:inventory) { create(:inventory) }

    context "when the inventory exists" do
      it "deletes the inventory" do
        expect {
          delete api_v1_inventory_path(inventory), headers: headers
        }.to change(Inventory, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end
    end

    context "when the inventory does not exist" do
      it "returns 404" do
        delete api_v1_inventory_path(id: "non-existent"), headers: headers

        expect(response).to have_http_status(:not_found)

        json = JSON.parse(response.body)
        expect(json["code"]).to eq("resource_not_found")
      end
    end
  end
end
