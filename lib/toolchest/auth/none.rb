module Toolchest
  module Auth
    class None < Base
      def authenticate(request) = nil
    end
  end
end
