ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/application"

# spec_helper (loaded via .rspec) requires toolchest before Rails::Engine
# exists, so the engine + OAuth routes aren't loaded. Fix that here.
require "toolchest/engine" unless defined?(Toolchest::Engine)
require "toolchest/oauth/routes"

Rails.application.initialize!
require "mcp"

# When spec_helper loads toolchest before Rails boots, Zeitwerk can't
# autoload controllers under Toolchest::Oauth. Load them explicitly.
module Toolchest; module Oauth; end; end
Dir[File.expand_path("../app/controllers/toolchest/**/*.rb", __dir__)].sort.each do |f|
  load f
end

require "rspec/rails"
require_relative "support/active_record"

# Rails initialization may have established a new connection.
# Re-create tables on whatever connection is now active.
ToolchestTestSchema.load!

RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.around(:each, :db) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
