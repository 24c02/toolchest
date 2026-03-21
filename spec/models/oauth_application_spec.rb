require "spec_helper"
require "support/active_record"

RSpec.describe Toolchest::OauthApplication, :db do
  def create_app(attrs = {})
    described_class.create!({
      name: "Test App",
      redirect_uri: "http://localhost:3000/callback",
      confidential: false
    }.merge(attrs))
  end

  describe "validations" do
    it "requires name" do
      app = described_class.new(redirect_uri: "http://example.com/cb", confidential: false)
      expect(app).not_to be_valid
      expect(app.errors[:name]).to be_present
    end

    it "requires redirect_uri" do
      app = described_class.new(name: "Test", confidential: false)
      expect(app).not_to be_valid
      expect(app.errors[:redirect_uri]).to be_present
    end

    it "requires unique uid" do
      app1 = create_app
      app2 = described_class.new(name: "Dupe", redirect_uri: "http://example.com", uid: app1.uid, confidential: false)
      expect(app2).not_to be_valid
      expect(app2.errors[:uid]).to be_present
    end
  end

  describe "auto-generated fields" do
    it "generates uid on create" do
      app = create_app
      expect(app.uid).to be_present
    end

    it "does not generate secret for public apps" do
      app = create_app(confidential: false)
      expect(app.secret).to be_nil
    end
  end

  describe "#redirect_uris" do
    it "splits newline-separated URIs" do
      app = create_app(redirect_uri: "http://a.com/cb\nhttp://b.com/cb")
      expect(app.redirect_uris).to eq(["http://a.com/cb", "http://b.com/cb"])
    end

    it "returns array for single URI" do
      app = create_app(redirect_uri: "http://a.com/cb")
      expect(app.redirect_uris).to eq(["http://a.com/cb"])
    end

    it "strips whitespace" do
      app = create_app(redirect_uri: " http://a.com/cb \n http://b.com/cb ")
      expect(app.redirect_uris).to eq(["http://a.com/cb", "http://b.com/cb"])
    end
  end

  describe "#redirect_uri_matches?" do
    it "returns true for matching URI" do
      app = create_app(redirect_uri: "http://a.com/cb\nhttp://b.com/cb")
      expect(app.redirect_uri_matches?("http://b.com/cb")).to be true
    end

    it "returns false for non-matching URI" do
      app = create_app(redirect_uri: "http://a.com/cb")
      expect(app.redirect_uri_matches?("http://evil.com/cb")).to be false
    end
  end
end
