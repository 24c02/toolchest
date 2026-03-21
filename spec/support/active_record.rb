require "active_record"
require "securerandom"
require "digest"
require "base64"
require "openssl"

module ToolchestTestSchema
  def self.load!
    ActiveRecord::Schema.define do
      create_table :toolchest_tokens, force: true do |t|
        t.string :token_digest, null: false, index: { unique: true }
        t.string :name
        t.string :owner_type
        t.string :owner_id
        t.string :scopes
        t.string :namespace, default: "default"
        t.datetime :expires_at
        t.datetime :last_used_at
        t.datetime :revoked_at
        t.timestamps
      end

      create_table :toolchest_oauth_applications, force: true do |t|
        t.string  :name,         null: false
        t.string  :uid,          null: false, index: { unique: true }
        t.string  :secret
        t.text    :redirect_uri, null: false
        t.string  :scopes,       null: false, default: ""
        t.boolean :confidential, null: false, default: true
        t.timestamps
      end

      create_table :toolchest_oauth_access_grants, force: true do |t|
        t.string     :resource_owner_id, null: false
        t.references :application, null: false, foreign_key: { to_table: :toolchest_oauth_applications }
        t.string     :token_digest, null: false, index: { unique: true }
        t.text       :redirect_uri, null: false
        t.string     :scopes,     null: false, default: ""
        t.string     :code_challenge
        t.string     :code_challenge_method
        t.string     :mount_key, null: false, default: "default"
        t.datetime   :expires_at, null: false
        t.datetime   :revoked_at
        t.timestamps
      end

      create_table :toolchest_oauth_access_tokens, force: true do |t|
        t.string     :resource_owner_id
        t.references :application, null: false, foreign_key: { to_table: :toolchest_oauth_applications }
        t.string     :token,         null: false, index: { unique: true }
        t.string     :refresh_token, index: { unique: true }
        t.string     :scopes
        t.string     :mount_key, null: false, default: "default"
        t.datetime   :expires_at
        t.datetime   :revoked_at
        t.timestamps
      end
    end
  end
end

# Establish connection only when Rails isn't managing it
unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.initialized?
  ActiveRecord::Base.establish_connection(
    adapter: "sqlite3",
    database: ":memory:"
  )
end

ToolchestTestSchema.load!

# Now load the AR models
require_relative "../../app/models/toolchest/token"
require_relative "../../app/models/toolchest/oauth_application"
require_relative "../../app/models/toolchest/oauth_access_grant"
require_relative "../../app/models/toolchest/oauth_access_token"

RSpec.configure do |config|
  config.around(:each, :db) do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end
end
