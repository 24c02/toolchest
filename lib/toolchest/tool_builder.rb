module Toolchest
  class ToolBuilder
    attr_reader :params

    def initialize = @params = []

    def param(name, type, description = "", **options, &block)
      @params << ParamDefinition.new(
        name: name,
        type: type,
        description: description,
        optional: options.fetch(:optional, false),
        enum: options[:enum],
        default: options.fetch(:default, :__unset__),
        &block
      )
    end
  end
end
