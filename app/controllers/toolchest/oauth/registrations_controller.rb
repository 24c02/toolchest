module Toolchest
  module Oauth
    class RegistrationsController < ::ApplicationController
      skip_forgery_protection
      wrap_parameters false

      # POST /register — Dynamic Client Registration (RFC 7591)
      # Applications are global (not mount-scoped). Mount scoping happens
      # at authorization time via the resource param.
      def create
        name = (params[:client_name] || "MCP Client").truncate(255)
        uris = Array(params[:redirect_uris])

        if uris.size > 10
          return render json: {
            error: "invalid_client_metadata",
            error_description: "Too many redirect URIs (max 10)"
          }, status: :bad_request
        end

        if uris.any? { |u| u.to_s.length > 2048 }
          return render json: {
            error: "invalid_client_metadata",
            error_description: "Redirect URI too long (max 2048 characters)"
          }, status: :bad_request
        end

        application = Toolchest::OauthApplication.new(
          name: name,
          redirect_uri: uris.join("\n"),
          confidential: false
        )

        if application.save
          render json: {
            client_name: application.name,
            client_id: application.uid,
            client_id_issued_at: application.created_at.to_i,
            redirect_uris: application.redirect_uris,
            grant_types: params[:grant_types] || ["authorization_code"],
            response_types: params[:response_types] || ["code"],
            token_endpoint_auth_method: params[:token_endpoint_auth_method] || "none"
          }, status: :created
        else
          render json: {
            error: "invalid_client_metadata",
            error_description: application.errors.full_messages.join(", ")
          }, status: :bad_request
        end
      end
    end
  end
end
