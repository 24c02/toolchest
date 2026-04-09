require "spec_helper"
require "support/active_record"

RSpec.describe Toolchest::Auth::OAuth do
  let(:strategy) { described_class.new }
  let(:mount_strategy) { described_class.new(:admin) }

  def request_with_token(token) = Struct.new(:env).new({"HTTP_AUTHORIZATION" => "Bearer #{token}"})

  def fake_token(scopes: "orders:read")
    double("OauthAccessToken", accessible?: true, scopes_array: scopes.split(" "))
  end

  describe "#authenticate" do
    it "returns nil without a bearer token" do
      request = Struct.new(:env).new({"HTTP_AUTHORIZATION" => ""})
      expect(strategy.authenticate(request)).to be_nil
    end

    it "returns nil with missing Authorization header" do
      request = Struct.new(:env).new({})
      expect(strategy.authenticate(request)).to be_nil
    end

    it "returns AuthContext wrapping the token" do
      token = fake_token
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .with("my_token", mount_key: "default")
        .and_return(token)

      result = strategy.authenticate(request_with_token("my_token"))
      expect(result).to be_a(Toolchest::AuthContext)
      expect(result.token).to eq(token)
      expect(result.scopes).to eq(["orders:read"])
      expect(result.resource_owner).to be_nil
    end

    it "returns nil when token is not accessible" do
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .and_return(nil)

      result = strategy.authenticate(request_with_token("expired_token"))
      expect(result).to be_nil
    end

    it "returns nil when token not found" do
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .and_return(nil)

      result = strategy.authenticate(request_with_token("nonexistent"))
      expect(result).to be_nil
    end

    it "scopes lookup by mount_key" do
      token = fake_token
      expect(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .with("my_token", mount_key: "admin")
        .and_return(token)

      mount_strategy.authenticate(request_with_token("my_token"))
    end

    it "sets resource_owner from authenticate block" do
      Toolchest.configure do |c|
        c.authenticate { |token| "user_42" }
      end

      token = fake_token
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .and_return(token)

      result = strategy.authenticate(request_with_token("my_token"))
      expect(result.resource_owner).to eq("user_42")
      expect(result.scopes).to eq(["orders:read"])
    end
  end
end
