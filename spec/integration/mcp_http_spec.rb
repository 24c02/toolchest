require_relative "../rails_helper"
require "json"
require "rack/mock"

# Exercises the full MCP-over-HTTP path through Toolchest::RackApp and the mcp
# gem's StreamableHTTPTransport. RackApp overrides private mcp internals
# (call_tool/get_prompt/complete and the @handlers table), so this is the spec
# that catches an mcp version bump changing dispatch or wire shapes.
RSpec.describe "MCP over HTTP" do
  def build_toolbox
    Class.new(Toolchest::Toolbox) do
      def self.name = "ItemsToolbox"

      tool "List items" do
      end
      def index = render text: "hello items"

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

  def build_app(mount_key, auth: :none)
    Toolchest.router(mount_key).register(build_toolbox)
    Toolchest.configuration(mount_key).auth = auth
    yield Toolchest.configuration(mount_key) if block_given?
    Toolchest::RackApp.new(mount_key: mount_key)
  end

  def rpc(app, body, host: "localhost", session: nil, origin: nil, bearer: nil)
    headers = {
      "CONTENT_TYPE" => "application/json",
      "HTTP_ACCEPT" => "application/json, text/event-stream",
      "HTTP_HOST" => host
    }
    headers["HTTP_MCP_SESSION_ID"] = session if session
    headers["HTTP_ORIGIN"] = origin if origin
    headers["HTTP_AUTHORIZATION"] = "Bearer #{bearer}" if bearer
    env = Rack::MockRequest.env_for("/mcp", method: "POST", input: JSON.dump(body), **headers)
    status, response_headers, response_body = app.call(env)
    [status, response_headers, read_body(response_body)]
  end

  # The transport answers with a single JSON object or an SSE stream (a proc
  # body emitting "data: {...}" frames); extract the JSON payload either way.
  def read_body(body)
    chunks = []
    if body.respond_to?(:call)
      stream = Class.new do
        attr_reader :chunks
        def initialize = @chunks = []
        def write(data) = @chunks << data
        def close; end
        def flush; end
      end.new
      body.call(stream)
      chunks = stream.chunks
    else
      body.each { |chunk| chunks << chunk }
    end
    raw = chunks.join
    json = raw.start_with?("data:") ? raw[/data: (.*)/, 1] : raw
    json.nil? || json.empty? ? nil : JSON.parse(json)
  end

  def initialize_session(app, **rpc_opts)
    body = {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "spec", version: "1" } }
    }
    status, headers, payload = rpc(app, body, **rpc_opts)
    [status, headers["mcp-session-id"] || headers["Mcp-Session-Id"], payload]
  end

  after { Toolchest.reset! }

  describe "JSON-RPC methods" do
    let(:app) { build_app(:mcp_http_spec) }

    let(:session_id) do
      status, sid, = initialize_session(app)
      expect(status).to eq(200)
      sid
    end

    def result_of(body)
      status, _, payload = rpc(app, body, session: session_id)
      expect(status).to eq(200)
      expect(payload["error"]).to be_nil, "expected no error, got: #{payload["error"].inspect}"
      payload["result"]
    end

    it "wraps tools/list in a tools object" do
      result = result_of({ jsonrpc: "2.0", id: 2, method: "tools/list" })
      expect(result["tools"].map { |t| t["name"] }).to eq(["items_index"])
    end

    it "dispatches tools/call through the router" do
      result = result_of({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "items_index", arguments: {} } })
      expect(result["isError"]).to be false
      expect(result["content"].first["text"]).to eq("hello items")
    end

    it "wraps prompts/list in a prompts object" do
      result = result_of({ jsonrpc: "2.0", id: 4, method: "prompts/list" })
      expect(result["prompts"].map { |p| p["name"] }).to eq(["debug-item"])
    end

    it "serves prompts/get from the router, not the server's prompt registry" do
      result = result_of({ jsonrpc: "2.0", id: 5, method: "prompts/get", params: { name: "debug-item", arguments: { item_id: "42" } } })
      expect(result["messages"]).to eq([{ "role" => "user", "content" => "Debug item 42" }])
    end

    it "wraps resources/list in a resources object" do
      result = result_of({ jsonrpc: "2.0", id: 6, method: "resources/list" })
      expect(result["resources"].map { |r| r["uri"] }).to eq(["items://schema"])
    end

    it "wraps resources/read contents" do
      result = result_of({ jsonrpc: "2.0", id: 7, method: "resources/read", params: { uri: "items://schema" } })
      expect(result["contents"].first["uri"]).to eq("items://schema")
      expect(JSON.parse(result["contents"].first["text"])).to eq({ "fields" => ["id"] })
    end

    it "serves completion/complete without registered prompts" do
      result = result_of({
        jsonrpc: "2.0", id: 8, method: "completion/complete",
        params: { ref: { type: "ref/prompt", name: "debug-item" }, argument: { name: "item_id", value: "" } }
      })
      expect(result["completion"]).to include("values" => [], "hasMore" => false)
    end
  end

  describe "DNS rebinding protection" do
    it "rejects unknown Host headers when auth is :none" do
      app = build_app(:mcp_dns_none)
      status, _, payload = initialize_session(app, host: "evil.example.com")
      expect(status).to eq(403)
      expect(payload.dig("error", "message")).to match(/Invalid Host/)
    end

    it "accepts loopback hosts when auth is :none" do
      app = build_app(:mcp_dns_loopback)
      status, sid, = initialize_session(app, host: "localhost")
      expect(status).to eq(200)
      expect(sid).not_to be_nil
    end

    it "honors allowed_hosts" do
      app = build_app(:mcp_dns_allowed) { |config| config.allowed_hosts = ["mcp.example.com"] }
      status, = initialize_session(app, host: "mcp.example.com")
      expect(status).to eq(200)
    end

    let(:auth_strategy) do
      Class.new do
        def authenticate(request)
          return nil unless request.get_header("HTTP_AUTHORIZATION") == "Bearer secret"

          Toolchest::AuthContext.new(resource_owner: "u", scopes: [], token: "secret")
        end
      end.new
    end

    it "is disabled by default for bearer-authenticated mounts" do
      app = build_app(:mcp_dns_token, auth: auth_strategy)
      status, = initialize_session(app, host: "prod.example.com", bearer: "secret")
      expect(status).to eq(200)
    end

    it "can be forced on for authenticated mounts" do
      app = build_app(:mcp_dns_forced, auth: auth_strategy) do |config|
        config.dns_rebinding_protection = true
      end
      status, = initialize_session(app, host: "prod.example.com", bearer: "secret")
      expect(status).to eq(403)
    end
  end
end
