require "spec_helper"

RSpec.describe Toolchest::Auth::Token do
  let(:strategy) { described_class.new }

  def request_with_token(token) = Struct.new(:env).new({"HTTP_AUTHORIZATION" => "Bearer #{token}"})

  describe "#authenticate" do
    context "without a bearer token" do
      it "returns nil" do
        request = Struct.new(:env).new({"HTTP_AUTHORIZATION" => ""})
        expect(strategy.authenticate(request)).to be_nil
      end
    end

    context "with TOOLCHEST_TOKEN env var" do
      around do |example|
        original_token = ENV["TOOLCHEST_TOKEN"]
        original_owner = ENV["TOOLCHEST_TOKEN_OWNER"]
        original_scopes = ENV["TOOLCHEST_TOKEN_SCOPES"]
        ENV["TOOLCHEST_TOKEN"] = "secret_env_token"
        ENV["TOOLCHEST_TOKEN_OWNER"] = "User:42"
        ENV["TOOLCHEST_TOKEN_SCOPES"] = "orders:read users:write"
        example.run
      ensure
        ENV["TOOLCHEST_TOKEN"] = original_token
        ENV["TOOLCHEST_TOKEN_OWNER"] = original_owner
        ENV["TOOLCHEST_TOKEN_SCOPES"] = original_scopes
      end

      it "authenticates matching token" do
        result = strategy.authenticate(request_with_token("secret_env_token"))
        expect(result).to be_a(Toolchest::Auth::Token::EnvTokenRecord)
        expect(result.token).to eq("secret_env_token")
      end

      it "returns nil for wrong token" do
        result = strategy.authenticate(request_with_token("wrong_token"))
        expect(result).to be_nil
      end

      it "exposes owner_id from env" do
        result = strategy.authenticate(request_with_token("secret_env_token"))
        expect(result.owner_id).to eq("User:42")
      end

      it "parses scopes from env" do
        result = strategy.authenticate(request_with_token("secret_env_token"))
        expect(result.scopes).to eq(["orders:read", "users:write"])
      end

      it "passes through authenticate_with callback if configured" do
        Toolchest.configure do |c|
          c.authenticate { |token_record| { user: token_record.owner_id } }
        end

        result = strategy.authenticate(request_with_token("secret_env_token"))
        expect(result).to eq(user: "User:42")
      end
    end

    context "without env token set" do
      around do |example|
        original = ENV["TOOLCHEST_TOKEN"]
        ENV.delete("TOOLCHEST_TOKEN")
        example.run
      ensure
        ENV["TOOLCHEST_TOKEN"] = original
      end

      it "returns nil when no DB token model is available" do
        # find_db_token checks defined?(Toolchest::Token) which is false in unit tests
        result = strategy.authenticate(request_with_token("some_token"))
        expect(result).to be_nil
      end
    end
  end

  describe "EnvTokenRecord" do
    let(:record) { described_class::EnvTokenRecord.new("tok", "User:42") }

    it "exposes token" do
      expect(record.token).to eq("tok")
    end

    it "exposes owner_id" do
      expect(record.owner_id).to eq("User:42")
    end

    it "parses owner_type" do
      expect(record.owner_type).to eq("User")
    end

    context "scopes from env" do
      around do |example|
        original = ENV["TOOLCHEST_TOKEN_SCOPES"]
        ENV["TOOLCHEST_TOKEN_SCOPES"] = "a:read b:write"
        example.run
      ensure
        ENV["TOOLCHEST_TOKEN_SCOPES"] = original
      end

      it "parses space-separated scopes" do
        expect(record.scopes).to eq(["a:read", "b:write"])
      end
    end

    context "without scopes env" do
      around do |example|
        original = ENV["TOOLCHEST_TOKEN_SCOPES"]
        ENV.delete("TOOLCHEST_TOKEN_SCOPES")
        example.run
      ensure
        ENV["TOOLCHEST_TOKEN_SCOPES"] = original
      end

      it "returns empty array" do
        expect(record.scopes).to eq([])
      end
    end

    context "nil owner_id" do
      let(:record) { described_class::EnvTokenRecord.new("tok", nil) }

      it "returns nil for owner_type" do
        expect(record.owner_type).to be_nil
      end
    end
  end
end
