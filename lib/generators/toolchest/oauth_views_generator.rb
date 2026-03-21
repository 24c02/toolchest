require "rails/generators"
require "rails/generators/base"

module Toolchest
  module Generators
    class OauthViewsGenerator < Rails::Generators::Base
      desc "Eject all OAuth views and controllers for customization"

      def copy_views
        engine_views = File.expand_path("../../../../app/views/toolchest/oauth", __dir__)

        Dir[File.join(engine_views, "**", "*.erb")].each do |src|
          relative = src.sub(engine_views + "/", "")
          copy_file src, "app/views/toolchest/oauth/#{relative}"
        end
      end

      def copy_controllers
        engine_controllers = File.expand_path("../../../../app/controllers/toolchest/oauth", __dir__)

        Dir[File.join(engine_controllers, "**", "*.rb")].each do |src|
          relative = src.sub(engine_controllers + "/", "")
          copy_file src, "app/controllers/toolchest/oauth/#{relative}"
        end
      end

      def show_instructions
        say ""
        say "OAuth views and controllers ejected!", :green
        say ""
        say "  Views:       app/views/toolchest/oauth/"
        say "  Controllers: app/controllers/toolchest/oauth/"
        say ""
        say "Controllers:"
        say "  authorizations_controller.rb — consent screen (GET/POST /mcp/oauth/authorize)"
        say "  tokens_controller.rb         — token exchange (POST /mcp/oauth/token)"
        say "  registrations_controller.rb  — DCR (POST /register)"
        say "  metadata_controller.rb       — .well-known endpoints"
        say "  authorized_applications_controller.rb — revocation UI (GET/DELETE /mcp/oauth/authorized_applications)"
        say ""
        say "Views:"
        say "  authorizations/new.html.erb           — consent page"
        say "  authorized_applications/index.html.erb — connected apps list"
        say ""
        say "All controllers inherit from ApplicationController."
        say "Override any file — your app's version takes precedence."
        say ""
      end
    end
  end
end
