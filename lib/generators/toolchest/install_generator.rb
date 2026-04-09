require "rails/generators"
require "rails/generators/base"
require "rails/generators/migration"

module Toolchest
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname) = Time.now.utc.strftime("%Y%m%d%H%M%S")

      class_option :auth, type: :string, default: "none",
        desc: "Auth strategy (none, token, oauth)"

      def create_application_toolbox = template "application_toolbox.rb.tt", "app/toolboxes/application_toolbox.rb"

      def create_initializer = template "initializer.rb.tt", "config/initializers/toolchest.rb"

      def create_toolboxes_directory = empty_directory "app/views/toolboxes"

      def mount_engine
        route 'mount Toolchest::Engine => "/mcp"'
        route "toolchest_oauth" if auth_strategy == :oauth
      end

      def create_migrations
        case auth_strategy
        when :token
          migration_template "create_toolchest_tokens.rb.tt",
            "db/migrate/create_toolchest_tokens.rb"
        when :oauth
          migration_template "create_toolchest_oauth.rb.tt",
            "db/migrate/create_toolchest_oauth.rb"
        end
      end

      # Consent view lives in the engine and works out of the box.
      # Run `rails g toolchest:consent` to eject and customize.

      def show_instructions
        say ""
        say "Toolchest installed!", :green
        say ""
        say "  Auth strategy: #{auth_strategy}"
        say "  Mount point:   /mcp"
        say ""
        say "Next steps:"
        if auth_strategy != :none
          say "  1. rails db:migrate"
          say "  2. rails g toolchest YourModel show create update"
          say "  3. rails s → point your MCP client at http://localhost:3000/mcp"
        else
          say "  1. rails g toolchest YourModel show create update"
          say "  2. rails s → point your MCP client at http://localhost:3000/mcp"
        end
        say ""
        say "To change auth later: rails g toolchest:auth token (or oauth)"
        say ""
      end

      private

      def auth_strategy = options[:auth].to_sym

      def migration_version = "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
    end
  end
end
