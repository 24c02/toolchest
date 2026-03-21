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
        @transport.handle_request(request)
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

      server.tools_list_handler { |_params| router.tools_for_handler }
      server.tools_call_handler { |params| router.dispatch_response(params) }
      server.resources_list_handler { |_params| router.resources_for_handler }
      server.resources_read_handler { |params| router.resources_read_response(params) }
      server.resources_templates_list_handler { |_params| router.resource_templates_for_handler }
      server.prompts_list_handler { |_params| router.prompts_for_handler }
      server.prompts_get_handler { |params| router.prompts_get_response(params) }

      handlers = server.instance_variable_get(:@handlers)
      handlers["completion/complete"] = ->(params) {
        arg_name = (params["argument"] || params[:argument] || {})["name"]
        values = arg_name ? router.completion_values(arg_name) : []
        { completion: { values: values, hasMore: false } }
      }
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
