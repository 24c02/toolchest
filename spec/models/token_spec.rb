require "spec_helper"
require "support/active_record"

RSpec.describe Toolchest::Token, :db do
  describe ".generate" do
    it "creates a token with a digest" do
      token = described_class.generate(name: "test")
      expect(token).to be_persisted
      expect(token.token_digest).to be_present
    end

    it "returns the raw token" do
      token = described_class.generate(name: "test")
      expect(token.raw_token).to start_with("tcht_")
    end

    it "stores the raw token only in memory" do
      token = described_class.generate(name: "test")
      reloaded = described_class.find(token.id)
      expect(reloaded.raw_token).to be_nil
    end

    it "hashes the raw token for storage" do
      token = described_class.generate(name: "test")
      expected_digest = OpenSSL::Digest::SHA256.hexdigest(token.raw_token)
      expect(token.token_digest).to eq(expected_digest)
    end

    it "sets owner_type and owner_id from owner string" do
      token = described_class.generate(name: "api", owner: "User:42")
      expect(token.owner_type).to eq("User")
      expect(token.owner_id).to eq("42")
    end

    it "sets scopes" do
      token = described_class.generate(name: "api", scopes: "orders:read users:write")
      expect(token.scopes).to eq("orders:read users:write")
    end

    it "sets namespace" do
      token = described_class.generate(name: "api", namespace: "admin")
      expect(token.namespace).to eq("admin")
    end

    it "sets expires_at" do
      token = described_class.generate(name: "api", expires_at: 1.hour.from_now)
      expect(token.expires_at).to be_within(1.second).of(1.hour.from_now)
    end
  end

  describe ".find_by_raw_token" do
    it "finds token by raw value" do
      token = described_class.generate(name: "test")
      found = described_class.find_by_raw_token(token.raw_token)
      expect(found.id).to eq(token.id)
    end

    it "returns nil for unknown token" do
      expect(described_class.find_by_raw_token("nonexistent")).to be_nil
    end
  end

  describe "#accessible?" do
    it "is true for active token" do
      token = described_class.generate(name: "test")
      expect(token).to be_accessible
    end

    it "is false for revoked token" do
      token = described_class.generate(name: "test")
      token.revoke!
      expect(token).not_to be_accessible
    end

    it "is false for expired token" do
      token = described_class.generate(name: "test", expires_at: 1.hour.ago)
      expect(token).not_to be_accessible
    end
  end

  describe "#expired?" do
    it "is false when no expiry" do
      token = described_class.generate(name: "test")
      expect(token).not_to be_expired
    end

    it "is true when past expiry" do
      token = described_class.generate(name: "test", expires_at: 1.hour.ago)
      expect(token).to be_expired
    end

    it "is false when before expiry" do
      token = described_class.generate(name: "test", expires_at: 1.hour.from_now)
      expect(token).not_to be_expired
    end
  end

  describe "#revoke!" do
    it "sets revoked_at" do
      token = described_class.generate(name: "test")
      token.revoke!
      expect(token.revoked_at).to be_present
    end
  end

  describe "#revoked?" do
    it "is false by default" do
      token = described_class.generate(name: "test")
      expect(token).not_to be_revoked
    end

    it "is true after revoke!" do
      token = described_class.generate(name: "test")
      token.revoke!
      expect(token).to be_revoked
    end
  end

  describe "#scopes_array" do
    it "splits scope string" do
      token = described_class.generate(name: "test", scopes: "orders:read users:write")
      expect(token.scopes_array).to eq(["orders:read", "users:write"])
    end

    it "returns empty for nil scopes" do
      token = described_class.generate(name: "test")
      expect(token.scopes_array).to eq([])
    end

    it "handles comma-separated scopes" do
      token = described_class.generate(name: "test", scopes: "a,b")
      expect(token.scopes_array).to eq(["a,b"])
    end
  end

  describe ".active scope" do
    it "excludes revoked tokens" do
      token = described_class.generate(name: "test")
      token.revoke!
      expect(described_class.active).not_to include(token)
    end

    it "excludes expired tokens" do
      described_class.generate(name: "expired", expires_at: 1.hour.ago)
      expect(described_class.active.where(name: "expired")).to be_empty
    end

    it "includes active tokens" do
      token = described_class.generate(name: "active")
      expect(described_class.active).to include(token)
    end
  end
end
