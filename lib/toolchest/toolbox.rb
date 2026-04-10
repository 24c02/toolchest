require "abstract_controller/callbacks"
require "active_support/rescuable"
require "active_support/concern"

module Toolchest
  class Toolbox
    include ActiveSupport::Callbacks
    include AbstractController::Callbacks
    include ActiveSupport::Rescuable

    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@_tool_definitions, {})
        subclass.instance_variable_set(:@_default_params, [])
        subclass.instance_variable_set(:@_resources, [])
        subclass.instance_variable_set(:@_prompts, [])
        subclass.instance_variable_set(:@_pending_tool, nil)
        subclass.instance_variable_set(:@_helper_methods, [])
        subclass.instance_variable_set(:@_helper_modules, [])
      end

      def tool_definitions
        ancestors
          .select { |a| a.respond_to?(:own_tool_definitions, true) }
          .reverse
          .each_with_object({}) { |a, h| h.merge!(a.send(:own_tool_definitions)) }
      end

      def default_params
        ancestors
          .select { |a| a.respond_to?(:own_default_params, true) }
          .reverse
          .flat_map { |a| a.send(:own_default_params) }
      end

      def resources
        ancestors
          .select { |a| a.respond_to?(:own_resources, true) }
          .reverse
          .flat_map { |a| a.send(:own_resources) }
      end

      def prompts
        ancestors
          .select { |a| a.respond_to?(:own_prompts, true) }
          .reverse
          .flat_map { |a| a.send(:own_prompts) }
      end

      def tool(description, name: nil, access: nil, scope: nil, annotations: nil, &block)
        builder = ToolBuilder.new
        builder.instance_eval(&block) if block
        @_pending_tool = { description:, custom_name: name, access_level: access, scope:, annotations:, builder: }
      end

      def default_param(name, type, description = "", **options)
        @_default_params << {
          param: ParamDefinition.new(
            name: name, type: type, description: description,
            optional: options.fetch(:optional, false),
            enum: options[:enum],
            default: options.fetch(:default, :__unset__)
          ),
          except: Array(options[:except]).map(&:to_sym),
          only: options[:only] ? Array(options[:only]).map(&:to_sym) : nil
        }
      end

      def resource(uri, name: nil, description: nil, &block)
        template = uri.include?("{")
        @_resources << {
          uri: uri,
          name: name || uri,
          description: description,
          block: block,
          template: template,
          toolbox_class: self
        }
      end

      def prompt(prompt_name, description: nil, arguments: {}, &block)
        @_prompts << {
          name: prompt_name,
          description: description,
          arguments: arguments,
          block: block,
          toolbox_class: self
        }
      end

      def method_added(method_name)
        super
        return unless @_pending_tool

        pending = @_pending_tool
        @_pending_tool = nil

        params = pending[:builder].params.dup

        default_params.each do |dp|
          next if dp[:except].include?(method_name.to_sym)
          next if dp[:only] && !dp[:only].include?(method_name.to_sym)
          next if params.any? { |p| p.name == dp[:param].name }
          params.unshift(dp[:param])
        end

        definition = ToolDefinition.new(
          method_name: method_name,
          description: pending[:description],
          params: params,
          toolbox_class: self,
          custom_name: pending[:custom_name],
          access_level: pending[:access_level],
          scope: pending[:scope],
          annotations: pending[:annotations]
        )

        @_tool_definitions[method_name.to_sym] = definition
      end

      # Expose toolbox methods as view helpers, like controller helper_method.
      #
      #   helper_method :current_user, :admin?
      #
      def helper_method(*methods)
        @_helper_methods.concat(methods.map(&:to_sym))
      end

      # Include modules as view helpers.
      #
      #   helper ApplicationHelper
      #   helper FormattingHelper, CurrencyHelper
      #
      def helper(*modules)
        @_helper_modules.concat(modules)
      end

      def helper_methods
        ancestors
          .select { |a| a.respond_to?(:own_helper_methods, true) }
          .reverse
          .flat_map { |a| a.send(:own_helper_methods) }
          .uniq
      end

      def helper_modules
        ancestors
          .select { |a| a.respond_to?(:own_helper_modules, true) }
          .reverse
          .flat_map { |a| a.send(:own_helper_modules) }
          .uniq
      end

      def controller_name = name&.underscore&.chomp("_toolbox") || "anonymous"

      protected

      def own_tool_definitions = @_tool_definitions || {}

      def own_default_params = @_default_params || []

      def own_resources = @_resources || []

      def own_prompts = @_prompts || []

      def own_helper_methods = @_helper_methods || []

      def own_helper_modules = @_helper_modules || []
    end

    attr_reader :params

    def initialize(params: {}, tool_definition: nil)
      @params = Parameters.new(params, tool_definition: tool_definition)
      @_tool_definition = tool_definition
      @_response = nil
      @_suggests = []
    end

    def auth = Toolchest::Current.auth

    def controller_name = self.class.controller_name

    def action_name = @_action_name.to_s

    def performed? = @_response.present?

    def render(action_or_template = nil, json: nil, text: nil)
      result = if json
        json.is_a?(String) ? json : json.to_json
      elsif text
        text
      else
        rendered = Renderer.render(self, action_or_template || action_name)
        rendered.is_a?(String) ? rendered : rendered.to_json
      end

      @_response = {
        content: [{ type: "text", text: result }],
        isError: false
      }
    end

    def render_error(message)
      @_response = {
        content: [{ type: "text", text: message }],
        isError: true
      }
    end

    def render_errors(record)
      messages = record.errors.full_messages.join(", ")
      render_error("Validation failed: #{messages}")
    end

    def suggests(tool_name, hint = nil)
      tool_name = tool_name.to_s
      if tool_name.exclude?("_") && tool_name.exclude?(".") && tool_name.exclude?("/")
        tool_name = Naming.generate(self.class, tool_name)
      end
      @_suggests << { tool: tool_name, hint: hint }
    end

    def halt(**response)
      if response[:error]
        render_error(response[:error])
      end
      throw :halt
    end

    def mcp_log(level, message) = Toolchest.router(Toolchest::Current.mount_key&.to_sym || :default).notify_log(level: level.to_s, message: message)

    # Report progress during long-running actions.
    # Client shows a progress bar. total and message are optional.
    def mcp_progress(progress, total: nil, message: nil)
      session = Toolchest::Current.mcp_session
      return unless session

      token = Toolchest::Current.mcp_progress_token
      return unless token

      session.notify_progress(
        progress_token: token,
        progress: progress,
        total: total,
        message: message,
        related_request_id: Toolchest::Current.mcp_request_id
      )
    end

    # Ask the client's LLM to do work. Returns the response text.
    #
    #   mcp_sample("Summarize this order", context: @order.to_json)
    #
    #   mcp_sample do |s|
    #     s.system "You are a fraud analyst"
    #     s.user "Analyze: #{@order.to_json}"
    #     s.max_tokens 500
    #     s.temperature 0.3
    #   end
    def mcp_sample(prompt = nil, context: nil, max_tokens: 1024, **kwargs, &block)
      session = Toolchest::Current.mcp_session
      raise Toolchest::Error, "Sampling requires an MCP client that supports it" unless session

      if block
        builder = SamplingBuilder.new
        yield builder
        messages = builder.messages
        options = { max_tokens: builder.max_tokens_value || max_tokens }
        options[:system_prompt] = builder.system_value if builder.system_value
        options[:temperature] = builder.temperature_value if builder.temperature_value
        options[:model_preferences] = builder.model_preferences_value if builder.model_preferences_value
        options[:stop_sequences] = builder.stop_sequences_value if builder.stop_sequences_value
      else
        text = prompt.to_s
        text = "#{text}\n\n#{context}" if context
        messages = [{ role: "user", content: { type: "text", text: text } }]
        options = { max_tokens: max_tokens }
        options[:system_prompt] = kwargs[:system] if kwargs[:system]
        options[:temperature] = kwargs[:temperature] if kwargs[:temperature]
      end

      begin
        result = session.create_sampling_message(
          messages: messages,
          related_request_id: Toolchest::Current.mcp_request_id,
          **options
        )
      rescue RuntimeError => e
        raise Toolchest::Error, "Sampling failed: #{e.message}"
      end

      # Extract text from response
      content = result[:content] || result["content"]
      case content
      when Hash then content[:text] || content["text"]
      when Array then content.map { |c| c[:text] || c["text"] }.compact.join("\n")
      when String then content
      else result.to_s
      end
    end

    def dispatch(action_name)
      @_action_name = action_name

      catch(:halt) do
        begin
          process_action(action_name)
        rescue => e
          unless rescue_with_handler(e)
            raise
          end
        end
      end

      implicit_render! unless performed?
      build_mcp_response
    end

    private

    def process_action(action_name)
      run_callbacks :process_action do
        send(action_name)
      end
    end

    def implicit_render!
      render(action_name)
    rescue Toolchest::MissingTemplate
      raise Toolchest::MissingTemplate,
        "Missing template toolboxes/#{controller_name}/#{action_name}.json.jb"
    end

    def build_mcp_response
      response = @_response || { content: [], isError: false }

      if @_suggests.any?
        hints = @_suggests.map { |s|
          text = "Suggested next: call #{s[:tool]}"
          text += " — #{s[:hint]}" if s[:hint]
          text
        }.join("\n")

        response[:content] << { type: "text", text: hints }
      end

      response
    end
  end
end
