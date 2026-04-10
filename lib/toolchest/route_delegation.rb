module Toolchest
  # Delegates unresolved _path/_url helpers to main_app so the host
  # application's layout works inside engine-rendered views without
  # requiring main_app. prefixes everywhere.
  #
  # Included as a view helper by the engine when
  # Toolchest.delegate_route_helpers is true (the default).
  #
  # To disable:
  #
  #   # config/initializers/toolchest.rb
  #   Toolchest.delegate_route_helpers = false
  #
  module RouteDelegation
    def method_missing(method, *args, **kwargs, &block)
      if method.to_s.end_with?("_path", "_url") && main_app.respond_to?(method)
        main_app.public_send(method, *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      (method.to_s.end_with?("_path", "_url") && main_app.respond_to?(method)) || super
    end
  end
end
