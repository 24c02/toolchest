module Toolchest
  # Rack app for MCP protocol requests (JSON-RPC over HTTP).
  # OAuth endpoints are handled by Rails controllers via engine routes.
  class Endpoint
    def call(env)
      Engine.ensure_initialized!

      mount_key = (env["toolchest.mount_key"] || "default").to_sym
      app = Toolchest.router(mount_key).rack_app ||= RackApp.new(mount_key: mount_key)
      app.call(env)
    end
  end
end
