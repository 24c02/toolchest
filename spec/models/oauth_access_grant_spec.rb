require "spec_helper"
require "support/active_record"

RSpec.describe Toolchest::OauthAccessGrant, :db do
  let(:app) do
    Toolchest::OauthApplication.create!(
      name: "Test App",
      redirect_uri: "http://localhost:3000/callback",
      confidential: false
    )
  end

  def create_grant(attrs = {})
    described_class.create_for(**{
      application: app,
      resource_owner_id: "user_1",
      redirect_uri: "http://localhost:3000/callback",
      scopes: "orders:read"
    }.merge(attrs))
  end

  describe ".create_for" do
    it "creates a grant" do
      grant = create_grant
      expect(grant).to be_persisted
    end

    it "returns raw_code" do
      grant = create_grant
      expect(grant.raw_code).to be_present
    end

    it "hashes the code for storage" do
      grant = create_grant
      expected = Digest::SHA256.hexdigest(grant.raw_code)
      expect(grant.token_digest).to eq(expected)
    end

    it "sets expires_at" do
      grant = create_grant(expires_in: 300)
      expect(grant.expires_at).to be_within(2.seconds).of(Time.current + 300)
    end

    it "stores PKCE challenge" do
      grant = create_grant(
        code_challenge: "abc123",
        code_challenge_method: "S256"
      )
      expect(grant.code_challenge).to eq("abc123")
      expect(grant.code_challenge_method).to eq("S256")
    end

    it "stores mount_key" do
      grant = create_grant(mount_key: "admin")
      expect(grant.mount_key).to eq("admin")
    end
  end

  describe ".find_by_code" do
    it "finds grant by raw code" do
      grant = create_grant
      found = described_class.find_by_code(grant.raw_code)
      expect(found.id).to eq(grant.id)
    end

    it "returns nil for unknown code" do
      expect(described_class.find_by_code("nonexistent")).to be_nil
    end
  end

  describe "#expired?" do
    it "is false when before expiry" do
      grant = create_grant(expires_in: 300)
      expect(grant).not_to be_expired
    end

    it "is true when past expiry" do
      grant = create_grant(expires_in: -1)
      expect(grant).to be_expired
    end
  end

  describe "#revoke!" do
    it "sets revoked_at" do
      grant = create_grant
      grant.revoke!
      expect(grant.revoked_at).to be_present
    end
  end

  describe "#revoked?" do
    it "is false by default" do
      expect(create_grant).not_to be_revoked
    end

    it "is true after revoke!" do
      grant = create_grant
      grant.revoke!
      expect(grant).to be_revoked
    end
  end

  describe "#uses_pkce?" do
    it "is true when code_challenge present" do
      grant = create_grant(code_challenge: "abc", code_challenge_method: "S256")
      expect(grant.uses_pkce?).to be true
    end

    it "is false when no code_challenge" do
      grant = create_grant
      expect(grant.uses_pkce?).to be false
    end
  end

  describe "#verify_pkce" do
    it "returns true when no PKCE required" do
      grant = create_grant
      expect(grant.verify_pkce("anything")).to be true
    end

    it "returns false when PKCE required but no verifier given" do
      grant = create_grant(code_challenge: "abc", code_challenge_method: "S256")
      expect(grant.verify_pkce(nil)).to be false
      expect(grant.verify_pkce("")).to be false
    end

    it "verifies correct S256 challenge" do
      verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
      challenge = Base64.urlsafe_encode64(
        Digest::SHA256.digest(verifier),
        padding: false
      )

      grant = create_grant(code_challenge: challenge, code_challenge_method: "S256")
      expect(grant.verify_pkce(verifier)).to be true
    end

    it "rejects wrong verifier" do
      verifier = "correct_verifier"
      challenge = Base64.urlsafe_encode64(
        Digest::SHA256.digest(verifier),
        padding: false
      )

      grant = create_grant(code_challenge: challenge, code_challenge_method: "S256")
      expect(grant.verify_pkce("wrong_verifier")).to be false
    end
  end

  describe ".revoke_all_for" do
    it "revokes all grants for an app and owner" do
      g1 = create_grant
      g2 = create_grant

      described_class.revoke_all_for(app, "user_1")

      expect(g1.reload.revoked_at).to be_present
      expect(g2.reload.revoked_at).to be_present
    end

    it "does not revoke grants for other owners" do
      g1 = create_grant(resource_owner_id: "user_1")
      g2 = create_grant(resource_owner_id: "user_2")

      described_class.revoke_all_for(app, "user_1")

      expect(g1.reload.revoked_at).to be_present
      expect(g2.reload.revoked_at).to be_nil
    end
  end

  describe ".active scope" do
    it "excludes revoked grants" do
      grant = create_grant
      grant.revoke!
      expect(described_class.active).not_to include(grant)
    end

    it "excludes expired grants" do
      create_grant(expires_in: -1)
      expect(described_class.active).to be_empty
    end

    it "includes valid grants" do
      grant = create_grant
      expect(described_class.active).to include(grant)
    end
  end
end
