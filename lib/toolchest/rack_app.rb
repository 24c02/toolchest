module Toolchest
  class RackApp
    attr_reader :mount_key

    def initialize(mount_key: :default)
      @mount_key = mount_key.to_sym
      @server = build_mcp_server
      # Transport auto-sets server.transport via super(server)
      @transport = MCP::Server::Transports::StreamableHTTPTransport.new(@server, **config.transport_options)
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
      router = Toolchest.router(@mount_key)

      opts = {
        name: config.resolved_server_name,
        version: config.server_version,
        tools: build_mcp_tools(router),
        prompts: build_mcp_prompts(router),
        resources: build_mcp_resources(router),
        resource_templates: build_mcp_resource_templates(router),
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
      opts[:page_size] = config.page_size if config.page_size
      opts[:ttl_ms] = config.cache_ttl if config.cache_ttl
      opts[:cache_scope] = config.cache_scope if config.cache_scope

      server = MCP::Server.new(**opts)
      router.mcp_server = server
      install_custom_handlers!(server, router)
      server
    end

    # Wire handlers that need custom dispatch logic:
    # - tools/list: scope filtering based on current auth
    # - resources/read: delegates to our router's resource lookup
    # - completion/complete: delegates to our router's enum completion
    def install_custom_handlers!(server, router)
      # tools/list goes through the handler hash (else branch in dispatch),
      # so overriding it gives us scope-filtered listing.
      server.instance_variable_get(:@handlers)[MCP::Methods::TOOLS_LIST] = ->(params) {
        { tools: router.tools_for_handler }
      }

      # resources/read has a public setter — use it
      server.resources_read_handler do |params|
        router.resources_read_response(params)
      end

      # completion/complete has a public setter — use it
      server.completion_handler do |params|
        arg_name = params.dig(:argument, :name) || params.dig(:argument, "name")
        values = arg_name ? router.completion_values(arg_name) : []
        { completion: { values: values, hasMore: false } }
      end
    end

    # --- Tool bridge ---
    # Build an MCP::Tool subclass for each Toolchest::ToolDefinition.
    # The tool's .call sets up Current context and delegates to Router#dispatch.

    def build_mcp_tools(router)
      naming = config.tool_naming
      router.toolbox_classes.flat_map { |klass|
        klass.tool_definitions.values.map { |td|
          build_mcp_tool(td, router, naming)
        }
      }
    end

    def build_mcp_tool(td, router, naming)
      tn = td.tool_name(naming)
      desc = td.description
      schema = td.input_schema
      hints = td.resolved_annotations
      r = router

      Class.new(MCP::Tool) do
        tool_name tn
        description desc
        input_schema schema

        if hints.any?
          annotations({
            read_only_hint: hints[:readOnlyHint],
            destructive_hint: hints[:destructiveHint],
            idempotent_hint: hints[:idempotentHint],
            open_world_hint: hints[:openWorldHint],
          }.compact)
        end

        define_singleton_method(:call) do |server_context: nil, **args|
          Toolchest::Current.mcp_server_context = server_context
          response = r.dispatch(tn, args)
          MCP::Tool::Response.new(response[:content], error: response[:isError] || false)
        end
      end
    end

    # --- Prompt bridge ---
    # Build an MCP::Prompt subclass for each prompt defined in toolboxes.
    # The prompt's .template delegates to Router#prompts_get.

    def build_mcp_prompts(router)
      router.toolbox_classes.flat_map { |klass|
        klass.prompts.map { |p| build_mcp_prompt(p, router) }
      }
    end

    def build_mcp_prompt(pdef, router)
      pn = pdef[:name]
      desc = pdef[:description]
      args_list = (pdef[:arguments] || {}).map { |name, opts|
        MCP::Prompt::Argument.new(
          name: name.to_s,
          description: opts[:description],
          required: opts[:required] || false
        )
      }
      r = router

      Class.new(MCP::Prompt) do
        prompt_name pn
        description desc
        arguments args_list

        define_singleton_method(:template) do |args, server_context: nil|
          Toolchest::Current.mcp_server_context = server_context
          r.prompts_get(pn, args || {})
        end
      end
    end

    # --- Resource bridge ---
    # Create MCP::Resource instances for listing (reads go through resources_read_handler).

    def build_mcp_resources(router)
      router.toolbox_classes.flat_map(&:resources)
        .reject { |r| r[:template] }
        .map { |r| MCP::Resource.new(uri: r[:uri], name: r[:name], description: r[:description]) }
    end

    def build_mcp_resource_templates(router)
      router.toolbox_classes.flat_map(&:resources)
        .select { |r| r[:template] }
        .map { |r| MCP::ResourceTemplate.new(uri_template: r[:uri], name: r[:name], description: r[:description]) }
    end

    # --- Auth ---

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
