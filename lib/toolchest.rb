require "active_support"
require "active_support/core_ext"
require "toolchest/version"

module Toolchest
  autoload :App, "toolchest/app"
  autoload :RouteDelegation, "toolchest/route_delegation"
  autoload :AuthContext, "toolchest/auth_context"
  autoload :Configuration, "toolchest/configuration"
  autoload :Current, "toolchest/current"
  autoload :Naming, "toolchest/naming"
  autoload :Parameters, "toolchest/parameters"
  autoload :ParamDefinition, "toolchest/param_definition"
  autoload :Endpoint, "toolchest/endpoint"
  autoload :RackApp, "toolchest/rack_app"
  autoload :Renderer, "toolchest/renderer"
  autoload :Router, "toolchest/router"
  autoload :SamplingBuilder, "toolchest/sampling_builder"
  autoload :Toolbox, "toolchest/toolbox"
  autoload :ToolBuilder, "toolchest/tool_builder"
  autoload :ToolDefinition, "toolchest/tool_definition"

  module Auth
    autoload :Base, "toolchest/auth/base"
    autoload :None, "toolchest/auth/none"
    autoload :Token, "toolchest/auth/token"
    autoload :OAuth, "toolchest/auth/oauth"
  end

  class Error < StandardError; end
  class MissingTemplate < Error; end
  class ParameterMissing < Error; end

  class << self
    # Per-mount configuration
    # Toolchest.configure { } → configures :default
    # Toolchest.configure(:admin) { } → configures :admin
    def configure(name = :default, &block)
      @configs ||= {}
      @configs[name.to_sym] ||= Configuration.new(name)
      yield @configs[name.to_sym] if block
      @configs[name.to_sym]
    end

    # Toolchest.configuration → :default config (backward compat)
    # Toolchest.configuration(:admin) → :admin config
    def configuration(name = :default)
      @configs ||= {}
      @configs[name.to_sym] ||= Configuration.new(name)
    end

    # Returns a Rack app for a mount.
    # Toolchest.app → :default app
    # Toolchest.app(:admin) → :admin app
    def app(name = :default)
      @apps ||= {}
      @apps[name.to_sym] ||= App.new(name.to_sym)
    end

    # Per-mount router
    def router(name = :default)
      @routers ||= {}
      @routers[name.to_sym] ||= Router.new(mount_key: name.to_sym)
    end

    # All configured mount names
    def mount_keys = (@configs || {}).keys

    # When multiple OAuth mounts exist, bare /.well-known/* resolves to this mount
    attr_accessor :default_oauth_mount

    # Parent class for engine HTML controllers. Default: "::ApplicationController".
    # Set to "ActionController::Base" to avoid inheriting host app behavior.
    attr_writer :base_controller
    def base_controller
      @base_controller || "::ApplicationController"
    end

    # Delegate unresolved _path/_url helpers to main_app so the host
    # layout renders correctly inside engine views. Default: true.
    # Set to false in an initializer to disable.
    attr_writer :delegate_route_helpers
    def delegate_route_helpers
      @delegate_route_helpers != false
    end

    def reset!
      @configs = nil
      @routers = nil
      @apps = nil
      @default_oauth_mount = nil
      @base_controller = nil
      @delegate_route_helpers = nil
    end

    # Reset only routers/apps (preserves config set by initializers)
    def reset_routers!
      @routers = nil
      @apps = nil
    end
  end
end

if defined?(Rails::Engine)
  require "toolchest/engine"
  require "toolchest/oauth/routes"
end
