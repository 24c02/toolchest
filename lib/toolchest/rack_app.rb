module Toolchest
  class RackApp
    attr_reader :mount_key

    def initialize(mount_key: :default)
      @mount_key = mount_key.to_sym
      @server = build_mcp_server
      @transport = build_transport
      @server.transport = @transport
      install_handlers!
    end

    def call(env)
      request = Rack::Request.new(env)
      env["toolchest.mount_key"] ||= @mount_key.to_s

      auth = authenticate(request)

      if auth.nil? && config.auth != :none
        mount_path = config.mount_path || "/mcp"
        resource_metadata = "#{request.base_url}/.well-known/oauth-protected-resource#{mount_path}"
        return [401, {
          "WWW-Authenticate" => %(Bearer resource_metadata="#{resource_metadata}"),
          "Content-Type" => "application/json"
        }, ['{"error":"unauthorized"}']]
      end

      Toolchest::Current.set(auth: auth, mount_key: @mount_key.to_s) do
        status, headers, body = @transport.handle_request(request)
        # The transport may return a streaming body (proc) that executes after
        # Current.set unwinds. Wrap it to restore Current for the duration.
        wrapped_body = if body.respond_to?(:call)
          captured_auth = auth
          captured_mount = @mount_key.to_s
          proc { |stream|
            Toolchest::Current.set(auth: captured_auth, mount_key: captured_mount) do
              body.call(stream)
            end
          }
        else
          body
        end
        [status, headers.dup, wrapped_body]
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

    def build_transport
      protection = case config.dns_rebinding_protection
      when :auto then config.auth == :none
      else config.dns_rebinding_protection
      end

      MCP::Server::Transports::StreamableHTTPTransport.new(
        @server,
        allowed_hosts: config.allowed_hosts,
        allowed_origins: config.allowed_origins,
        dns_rebinding_protection: protection
      )
    end

    def install_handlers!
      router = Toolchest.router(@mount_key)
      server = @server

      router.mcp_server = server

      handlers = server.instance_variable_get(:@handlers)

      # Since mcp 0.15, list handlers return the full result object (the server
      # no longer wraps them in { tools: ... } etc.). resources/read is the
      # exception: its handler result still becomes `contents`.
      handlers[MCP::Methods::TOOLS_LIST] = ->(params) { { tools: router.tools_for_handler } }
      handlers[MCP::Methods::RESOURCES_LIST] = ->(params) { { resources: router.resources_for_handler } }
      handlers[MCP::Methods::RESOURCES_READ] = ->(params) { router.resources_read_response(params) }
      handlers[MCP::Methods::RESOURCES_TEMPLATES_LIST] = ->(params) { { resourceTemplates: router.resource_templates_for_handler } }
      handlers[MCP::Methods::PROMPTS_LIST] = ->(params) { { prompts: router.prompts_for_handler } }

      # tools/call, prompts/get, and completion/complete are hardcoded in
      # handle_request to call these private methods (bypassing @handlers),
      # so they must be overridden as singleton methods.
      server.define_singleton_method(:call_tool) do |params, session: nil, related_request_id: nil, cancellation: nil|
        progress_token = params.dig(:_meta, :progressToken)
        Toolchest::Current.mcp_session = session
        Toolchest::Current.mcp_request_id = related_request_id
        Toolchest::Current.mcp_progress_token = progress_token
        router.dispatch_response(params)
      end

      server.define_singleton_method(:get_prompt) do |params, session: nil, related_request_id: nil, cancellation: nil|
        router.prompts_get_response(params)
      end

      # the stock complete validates against registered prompts/resources
      # (we don't register any), so replace it wholesale.
      server.define_singleton_method(:complete) do |params, session: nil, related_request_id: nil, cancellation: nil|
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
