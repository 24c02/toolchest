require "rails/generators"
require "rails/generators/base"

module Toolchest
  module Generators
    class ToolboxGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      argument :toolbox_name, type: :string
      argument :actions, type: :array, default: []

      def create_toolbox = template "toolbox.rb.tt", "app/toolboxes/#{file_path}_toolbox.rb"

      def create_views
        return if actions.empty?

        actions.each do |action|
          create_file "app/views/toolboxes/#{file_path}/#{action}.json.jb", <<~JB
            {
              # TODO: return data for #{toolbox_name.underscore}##{action}
            }
          JB
        end
      end

      def create_spec = template "toolbox_spec.rb.tt", "spec/toolboxes/#{file_path}_toolbox_spec.rb"

      private

      def file_path = toolbox_name.underscore

      def class_name = toolbox_name.camelize

      def parent_class
        if file_path.include?("/")
          namespace = file_path.split("/")[0..-2].map(&:camelize).join("::")
          "#{namespace}::ApplicationToolbox"
        else
          "ApplicationToolbox"
        end
      end
    end
  end
end
