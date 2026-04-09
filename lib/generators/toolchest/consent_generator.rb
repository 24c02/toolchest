require "rails/generators"
require "rails/generators/base"

module Toolchest
  module Generators
    class ConsentGenerator < Rails::Generators::Base
      source_root File.expand_path("../../../..", __dir__)

      desc "Eject the OAuth consent view for customization"

      def copy_consent_view
        copy_file "app/views/toolchest/oauth/authorizations/new.html.erb"
      end

      def show_instructions
        say ""
        say "Consent view ejected!", :green
        say ""
        say "  Customize at: app/views/toolchest/oauth/authorizations/new.html.erb"
        say "  It renders inside your app's layout (via yield)."
        say ""
        say "  Available instance variables:"
        say "    @client_name  — OAuth application name"
        say "    @scope_list   — [{ name: 'posts:read', description: 'View posts' }, ...]"
        say "    @oauth_params — hash of hidden fields for the form"
        say "    @scope_values — raw scope strings"
        say "    @authorize_url — POST target for the form"
        say ""
        say "  For full control, also eject the controller:"
        say "    rails g toolchest:oauth_views"
        say ""
      end
    end
  end
end
