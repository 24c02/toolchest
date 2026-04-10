require "spec_helper"

RSpec.describe Toolchest::Configuration do
  let(:config) { described_class.new }

  describe "defaults" do
    it "defaults auth to :none" do
      expect(config.auth).to eq(:none)
    end

    it "defaults tool_naming to :underscored" do
      expect(config.tool_naming).to eq(:underscored)
    end

    it "defaults filter_tools_by_scope to true" do
      expect(config.filter_tools_by_scope).to be true
    end

    it "defaults server_version to Toolchest::VERSION" do
      expect(config.server_version).to eq(Toolchest::VERSION)
    end

    it "defaults scopes to empty hash" do
      expect(config.scopes).to eq({})
    end

    it "defaults login_path to /login" do
      expect(config.login_path).to eq("/login")
    end

    it "defaults access_token_expires_in to 7200" do
      expect(config.access_token_expires_in).to eq(7200)
    end

    it "defaults server_name to nil" do
      expect(config.server_name).to be_nil
    end

    it "defaults toolboxes to nil" do
      expect(config.toolboxes).to be_nil
    end

    it "defaults toolbox_module to nil" do
      expect(config.toolbox_module).to be_nil
    end
  end

  describe "#authenticate" do
    it "stores an authenticate block" do
      config.authenticate { |token| "user_#{token}" }
      expect(config.authenticate_with("abc")).to eq("user_abc")
    end
  end

  describe "#authenticate_with" do
    it "returns nil when no block configured" do
      expect(config.authenticate_with("anything")).to be_nil
    end

    it "calls the block with the token" do
      called_with = nil
      config.authenticate { |t| called_with = t; :ok }
      config.authenticate_with("my_token")
      expect(called_with).to eq("my_token")
    end
  end

  describe "#current_user_for_oauth" do
    it "stores and retrieves the block" do
      config.current_user_for_oauth { |req| "user_from_request" }
      expect(config.current_user_for_oauth).to be_a(Proc)
    end
  end

  describe "#resolve_current_user" do
    it "returns nil when no block configured" do
      expect(config.resolve_current_user(double("request"))).to be_nil
    end

    it "calls the block with the request" do
      config.current_user_for_oauth { |req| req[:user] }

      result = config.resolve_current_user({ user: "nora" })
      expect(result).to eq("nora")
    end
  end

  describe "#resolved_server_name" do
    it "returns explicit server_name when set" do
      config.server_name = "My API"
      expect(config.resolved_server_name).to eq("My API")
    end

    it "falls back to Toolchest when Rails.application is nil" do
      allow(Rails).to receive(:application).and_return(nil)
      expect(config.resolved_server_name).to eq("Toolchest")
    end
  end

  describe "#auth=" do
    it "accepts valid strategies" do
      %i[none token oauth].each do |strategy|
        config.auth = strategy
        expect(config.auth).to eq(strategy)
      end
    end

    it "accepts string values" do
      config.auth = "token"
      expect(config.auth).to eq(:token)
    end

    it "raises for invalid strategies" do
      expect { config.auth = :potato }.to raise_error(
        Toolchest::Error, /Invalid auth strategy :potato/
      )
    end

    it "accepts a custom object responding to #authenticate" do
      custom = Class.new {
        def authenticate(request)
          request.env["CUSTOM_USER"]
        end
      }.new

      config.auth = custom
      expect(config.auth).to eq(custom)
    end

    it "rejects objects not responding to #authenticate" do
      expect { config.auth = Object.new }.to raise_error(Toolchest::Error)
    end
  end

  describe "#optional_scopes" do
    it "defaults to false" do
      expect(config.optional_scopes).to be false
    end
  end

  describe "#required_scopes" do
    it "defaults to empty array" do
      expect(config.required_scopes).to eq([])
    end
  end

  describe "#authorize_link" do
    it "stores and retrieves the block" do
      config.authorize_link { |user| user.admin? }
      expect(config.authorize_link).to be_a(Proc)
    end
  end

  describe "#authorize_link?" do
    it "returns true when no block configured" do
      expect(config.authorize_link?(:anyone)).to be true
    end

    it "delegates to the block" do
      config.authorize_link { |user| user == :allowed }
      expect(config.authorize_link?(:allowed)).to be true
      expect(config.authorize_link?(:denied)).to be false
    end
  end

  describe "#allowed_scopes_for" do
    it "stores and retrieves the block" do
      config.allowed_scopes_for { |user, scopes| scopes }
      expect(config.allowed_scopes_for).to be_a(Proc)
    end
  end

  describe "#resolve_allowed_scopes" do
    it "returns scopes unchanged when no block configured" do
      expect(config.resolve_allowed_scopes(:user, %w[a b c])).to eq(%w[a b c])
    end

    it "calls the block with user and scopes" do
      config.allowed_scopes_for { |user, scopes| scopes - ["admin"] }
      expect(config.resolve_allowed_scopes(:user, %w[read admin])).to eq(%w[read])
    end
  end

  describe "mount_key" do
    it "stores the mount key as a symbol" do
      config = described_class.new(:admin)
      expect(config.mount_key).to eq(:admin)
    end

    it "defaults to :default" do
      expect(config.mount_key).to eq(:default)
    end
  end
end
