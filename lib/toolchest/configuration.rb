module Toolchest
  class Configuration
    VALID_AUTH_STRATEGIES = %i[none token oauth].freeze

    attr_accessor :tool_naming, :filter_tools_by_scope,
                  :server_name, :server_version, :server_description, :server_instructions,
                  :scopes, :login_path, :additional_view_paths,
                  :access_token_expires_in, :toolboxes, :toolbox_module,
                  :mount_key, :mount_path,
                  :optional_scopes, :required_scopes
    attr_reader :auth

    def initialize(mount_key = :default)
      @mount_key = mount_key.to_sym
      @auth = :none
      @tool_naming = :underscored
      @filter_tools_by_scope = true
      @server_name = nil
      @server_version = Toolchest::VERSION
      @scopes = {}
      @login_path = "/login"
      @authenticate_block = nil
      @optional_scopes = false
      @required_scopes = []
      @allowed_scopes_for_block = nil
      @additional_view_paths = []
      @access_token_expires_in = 7200
      @toolboxes = nil
      @toolbox_module = nil
    end

    def auth=(value)
      if value.respond_to?(:authenticate)
        @auth = value
      elsif value.respond_to?(:to_sym)
        sym = value.to_sym
        unless VALID_AUTH_STRATEGIES.include?(sym)
          raise Toolchest::Error,
            "Invalid auth strategy :#{value}. Valid options: #{VALID_AUTH_STRATEGIES.map { |s| ":#{s}" }.join(', ')}, or an object responding to #authenticate(request)"
        end
        @auth = sym
      else
        raise Toolchest::Error,
          "Auth must be a symbol (:none, :token, :oauth) or an object responding to #authenticate(request)"
      end
    end

    def authenticate(&block) = @authenticate_block = block

    def authenticate_with(token)
      return nil unless @authenticate_block
      @authenticate_block.call(token)
    end

    def allowed_scopes_for(&block)
      if block
        @allowed_scopes_for_block = block
      else
        @allowed_scopes_for_block
      end
    end

    def resolve_allowed_scopes(user, scopes)
      @allowed_scopes_for_block ? @allowed_scopes_for_block.call(user, scopes) : scopes
    end

    def current_user_for_oauth(&block)
      if block
        @current_user_for_oauth_block = block
      else
        @current_user_for_oauth_block
      end
    end

    def resolve_current_user(request)
      return nil unless @current_user_for_oauth_block
      @current_user_for_oauth_block.call(request)
    end

    def resolved_server_name = @server_name || (defined?(Rails) && Rails.application ? Rails.application.class.module_parent_name : "Toolchest")
  end
end
