require "spec_helper"

RSpec.describe Toolchest::Router do
  let(:router) { described_class.new }

  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "ItemsToolbox"

      tool "List items" do
      end
      def index = render_error "not implemented"

      tool "Show an item" do
        param :item_id, :string, "Item ID"
      end
      def show = render_error "not implemented"

      resource "items://schema", name: "Items Schema", description: "Schema" do
        { fields: ["id"] }
      end

      prompt "debug-item",
        description: "Debug an item",
        arguments: { item_id: { type: :string, required: true } } do |item_id:|
        [{ role: "user", content: "Debug item #{item_id}" }]
      end
    end
  end

  before { router.register(toolbox_class) }

  describe "#register" do
    it "raises on duplicate tool names from different toolboxes" do
      other_class = Class.new(Toolchest::Toolbox) do
        def self.name = "ItemsToolbox"

        tool "Conflicting index" do
        end
        def index = render text: "conflict"
      end

      expect { router.register(other_class) }.to raise_error(
        Toolchest::Error, /Duplicate tool name 'items_index'/
      )
    end
  end

  describe "#tools_for_handler" do
    it "returns MCP-formatted tools list" do
      tools = router.tools_for_handler

      expect(tools.length).to eq(2)
      names = tools.map { |t| t[:name] }
      expect(names).to contain_exactly("items_index", "items_show")
    end
  end

  describe "#dispatch" do
    it "dispatches to the right toolbox action" do
      response = router.dispatch("items_index", {})
      expect(response[:isError]).to be true
      expect(response[:content].first[:text]).to eq("not implemented")
    end

    it "returns error for unknown tools" do
      response = router.dispatch("nonexistent_tool", {})
      expect(response[:isError]).to be true
      expect(response[:content].first[:text]).to include("Unknown tool")
    end
  end

  describe "#resources_for_handler" do
    it "lists non-template resources" do
      resources = router.resources_for_handler
      expect(resources.length).to eq(1)
      expect(resources.first[:name]).to eq("Items Schema")
    end
  end

  describe "#resources_read" do
    it "reads a static resource" do
      result = router.resources_read("items://schema")
      expect(JSON.parse(result.first[:text])).to eq("fields" => ["id"])
    end
  end

  describe "#prompts_for_handler" do
    it "lists prompts" do
      prompts = router.prompts_for_handler
      expect(prompts.length).to eq(1)
      expect(prompts.first[:name]).to eq("debug-item")
    end
  end

  describe "#prompts_get" do
    it "executes a prompt" do
      result = router.prompts_get("debug-item", { item_id: "42" })
      expect(result[:messages].first[:content]).to eq("Debug item 42")
    end
  end
end
