require "spec_helper"
require "rack/test"
require "json"
require "mcp"

# Integration test: boots a real Toolchest::RackApp backed by MCP 1.x,
# sends actual JSON-RPC requests, and verifies protocol-correct responses.

RSpec.describe "MCP protocol integration", type: :integration do
  include Rack::Test::Methods

  let(:toolbox_class) do
    Class.new(Toolchest::Toolbox) do
      def self.name = "WidgetsToolbox"

      tool "List widgets", title: "List All Widgets", access: :read do
      end
      def index
        render json: [{ id: "w1", name: "Sprocket" }, { id: "w2", name: "Cog" }]
      end

      tool "Get a widget", access: :read do
        param :widget_id, :string, "Widget ID"
      end
      def show
        render json: { id: params[:widget_id], name: "Sprocket" }
      end

      tool "Create a widget", access: :write, output: { type: "object", properties: { id: { type: "string" } } } do
        param :name, :string, "Widget name"
      end
      def create
        render json: { id: "w3", name: params[:name] }
      end

      resource "widgets://schema", name: "Widget Schema", title: "Schema", description: "The widget schema" do
        { fields: %w[id name] }
      end

      resource "widgets://items/{id}", name: "Widget", description: "A single widget" do |id:|
        { id: id, name: "Widget #{id}" }
      end

      prompt "debug-widget",
        title: "Debug Widget",
        description: "Debug a widget",
        arguments: { widget_id: { description: "Widget ID", required: true } } do |widget_id:|
        [{ role: "user", content: { type: "text", text: "Debug widget #{widget_id}" } }]
      end
    end
  end

  let(:app) do
    Toolchest.configure do |c|
      c.auth = :none
      c.dns_rebinding_protection = false
    end
    Toolchest.router(:default).register(toolbox_class)

    Toolchest::RackApp.new(mount_key: :default)
  end

  def jsonrpc(method, params = nil, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method }
    body[:params] = params if params
    body
  end

  def post_rpc(method, params = nil, id: 1)
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    post "/", jsonrpc(method, params, id: id).to_json
  end

  def init_session!
    post_rpc("initialize", {
      protocolVersion: "2025-11-25",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0" }
    })
    expect(last_response.status).to eq(200)

    # Extract session ID from response header
    @session_id = last_response.headers["mcp-session-id"] || last_response.headers["Mcp-Session-Id"]

    # Send initialized notification
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    header "Mcp-Session-Id", @session_id if @session_id
    post "/", { jsonrpc: "2.0", method: "notifications/initialized" }.to_json
  end

  def post_rpc_with_session(method, params = nil, id: 2)
    header "Content-Type", "application/json"
    header "Accept", "application/json, text/event-stream"
    header "Mcp-Session-Id", @session_id if @session_id
    post "/", jsonrpc(method, params, id: id).to_json
  end

  def parse_sse_result(response_body)
    # SSE responses contain "event: message\ndata: {...}\n\n"
    # Extract the JSON data from the last message event
    events = response_body.scan(/^data: (.+)$/m)
    return nil if events.empty?

    results = events.map { |e| JSON.parse(e[0], symbolize_names: true) }
    results.last
  end

  def extract_result(response)
    if response.content_type&.include?("text/event-stream")
      msg = parse_sse_result(response.body)
      msg&.dig(:result)
    else
      JSON.parse(response.body, symbolize_names: true)[:result]
    end
  end

  # --- Protocol handshake ---

  describe "initialize" do
    it "negotiates protocol version and returns capabilities" do
      post_rpc("initialize", {
        protocolVersion: "2025-11-25",
        capabilities: {},
        clientInfo: { name: "test-client", version: "1.0" }
      })

      expect(last_response.status).to eq(200)
      result = extract_result(last_response)
      expect(result[:protocolVersion]).to be_a(String)
      expect(result[:capabilities]).to include(:tools, :prompts, :resources)
      expect(result.dig(:serverInfo, :name)).to be_a(String)
    end
  end

  # --- Tools ---

  describe "tools/list" do
    before { init_session! }

    it "lists all registered tools with names and descriptions" do
      post_rpc_with_session("tools/list")

      result = extract_result(last_response)
      tools = result[:tools]
      expect(tools).to be_an(Array)

      names = tools.map { |t| t[:name] }
      expect(names).to include("widgets_index", "widgets_show", "widgets_create")

      index_tool = tools.find { |t| t[:name] == "widgets_index" }
      expect(index_tool[:description]).to eq("List widgets")
    end
  end

  describe "tools/call" do
    before { init_session! }

    it "calls a tool and returns content" do
      post_rpc_with_session("tools/call", {
        name: "widgets_show",
        arguments: { widget_id: "w1" }
      })

      result = extract_result(last_response)
      expect(result[:isError]).to be_falsey
      text = result[:content].first[:text]
      parsed = JSON.parse(text)
      expect(parsed["id"]).to eq("w1")
    end

    it "returns error for unknown tool" do
      post_rpc_with_session("tools/call", {
        name: "nonexistent",
        arguments: {}
      })

      # MCP SDK returns a protocol error for unknown tools
      body = last_response.body
      expect(body).to include("not found").or include("Unknown tool").or include("error")
    end
  end

  # --- Resources ---

  describe "resources/list" do
    before { init_session! }

    it "lists non-template resources" do
      post_rpc_with_session("resources/list")

      result = extract_result(last_response)
      resources = result[:resources]
      expect(resources).to be_an(Array)
      expect(resources.any? { |r| r[:name] == "Widget Schema" }).to be true
    end
  end

  describe "resources/read" do
    before { init_session! }

    it "reads a static resource" do
      post_rpc_with_session("resources/read", { uri: "widgets://schema" })

      result = extract_result(last_response)
      contents = result[:contents]
      expect(contents).to be_an(Array)
      text = contents.first[:text]
      parsed = JSON.parse(text)
      expect(parsed["fields"]).to eq(%w[id name])
    end

    it "reads a templated resource" do
      post_rpc_with_session("resources/read", { uri: "widgets://items/42" })

      result = extract_result(last_response)
      contents = result[:contents]
      text = contents.first[:text]
      parsed = JSON.parse(text)
      expect(parsed["id"]).to eq("42")
    end
  end

  # --- Prompts ---

  describe "prompts/list" do
    before { init_session! }

    it "lists registered prompts" do
      post_rpc_with_session("prompts/list")

      result = extract_result(last_response)
      prompts = result[:prompts]
      expect(prompts).to be_an(Array)
      expect(prompts.first[:name]).to eq("debug-widget")
      expect(prompts.first[:description]).to eq("Debug a widget")
    end
  end

  describe "prompts/get" do
    before { init_session! }

    it "executes a prompt with arguments" do
      post_rpc_with_session("prompts/get", {
        name: "debug-widget",
        arguments: { widget_id: "w1" }
      })

      result = extract_result(last_response)
      messages = result[:messages]
      expect(messages).to be_an(Array)
      expect(messages.first[:content]).to include("Debug widget w1").or include(text: "Debug widget w1")
    end
  end

  # --- Completion ---

  describe "completion/complete" do
    let(:toolbox_with_enum) do
      Class.new(Toolchest::Toolbox) do
        def self.name = "StatusToolbox"

        tool "Update status" do
          param :status, :string, "Status", enum: %w[pending shipped delivered]
        end
        def update = render_error "stub"
      end
    end

    it "returns completion values for enum params" do
      Toolchest.router(:default).register(toolbox_with_enum)
      init_session!

      post_rpc_with_session("completion/complete", {
        ref: { type: "ref/prompt", name: "debug-widget" },
        argument: { name: "status", value: "" }
      })

      result = extract_result(last_response)
      expect(result[:completion]).to be_a(Hash)
      expect(result[:completion][:values]).to include("pending", "shipped", "delivered")
    end
  end

  # --- Ping ---

  describe "ping" do
    before { init_session! }

    it "responds to ping" do
      post_rpc_with_session("ping")
      result = extract_result(last_response)
      expect(result).to eq({})
    end
  end
end
