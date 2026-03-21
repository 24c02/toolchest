require "spec_helper"

RSpec.describe Toolchest::ParamDefinition do
  describe "#to_json_schema" do
    it "generates string schema" do
      param = described_class.new(name: :status, type: :string, description: "Order status")
      expect(param.to_json_schema).to eq(type: "string", description: "Order status")
    end

    it "generates integer schema" do
      param = described_class.new(name: :count, type: :integer)
      expect(param.to_json_schema).to include(type: "integer")
    end

    it "generates boolean schema" do
      param = described_class.new(name: :active, type: :boolean)
      expect(param.to_json_schema).to include(type: "boolean")
    end

    it "includes enum values" do
      param = described_class.new(name: :status, type: :string, enum: %w[pending shipped])
      expect(param.to_json_schema[:enum]).to eq(%w[pending shipped])
    end

    it "includes default value" do
      param = described_class.new(name: :qty, type: :integer, default: 1)
      expect(param.to_json_schema[:default]).to eq(1)
    end

    it "generates array of objects schema" do
      defn = described_class.new(name: :items, type: [:object]) do
        param :product_id, :string, "SKU"
        param :quantity, :integer, "How many"
      end

      schema = defn.to_json_schema
      expect(schema[:type]).to eq("array")
      expect(schema[:items][:type]).to eq("object")
      expect(schema[:items][:properties][:product_id]).to eq(type: "string", description: "SKU")
      expect(schema[:items][:required]).to eq(["product_id", "quantity"])
    end

    it "generates object schema with nested params" do
      defn = described_class.new(name: :address, type: :object) do
        param :street, :string, "Street"
        param :city, :string, "City", optional: true
      end

      schema = defn.to_json_schema
      expect(schema[:type]).to eq("object")
      expect(schema[:properties][:street]).to include(type: "string")
      expect(schema[:required]).to eq(["street"])
    end
  end

  describe "#required?" do
    it "is required by default" do
      param = described_class.new(name: :id, type: :string)
      expect(param).to be_required
    end

    it "is optional when specified" do
      param = described_class.new(name: :id, type: :string, optional: true)
      expect(param).not_to be_required
    end
  end
end
