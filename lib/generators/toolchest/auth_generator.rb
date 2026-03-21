require "rails/generators"
require "rails/generators/base"
require "rails/generators/migration"

module Toolchest
  module Generators
    class AuthGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dirname) = Time.now.utc.strftime("%Y%m%d%H%M%S")

      argument :strategy, type: :string, desc: "Auth strategy to add (token, oauth)"

      def validate_strategy
        unless %w[token oauth].include?(strategy)
          raise Thor::Error, "Unknown auth strategy: #{strategy}. Use 'token' or 'oauth'."
        end
      end

      def create_migration
        case strategy
        when "token"
          migration_template "create_toolchest_tokens.rb.tt",
            "db/migrate/create_toolchest_tokens.rb"
        when "oauth"
          migration_template "create_toolchest_oauth.rb.tt",
            "db/migrate/create_toolchest_oauth.rb"
        end
      end

      def create_consent_view
        return unless strategy == "oauth"
        template "oauth_authorize.html.erb.tt",
          "app/views/toolchest/oauth/authorizations/new.html.erb"
      end

      def update_initializer
        say ""
        say "Auth migration created for :#{strategy}.", :green
        say ""
        say "Update your initializer:"
        say "  config.auth = :#{strategy}"
        say ""
        say "Then run: rails db:migrate"
        say ""
      end

      private

      def migration_version = "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
    end
  end
end
