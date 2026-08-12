module Toolchest
  class ApplicationController < Toolchest.base_controller.constantize
    protect_from_forgery with: :exception
    before_action :set_frame_options

    helper Toolchest::RouteDelegation if Toolchest.delegate_route_helpers

    private

    def set_frame_options
      response.headers["X-Frame-Options"] = "DENY"
    end
  end
end
