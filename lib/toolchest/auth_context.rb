module Toolchest
  class AuthContext
    attr_reader :resource_owner, :scopes, :token

    def initialize(resource_owner:, scopes:, token:)
      @resource_owner = resource_owner
      @scopes = scopes
      @token = token
    end

    def scopes_array = @scopes
  end
end
