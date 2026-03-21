module Toolchest
  module Oauth
    class AuthorizedApplicationsController < ::ApplicationController
      before_action :authenticate_resource_owner!

      # GET /mcp/oauth/authorized_applications
      def index = @applications = authorized_applications

      # DELETE /mcp/oauth/authorized_applications/:id
      def destroy
        app = Toolchest::OauthApplication.find_by(id: params[:id])

        unless app
          redirect_to "#{request.script_name}/oauth/authorized_applications",
            alert: "Application not found."
          return
        end

        Toolchest::OauthAccessToken.revoke_all_for(app, current_resource_owner_id)
        Toolchest::OauthAccessGrant.revoke_all_for(app, current_resource_owner_id)

        redirect_to "#{request.script_name}/oauth/authorized_applications",
          notice: "#{app.name} has been disconnected."
      end

      private

      def toolchest_config = Toolchest.configuration(mount_key.to_sym)

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

      def mount_key = request.env["toolchest.mount_key"] || "default"

      def authorized_applications
        tokens_scope = Toolchest::OauthAccessToken
          .where(resource_owner_id: current_resource_owner_id, revoked_at: nil, mount_key: mount_key)

        app_ids = tokens_scope.select(:application_id).distinct

        Toolchest::OauthApplication.where(id: app_ids).map do |app|
          tokens = tokens_scope.where(application: app)
          latest = tokens.order(created_at: :desc).first
          scopes = tokens.flat_map(&:scopes_array).uniq

          {
            application: app,
            scopes: scopes,
            connected_at: tokens.minimum(:created_at),
            last_used_at: latest&.updated_at
          }
        end
      end
    end
  end
end
