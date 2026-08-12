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

  describe "#resolved_annotations" do
    it "derives readOnlyHint from access: :read" do
      td = described_class.new(
        method_name: :show, description: "test", params: [],
        toolbox_class: toolbox_class, access_level: :read
      )
      expect(td.resolved_annotations).to eq(readOnlyHint: true, destructiveHint: false)
    end

    it "derives destructiveHint from access: :write" do
      td = described_class.new(
        method_name: :destroy, description: "test", params: [],
        toolbox_class: toolbox_class, access_level: :write
      )
      expect(td.resolved_annotations).to eq(readOnlyHint: false, destructiveHint: true)
    end

    it "returns empty hash when no access level" do
      expect(definition.resolved_annotations).to eq({})
    end

    it "merges explicit annotations with derived ones" do
      td = described_class.new(
        method_name: :export, description: "test", params: [],
        toolbox_class: toolbox_class, access_level: :read,
        annotations: { openWorldHint: true }
      )
      expect(td.resolved_annotations).to eq(readOnlyHint: true, destructiveHint: false, openWorldHint: true)
    end

    it "allows explicit annotations to override derived ones" do
      td = described_class.new(
        method_name: :update, description: "test", params: [],
        toolbox_class: toolbox_class, access_level: :write,
        annotations: { destructiveHint: false }
      )
      expect(td.resolved_annotations[:destructiveHint]).to be false
    end
  end

  describe "#to_mcp_schema annotations" do
    it "includes annotations when access level is set" do
      td = described_class.new(
        method_name: :show, description: "test", params: [],
        toolbox_class: toolbox_class, access_level: :read
      )
      expect(td.to_mcp_schema[:annotations]).to eq(readOnlyHint: true, destructiveHint: false)
    end

    it "omits annotations when empty" do
      expect(definition.to_mcp_schema).not_to have_key(:annotations)
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

  describe "#title" do
    it "defaults to nil" do
      expect(definition.title).to be_nil
    end

    it "includes title in schema when set" do
      td = described_class.new(
        method_name: :show,
        description: "Look up an order",
        params: params,
        toolbox_class: toolbox_class,
        title: "Show Order"
      )
      schema = td.to_mcp_schema
      expect(schema[:title]).to eq("Show Order")
    end

    it "omits title from schema when nil" do
      schema = definition.to_mcp_schema
      expect(schema).not_to have_key(:title)
    end
  end

  describe "#output_schema" do
    it "defaults to nil" do
      expect(definition.output_schema).to be_nil
    end

    it "includes output schema when set" do
      td = described_class.new(
        method_name: :show,
        description: "Look up an order",
        params: params,
        toolbox_class: toolbox_class,
        output_schema: { type: "object", properties: { id: { type: "string" } } }
      )
      schema = td.to_mcp_schema
      expect(schema[:outputSchema]).to eq(type: "object", properties: { id: { type: "string" } })
    end

    it "omits output schema when nil" do
      schema = definition.to_mcp_schema
      expect(schema).not_to have_key(:outputSchema)
    end
  end
end
