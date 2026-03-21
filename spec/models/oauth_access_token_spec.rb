require "spec_helper"
require "support/active_record"

RSpec.describe Toolchest::OauthAccessToken, :db do
  let(:app) do
    Toolchest::OauthApplication.create!(
      name: "Test App",
      redirect_uri: "http://localhost:3000/callback",
      confidential: false
    )
  end

  def create_token(attrs = {})
    described_class.create_for(**{
      application: app,
      resource_owner_id: "user_1",
      scopes: "orders:read",
      mount_key: "default"
    }.merge(attrs))
  end

  describe ".create_for" do
    it "creates a token" do
      token = create_token
      expect(token).to be_persisted
    end

    it "returns raw_token" do
      token = create_token
      expect(token.raw_token).to be_present
    end

    it "returns raw_refresh_token" do
      token = create_token
      expect(token.raw_refresh_token).to be_present
    end

    it "hashes the token for storage" do
      token = create_token
      expected = Digest::SHA256.hexdigest(token.raw_token)
      expect(token.token).to eq(expected)
    end

    it "sets expires_at from expires_in" do
      token = create_token(expires_in: 3600)
      expect(token.expires_at).to be_within(2.seconds).of(Time.current + 3600)
    end

    it "sets nil expires_at when expires_in is nil" do
      token = create_token(expires_in: nil)
      expect(token.expires_at).to be_nil
    end

    it "stores mount_key" do
      token = create_token(mount_key: "admin")
      expect(token.mount_key).to eq("admin")
    end
  end

  describe ".find_by_token" do
    it "finds by raw token" do
      token = create_token
      found = described_class.find_by_token(token.raw_token)
      expect(found.id).to eq(token.id)
    end

    it "scopes by mount_key" do
      token = create_token(mount_key: "admin")
      expect(described_class.find_by_token(token.raw_token, mount_key: "admin")).to be_present
      expect(described_class.find_by_token(token.raw_token, mount_key: "other")).to be_nil
    end

    it "returns nil for unknown token" do
      expect(described_class.find_by_token("nonexistent")).to be_nil
    end
  end

  describe ".find_by_refresh_token" do
    it "finds by raw refresh token" do
      token = create_token
      found = described_class.find_by_refresh_token(token.raw_refresh_token)
      expect(found.id).to eq(token.id)
    end

    it "scopes by mount_key" do
      token = create_token(mount_key: "admin")
      expect(described_class.find_by_refresh_token(token.raw_refresh_token, mount_key: "admin")).to be_present
      expect(described_class.find_by_refresh_token(token.raw_refresh_token, mount_key: "other")).to be_nil
    end
  end

  describe "#accessible?" do
    it "is true for valid token" do
      expect(create_token).to be_accessible
    end

    it "is false when revoked" do
      token = create_token
      token.revoke!
      expect(token).not_to be_accessible
    end

    it "is false when expired" do
      token = create_token(expires_in: -1)
      expect(token).not_to be_accessible
    end
  end

  describe "#revoke!" do
    it "sets revoked_at" do
      token = create_token
      token.revoke!
      expect(token.revoked_at).to be_present
    end
  end

  describe "#scopes_array" do
    it "splits space-separated scopes" do
      token = create_token(scopes: "orders:read users:write")
      expect(token.scopes_array).to eq(["orders:read", "users:write"])
    end

    it "returns empty for nil scopes" do
      token = create_token(scopes: nil)
      expect(token.scopes_array).to eq([])
    end
  end

  describe ".revoke_all_for" do
    it "revokes all tokens for an app and owner" do
      t1 = create_token
      t2 = create_token

      described_class.revoke_all_for(app, "user_1")

      expect(t1.reload.revoked_at).to be_present
      expect(t2.reload.revoked_at).to be_present
    end

    it "does not revoke tokens for other owners" do
      t1 = create_token(resource_owner_id: "user_1")
      t2 = create_token(resource_owner_id: "user_2")

      described_class.revoke_all_for(app, "user_1")

      expect(t1.reload.revoked_at).to be_present
      expect(t2.reload.revoked_at).to be_nil
    end
  end

  describe ".active scope" do
    it "excludes revoked tokens" do
      token = create_token
      token.revoke!
      expect(described_class.active).not_to include(token)
    end

    it "includes valid tokens" do
      token = create_token
      expect(described_class.active).to include(token)
    end
  end
end
