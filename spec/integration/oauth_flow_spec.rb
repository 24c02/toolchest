require_relative "../rails_helper"
require "base64"
require "digest"
require "json"

RSpec.describe "OAuth flow", :db do
  include Rack::Test::Methods

  def app = Rails.application

  def json_response = JSON.parse(last_response.body)

  # --- DCR helpers ---

  def register_client(name: "Test Client", redirect_uris: ["http://localhost:3000/callback"])
    post "/mcp/oauth/register",
      { client_name: name, redirect_uris: redirect_uris }.to_json,
      "CONTENT_TYPE" => "application/json"
    json_response
  end

  # --- PKCE helpers ---

  def pkce_pair
    verifier = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    [verifier, challenge]
  end

  # --- Auth stub ---

  let(:fake_user) { Struct.new(:id).new(42) }

  before do
    Toolchest.configure do |c|
      c.auth = :oauth
      c.mount_path = "/mcp"
      c.scopes = {
        "orders:read" => "View orders",
        "orders:write" => "Modify orders"
      }
      c.current_user_for_oauth { |_req| fake_user }
    end
  end

  # ============================================================
  # Dynamic Client Registration (RFC 7591)
  # ============================================================

  describe "POST /mcp/oauth/register" do
    it "registers a new client" do
      result = register_client
      expect(last_response.status).to eq(201)
      expect(result["client_id"]).to be_present
      expect(result["client_name"]).to eq("Test Client")
      expect(result["redirect_uris"]).to eq(["http://localhost:3000/callback"])
    end

    it "defaults client_name to MCP Client" do
      post "/mcp/oauth/register",
        { redirect_uris: ["http://localhost/cb"] }.to_json,
        "CONTENT_TYPE" => "application/json"
      expect(json_response["client_name"]).to eq("MCP Client")
    end

    it "rejects too many redirect URIs" do
      uris = (1..11).map { |i| "http://localhost/cb#{i}" }
      post "/mcp/oauth/register",
        { client_name: "Bad", redirect_uris: uris }.to_json,
        "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_client_metadata")
    end

    it "rejects overly long redirect URIs" do
      post "/mcp/oauth/register",
        { client_name: "Bad", redirect_uris: ["http://localhost/#{"a" * 2049}"] }.to_json,
        "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(400)
      expect(json_response["error"]).to eq("invalid_client_metadata")
    end

    it "truncates overly long client names" do
      result = register_client(name: "A" * 300)
      expect(last_response.status).to eq(201)
      expect(result["client_name"].length).to be <= 255
    end
  end

  # ============================================================
  # Authorization Code Flow with PKCE
  # ============================================================

  describe "full authorization code flow" do
    let(:verifier) { SecureRandom.urlsafe_base64(32) }
    let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }
    let(:client) { register_client }
    let(:client_id) { client["client_id"] }
    let(:redirect_uri) { "http://localhost:3000/callback" }

    describe "GET /mcp/oauth/authorize" do
      it "renders the consent screen" do
        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include("Test Client")
      end

      it "returns 400 for unknown client_id" do
        get "/mcp/oauth/authorize", {
          client_id: "nonexistent",
          redirect_uri: redirect_uri,
          response_type: "code"
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_client")
      end

      it "returns 400 for mismatched redirect_uri" do
        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: "http://evil.com/steal",
          response_type: "code"
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_redirect_uri")
      end

      it "redirects to login when user is not authenticated" do
        Toolchest.configure do |c|
          c.auth = :oauth
          c.mount_path = "/mcp"
          c.current_user_for_oauth { |_req| nil }
        end

        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code"
        }
        expect(last_response.status).to eq(302)
        expect(last_response.headers["Location"]).to include("/login")
      end
    end

    describe "POST /mcp/oauth/authorize" do
      it "redirects with an authorization code" do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: "orders:read",
          state: "xyz",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.status).to eq(302)
        location = URI.parse(last_response.headers["Location"])
        params = URI.decode_www_form(location.query).to_h
        expect(params["code"]).to be_present
        expect(params["state"]).to eq("xyz")
      end
    end

    describe "DELETE /mcp/oauth/authorize" do
      it "redirects with error=access_denied" do
        delete "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          state: "xyz"
        }
        expect(last_response.status).to eq(302)
        location = URI.parse(last_response.headers["Location"])
        params = URI.decode_www_form(location.query).to_h
        expect(params["error"]).to eq("access_denied")
        expect(params["state"]).to eq("xyz")
      end

      it "returns 400 for unknown client_id" do
        delete "/mcp/oauth/authorize", {
          client_id: "nonexistent",
          redirect_uri: redirect_uri
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_client")
      end

      it "omits state from redirect when not provided" do
        delete "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri
        }
        expect(last_response.status).to eq(302)
        location = URI.parse(last_response.headers["Location"])
        params = URI.decode_www_form(location.query).to_h
        expect(params["error"]).to eq("access_denied")
        expect(params).not_to have_key("state")
      end
    end

    describe "POST /mcp/oauth/token (authorization_code)" do
      let(:auth_code) do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: "orders:read",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        location = URI.parse(last_response.headers["Location"])
        URI.decode_www_form(location.query).to_h["code"]
      end

      it "exchanges code for tokens with valid PKCE" do
        code = auth_code
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(last_response.status).to eq(200)
        body = json_response
        expect(body["access_token"]).to be_present
        expect(body["refresh_token"]).to be_present
        expect(body["token_type"]).to eq("bearer")
        expect(body["expires_in"]).to be_a(Integer)
      end

      it "rejects invalid authorization code" do
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: "bogus",
          redirect_uri: redirect_uri,
          code_verifier: verifier
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
      end

      it "rejects wrong PKCE verifier" do
        code = auth_code
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: "wrong_verifier"
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
        expect(json_response["error_description"]).to include("PKCE")
      end

      it "rejects mismatched redirect_uri" do
        code = auth_code
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: "http://other.com/cb",
          client_id: client_id,
          code_verifier: verifier
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
      end

      it "rejects expired code" do
        code = auth_code
        # Expire the grant
        Toolchest::OauthAccessGrant.update_all(expires_at: 1.hour.ago)

        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
      end

      it "revokes the code after exchange" do
        code = auth_code
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(last_response.status).to eq(200)

        # Second use should fail
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
      end

      it "rejects unsupported grant type" do
        post "/mcp/oauth/token", { grant_type: "client_credentials" }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("unsupported_grant_type")
      end

      it "rejects token exchange without PKCE for public clients" do
        # Create a grant without code_challenge (no PKCE)
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

    describe "POST /mcp/oauth/token (refresh_token)" do
      let(:tokens) do
        code = auth_code
        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        json_response
      end

      # Need auth_code for the chain
      let(:auth_code) do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: "orders:read",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        location = URI.parse(last_response.headers["Location"])
        URI.decode_www_form(location.query).to_h["code"]
      end

      it "refreshes tokens" do
        refresh = tokens["refresh_token"]
        post "/mcp/oauth/token", {
          grant_type: "refresh_token",
          refresh_token: refresh
        }
        expect(last_response.status).to eq(200)
        body = json_response
        expect(body["access_token"]).to be_present
        expect(body["refresh_token"]).to be_present
        expect(body["access_token"]).not_to eq(tokens["access_token"])
      end

      it "revokes old token after refresh" do
        refresh = tokens["refresh_token"]
        post "/mcp/oauth/token", {
          grant_type: "refresh_token",
          refresh_token: refresh
        }
        expect(last_response.status).to eq(200)

        # Old refresh token should be revoked
        post "/mcp/oauth/token", {
          grant_type: "refresh_token",
          refresh_token: refresh
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
      end

      it "rejects invalid refresh token" do
        post "/mcp/oauth/token", {
          grant_type: "refresh_token",
          refresh_token: "bogus"
        }
        expect(last_response.status).to eq(400)
        expect(json_response["error"]).to eq("invalid_grant")
      end
    end
  end

  # ============================================================
  # Metadata Discovery
  # ============================================================

  describe "GET /.well-known/oauth-authorization-server" do
    it "returns OAuth metadata" do
      get "/.well-known/oauth-authorization-server/mcp"
      expect(last_response.status).to eq(200)
      body = json_response
      expect(body["authorization_endpoint"]).to include("/mcp/oauth/authorize")
      expect(body["token_endpoint"]).to include("/mcp/oauth/token")
      expect(body["registration_endpoint"]).to include("/mcp/oauth/register")
      expect(body["code_challenge_methods_supported"]).to eq(["S256"])
      expect(body["scopes_supported"]).to include("orders:read", "orders:write")
    end
  end

  describe "GET /.well-known/oauth-protected-resource" do
    it "returns protected resource metadata" do
      get "/.well-known/oauth-protected-resource/mcp"
      expect(last_response.status).to eq(200)
      body = json_response
      expect(body["resource"]).to include("/mcp")
      expect(body["bearer_methods_supported"]).to eq(["header"])
    end
  end

  # ============================================================
  # Authorized Applications
  # ============================================================

  describe "authorized applications" do
    it "lists authorized apps after token exchange" do
      verifier, challenge = pkce_pair
      client = register_client
      client_id = client["client_id"]
      redirect_uri = "http://localhost:3000/callback"

      # Authorize
      post "/mcp/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        scope: "orders:read",
        code_challenge: challenge,
        code_challenge_method: "S256"
      }
      code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]

      # Exchange
      post "/mcp/oauth/token", {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri,
        client_id: client_id,
        code_verifier: verifier
      }
      expect(last_response.status).to eq(200)

      # List
      get "/mcp/oauth/authorized_applications"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Test Client")
    end

    it "revokes access when destroying an authorized app" do
      verifier, challenge = pkce_pair
      client = register_client
      client_id = client["client_id"]
      redirect_uri = "http://localhost:3000/callback"

      # Full flow
      post "/mcp/oauth/authorize", {
        client_id: client_id,
        redirect_uri: redirect_uri,
        scope: "orders:read",
        code_challenge: challenge,
        code_challenge_method: "S256"
      }
      code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]
      post "/mcp/oauth/token", {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri,
        client_id: client_id,
        code_verifier: verifier
      }
      access_token = json_response["access_token"]

      # Revoke via authorized applications
      oauth_app = Toolchest::OauthApplication.find_by(uid: client_id)
      delete "/mcp/oauth/authorized_applications/#{oauth_app.id}"
      expect(last_response.status).to eq(302)

      # Token should now be revoked (active-scoped find returns nil)
      expect(Toolchest::OauthAccessToken.find_by_token(access_token)).to be_nil
    end
  end

  # ============================================================
  # Scope Checkboxes
  # ============================================================

  describe "optional scopes (checkboxes)" do
    let(:client) { register_client }
    let(:client_id) { client["client_id"] }
    let(:redirect_uri) { "http://localhost:3000/callback" }
    let(:verifier) { SecureRandom.urlsafe_base64(32) }
    let(:challenge) { Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false) }

    context "when optional_scopes is false (default)" do
      it "grants all requested scopes regardless of submission" do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: %w[orders:read orders:write],
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]

        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(json_response["scope"]).to eq("orders:read orders:write")
      end
    end

    context "when optional_scopes is true" do
      before do
        Toolchest.configure do |c|
          c.auth = :oauth
          c.mount_path = "/mcp"
          c.scopes = {
            "orders:read" => "View orders",
            "orders:write" => "Modify orders"
          }
          c.optional_scopes = true
          c.current_user_for_oauth { |_req| fake_user }
        end
      end

      it "renders checkboxes on consent screen" do
        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read orders:write",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.body).to include('type="checkbox"')
        expect(last_response.body).to include("orders:read")
        expect(last_response.body).to include("orders:write")
      end

      it "grants only submitted scopes" do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: ["orders:read"],
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]

        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(json_response["scope"]).to eq("orders:read")
      end

      it "strips scopes not in the allowed set (tamper protection)" do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: ["orders:read", "admin:nuke"],
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]

        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(json_response["scope"]).to eq("orders:read")
      end
    end

    context "with required_scopes" do
      before do
        Toolchest.configure do |c|
          c.auth = :oauth
          c.mount_path = "/mcp"
          c.scopes = {
            "orders:read" => "View orders",
            "orders:write" => "Modify orders"
          }
          c.optional_scopes = true
          c.required_scopes = ["orders:read"]
          c.current_user_for_oauth { |_req| fake_user }
        end
      end

      it "always includes required scopes even if not submitted" do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: ["orders:write"],
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]

        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        scopes = json_response["scope"].split(" ")
        expect(scopes).to include("orders:read")
        expect(scopes).to include("orders:write")
      end
    end

    context "with allowed_scopes_for" do
      let(:admin_user) { Struct.new(:id, :admin?).new(1, true) }
      let(:normal_user) { Struct.new(:id, :admin?).new(2, false) }

      before do
        Toolchest.configure do |c|
          c.auth = :oauth
          c.mount_path = "/mcp"
          c.scopes = {
            "orders:read" => "View orders",
            "orders:write" => "Modify orders"
          }
          c.optional_scopes = true
          c.allowed_scopes_for do |user, scopes|
            user.admin? ? scopes : scopes - ["orders:write"]
          end
        end
      end

      it "hides gated scopes from non-admin on consent screen" do
        Toolchest.configure { |c| c.current_user_for_oauth { |_| normal_user } }

        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read orders:write",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        # Check scope list items, not hidden fields (original_scope preserves the full request)
        expect(last_response.body).to include("scope_orders-read")
        expect(last_response.body).not_to include("scope_orders-write")
      end

      it "shows all scopes to admin on consent screen" do
        Toolchest.configure { |c| c.current_user_for_oauth { |_| admin_user } }

        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read orders:write",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.body).to include("orders:read")
        expect(last_response.body).to include("orders:write")
      end

      it "strips gated scopes even if submitted by non-admin" do
        Toolchest.configure { |c| c.current_user_for_oauth { |_| normal_user } }

        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: ["orders:read", "orders:write"],
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        code = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h["code"]

        post "/mcp/oauth/token", {
          grant_type: "authorization_code",
          code: code,
          redirect_uri: redirect_uri,
          client_id: client_id,
          code_verifier: verifier
        }
        expect(json_response["scope"]).to eq("orders:read")
      end
    end

    context "with authorize_link" do
      let(:blocked_user) { Struct.new(:id, :blocked?).new(99, true) }

      before do
        Toolchest.configure do |c|
          c.auth = :oauth
          c.mount_path = "/mcp"
          c.scopes = {
            "orders:read" => "View orders",
            "orders:write" => "Modify orders"
          }
          c.current_user_for_oauth { |_| blocked_user }
          c.authorize_link { |user| !user.blocked? }
        end
      end

      it "redirects with access_denied on GET authorize" do
        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read orders:write",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.status).to eq(302)
        query = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h
        expect(query["error"]).to eq("access_denied")
      end

      it "redirects with access_denied on POST authorize" do
        post "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          scope: ["orders:read"],
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.status).to eq(302)
        query = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h
        expect(query["error"]).to eq("access_denied")
      end

      it "rejects even when required_scopes are configured" do
        Toolchest.configure { |c| c.required_scopes = ["orders:read"] }

        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.status).to eq(302)
        query = URI.decode_www_form(URI.parse(last_response.headers["Location"]).query).to_h
        expect(query["error"]).to eq("access_denied")
      end

      it "allows connection when block returns true" do
        allowed_user = Struct.new(:id, :blocked?).new(1, false)
        Toolchest.configure { |c| c.current_user_for_oauth { |_| allowed_user } }

        get "/mcp/oauth/authorize", {
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "orders:read",
          code_challenge: challenge,
          code_challenge_method: "S256"
        }
        expect(last_response.status).to eq(200)
      end
    end
  end

  # ============================================================
  # MCP Endpoint Auth
  # ============================================================

  describe "MCP endpoint with OAuth" do
    it "returns 401 without a bearer token" do
      post "/mcp", {}.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(401)
      expect(last_response.headers["WWW-Authenticate"]).to include("Bearer")
    end
  end

  describe "MCP endpoint with token auth" do
    around do |example|
      original = ENV["TOOLCHEST_TOKEN"]
      ENV["TOOLCHEST_TOKEN"] = "test_secret_token"
      example.run
    ensure
      ENV["TOOLCHEST_TOKEN"] = original
    end

    before do
      Toolchest.configure do |c|
        c.auth = :token
        c.mount_path = "/mcp"
      end
    end

    it "returns 401 without a bearer token" do
      post "/mcp", {}.to_json, "CONTENT_TYPE" => "application/json"
      expect(last_response.status).to eq(401)
    end

    it "returns 401 with an invalid bearer token" do
      post "/mcp", {}.to_json,
        "CONTENT_TYPE" => "application/json",
        "HTTP_AUTHORIZATION" => "Bearer wrong_token"
      expect(last_response.status).to eq(401)
    end
  end
end
