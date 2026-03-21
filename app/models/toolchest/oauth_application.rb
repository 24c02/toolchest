require "securerandom"

module Toolchest
  class OauthApplication < ActiveRecord::Base
    self.table_name = "toolchest_oauth_applications"

    has_many :access_grants, class_name: "Toolchest::OauthAccessGrant",
      foreign_key: :application_id, dependent: :delete_all
    has_many :access_tokens, class_name: "Toolchest::OauthAccessToken",
      foreign_key: :application_id, dependent: :delete_all

    validates :name, :uid, presence: true
    validates :uid, uniqueness: true
    validates :redirect_uri, presence: true

    before_validation :generate_uid, on: :create

    def redirect_uris = redirect_uri&.split("\n")&.map(&:strip)&.reject(&:empty?) || []

    def redirect_uri_matches?(uri) = redirect_uris.include?(uri)

    private

    def generate_uid = self.uid ||= SecureRandom.urlsafe_base64(32)
  end
end
