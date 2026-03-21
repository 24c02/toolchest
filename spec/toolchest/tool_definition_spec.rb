require "spec_helper"

RSpec.describe Toolchest::ToolDefinition do
  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "OrdersToolbox"
    end
  end

  let(:params) do
    [
      Toolchest::ParamDefinition.new(name: :order_id, type: :string, description: "The order ID"),
      Toolchest::ParamDefinition.new(name: :status, type: :string, description: "Filter", optional: true,
                                     enum: %w[pending shipped])
    ]
  end

  let(:definition) do
    described_class.new(
      method_name: :show,
      description: "Look up an order",
      params: params,
      toolbox_class: toolbox_class
    )
  end

  describe "#tool_name" do
    it "generates underscored name by default" do
      expect(definition.tool_name(:underscored)).to eq("orders_show")
    end

    it "generates dotted name" do
      expect(definition.tool_name(:dotted)).to eq("orders.show")
    end

    it "uses custom name when set" do
      custom = described_class.new(
        method_name: :show, description: "test", params: [],
        toolbox_class: toolbox_class, custom_name: "get_order"
      )
      expect(custom.tool_name).to eq("get_order")
    end
  end

  describe "#to_mcp_schema" do
    it "returns valid MCP tool schema" do
      schema = definition.to_mcp_schema(:underscored)

      expect(schema[:name]).to eq("orders_show")
      expect(schema[:description]).to eq("Look up an order")
      expect(schema[:inputSchema][:type]).to eq("object")
      expect(schema[:inputSchema][:properties][:order_id]).to include(type: "string")
      expect(schema[:inputSchema][:required]).to eq(["order_id"])
    end
  end

  describe "#input_schema" do
    it "marks required params" do
      schema = definition.input_schema
      expect(schema[:required]).to eq(["order_id"])
    end

    it "includes all params in properties" do
      schema = definition.input_schema
      expect(schema[:properties].keys).to contain_exactly(:order_id, :status)
    end
  end
end
