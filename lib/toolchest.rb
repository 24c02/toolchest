require "active_support"
require "active_support/core_ext"
require "toolchest/version"

module Toolchest
  autoload :App, "toolchest/app"
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

    def reset!
      @configs = nil
      @routers = nil
      @apps = nil
      @default_oauth_mount = nil
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
