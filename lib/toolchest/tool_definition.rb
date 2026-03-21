module Toolchest
  class ToolDefinition
    attr_reader :method_name, :description, :params, :toolbox_class, :custom_name, :access_level

    def initialize(method_name:, description:, params:, toolbox_class:, custom_name: nil, access_level: nil)
      @method_name = method_name.to_sym
      @description = description
      @params = params
      @toolbox_class = toolbox_class
      @custom_name = custom_name
      @access_level = access_level
    end

    def tool_name(naming_strategy = nil)
      return @custom_name if @custom_name
      naming_strategy ||= Toolchest.configuration.tool_naming
      Naming.generate(toolbox_class, method_name, naming_strategy)
    end

    def to_mcp_schema(naming_strategy = nil)
      {
        name: tool_name(naming_strategy),
        description: @description,
        inputSchema: input_schema
      }
    end

    def input_schema
      properties = {}
      required = []

      @params.each do |param|
        properties[param.name] = param.to_json_schema
        required << param.name.to_s if param.required?
      end

      schema = { type: "object", properties: properties }
      schema[:required] = required if required.any?
      schema
    end
  end
end
