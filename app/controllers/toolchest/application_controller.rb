module Toolchest
  class ApplicationController < Toolchest.base_controller.constantize
    helper Toolchest::RouteDelegation if Toolchest.delegate_route_helpers
  end
end
