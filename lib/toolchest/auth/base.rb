module Toolchest
  module Auth
    class Base
      def authenticate(request) = raise NotImplementedError

      private

      def extract_bearer_token(request)
        auth_header = request.env["HTTP_AUTHORIZATION"] || ""
        match = auth_header.match(/\ABearer\s+(.+)\z/i)
        match&.[](1)
      end
    end
  end
end
