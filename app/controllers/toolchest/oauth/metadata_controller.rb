module Toolchest
  module Oauth
    class MetadataController < ActionController::API
      # GET /.well-known/oauth-authorization-server(/*rest)
      def authorization_server
        mount_path, cfg = resolve_mount
        return if performed?

        render json: {
          issuer: "#{request.base_url}#{mount_path}",
          authorization_endpoint: "#{request.base_url}#{mount_path}/oauth/authorize",
          token_endpoint: "#{request.base_url}#{mount_path}/oauth/token",
          registration_endpoint: "#{request.base_url}#{mount_path}/oauth/register",
          response_types_supported: ["code"],
          grant_types_supported: ["authorization_code", "refresh_token"],
          token_endpoint_auth_methods_supported: ["none"],
          scopes_supported: cfg.scopes.keys,
          code_challenge_methods_supported: ["S256"]
        }
      end

      # GET /.well-known/oauth-protected-resource(/*rest)
      def protected_resource
        mount_path, cfg = resolve_mount
        return if performed?

        render json: {
          resource: "#{request.base_url}#{mount_path}",
          authorization_servers: ["#{request.base_url}#{mount_path}"],
          scopes_supported: cfg.scopes.keys,
          bearer_methods_supported: ["header"]
        }
      end

      private

      # Returns [mount_path, config] or renders 404 and returns [nil, nil].
      def resolve_mount
        if params[:rest].present?
          # Suffixed path (RFC 8414) — must match a configured mount exactly.
          path = "/#{params[:rest]}"
          key = Toolchest.mount_keys.find { |k| Toolchest.configuration(k).mount_path == path }
          unless key
            head :not_found
            return [nil, nil]
          end
          return [path, Toolchest.configuration(key)]
        end

        # No suffix (e.g. Cursor). Use default_oauth_mount if set.
        if Toolchest.default_oauth_mount
          cfg = Toolchest.configuration(Toolchest.default_oauth_mount)
          return [cfg.mount_path || "/mcp", cfg]
        end

        # Auto-resolve when there's exactly one OAuth mount.
        oauth_mounts = Toolchest.mount_keys.select { |k| Toolchest.configuration(k).auth == :oauth }
        if oauth_mounts.size == 1
          cfg = Toolchest.configuration(oauth_mounts.first)
          return [cfg.mount_path || "/mcp", cfg]
        end

        head :not_found
        [nil, nil]
      end
    end
  end
end
