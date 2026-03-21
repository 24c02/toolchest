module Toolchest
  module Naming
    class << self
      def generate(toolbox_class, method_name, strategy = :underscored)
        prefix = toolbox_prefix(toolbox_class)

        case strategy
        when :underscored
          "#{prefix}_#{method_name}"
        when :dotted
          "#{prefix}.#{method_name}"
        when :slashed
          "#{prefix}/#{method_name}"
        when Proc
          strategy.call(prefix, method_name.to_s)
        else
          "#{prefix}_#{method_name}"
        end
      end

        private

      def toolbox_prefix(toolbox_class)
        name = toolbox_class.name || toolbox_class.to_s
        name.underscore
            .chomp("_toolbox")
            .gsub("/", "_")
      end
    end
  end
end
