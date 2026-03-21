require "spec_helper"

RSpec.describe Toolchest::Auth::Base do
  # Base is abstract, but extract_bearer_token is shared by all strategies.
  # Easiest to test via a concrete subclass that exposes the private method.
  let(:strategy) { Toolchest::Auth::None.new }
  let(:request) { Struct.new(:env).new(env) }

  describe "#extract_bearer_token (via subclass)" do
    it "extracts a valid bearer token" do
      env = { "HTTP_AUTHORIZATION" => "Bearer abc123" }
      result = strategy.send(:extract_bearer_token, Struct.new(:env).new(env))
      expect(result).to eq("abc123")
    end

    it "is case-insensitive on Bearer keyword" do
      env = { "HTTP_AUTHORIZATION" => "bearer abc123" }
      result = strategy.send(:extract_bearer_token, Struct.new(:env).new(env))
      expect(result).to eq("abc123")
    end

    it "returns nil for empty header" do
      env = { "HTTP_AUTHORIZATION" => "" }
      result = strategy.send(:extract_bearer_token, Struct.new(:env).new(env))
      expect(result).to be_nil
    end

    it "returns nil for missing header" do
      env = {}
      result = strategy.send(:extract_bearer_token, Struct.new(:env).new(env))
      expect(result).to be_nil
    end

    it "returns nil for non-bearer auth" do
      env = { "HTTP_AUTHORIZATION" => "Basic dXNlcjpwYXNz" }
      result = strategy.send(:extract_bearer_token, Struct.new(:env).new(env))
      expect(result).to be_nil
    end

    it "handles tokens with special characters" do
      token = "tcht_abc123+/def456=="
      env = { "HTTP_AUTHORIZATION" => "Bearer #{token}" }
      result = strategy.send(:extract_bearer_token, Struct.new(:env).new(env))
      expect(result).to eq(token)
    end
  end

  describe "#authenticate" do
    it "raises NotImplementedError" do
      expect {
        described_class.new.authenticate(nil)
      }.to raise_error(NotImplementedError)
    end
  end
end
