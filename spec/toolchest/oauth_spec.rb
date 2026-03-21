require "spec_helper"
require "support/active_record"

RSpec.describe Toolchest::Auth::OAuth do
  let(:strategy) { described_class.new }
  let(:mount_strategy) { described_class.new(:admin) }

  def request_with_token(token) = Struct.new(:env).new({"HTTP_AUTHORIZATION" => "Bearer #{token}"})

  describe "#authenticate" do
    it "returns nil without a bearer token" do
      request = Struct.new(:env).new({"HTTP_AUTHORIZATION" => ""})
      expect(strategy.authenticate(request)).to be_nil
    end

    it "returns nil with missing Authorization header" do
      request = Struct.new(:env).new({})
      expect(strategy.authenticate(request)).to be_nil
    end

    it "looks up token via OauthAccessToken" do
      fake_token = double("OauthAccessToken", accessible?: true)
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .with("my_token", mount_key: "default")
        .and_return(fake_token)

      result = strategy.authenticate(request_with_token("my_token"))
      expect(result).to eq(fake_token)
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
      fake_token = double("OauthAccessToken", accessible?: true)
      expect(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .with("my_token", mount_key: "admin")
        .and_return(fake_token)

      mount_strategy.authenticate(request_with_token("my_token"))
    end

    it "passes through authenticate_with callback if configured" do
      Toolchest.configure do |c|
        c.authenticate { |token| { custom: token.object_id } }
      end

      fake_token = double("OauthAccessToken", accessible?: true)
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .and_return(fake_token)

      result = strategy.authenticate(request_with_token("my_token"))
      expect(result).to eq(custom: fake_token.object_id)
    end

    it "returns raw token when no authenticate block" do
      fake_token = double("OauthAccessToken", accessible?: true)
      allow(Toolchest::OauthAccessToken).to receive(:find_by_token)
        .and_return(fake_token)

      result = strategy.authenticate(request_with_token("my_token"))
      expect(result).to eq(fake_token)
    end
  end
end
