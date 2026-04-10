module Toolchest
  module Oauth
    class AuthorizationsController < Toolchest::ApplicationController
      before_action :authenticate_resource_owner!
      before_action :validate_client!

      # GET /mcp/oauth/authorize — consent screen
      def new
        @client_name = @application.name
        @redirect_uri = params[:redirect_uri]
        @optional = toolchest_config.optional_scopes
        @original_scope = requested_scopes.join(" ")

        unless toolchest_config.authorize_link?(@current_resource_owner)
          redirect_url = build_redirect(params[:redirect_uri],
            error: "access_denied",
            error_description: "User is not authorized to connect",
            state: params[:state]
          )
          redirect_to redirect_url, allow_other_host: true
          return
        end

        requested = requested_scopes
        allowed = toolchest_config.resolve_allowed_scopes(@current_resource_owner, requested)
        known = toolchest_config.scopes.keys
        allowed = allowed & known if known.any?
        required = Array(toolchest_config.required_scopes) & known
        visible = (allowed | required).uniq

        @scope_list = visible.map { |s|
          { name: s, description: toolchest_config.scopes[s] || s, required: required.include?(s) }
        }
        @oauth_params = oauth_hidden_params
        @authorize_url = "#{request.script_name}/oauth/authorize"
      end

      # DELETE /mcp/oauth/authorize — user denied
      def deny
        redirect_url = build_redirect(params[:redirect_uri],
          error: "access_denied",
          state: params[:state]
        )
        redirect_to redirect_url, allow_other_host: true
      end

      # POST /mcp/oauth/authorize — approve and redirect with code
      def create
        unless toolchest_config.authorize_link?(@current_resource_owner)
          redirect_url = build_redirect(params[:redirect_uri],
            error: "access_denied",
            error_description: "User is not authorized to connect",
            state: params[:state]
          )
          redirect_to redirect_url, allow_other_host: true
          return
        end

        requested = original_requested_scopes
        allowed = toolchest_config.resolve_allowed_scopes(@current_resource_owner, requested)
        known = toolchest_config.scopes.keys
        allowed = allowed & known if known.any?
        required = Array(toolchest_config.required_scopes) & known

        granted = if toolchest_config.optional_scopes
          submitted = Array(params[:scope])
          (submitted & allowed) | required
        else
          allowed | required
        end

        grant = Toolchest::OauthAccessGrant.create_for(
          application: @application,
          resource_owner_id: current_resource_owner_id,
          redirect_uri: params[:redirect_uri],
          scopes: granted.join(" "),
          mount_key: mount_key,
          code_challenge: params[:code_challenge],
          code_challenge_method: params[:code_challenge_method]
        )

        redirect_url = build_redirect(params[:redirect_uri],
          code: grant.raw_code,
          state: params[:state]
        )
        redirect_to redirect_url, allow_other_host: true
      end

      private

      def toolchest_config = Toolchest.configuration(mount_key.to_sym)

      def mount_key
        # 1. From env (inside a mount — /admin-mcp/oauth/authorize)
        return request.env["toolchest.mount_key"] if request.env["toolchest.mount_key"]

        # 2. From resource param (RFC 8707 — CC always sends this)
        if params[:resource].present?
          resource_path = URI.parse(params[:resource]).path rescue nil
          if resource_path
            found = Toolchest.mount_keys.find { |k|
              Toolchest.configuration(k).mount_path == resource_path
            }
            return found.to_s if found
          end
        end

        "default"
      end

      def authenticate_resource_owner!
        user = toolchest_config.resolve_current_user(request)
        if user
          @current_resource_owner = user
        else
          login_path = toolchest_config.login_path || "/login"
          redirect_to "#{login_path}?return_to=#{CGI.escape(request.url)}", allow_other_host: true
        end
      end

      def current_resource_owner_id
        owner = @current_resource_owner
        (owner.respond_to?(:id) ? owner.id : owner).to_s
      end

      def validate_client!
        # Applications are global — look up by uid only (no mount_key filter)
        @application = Toolchest::OauthApplication.find_by(uid: params[:client_id])
        unless @application
          render json: { error: "invalid_client", error_description: "Unknown client_id" }, status: :bad_request
          return
        end

        if params[:redirect_uri].present? && !@application.redirect_uri_matches?(params[:redirect_uri])
          render json: { error: "invalid_redirect_uri" }, status: :bad_request
        end
      end

      def requested_scopes
        scope = params[:scope]
        case scope
        when Array then scope.flat_map { |s| s.split(" ") }
        when String then scope.split(" ")
        else []
        end
      end

      def oauth_hidden_params
        params.to_unsafe_h.slice(
          "client_id", "state", "redirect_uri", "response_type", "response_mode",
          "access_type", "code_challenge", "code_challenge_method", "resource"
        )
      end

      def original_requested_scopes
        if params[:original_scope].present?
          params[:original_scope].split(" ")
        else
          requested_scopes
        end
      end

      def build_redirect(base_uri, query_params)
        uri = URI.parse(base_uri)
        existing = URI.decode_www_form(uri.query || "")
        query_params.compact.each { |k, v| existing << [k.to_s, v.to_s] }
        uri.query = URI.encode_www_form(existing)
        uri.to_s
      end
    end
  end
end
