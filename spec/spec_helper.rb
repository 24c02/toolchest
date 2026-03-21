require "bundler/setup"
require "active_support"
require "active_support/core_ext"
require "active_support/security_utils"
require "toolchest"

# Stub Rails for tests that don't need a full Rails environment
module Rails
  class << self
    attr_accessor :root, :application

    def respond_to?(method, include_private = false)
      %i[root application].include?(method) || super
    end
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.order = :random
  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.before(:each) do
    Toolchest.reset!
  end
end
