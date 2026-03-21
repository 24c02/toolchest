require "securerandom"
require "digest"

module Toolchest
  class OauthAccessToken < ActiveRecord::Base
    self.table_name = "toolchest_oauth_access_tokens"

    belongs_to :application, class_name: "Toolchest::OauthApplication", optional: true

    scope :active, -> {
      where(revoked_at: nil)
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
    }

    def expired? = expires_at.present? && expires_at < Time.current

    def revoked? = revoked_at.present?

    def revoke! = update!(revoked_at: Time.current)

    def accessible? = !revoked? && !expired?

    def scopes_array = (scopes || "").split(" ").reject(&:empty?)

    class << self
      def revoke_all_for(application, resource_owner_id)
        where(application: application, resource_owner_id: resource_owner_id.to_s, revoked_at: nil)
          .update_all(revoked_at: Time.current)
      end

      def create_for(application:, resource_owner_id:, scopes:, mount_key: "default", expires_in: 7200)
        raw_token = SecureRandom.urlsafe_base64(32)
        raw_refresh = SecureRandom.urlsafe_base64(32)

        token = create!(
          application: application,
          resource_owner_id: resource_owner_id,
          token: Digest::SHA256.hexdigest(raw_token),
          refresh_token: Digest::SHA256.hexdigest(raw_refresh),
          scopes: scopes,
          mount_key: mount_key,
          expires_at: expires_in ? Time.current + expires_in.seconds : nil
        )

        token.instance_variable_set(:@raw_token, raw_token)
        token.instance_variable_set(:@raw_refresh_token, raw_refresh)
        token
      end

      # Timing-safe by design: we hash the raw token before lookup, so the
      # database comparison runs against the hash (which the attacker doesn't
      # know). No constant-time comparison needed here.
      def find_by_token(raw_token, mount_key: nil)
        scope = active.where(token: Digest::SHA256.hexdigest(raw_token))
        scope = scope.where(mount_key: mount_key) if mount_key
        scope.first
      end

      # See find_by_token for timing safety rationale.
      def find_by_refresh_token(raw_refresh, mount_key: nil)
        scope = active.where(refresh_token: Digest::SHA256.hexdigest(raw_refresh))
        scope = scope.where(mount_key: mount_key) if mount_key
        scope.first
      end
    end

    def raw_token = @raw_token

    def raw_refresh_token = @raw_refresh_token
  end
end
