require "openssl"

module Toolchest
  class Token < ActiveRecord::Base
    self.table_name = "toolchest_tokens"

    scope :active, -> {
      where(revoked_at: nil)
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
    }

    def expired? = expires_at.present? && expires_at < Time.current

    def revoked? = revoked_at.present?

    def accessible? = !revoked? && !expired?

    def revoke! = update!(revoked_at: Time.current)

    def scopes_array = (scopes || "").split(" ").reject(&:empty?)

    class << self
      def find_by_raw_token(raw_token)
        digest = OpenSSL::Digest::SHA256.hexdigest(raw_token)
        active.find_by(token_digest: digest)
      end

      def generate(owner: nil, name: nil, scopes: nil, namespace: "default", expires_at: nil)
        raw = "tcht_#{SecureRandom.hex(24)}"
        digest = OpenSSL::Digest::SHA256.hexdigest(raw)

        owner_type, owner_id = owner&.split(":", 2)

        token = create!(
          token_digest: digest,
          name: name,
          owner_type: owner_type,
          owner_id: owner_id,
          scopes: scopes,
          namespace: namespace,
          expires_at: expires_at
        )

        token.instance_variable_set(:@raw_token, raw)
        token
      end
    end

    def raw_token = @raw_token
  end
end
