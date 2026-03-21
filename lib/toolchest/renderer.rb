require "action_view"

module Toolchest
  module Renderer
    class << self
      def render(toolbox, action_or_template)
        ensure_handlers_registered!

        name = action_or_template.to_s
        template_name = name.include?("/") ? name : "#{toolbox.controller_name}/#{name}"
        assigns = extract_assigns(toolbox)

        lookup = ActionView::LookupContext.new(view_paths)
        view = ActionView::Base.with_empty_template_cache.new(lookup, assigns, nil)

        result = view.render(template: template_name, formats: [:json])

        case result
        when String
          # jb returns JSON string via monkey patches, jbuilder returns JSON string natively
          begin
            JSON.parse(result)
          rescue JSON::ParserError
            result
          end
        when Hash, Array
          result
        else
          result
        end
      rescue ActionView::MissingTemplate
        raise Toolchest::MissingTemplate,
          "Missing template toolboxes/#{template_name} with formats: json (searched in: #{view_paths.join(", ")})"
      end

      private

      def ensure_handlers_registered!
        return if @handlers_registered

        handler_found = false

        # Register jb handler if available
        begin
          require "jb/handler"
          require "jb/action_view_monkeys"
          ActionView::Template.register_template_handler :jb, Jb::Handler
          handler_found = true
        rescue LoadError
        end

        # jbuilder registers via its own railtie, but if we're outside Rails boot:
        begin
          require "jbuilder/jbuilder_template"
          handler_found = true
        rescue LoadError
        end

        unless handler_found
          warn "[Toolchest] No template handler found. Add gem 'jb' (recommended) or gem 'jbuilder' to your Gemfile."
        end

        @handlers_registered = true
      end

      def extract_assigns(toolbox)
        assigns = {}
        toolbox.instance_variables.each do |ivar|
          next if ivar.to_s.start_with?("@_")
          key = ivar.to_s.sub("@", "")
          assigns[key] = toolbox.instance_variable_get(ivar)
        end
        assigns
      end

      def view_paths
        paths = []
        if defined?(Rails) && Rails.respond_to?(:root) && Rails.root
          paths << Rails.root.join("app", "views", "toolboxes").to_s
        end
        paths += Toolchest.configuration.additional_view_paths
        paths
      end

      def reset! = @handlers_registered = false
    end
  end
end
