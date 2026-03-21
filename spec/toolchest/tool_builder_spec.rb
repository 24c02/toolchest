require "spec_helper"

RSpec.describe Toolchest::ToolBuilder do
  let(:builder) { described_class.new }

  describe "#param" do
    it "starts with no params" do
      expect(builder.params).to be_empty
    end

    it "adds a simple param" do
      builder.param(:name, :string, "The name")
      expect(builder.params.length).to eq(1)
      expect(builder.params.first.name).to eq(:name)
      expect(builder.params.first.type).to eq(:string)
    end

    it "adds multiple params" do
      builder.param(:name, :string, "Name")
      builder.param(:count, :integer, "Count")
      expect(builder.params.length).to eq(2)
    end

    it "passes optional flag" do
      builder.param(:note, :string, "Note", optional: true)
      expect(builder.params.first).not_to be_required
    end

    it "passes enum values" do
      builder.param(:status, :string, "Status", enum: %w[a b c])
      expect(builder.params.first.enum).to eq(%w[a b c])
    end

    it "passes default value" do
      builder.param(:qty, :integer, "Qty", default: 1)
      expect(builder.params.first.default).to eq(1)
    end

    it "passes nested block for object params" do
      builder.param(:address, :object, "Address") do
        param :street, :string, "Street"
      end
      schema = builder.params.first.to_json_schema
      expect(schema[:type]).to eq("object")
      expect(schema[:properties][:street]).to include(type: "string")
    end
  end
end
