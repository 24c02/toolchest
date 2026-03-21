require_relative "boot"
require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)
require "toolchest"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false
    config.active_support.deprecation = :stderr
    config.secret_key_base = "test-secret-key-base-for-toolchest-specs"
    config.root = File.expand_path("..", __dir__)
  end
end
