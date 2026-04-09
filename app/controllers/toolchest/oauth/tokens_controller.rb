module Toolchest
  module Oauth
    class TokensController < ::ApplicationController
      skip_forgery_protection

      # POST /mcp/oauth/token
      def create
        case params[:grant_type]
        when "authorization_code"
          handle_authorization_code
        when "refresh_token"
          handle_refresh_token
        else
          error_response("unsupported_grant_type", "Grant type '#{params[:grant_type]}' is not supported")
        end
      end

      private

      def mount_key = request.env["toolchest.mount_key"] || "default"

      def toolchest_config = Toolchest.configuration(mount_key.to_sym)

      def handle_authorization_code
        grant = Toolchest::OauthAccessGrant.find_by_code(params[:code])

        unless grant
          return error_response("invalid_grant", "Authorization code not found or expired")
        end

        app = grant.application

        if params[:client_id].present? && app.uid != params[:client_id]
          return error_response("invalid_client", "Client ID mismatch")
        end

        if grant.redirect_uri.present? && grant.redirect_uri != params[:redirect_uri]
          return error_response("invalid_grant", "Redirect URI mismatch")
        end

        if !grant.uses_pkce? && !app.confidential?
          return error_response("invalid_request", "PKCE required for public clients")
        end

        unless grant.verify_pkce(params[:code_verifier])
          return error_response("invalid_grant", "PKCE verification failed")
        end

        grant.revoke!

        token = Toolchest::OauthAccessToken.create_for(
          application: app,
          resource_owner_id: grant.resource_owner_id,
          scopes: grant.scopes,
          mount_key: grant.mount_key,
          expires_in: toolchest_config.access_token_expires_in
        )

        render json: token_response(token)
      end

      def handle_refresh_token
        old_token = Toolchest::OauthAccessToken.find_by_refresh_token(
          params[:refresh_token], mount_key: mount_key
        )

        unless old_token
          return error_response("invalid_grant", "Refresh token invalid or expired")
        end

        old_token.revoke!

        token = Toolchest::OauthAccessToken.create_for(
          application: old_token.application,
          resource_owner_id: old_token.resource_owner_id,
          scopes: old_token.scopes,
          mount_key: old_token.mount_key,
          expires_in: toolchest_config.access_token_expires_in
        )

        render json: token_response(token)
      end

      def token_response(token)
        response = {
          access_token: token.raw_token,
          token_type: "bearer"
        }
        response[:expires_in] = (token.expires_at - Time.current).to_i if token.expires_at
        response[:refresh_token] = token.raw_refresh_token if token.raw_refresh_token
        response[:scope] = token.scopes if token.scopes.present?
        response
      end

      def error_response(error, description) = render json: { error: error, error_description: description }, status: :bad_request
    end
  end
end
