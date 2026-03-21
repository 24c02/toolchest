module Toolchest
  class ParamDefinition
    attr_reader :name, :type, :description, :optional, :enum, :default, :children

    def initialize(name:, type:, description: "", optional: false, enum: nil, default: :__unset__, &block)
      @name = name.to_sym
      @type = type
      @description = description
      @optional = optional
      @enum = enum
      @default = default
      @children = []

      if block
        builder = ToolBuilder.new
        builder.instance_eval(&block)
        @children = builder.params
      end
    end

    def required? = !@optional

    def has_default? = @default != :__unset__

    def to_json_schema
      schema = case @type
      when :string
        { type: "string" }
      when :integer
        { type: "integer" }
      when :number
        { type: "number" }
      when :boolean
        { type: "boolean" }
      when :object
        object_schema
      when Array
        if @type.first == :object
          { type: "array", items: object_schema }
        else
          { type: "array", items: { type: @type.first.to_s } }
        end
      else
        { type: @type.to_s }
      end

      schema[:description] = @description if @description.present?
      schema[:enum] = @enum if @enum
      schema[:default] = @default if has_default?
      schema
    end

    private

    def object_schema
      props = {}
      required = []

      @children.each do |child|
        props[child.name] = child.to_json_schema
        required << child.name.to_s if child.required?
      end

      schema = { type: "object", properties: props }
      schema[:required] = required if required.any?
      schema
    end
  end
end
