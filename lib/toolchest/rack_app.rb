module Toolchest
  class RackApp
    attr_reader :mount_key

    def initialize(mount_key: :default)
      @mount_key = mount_key.to_sym
      @server = build_mcp_server
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(@server)
      @server.transport = @transport
      install_handlers!
    end

    def call(env)
      request = Rack::Request.new(env)
      env["toolchest.mount_key"] ||= @mount_key.to_s

      auth = authenticate(request)

      if auth.nil? && config.auth == :oauth
        mount_path = config.mount_path || "/mcp"
        resource_metadata = "#{request.base_url}/.well-known/oauth-protected-resource#{mount_path}"
        return [401, {
          "WWW-Authenticate" => %(Bearer resource_metadata="#{resource_metadata}"),
          "Content-Type" => "application/json"
        }, ['{"error":"unauthorized"}']]
      end

      Toolchest::Current.set(auth: auth, mount_key: @mount_key.to_s) do
        status, headers, body = @transport.handle_request(request)
        [status, headers.dup, body]
      end
    end

    private

    def config = Toolchest.configuration(@mount_key)

    def build_mcp_server
      opts = {
        name: config.resolved_server_name,
        version: config.server_version,
        capabilities: {
          tools: { listChanged: true },
          prompts: { listChanged: true },
          resources: { listChanged: true },
          logging: {},
          completions: {}
        }
      }

      opts[:description] = config.server_description if config.server_description
      opts[:instructions] = config.server_instructions if config.server_instructions

      MCP::Server.new(**opts)
    end

    def install_handlers!
      router = Toolchest.router(@mount_key)
      server = @server

      router.mcp_server = server

      handlers = server.instance_variable_get(:@handlers)

      handlers[MCP::Methods::TOOLS_LIST] = ->(params) { router.tools_for_handler }
      handlers[MCP::Methods::RESOURCES_LIST] = ->(params) { router.resources_for_handler }
      handlers[MCP::Methods::RESOURCES_READ] = ->(params) { router.resources_read_response(params) }
      handlers[MCP::Methods::RESOURCES_TEMPLATES_LIST] = ->(params) { router.resource_templates_for_handler }
      handlers[MCP::Methods::PROMPTS_LIST] = ->(params) { router.prompts_for_handler }
      handlers[MCP::Methods::PROMPTS_GET] = ->(params) { router.prompts_get_response(params) }

      # tools/call is hardcoded in handle_request to call private call_tool
      server.define_singleton_method(:call_tool) do |params, **_kwargs|
        router.dispatch_response(params)
      end

      # completion/complete is hardcoded to call private complete, which validates
      # against registered prompts/resources (we don't register any). override it.
      server.define_singleton_method(:complete) do |params|
        arg_name = params.dig(:argument, :name) || params.dig(:argument, "name")
        values = arg_name ? router.completion_values(arg_name) : []
        { completion: { values: values, hasMore: false } }
      end
    end

    def authenticate(request)
      strategy = case config.auth
      when :none then Auth::None.new
      when :token then Auth::Token.new
      when :oauth then Auth::OAuth.new(@mount_key)
      else config.auth
      end

      strategy.authenticate(request)
    end
  end
end
