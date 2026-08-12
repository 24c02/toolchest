require_relative "../rails_helper"
require "base64"
require "digest"
require "json"

RSpec.describe "OAuth security regressions", :db do
  include Rack::Test::Methods

  def app = Rails.application

  def json_response = JSON.parse(last_response.body)

  def register_client(redirect_uris: ["http://localhost:3000/callback"])
    post "/mcp/oauth/register",
      { client_name: "Test Client", redirect_uris: redirect_uris }.to_json,
      "CONTENT_TYPE" => "application/json"
    json_response
  end

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [verifier, challenge]
  end

  let(:fake_user) { Struct.new(:id).new(42) }

  before do
    Toolchest.configure do |c|
      c.auth = :oauth
      c.mount_path = "/mcp"
      c.scopes = { "orders:read" => "View orders", "orders:write" => "Modify orders" }
      c.current_user_for_oauth { |_req| fake_user }
    end
  end

  let(:client) { register_client }
  let(:client_id) { client["client_id"] }
  let(:redirect_uri) { "http://localhost:3000/callback" }
  let(:verifier) { @verifier ||= SecureRandom.urlsafe_base64(32) }
  let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

  def get_auth_code(extra_params = {})
    params = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: "orders:read",
      code_challenge: challenge,
      code_challenge_method: "S256"
    }.merge(extra_params)
    post "/mcp/oauth/authorize", params
    location = URI.parse(last_response.headers["Location"])
    URI.decode_www_form(location.query).to_h["code"]
  end

  def exchange_code(code)
    post "/mcp/oauth/token", {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: client_id,
      code_verifier: verifier
    }
    json_response
  end

  # ============================================================
  # Refresh token race condition (atomic revocation)
  # ============================================================

  describe "refresh token replay" do
    it "rejects a refresh token that was already used" do
      code = get_auth_code
      tokens = exchange_code(code)
      refresh = tokens["refresh_token"]

      # First refresh succeeds
      post "/mcp/oauth/token", { grant_type: "refresh_token", refresh_token: refresh }
      expect(last_response.status).to eq(200)

      # Second use of same refresh token must fail
      post "/mcp/oauth/token", { grant_type: "refresh_token", refresh_token: refresh }
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_grant")
    end
  end

  # ============================================================
  # Refresh token client binding
  # ============================================================

  describe "refresh token client binding" do
    it "rejects refresh with wrong client_id" do
      code = get_auth_code
      tokens = exchange_code(code)

      other_client = register_client(redirect_uris: ["http://other.com/cb"])

      post "/mcp/oauth/token", {
        grant_type: "refresh_token",
        refresh_token: tokens["refresh_token"],
        client_id: other_client["client_id"]
      }
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_client")
    end
  end

  # ============================================================
  # client_id required at token exchange
  # ============================================================

  describe "client_id requirement" do
    it "rejects token exchange without client_id" do
      code = get_auth_code

      post "/mcp/oauth/token", {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri,
        code_verifier: verifier
        # client_id intentionally omitted
      }
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_request")
      expect(json_response["error_description"]).to include("client_id")
    end
  end

  # ============================================================
  # PKCE always required (no confidential bypass)
  # ============================================================

  describe "PKCE mandatory" do
    it "rejects token exchange without PKCE regardless of confidentiality" do
      # Create a grant without code_challenge
      post "/mcp/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        scope: "orders:read"
      }
      location = URI.parse(last_response.headers["Location"])
      code = URI.decode_www_form(location.query).to_h["code"]

      post "/mcp/oauth/token", {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri,
        client_id: client_id
      }
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_request")
      expect(json_response["error_description"]).to include("PKCE")
    end
  end

  # ============================================================
  # response_type validation
  # ============================================================

  describe "response_type validation" do
    it "rejects response_type=token (implicit flow)" do
      get "/mcp/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "token",
        scope: "orders:read",
        state: "s"
      }
      expect(last_response.status).to eq(302)
      location = URI.parse(last_response.headers["Location"])
      params = URI.decode_www_form(location.query).to_h
      expect(params["error"]).to eq("unsupported_response_type")
    end
  end

  # ============================================================
  # code_challenge_method validation
  # ============================================================

  describe "code_challenge_method validation" do
    it "rejects code_challenge_method=plain" do
      get "/mcp/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "orders:read",
        code_challenge: "something",
        code_challenge_method: "plain",
        state: "s"
      }
      expect(last_response.status).to eq(302)
      location = URI.parse(last_response.headers["Location"])
      params = URI.decode_www_form(location.query).to_h
      expect(params["error"]).to eq("invalid_request")
      expect(params["error_description"]).to include("S256")
    end
  end

  # ============================================================
  # Redirect URI scheme validation on registration
  # ============================================================

  describe "redirect URI validation on registration" do
    it "rejects redirect URIs without a scheme" do
      post "/mcp/oauth/register",
        { client_name: "Evil", redirect_uris: ["localhost/callback"] }.to_json,
        "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_client_metadata")
    end

    it "rejects javascript: URIs" do
      post "/mcp/oauth/register",
        { client_name: "Evil", redirect_uris: ["javascript://alert(1)"] }.to_json,
        "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
      expect(json_response["error_description"]).to include("scheme")
    end

    it "accepts valid http/https URIs" do
      result = register_client(redirect_uris: ["https://example.com/callback"])
      expect(last_response.status).to eq(201)
      expect(result["client_id"]).to be_present
    end
  end

  # ============================================================
  # Clickjacking protection
  # ============================================================

  describe "clickjacking protection" do
    it "sets X-Frame-Options: DENY on consent screen" do
      get "/mcp/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "orders:read"
      }
      expect(last_response.headers["X-Frame-Options"]).to eq("DENY")
    end
  end

  # ============================================================
  # Bearer token whitespace
  # ============================================================

  describe "bearer token extraction" do
    it "does not capture trailing whitespace" do
      strategy = Toolchest::Auth::Base.new
      request = double("request", env: { "HTTP_AUTHORIZATION" => "Bearer abc123  " })
      token = strategy.send(:extract_bearer_token, request)
      # \S+ won't match trailing spaces, so token should be nil (no match at \z)
      expect(token).to be_nil
    end

    it "extracts clean tokens" do
      strategy = Toolchest::Auth::Base.new
      request = double("request", env: { "HTTP_AUTHORIZATION" => "Bearer abc123" })
      token = strategy.send(:extract_bearer_token, request)
      expect(token).to eq("abc123")
    end
  end
end
