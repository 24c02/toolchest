module ActionDispatch
  module Routing
    class Mapper
      # Mount well-known OAuth discovery routes at the app root.
      # MCP clients discover OAuth endpoints via these paths.
      #
      #   mount Toolchest::Engine => "/mcp"
      #   toolchest_oauth
      #
      # For multi-mount, call once — the (/*rest) suffix lets the
      # MetadataController return the correct endpoints per mount:
      #   /.well-known/oauth-authorization-server/mcp       → /mcp mount
      #   /.well-known/oauth-authorization-server/admin-mcp → /admin-mcp mount
      #
      def toolchest_oauth(default_mount: nil)
        Toolchest.default_oauth_mount = default_mount.to_sym if default_mount

        get "/.well-known/oauth-authorization-server(/*rest)",
          to: "toolchest/oauth/metadata#authorization_server"
        get "/.well-known/oauth-protected-resource(/*rest)",
          to: "toolchest/oauth/metadata#protected_resource"
      end
    end
  end
end
