require "rails/engine"

module Toolchest
  class Engine < ::Rails::Engine
    isolate_namespace Toolchest

    rake_tasks do
      load File.expand_path("tasks/toolchest.rake", __dir__)
    end

    initializer "toolchest.autoload_paths", before: :set_autoload_paths do |app|
      app.config.autoload_paths += [Rails.root.join("app", "toolboxes").to_s]
      app.config.eager_load_paths += [Rails.root.join("app", "toolboxes").to_s]
    end

    initializer "toolchest.setup" do
      config.after_initialize do
        Toolchest::Engine.ensure_initialized!
      end

      config.to_prepare do
        Toolchest::Engine.reload!
      end
    end

    class << self
      def ensure_initialized!
        return if @initialized

        require "mcp"

        discover_and_assign_toolboxes!

        @initialized = true
      end

      def reload!
        @initialized = false
        Toolchest.reset_routers!
        ensure_initialized!
      end

      private

      def discover_and_assign_toolboxes!
        return unless defined?(Rails) && Rails.respond_to?(:root) && Rails.root

        toolboxes_path = Rails.root.join("app", "toolboxes")
        return unless toolboxes_path.exist?

        all_toolboxes = []

        Dir[toolboxes_path.join("**", "*_toolbox.rb")].each do |file|
          class_name = file
            .sub(toolboxes_path.to_s + "/", "")
            .sub(/\.rb$/, "")
            .camelize

          next if class_name == "ApplicationToolbox"

          begin
            klass = class_name.constantize
            all_toolboxes << klass if klass < Toolchest::Toolbox
          rescue NameError
          end
        end

        # Assign toolboxes to mounts based on config
        Toolchest.mount_keys.each do |mount_key|
          cfg = Toolchest.configuration(mount_key)
          router = Toolchest.router(mount_key)

          assigned = if cfg.toolboxes
            # Explicit list (supports strings for lazy loading)
            cfg.toolboxes.map { |t| t.is_a?(String) ? t.constantize : t }
          elsif cfg.toolbox_module
            # Module convention
            all_toolboxes.select { |t| t.name&.start_with?("#{cfg.toolbox_module}::") }
          else
            # Default: all toolboxes (only valid for single-mount)
            all_toolboxes
          end

          assigned.each { |t| router.register(t) }
        end

        # If no mounts configured yet, register all to :default
        if Toolchest.mount_keys.empty?
          all_toolboxes.each { |t| Toolchest.router(:default).register(t) }
        end
      end
    end

  end
end
