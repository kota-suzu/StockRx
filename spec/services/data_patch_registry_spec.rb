# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataPatchRegistry do
  let(:registry) { DataPatchRegistry.instance }

  # Mock patch classes for testing
  class TestDataPatch
    def self.new
      self
    end

    def execute_batch(batch)
      batch
    end

    def estimate_target_count
      100
    end
  end

  class InvalidDataPatch
    # Missing required methods
  end

  before do
    # Clear registry before each test
    registry.instance_variable_set(:@patches, {})
    registry.instance_variable_set(:@metadata, {})
  end

  describe "#register_patch" do
    it "registers a valid patch class" do
      result = registry.register_patch("test_patch", TestDataPatch, { category: "test" })

      expect(result).to be true
      expect(registry.patch_exists?("test_patch")).to be true
    end

    it "stores metadata with patch" do
      registry.register_patch("test_patch", TestDataPatch, {
        description: "Test patch for specs",
        category: "testing"
      })

      metadata = registry.patch_metadata("test_patch")
      expect(metadata[:description]).to eq("Test patch for specs")
      expect(metadata[:category]).to eq("testing")
      expect(metadata[:registered_at]).to be_present
      expect(metadata[:class_name]).to eq("TestDataPatch")
    end

    it "validates patch class before registration" do
      expect {
        registry.register_patch("invalid_patch", InvalidDataPatch)
      }.to raise_error(DataPatchRegistry::InvalidPatchClassError)
    end

    it "rejects non-class objects" do
      expect {
        registry.register_patch("not_a_class", "string")
      }.to raise_error(DataPatchRegistry::InvalidPatchClassError, /クラスオブジェクトが必要です/)
    end

    it "logs patch registration" do
      expect(Rails.logger).to receive(:info).with(/パッチ登録: test_patch/)

      registry.register_patch("test_patch", TestDataPatch)
    end
  end

  describe "#find_patch" do
    before do
      registry.register_patch("test_patch", TestDataPatch)
    end

    it "finds registered patch by name" do
      patch_class = registry.find_patch("test_patch")
      expect(patch_class).to eq(TestDataPatch)
    end

    it "finds patch with string or symbol name" do
      expect(registry.find_patch("test_patch")).to eq(TestDataPatch)
      expect(registry.find_patch(:test_patch)).to eq(TestDataPatch)
    end

    it "raises error for non-existent patch" do
      expect {
        registry.find_patch("non_existent")
      }.to raise_error(DataPatchRegistry::PatchNotFoundError, /パッチが見つかりません/)
    end
  end

  describe "#patch_exists?" do
    before do
      registry.register_patch("test_patch", TestDataPatch)
    end

    it "returns true for existing patch" do
      expect(registry.patch_exists?("test_patch")).to be true
      expect(registry.patch_exists?(:test_patch)).to be true
    end

    it "returns false for non-existent patch" do
      expect(registry.patch_exists?("non_existent")).to be false
    end
  end

  describe "#list_patches" do
    before do
      registry.register_patch("patch1", TestDataPatch, { category: "inventory", status: "active" })
      registry.register_patch("patch2", TestDataPatch, { category: "pricing", status: "active" })
      registry.register_patch("patch3", TestDataPatch, { category: "inventory", status: "inactive" })
    end

    it "lists all active patches by default" do
      patches = registry.list_patches

      expect(patches.size).to eq(2)
      expect(patches.map { |p| p[:name] }).to contain_exactly("patch1", "patch2")
    end

    it "filters patches by category" do
      patches = registry.list_patches(category: "inventory")

      expect(patches.size).to eq(1)
      expect(patches.first[:name]).to eq("patch1")
    end

    it "filters patches by status" do
      patches = registry.list_patches(status: :inactive)

      expect(patches.size).to eq(1)
      expect(patches.first[:name]).to eq("patch3")
    end

    it "shows all patches when status is :all" do
      patches = registry.list_patches(status: :all)

      expect(patches.size).to eq(3)
    end

    it "combines category and status filters" do
      patches = registry.list_patches(category: "inventory", status: :all)

      expect(patches.size).to eq(2)
      expect(patches.map { |p| p[:name] }).to contain_exactly("patch1", "patch3")
    end

    it "includes metadata in listing" do
      patches = registry.list_patches
      patch = patches.first

      expect(patch[:class_name]).to eq("TestDataPatch")
      expect(patch[:metadata]).to include(:category, :status, :registered_at)
    end
  end

  describe "#patch_metadata" do
    before do
      registry.register_patch("test_patch", TestDataPatch, {
        description: "Test description",
        batch_size: 500
      })
    end

    it "returns metadata for existing patch" do
      metadata = registry.patch_metadata("test_patch")

      expect(metadata[:description]).to eq("Test description")
      expect(metadata[:batch_size]).to eq(500)
      expect(metadata[:category]).to eq("general") # default value
    end

    it "returns a copy of metadata" do
      metadata = registry.patch_metadata("test_patch")
      metadata[:description] = "Modified"

      expect(registry.patch_metadata("test_patch")[:description]).to eq("Test description")
    end

    it "raises error for non-existent patch" do
      expect {
        registry.patch_metadata("non_existent")
      }.to raise_error(DataPatchRegistry::PatchNotFoundError)
    end
  end

  describe "#update_patch_metadata" do
    before do
      registry.register_patch("test_patch", TestDataPatch, { description: "Original" })
    end

    it "updates existing patch metadata" do
      registry.update_patch_metadata("test_patch", { description: "Updated", priority: "high" })

      metadata = registry.patch_metadata("test_patch")
      expect(metadata[:description]).to eq("Updated")
      expect(metadata[:priority]).to eq("high")
    end

    it "preserves non-updated metadata" do
      original_time = registry.patch_metadata("test_patch")[:registered_at]

      registry.update_patch_metadata("test_patch", { description: "Updated" })

      metadata = registry.patch_metadata("test_patch")
      expect(metadata[:registered_at]).to eq(original_time)
      expect(metadata[:category]).to eq("general")
    end

    it "raises error for non-existent patch" do
      expect {
        registry.update_patch_metadata("non_existent", {})
      }.to raise_error(DataPatchRegistry::PatchNotFoundError)
    end
  end

  describe "#validate_patch_class" do
    it "validates class with required methods" do
      expect(registry.validate_patch_class(TestDataPatch)).to be true
    end

    it "raises error for non-class objects" do
      expect {
        registry.validate_patch_class("not a class")
      }.to raise_error(DataPatchRegistry::InvalidPatchClassError)
    end

    it "raises error when required methods are missing" do
      expect {
        registry.validate_patch_class(InvalidDataPatch)
      }.to raise_error(DataPatchRegistry::InvalidPatchClassError, /必須メソッドが不足/)
    end

    it "logs warning when patch doesn't inherit from DataPatch" do
      allow(Object).to receive(:const_defined?).with("DataPatch").and_return(true)
      allow(Rails.logger).to receive(:warn)

      registry.validate_patch_class(TestDataPatch)

      expect(Rails.logger).to have_received(:warn).with(/DataPatch を継承していません/)
    end
  end

  describe "#reload_patches" do
    before do
      registry.register_patch("test_patch", TestDataPatch)
      allow(registry).to receive(:load_patches_from_directory)
      allow(registry).to receive(:load_patches_from_config)
    end

    it "clears existing patches" do
      registry.reload_patches

      expect(registry.patch_exists?("test_patch")).to be false
    end

    it "reloads patches from sources" do
      expect(registry).to receive(:load_patches_from_directory)
      expect(registry).to receive(:load_patches_from_config)

      registry.reload_patches
    end

    it "logs reload action" do
      expect(Rails.logger).to receive(:info).with(/パッチレジストリを再ロードしました/)

      registry.reload_patches
    end
  end

  describe "#registry_statistics" do
    before do
      registry.register_patch("patch1", TestDataPatch, { category: "inventory", status: "active" })
      registry.register_patch("patch2", TestDataPatch, { category: "pricing", status: "active" })
      registry.register_patch("patch3", TestDataPatch, { category: "inventory", status: "inactive" })
    end

    it "returns total patch count" do
      stats = registry.registry_statistics

      expect(stats[:total_patches]).to eq(3)
    end

    it "groups patches by category" do
      stats = registry.registry_statistics

      expect(stats[:by_category]).to eq({
        "inventory" => 2,
        "pricing" => 1
      })
    end

    it "groups patches by status" do
      stats = registry.registry_statistics

      expect(stats[:by_status]).to eq({
        "active" => 2,
        "inactive" => 1
      })
    end

    it "includes last registration time" do
      stats = registry.registry_statistics

      expect(stats[:last_registered]).to be_present
      expect(stats[:last_registered]).to be_a(Time)
    end
  end

  describe "class methods delegation" do
    it "delegates methods to instance" do
      expect(DataPatchRegistry).to respond_to(:register_patch)
      expect(DataPatchRegistry).to respond_to(:find_patch)
      expect(DataPatchRegistry).to respond_to(:patch_exists?)
      expect(DataPatchRegistry).to respond_to(:list_patches)
    end

    it "uses singleton instance" do
      DataPatchRegistry.register_patch("singleton_test", TestDataPatch)

      expect(registry.patch_exists?("singleton_test")).to be true
    end
  end

  describe "auto-loading" do
    let(:patches_dir) { Rails.root.join("app", "data_patches") }

    before do
      allow(patches_dir).to receive(:exist?).and_return(true)
      allow(Dir).to receive(:glob).and_return([
        patches_dir.join("inventory_price_adjustment_patch.rb").to_s
      ])
      allow(registry).to receive(:require)
      allow(Object).to receive(:const_defined?).with("InventoryPriceAdjustmentPatch").and_return(true)
      allow(Object).to receive(:const_get).with("InventoryPriceAdjustmentPatch").and_return(TestDataPatch)
    end

    it "loads patches from directory" do
      registry.send(:load_patches_from_directory)

      expect(registry.patch_exists?("inventory_price_adjustment_patch")).to be true
    end

    it "handles load errors gracefully" do
      allow(registry).to receive(:require).and_raise(StandardError, "Load error")
      expect(Rails.logger).to receive(:error).with(/パッチロードエラー/)

      expect { registry.send(:load_patches_from_directory) }.not_to raise_error
    end
  end

  describe "config file loading" do
    let(:config_file) { Rails.root.join("config", "data_patches.yml") }
    let(:config_content) do
      {
        "patches" => {
          "test_config_patch" => {
            "class_name" => "TestDataPatch",
            "description" => "Configured patch",
            "category" => "config_test",
            "batch_size" => 2000
          }
        }
      }
    end

    before do
      allow(config_file).to receive(:exist?).and_return(true)
      allow(YAML).to receive(:load_file).and_return(config_content)
      allow(Object).to receive(:const_defined?).with("TestDataPatch").and_return(true)
      allow(Object).to receive(:const_get).with("TestDataPatch").and_return(TestDataPatch)
    end

    it "loads patches from config file" do
      registry.send(:load_patches_from_config)

      expect(registry.patch_exists?("test_config_patch")).to be true

      metadata = registry.patch_metadata("test_config_patch")
      expect(metadata[:description]).to eq("Configured patch")
      expect(metadata[:category]).to eq("config_test")
      expect(metadata[:batch_size]).to eq(2000)
    end

    it "handles missing config file" do
      allow(config_file).to receive(:exist?).and_return(false)

      expect { registry.send(:load_patches_from_config) }.not_to raise_error
    end

    it "handles config load errors" do
      allow(YAML).to receive(:load_file).and_raise(StandardError, "YAML error")
      expect(Rails.logger).to receive(:error).with(/設定ファイルロードエラー/)

      expect { registry.send(:load_patches_from_config) }.not_to raise_error
    end
  end

  describe "edge cases" do
    it "handles patches with same name" do
      registry.register_patch("duplicate", TestDataPatch)
      registry.register_patch("duplicate", TestDataPatch, { category: "updated" })

      metadata = registry.patch_metadata("duplicate")
      expect(metadata[:category]).to eq("updated")
    end

    it "preserves metadata defaults" do
      registry.register_patch("minimal", TestDataPatch)

      metadata = registry.patch_metadata("minimal")
      expect(metadata[:status]).to eq("active")
      expect(metadata[:batch_size]).to eq(1000)
      expect(metadata[:memory_limit]).to eq(500)
    end
  end
end
