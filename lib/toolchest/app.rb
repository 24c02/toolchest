require "action_dispatch"

module Toolchest
  # Rack app for a named mount. Used for multi-mount:
  #   mount Toolchest.app(:admin) => "/admin-mcp"
  #
  # Handles OAuth routes (authorize, token, register, authorized_applications)
  # and delegates everything else to the MCP transport (RackApp).
  class App
    attr_reader :mount_key

    def initialize(mount_key = :default)
      @mount_key = mount_key.to_sym
      @router = build_action_dispatch_router
    end

    def call(env)
      Engine.ensure_initialized!
      env["toolchest.mount_key"] = @mount_key.to_s

      cfg = Toolchest.configuration(@mount_key)
      if cfg.mount_path.nil? && env["SCRIPT_NAME"].present?
        cfg.mount_path = env["SCRIPT_NAME"]
      end

      @router.call(env)
    end

    private

    def build_action_dispatch_router
      mk = @mount_key
      endpoint = Endpoint.new

      ActionDispatch::Routing::RouteSet.new.tap do |routes|
        routes.draw do
          get    "oauth/authorize", to: "toolchest/oauth/authorizations#new"
          post   "oauth/authorize", to: "toolchest/oauth/authorizations#create"
          delete "oauth/authorize", to: "toolchest/oauth/authorizations#deny"
          post "oauth/token",     to: "toolchest/oauth/tokens#create"
          post "oauth/register",  to: "toolchest/oauth/registrations#create"

          resources :oauth_authorized_applications, only: [:index, :destroy],
            path: "oauth/authorized_applications",
            controller: "toolchest/oauth/authorized_applications"

          match "/", to: endpoint, via: [:get, :post, :delete]
          match "/*path", to: endpoint, via: [:get, :post, :delete]
        end
      end
    end
  end
end
