require "securerandom"
require "digest"
require "base64"

module Toolchest
  class OauthAccessGrant < ActiveRecord::Base
    self.table_name = "toolchest_oauth_access_grants"

    belongs_to :application, class_name: "Toolchest::OauthApplication"

    def self.revoke_all_for(application, resource_owner_id)
      where(application: application, resource_owner_id: resource_owner_id.to_s, revoked_at: nil)
        .update_all(revoked_at: Time.current)
    end

    scope :active, -> {
      where(revoked_at: nil)
        .where("expires_at > ?", Time.current)
    }

    def expired? = expires_at < Time.current

    def revoked? = revoked_at.present?

    def revoke! = update!(revoked_at: Time.current)

    # Atomic revocation — returns true only if THIS call revoked the grant.
    # Prevents race conditions where two concurrent token exchanges both
    # find the grant active and both mint tokens (RFC 6749 §4.1.2).
    def revoke_atomically!
      self.class.where(id: id, revoked_at: nil).update_all(revoked_at: Time.current) > 0
    end

    def uses_pkce? = code_challenge.present?

    def verify_pkce(code_verifier)
      return true unless uses_pkce?
      return false if code_verifier.blank?

      generated = Base64.urlsafe_encode64(
        Digest::SHA256.digest(code_verifier),
        padding: false
      )
      ActiveSupport::SecurityUtils.secure_compare(generated, code_challenge)
    end

    class << self
      def create_for(application:, resource_owner_id:, redirect_uri:, scopes:, mount_key: "default",
                     expires_in: 300, code_challenge: nil, code_challenge_method: nil)
        raw_code = SecureRandom.urlsafe_base64(32)

        grant = create!(
          application: application,
          resource_owner_id: resource_owner_id,
          token_digest: Digest::SHA256.hexdigest(raw_code),
          redirect_uri: redirect_uri,
          scopes: scopes,
          mount_key: mount_key,
          expires_at: Time.current + expires_in.seconds,
          code_challenge: code_challenge,
          code_challenge_method: code_challenge_method
        )

        grant.instance_variable_set(:@raw_code, raw_code)
        grant
      end

      def find_by_code(raw_code) = active.find_by(token_digest: Digest::SHA256.hexdigest(raw_code))
    end

    def raw_code = @raw_code
  end
end
