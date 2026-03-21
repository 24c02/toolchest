require "openssl"

module Toolchest
  module Auth
    class Token < Base
      def authenticate(request)
        token_string = extract_bearer_token(request)
        return nil unless token_string

        token_record = find_token(token_string)
        return nil unless token_record

        config = Toolchest.configuration
        if config.respond_to?(:authenticate_with) && config.send(:instance_variable_get, :@authenticate_block)
          config.authenticate_with(token_record)
        else
          token_record
        end
      end

      private

      def find_token(token_string)
        env_token = find_env_token(token_string)
        return env_token if env_token

        find_db_token(token_string)
      end

      def find_env_token(token_string)
        expected = ENV["TOOLCHEST_TOKEN"]
        return nil unless expected
        return nil unless secure_compare(token_string, expected)

        owner = ENV["TOOLCHEST_TOKEN_OWNER"]
        EnvTokenRecord.new(token_string, owner)
      end

      def find_db_token(token_string)
        return nil unless defined?(Toolchest::Token) && Toolchest::Token.table_exists?

        token = Toolchest::Token.find_by_raw_token(token_string)
        return nil unless token

        token.update_column(:last_used_at, Time.current)
        token
      end

      def secure_compare(a, b) = ActiveSupport::SecurityUtils.secure_compare(a, b)

      EnvTokenRecord = Struct.new(:token, :owner_id) do
        def owner_type
          type, _ = owner_id&.split(":", 2)
          type
        end

        def scopes = ENV.fetch("TOOLCHEST_TOKEN_SCOPES", "").split(" ").reject(&:empty?)
      end
    end
  end
end
