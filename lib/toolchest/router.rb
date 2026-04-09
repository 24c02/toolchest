module Toolchest
  class Router
    attr_accessor :mcp_server, :rack_app

    def initialize(mount_key: :default)
      @mount_key = mount_key.to_sym
      @tool_map = {}
      @toolbox_classes = []
      @mcp_server = nil
      @rack_app = nil
    end

    def register(toolbox_class)
      @toolbox_classes << toolbox_class unless @toolbox_classes.include?(toolbox_class)
      rebuild_tool_map!
    end

    def toolbox_classes = @toolbox_classes

    def tools_list = tool_definitions.map { |td| td.to_mcp_schema }

    # For the MCP SDK handler — returns array (SDK wraps it)
    def tools_for_handler
      config = Toolchest.configuration(@mount_key)

      unless config.filter_tools_by_scope
        return tools_list
      end

      auth = Toolchest::Current.auth

      # No auth: show all tools for :none, show nothing otherwise
      unless auth
        return config.auth == :none ? tools_list : []
      end

      scopes = extract_scopes(auth)

      # Auth present but no scopes extractable: fail closed
      unless scopes
        return []
      end

      tool_definitions.select { |td| tool_allowed_by_scopes?(td, scopes) }
                      .map { |td| td.to_mcp_schema }
    end

    def dispatch(tool_name, arguments = {})
      definition = find_tool(tool_name)
      unless definition
        return { content: [{ type: "text", text: "Unknown tool: #{tool_name}" }], isError: true }
      end

      config = Toolchest.configuration(@mount_key)
      if config.filter_tools_by_scope
        auth = Toolchest::Current.auth
        scopes = auth ? extract_scopes(auth) : nil
        if config.auth != :none && (!scopes || !tool_allowed_by_scopes?(definition, scopes))
          return { content: [{ type: "text", text: "Forbidden: insufficient scope" }], isError: true }
        end
      end

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      auth = Toolchest::Current.auth
      token_hint = extract_token_hint(auth)

      log_request_start(definition, arguments, token_hint)

      toolbox = definition.toolbox_class.new(
        params: arguments,
        tool_definition: definition
      )
      response = toolbox.dispatch(definition.method_name)

      duration = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(1)
      log_request_complete(definition, response, duration)

      response
    end

    def dispatch_response(params)
      name = params[:name] || params["name"]
      arguments = params[:arguments] || params["arguments"] || {}
      dispatch(name, arguments)
    end

    def resources_list = @toolbox_classes.flat_map(&:resources).reject { |r| r[:template] }

    def resources_for_handler
      resources_list.map { |r|
        { uri: r[:uri], name: r[:name], description: r[:description] }.compact
      }
    end

    def resource_templates_for_handler
      @toolbox_classes.flat_map(&:resources).select { |r| r[:template] }.map { |r|
        { uriTemplate: r[:uri], name: r[:name], description: r[:description] }.compact
      }
    end

    def resources_read(uri)
      resource = @toolbox_classes.flat_map(&:resources).find { |r|
        if r[:template]
          pattern = r[:uri].gsub(/\{[^}]+\}/, "([^/]+)")
          uri.match?(Regexp.new("^#{pattern}$"))
        else
          r[:uri] == uri
        end
      }

      unless resource
        return [{ uri: uri, mimeType: "text/plain", text: "Resource not found: #{uri}" }]
      end

      result = if resource[:template]
        pattern = resource[:uri].gsub(/\{([^}]+)\}/, '(?<\1>[^/]+)')
        match = uri.match(Regexp.new("^#{pattern}$"))
        kwargs = match.named_captures.transform_keys(&:to_sym)
        resource[:block].call(**kwargs)
      else
        resource[:block].call
      end

      [{ uri: uri, mimeType: "application/json", text: result.to_json }]
    end

    def resources_read_response(params)
      uri = params[:uri] || params["uri"]
      resources_read(uri)
    end

    def prompts_list = @toolbox_classes.flat_map(&:prompts)

    def prompts_for_handler
      prompts_list.map { |p|
        prompt = { name: p[:name], description: p[:description] }.compact
        if p[:arguments].any?
          prompt[:arguments] = p[:arguments].map { |name, opts|
            arg = { name: name.to_s }
            arg[:description] = opts[:description] if opts[:description]
            arg[:required] = opts[:required] if opts.key?(:required)
            arg
          }
        end
        prompt
      }
    end

    def prompts_get(name, arguments = {})
      prompt = prompts_list.find { |p| p[:name] == name }
      return { messages: [] } unless prompt

      kwargs = arguments.transform_keys(&:to_sym)
      messages = prompt[:block].call(**kwargs)
      { messages: messages }
    end

    def prompts_get_response(params)
      name = params[:name] || params["name"]
      arguments = params[:arguments] || params["arguments"] || {}
      prompts_get(name, arguments)
    end

    def completion_values(argument_name)
      tool_definitions.flat_map(&:params)
        .select { |p| p.name.to_s == argument_name.to_s && p.enum }
        .flat_map(&:enum)
        .uniq
    end

    def notify_log(level:, message:)
      return unless @mcp_server
      @mcp_server.notify_log_message(
        data: message,
        level: level,
        logger: "Toolchest"
      )
    end

    private

    def tool_definitions = @toolbox_classes.flat_map { |klass| klass.tool_definitions.values }

    def find_tool(tool_name)
      rebuild_tool_map! if @tool_map.empty? && @toolbox_classes.any?
      @tool_map[tool_name]
    end

    def rebuild_tool_map!
      @tool_map = {}
      tool_definitions.each do |td|
        if @tool_map.key?(td.tool_name) && @tool_map[td.tool_name].toolbox_class != td.toolbox_class
          existing = @tool_map[td.tool_name].toolbox_class.name
          raise Toolchest::Error,
            "Duplicate tool name '#{td.tool_name}' in #{td.toolbox_class.name} " \
            "(already defined in #{existing})"
        end
        @tool_map[td.tool_name] = td
      end
    end

    # --- Scope filtering ---

    def extract_scopes(auth)
      return nil unless auth
      if auth.respond_to?(:scopes_array)
        auth.scopes_array
      elsif auth.respond_to?(:scopes) && auth.scopes.is_a?(String)
        auth.scopes.split(" ").reject(&:empty?)
      elsif auth.respond_to?(:scopes) && auth.scopes.is_a?(Array)
        auth.scopes
      else
        nil
      end
    end

    READ_ACTIONS = Set.new(%i[show index list search]).freeze

    def tool_allowed_by_scopes?(tool_definition, scopes)
      return true if scopes.empty?

      prefix = tool_definition.toolbox_class.controller_name.split("/").last
      tool_access = tool_definition.access_level ||
        (READ_ACTIONS.include?(tool_definition.method_name) ? :read : :write)

      scopes.any? { |s|
        scope_prefix, scope_action = s.split(":", 2)
        next false unless scope_prefix == prefix

        # No action suffix (e.g. "orders") → full access
        next true if scope_action.nil?

        # "write" scope grants both read and write
        scope_action == tool_access.to_s || scope_action == "write"
      }
    end

    # --- Request logging ---

    def log_request_start(definition, arguments, token_hint)
      return unless logger

      toolbox_name = definition.toolbox_class.name || definition.toolbox_class.controller_name.camelize
      method_name = definition.method_name

      parts = ["MCP #{toolbox_name}##{method_name}"]
      parts << "(#{token_hint})" if token_hint
      logger.info parts.join(" ")

      filtered = arguments.respond_to?(:to_h) ? arguments.to_h : arguments
      logger.info "  Parameters: #{filtered.inspect}" if filtered.any?
    end

    def log_request_complete(definition, response, duration)
      return unless logger

      status = response[:isError] ? "Error" : "OK"
      logger.info "Completed #{status} in #{duration}ms"
    end

    def extract_token_hint(auth)
      return nil unless auth
      if auth.respond_to?(:token) && auth.token.is_a?(String)
        "#{auth.token[0..8]}..."
      elsif auth.respond_to?(:token_digest) && auth.token_digest.is_a?(String)
        "#{auth.token_digest[0..8]}..."
      else
        nil
      end
    end

    def logger
      return @logger if defined?(@logger)
      @logger = defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
    end
  end
end
