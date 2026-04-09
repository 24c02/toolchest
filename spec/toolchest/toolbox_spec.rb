require "spec_helper"

RSpec.describe Toolchest::Toolbox do
  let(:toolbox_class) do
    Class.new(described_class) do
      def self.name = "OrdersToolbox"

      default_param :order_id, :string, "The order ID", except: [:create]

      tool "Look up an order" do
      end
      def show = @order = { id: params[:order_id], status: "shipped" }

      tool "Update order status", name: "modify_order" do
        param :status, :string, "New status", enum: %w[pending confirmed shipped]
        param :tracking, :string, "Tracking number", optional: true
      end
      def update = @order = { id: params[:order_id], status: params[:status] }

      tool "Create a new order" do
        param :customer_id, :string, "Customer"
      end
      def create
        @order = { id: "new", customer: params[:customer_id] }
        suggests :show, "Get the full order"
      end
    end
  end

  describe "tool registration" do
    it "registers tools from the DSL" do
      definitions = toolbox_class.tool_definitions
      expect(definitions.keys).to contain_exactly(:show, :update, :create)
    end

    it "sets tool descriptions" do
      expect(toolbox_class.tool_definitions[:show].description).to eq("Look up an order")
    end

    it "supports custom tool names" do
      expect(toolbox_class.tool_definitions[:update].custom_name).to eq("modify_order")
      expect(toolbox_class.tool_definitions[:update].tool_name).to eq("modify_order")
    end
  end

  describe "default_param" do
    it "merges default params into tools" do
      show_params = toolbox_class.tool_definitions[:show].params
      expect(show_params.map(&:name)).to include(:order_id)
    end

    it "respects except option" do
      create_params = toolbox_class.tool_definitions[:create].params
      expect(create_params.map(&:name)).not_to include(:order_id)
    end

    it "puts default params first" do
      update_params = toolbox_class.tool_definitions[:update].params
      expect(update_params.first.name).to eq(:order_id)
    end
  end

  describe "param schema" do
    it "generates MCP-compatible tool schemas" do
      schema = toolbox_class.tool_definitions[:update].to_mcp_schema
      expect(schema[:name]).to eq("modify_order")
      expect(schema[:inputSchema][:properties][:status][:enum]).to eq(%w[pending confirmed shipped])
      expect(schema[:inputSchema][:required]).to include("order_id", "status")
    end
  end

  describe "dispatch" do
    it "dispatches tool calls" do
      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "123" }, tool_definition: definition)

      # stub render to avoid template lookup
      allow(Toolchest::Renderer).to receive(:render).and_return({ id: "123", status: "shipped" })

      response = toolbox.dispatch(:show)
      expect(response[:isError]).to be false
    end

    it "adds suggests to response" do
      definition = toolbox_class.tool_definitions[:create]
      toolbox = toolbox_class.new(params: { customer_id: "cust_1" }, tool_definition: definition)

      allow(Toolchest::Renderer).to receive(:render).and_return({ id: "new" })

      response = toolbox.dispatch(:create)
      texts = response[:content].map { |c| c[:text] }
      expect(texts.last).to include("orders_show")
    end
  end

  describe "render_error" do
    it "returns MCP error format" do
      toolbox_with_error = Class.new(described_class) do
        def self.name = "ErrorToolbox"

        tool "Fail" do
        end
        def fail_action = render_error "Something went wrong"
      end

      definition = toolbox_with_error.tool_definitions[:fail_action]
      toolbox = toolbox_with_error.new(params: {}, tool_definition: definition)
      response = toolbox.dispatch(:fail_action)

      expect(response[:isError]).to be true
      expect(response[:content].first[:text]).to eq("Something went wrong")
    end
  end

  describe "halt" do
    it "stops execution with throw/catch" do
      toolbox_with_halt = Class.new(described_class) do
        def self.name = "HaltToolbox"

        before_action :check_auth

        tool "Protected" do
        end
        def protected_action = @reached = true

        private

        def check_auth = halt error: "forbidden"
      end

      definition = toolbox_with_halt.tool_definitions[:protected_action]
      toolbox = toolbox_with_halt.new(params: {}, tool_definition: definition)
      response = toolbox.dispatch(:protected_action)

      expect(response[:isError]).to be true
      expect(response[:content].first[:text]).to eq("forbidden")
      expect(toolbox.instance_variable_get(:@reached)).to be_nil
    end
  end

  describe "before_action" do
    it "runs before_action callbacks" do
      toolbox_with_callback = Class.new(described_class) do
        def self.name = "CallbackToolbox"

        before_action :set_thing

        tool "Show thing" do
        end
        def show; end

        private

        def set_thing
          @thing = "hello"
        end
      end

      definition = toolbox_with_callback.tool_definitions[:show]
      toolbox = toolbox_with_callback.new(params: {}, tool_definition: definition)

      allow(Toolchest::Renderer).to receive(:render).and_return({ thing: "hello" })

      toolbox.dispatch(:show)
      expect(toolbox.instance_variable_get(:@thing)).to eq("hello")
    end
  end

  describe "rescue_from" do
    it "catches exceptions with rescue_from" do
      toolbox_with_rescue = Class.new(described_class) do
        def self.name = "RescueToolbox"

        rescue_from StandardError do |e|
          render_error "Caught: #{e.message}"
        end

        tool "Explode" do
        end
        def explode = raise "boom"
      end

      definition = toolbox_with_rescue.tool_definitions[:explode]
      toolbox = toolbox_with_rescue.new(params: {}, tool_definition: definition)
      response = toolbox.dispatch(:explode)

      expect(response[:isError]).to be true
      expect(response[:content].first[:text]).to eq("Caught: boom")
    end
  end

  describe "inheritance" do
    it "inherits tools from parent" do
      parent = Class.new(described_class) do
        def self.name = "BaseToolbox"

        tool "Shared" do
        end
        def shared
        end
      end

      child = Class.new(parent) do
        def self.name = "ChildToolbox"

        tool "Extra" do
        end
        def extra
        end
      end

      expect(child.tool_definitions.keys).to contain_exactly(:shared, :extra)
    end
  end

  describe "resources" do
    it "registers resources on the toolbox" do
      toolbox_with_resources = Class.new(described_class) do
        def self.name = "ResourceToolbox"

        resource "data://schema", name: "Schema", description: "The schema" do
          { fields: ["id", "name"] }
        end
      end

      resources = toolbox_with_resources.resources
      expect(resources.length).to eq(1)
      expect(resources.first[:uri]).to eq("data://schema")
      expect(resources.first[:block].call).to eq(fields: ["id", "name"])
    end
  end

  describe "prompts" do
    it "registers prompts on the toolbox" do
      toolbox_with_prompts = Class.new(described_class) do
        def self.name = "PromptToolbox"

        prompt "debug-thing",
          description: "Debug something",
          arguments: { thing_id: { type: :string, required: true } } do |thing_id:|
          [{ role: "user", content: "Debug #{thing_id}" }]
        end
      end

      prompts = toolbox_with_prompts.prompts
      expect(prompts.length).to eq(1)
      expect(prompts.first[:name]).to eq("debug-thing")
      expect(prompts.first[:block].call(thing_id: "123")).to eq([{ role: "user", content: "Debug 123" }])
    end
  end

  describe "mcp_progress" do
    it "sends progress notification via session" do
      session = double("session")
      expect(session).to receive(:notify_progress).with(
        progress_token: "tok_123",
        progress: 3,
        total: 10,
        message: "Processing",
        related_request_id: "req_1"
      )

      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)

      Toolchest::Current.set(
        mcp_session: session,
        mcp_progress_token: "tok_123",
        mcp_request_id: "req_1"
      ) do
        toolbox.mcp_progress(3, total: 10, message: "Processing")
      end
    end

    it "is a no-op without a session" do
      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)
      # should not raise
      toolbox.mcp_progress(1, total: 5)
    end

    it "is a no-op without a progress token" do
      session = double("session")

      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)

      Toolchest::Current.set(mcp_session: session) do
        # no progress token — should not call send_notification
        toolbox.mcp_progress(1, total: 5)
      end
    end
  end

  describe "mcp_sample" do
    let(:session) { double("session") }

    it "sends a simple prompt and returns text" do
      expect(session).to receive(:create_sampling_message).with(
        messages: [{ role: "user", content: { type: "text", text: "Summarize this" } }],
        related_request_id: "req_1",
        max_tokens: 1024
      ).and_return({ content: { type: "text", text: "Here's the summary" } })

      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)

      result = Toolchest::Current.set(mcp_session: session, mcp_request_id: "req_1") do
        toolbox.mcp_sample("Summarize this")
      end

      expect(result).to eq("Here's the summary")
    end

    it "appends context to prompt" do
      expect(session).to receive(:create_sampling_message).with(
        messages: [{ role: "user", content: { type: "text", text: "Summarize\n\n{\"id\":1}" } }],
        related_request_id: nil,
        max_tokens: 1024
      ).and_return({ content: { type: "text", text: "done" } })

      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)

      result = Toolchest::Current.set(mcp_session: session) do
        toolbox.mcp_sample("Summarize", context: '{"id":1}')
      end

      expect(result).to eq("done")
    end

    it "supports block form" do
      expect(session).to receive(:create_sampling_message).with(
        messages: [{ role: "user", content: { type: "text", text: "Analyze this" } }],
        related_request_id: nil,
        max_tokens: 500,
        system_prompt: "You are an analyst",
        temperature: 0.3
      ).and_return({ content: { type: "text", text: "Analysis complete" } })

      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)

      result = Toolchest::Current.set(mcp_session: session) do
        toolbox.mcp_sample do |s|
          s.system "You are an analyst"
          s.user "Analyze this"
          s.max_tokens 500
          s.temperature 0.3
        end
      end

      expect(result).to eq("Analysis complete")
    end

    it "raises without a session" do
      definition = toolbox_class.tool_definitions[:show]
      toolbox = toolbox_class.new(params: { order_id: "1" }, tool_definition: definition)

      expect { toolbox.mcp_sample("test") }.to raise_error(
        Toolchest::Error, /Sampling requires an MCP client/
      )
    end
  end
end
