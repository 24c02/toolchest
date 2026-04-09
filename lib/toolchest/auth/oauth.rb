module Toolchest
  module Auth
    class OAuth < Base
      def initialize(mount_key = :default)
        @mount_key = mount_key.to_s
      end

      def authenticate(request)
        token_string = extract_bearer_token(request)
        return nil unless token_string

        token = Toolchest::OauthAccessToken.find_by_token(token_string, mount_key: @mount_key)
        return nil unless token

        config = Toolchest.configuration(@mount_key.to_sym)
        owner = if config.send(:instance_variable_get, :@authenticate_block)
          config.authenticate_with(token)
        end

        AuthContext.new(
          resource_owner: owner,
          scopes: token.scopes_array,
          token: token
        )
      end
    end
  end
end
